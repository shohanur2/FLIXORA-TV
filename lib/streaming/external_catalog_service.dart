import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OmdbMetadata {
  const OmdbMetadata({
    required this.imdbRating,
    required this.metascore,
    required this.rated,
    required this.runtime,
    required this.awards,
    required this.imdbVotes,
    required this.boxOffice,
    required this.country,
    required this.language,
  });

  final String imdbRating;
  final String metascore;
  final String rated;
  final String runtime;
  final String awards;
  final String imdbVotes;
  final String boxOffice;
  final String country;
  final String language;

  factory OmdbMetadata.fromJson(Map<String, dynamic> json) {
    String value(String key) {
      final raw = (json[key] ?? '').toString().trim();
      return raw == 'N/A' ? '' : raw;
    }

    return OmdbMetadata(
      imdbRating: value('imdbRating'),
      metascore: value('Metascore'),
      rated: value('Rated'),
      runtime: value('Runtime'),
      awards: value('Awards'),
      imdbVotes: value('imdbVotes'),
      boxOffice: value('BoxOffice'),
      country: value('Country'),
      language: value('Language'),
    );
  }

  bool get hasContent => <String>[
        imdbRating, metascore, rated, runtime, awards, imdbVotes,
        boxOffice, country, language,
      ].any((value) => value.isNotEmpty);
}

class WatchmodeSource {
  const WatchmodeSource({
    required this.name,
    required this.type,
    required this.region,
    required this.format,
    required this.price,
    required this.webUrl,
  });

  final String name;
  final String type;
  final String region;
  final String format;
  final String price;
  final String webUrl;

  factory WatchmodeSource.fromJson(Map<String, dynamic> json) {
    String value(String key) {
      final raw = (json[key] ?? '').toString().trim();
      return raw == 'null' || raw == 'N/A' ? '' : raw;
    }

    return WatchmodeSource(
      name: value('name'),
      type: value('type'),
      region: value('region'),
      format: value('format'),
      price: value('price'),
      webUrl: value('web_url'),
    );
  }
}

class TasteDiveSuggestion {
  const TasteDiveSuggestion({
    required this.name,
    required this.type,
    required this.description,
  });

  final String name;
  final String type;
  final String description;

  factory TasteDiveSuggestion.fromJson(Map<String, dynamic> json) {
    return TasteDiveSuggestion(
      name: (json['Name'] ?? '').toString().trim(),
      type: (json['Type'] ?? '').toString().trim(),
      description: (json['wTeaser'] ?? '').toString().trim(),
    );
  }
}

class TraktTitleInfo {
  const TraktTitleInfo({
    required this.rating,
    required this.votes,
    required this.rank,
    required this.traktUrl,
  });

  final double? rating;
  final int? votes;
  final int? rank;
  final String traktUrl;

  bool get hasContent => rating != null || votes != null || rank != null;
}

class ExternalCatalogData {
  const ExternalCatalogData({
    this.omdb,
    this.watchmode = const <WatchmodeSource>[],
    this.similar = const <TasteDiveSuggestion>[],
    this.trakt,
  });

  final OmdbMetadata? omdb;
  final List<WatchmodeSource> watchmode;
  final List<TasteDiveSuggestion> similar;
  final TraktTitleInfo? trakt;

  bool get isEmpty =>
      (omdb == null || !omdb!.hasContent) &&
      watchmode.isEmpty &&
      similar.isEmpty &&
      (trakt == null || !trakt!.hasContent);
}

/// Optional metadata/discovery integrations. These APIs do not provide
/// playable movie streams; FLIXORA's existing Player sources remain separate.
class ExternalCatalogService {
  ExternalCatalogService._();

  /// API credentials stay in Supabase Edge Function secrets, never in the APK.
  static Future<ExternalCatalogData> load({
    required SupabaseClient client,
    required String title,
    required String year,
    required String mediaType,
    required int tmdbId,
    String region = 'BD',
  }) async {
    try {
      final response = await client.functions.invoke(
        'external-catalog',
        body: <String, dynamic>{
          'title': title,
          'year': year,
          'mediaType': mediaType,
          'tmdbId': tmdbId,
          'region': region,
        },
      );
      if (response.status < 200 || response.status >= 300 ||
          response.data is! Map) {
        return const ExternalCatalogData();
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      final rawOmdb = data['omdb'];
      final rawWatchmode = data['watchmode'];
      final rawSimilar = data['similar'];
      final rawTrakt = data['trakt'];

      return ExternalCatalogData(
        omdb: rawOmdb is Map
            ? OmdbMetadata.fromJson(Map<String, dynamic>.from(rawOmdb))
            : null,
        watchmode: rawWatchmode is List
            ? rawWatchmode
                .whereType<Map>()
                .map((item) => WatchmodeSource.fromJson(
                      Map<String, dynamic>.from(item),
                    ))
                .where((item) => item.name.isNotEmpty)
                .toList()
            : const <WatchmodeSource>[],
        similar: rawSimilar is List
            ? rawSimilar
                .whereType<Map>()
                .map((item) => TasteDiveSuggestion.fromJson(
                      Map<String, dynamic>.from(item),
                    ))
                .where((item) => item.name.isNotEmpty)
                .take(8)
                .toList()
            : const <TasteDiveSuggestion>[],
        trakt: rawTrakt is Map
            ? TraktTitleInfo(
                rating: (rawTrakt['rating'] as num?)?.toDouble(),
                votes: (rawTrakt['votes'] as num?)?.toInt(),
                rank: (rawTrakt['rank'] as num?)?.toInt(),
                traktUrl: (rawTrakt['traktUrl'] ?? '').toString(),
              )
            : null,
      );
    } catch (_) {
      // External discovery is optional; it must never block the FLIXORA player.
      return const ExternalCatalogData();
    }
  }
}

class ExternalCatalogSection extends StatefulWidget {
  const ExternalCatalogSection({
    super.key,
    required this.title,
    required this.year,
    required this.mediaType,
    required this.tmdbId,
    required this.client,
  });

  final SupabaseClient? client;
  final String title;
  final String year;
  final String mediaType;
  final int tmdbId;

  @override
  State<ExternalCatalogSection> createState() =>
      _ExternalCatalogSectionState();
}

class _ExternalCatalogSectionState extends State<ExternalCatalogSection> {
  late final Future<ExternalCatalogData> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.client == null
        ? Future<ExternalCatalogData>.value(const ExternalCatalogData())
        : ExternalCatalogService.load(
      client: widget.client!,
      title: widget.title,
      year: widget.year,
      mediaType: widget.mediaType,
      tmdbId: widget.tmdbId,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.client == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<ExternalCatalogData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null || data.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'More from our data partners',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (data.trakt != null && data.trakt!.hasContent) ...[
                _ExternalPanel(
                  title: 'Trakt community rating',
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 9,
                    children: [
                      if (data.trakt!.rating != null)
                        _ExternalMetric(
                          label: 'Rating',
                          value: data.trakt!.rating!.toStringAsFixed(1) + '/10',
                        ),
                      if (data.trakt!.votes != null)
                        _ExternalMetric(
                          label: 'Votes',
                          value: data.trakt!.votes.toString(),
                        ),
                      if (data.trakt!.rank != null)
                        _ExternalMetric(
                          label: 'Rank',
                          value: '#${data.trakt!.rank}',
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (data.omdb != null && data.omdb!.hasContent) ...[
                const SizedBox(height: 10),
                _ExternalPanel(
                  title: 'OMDb details',
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 9,
                    children: [
                      if (data.omdb!.imdbRating.isNotEmpty)
                        _ExternalMetric(
                          label: 'IMDb',
                          value: data.omdb!.imdbRating,
                        ),
                      if (data.omdb!.metascore.isNotEmpty)
                        _ExternalMetric(
                          label: 'Metascore',
                          value: data.omdb!.metascore,
                        ),
                      if (data.omdb!.rated.isNotEmpty)
                        _ExternalMetric(
                          label: 'Rated',
                          value: data.omdb!.rated,
                        ),
                      if (data.omdb!.runtime.isNotEmpty)
                        _ExternalMetric(
                          label: 'Runtime',
                          value: data.omdb!.runtime,
                        ),
                      if (data.omdb!.imdbVotes.isNotEmpty)
                        _ExternalMetric(
                          label: 'Votes',
                          value: data.omdb!.imdbVotes,
                        ),
                      if (data.omdb!.boxOffice.isNotEmpty)
                        _ExternalMetric(
                          label: 'Box office',
                          value: data.omdb!.boxOffice,
                        ),
                    ],
                  ),
                ),
              ],
              if (data.watchmode.isNotEmpty) ...[
                const SizedBox(height: 10),
                _ExternalPanel(
                  title: 'Where to watch · Bangladesh',
                  child: Column(
                    children: data.watchmode.take(8).map((source) {
                      final detail = <String>[
                        if (source.type.isNotEmpty)
                          source.type.toUpperCase(),
                        if (source.format.isNotEmpty) source.format,
                        if (source.price.isNotEmpty) source.price,
                      ].join(' · ');
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.live_tv_outlined,
                              color: Color(0xFFD6AD45),
                              size: 17,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                source.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (detail.isNotEmpty)
                              Text(
                                detail,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              if (data.similar.isNotEmpty) ...[
                const SizedBox(height: 10),
                _ExternalPanel(
                  title: 'You may also like',
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: data.similar.map((item) {
                      return Chip(
                        label: Text(
                          item.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                        backgroundColor: const Color(0xFF292929),
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.only(top: 7),
                child: Text(
                  'Availability and recommendations are informational only; they do not provide playback streams.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExternalPanel extends StatelessWidget {
  const _ExternalPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF191919),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFFF6670),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }
}

class _ExternalMetric extends StatelessWidget {
  const _ExternalMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
