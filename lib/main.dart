import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _bg = Color(0xFF080808);
const _panel = Color(0xFF171717);
const _gold = Color(0xFFD6AD45);
const _muted = Color(0xFFB8B8B8);
const _imageBase = 'https://image.tmdb.org/t/p/';

const _tmdbKey = String.fromEnvironment('TMDB_API_KEY');
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
  }
  runApp(const FlixoraTvApp());
}

class TvTitle {
  const TvTitle({
    required this.id,
    required this.name,
    required this.overview,
    required this.poster,
    required this.backdrop,
    required this.type,
    this.rating = 0,
  });

  final int id;
  final String name;
  final String overview;
  final String poster;
  final String backdrop;
  final String type;
  final double rating;

  factory TvTitle.fromJson(Map<String, dynamic> json, String type) {
    final date = (json['release_date'] ?? json['first_air_date'] ?? '').toString();
    return TvTitle(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['title'] ?? json['name'] ?? 'Untitled').toString(),
      overview: (json['overview'] ?? '').toString(),
      poster: (json['poster_path'] ?? '').toString(),
      backdrop: (json['backdrop_path'] ?? '').toString(),
      type: type,
      rating: (json['vote_average'] as num?)?.toDouble() ?? 0,
    );
  }

  String get posterUrl => poster.isEmpty ? '' : '$_imageBase w500$poster';
  String get backdropUrl => backdrop.isEmpty ? posterUrl : '$_imageBase original$backdrop';
}

class TvCatalog {
  static Future<List<TvTitle>> trending(String type) async {
    if (_tmdbKey.isEmpty) return [];
    final uri = Uri.https('api.themoviedb.org', '/3/trending/$type/week', {
      'api_key': _tmdbKey,
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Catalogue request failed (${response.statusCode})');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['results'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => TvTitle.fromJson(Map<String, dynamic>.from(item), type))
        .where((item) => item.poster.isNotEmpty || item.backdrop.isNotEmpty)
        .toList(growable: false);
  }
}

class FlixoraTvApp extends StatelessWidget {
  const FlixoraTvApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FLIXORA TV',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _bg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _gold,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          focusColor: _gold.withValues(alpha: .28),
        ),
        home: const TvHomeScreen(),
      );
}

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  final _pageController = PageController();
  final _scrollController = ScrollController();
  final _focusNodes = List<FocusNode>.generate(5, (_) => FocusNode());
  Timer? _autoSlide;
  List<TvTitle> _movies = [];
  List<TvTitle> _series = [];
  int _slide = 0;
  int _navIndex = 0;
  bool _loading = true;
  String? _error;

  List<TvTitle> get _featured {
    final combined = <TvTitle>[];
    for (var i = 0; i < 12; i++) {
      if (i.isEven && i ~/ 2 < _movies.length) combined.add(_movies[i ~/ 2]);
      if (i.isOdd && i ~/ 2 < _series.length) combined.add(_series[i ~/ 2]);
    }
    return combined;
  }

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _autoSlide = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || _featured.length < 2) return;
      final next = (_slide + 1) % _featured.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
    });
  }

  Future<void> _loadCatalog() async {
    try {
      final results = await Future.wait([
        TvCatalog.trending('movie'),
        TvCatalog.trending('tv'),
      ]);
      if (!mounted) return;
      setState(() {
        _movies = results[0];
        _series = results[1];
        _loading = false;
        _error = _tmdbKey.isEmpty ? 'TMDB_API_KEY is not configured in the build.' : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _moveFocus(int direction) {
    final next = (_navIndex + direction).clamp(0, _focusNodes.length - 1);
    _focusNodes[next].requestFocus();
    setState(() => _navIndex = next);
  }

  @override
  void dispose() {
    _autoSlide?.cancel();
    _pageController.dispose();
    _scrollController.dispose();
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final featured = _featured;
    return Scaffold(
      body: SafeArea(
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              if (_navIndex == 0 && featured.isNotEmpty) {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                );
                return KeyEventResult.handled;
              }
              _moveFocus(-1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              if (_navIndex == 0 && featured.isNotEmpty) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                );
                return KeyEventResult.handled;
              }
              _moveFocus(1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _scrollController.animateTo(
                (_scrollController.offset + 360).clamp(0, _scrollController.position.maxScrollExtent),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOut,
              );
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _scrollController.animateTo(
                (_scrollController.offset - 360).clamp(0, _scrollController.position.maxScrollExtent),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOut,
              );
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(54, 22, 54, 0),
                sliver: SliverToBoxAdapter(child: _topBar()),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: _hero(featured),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: _gold)),
                )
              else if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Text(_error!, style: const TextStyle(color: _muted)),
                  ),
                )
              else ...[
                _section('Trending Movies', _movies),
                _section('Popular Web Series', _series),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Row(
        children: [
          const Text(
            'FLIXORA',
            style: TextStyle(
              color: _gold,
              fontSize: 30,
              letterSpacing: 4,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          const Text('TV', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const Spacer(),
          _navButton('Home', 0, Icons.home_rounded),
          _navButton('Movies', 1, Icons.movie_rounded),
          _navButton('Series', 2, Icons.live_tv_rounded),
          _navButton('Search', 3, Icons.search_rounded),
          _navButton('My List', 4, Icons.bookmark_rounded),
        ],
      );

  Widget _navButton(String label, int index, IconData icon) {
    final selected = _navIndex == index;
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Focus(
        focusNode: _focusNodes[index],
        onFocusChange: (focused) {
          if (focused && mounted) setState(() => _navIndex = index);
        },
        child: Builder(builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
            decoration: BoxDecoration(
              color: focused ? _gold : (selected ? _panel : Colors.transparent),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: focused ? _gold : Colors.transparent),
            ),
            child: Row(
              children: [
                Icon(icon, size: 19, color: focused ? Colors.black : Colors.white70),
                const SizedBox(width: 7),
                Text(label, style: TextStyle(
                  color: focused ? Colors.black : Colors.white70,
                  fontWeight: focused ? FontWeight.bold : FontWeight.w500,
                )),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _hero(List<TvTitle> items) {
    if (items.isEmpty) {
      return Container(
        height: 410,
        margin: const EdgeInsets.symmetric(horizontal: 54),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(22)),
        child: const Center(child: Text('Your entertainment starts here')),
      );
    }
    return SizedBox(
      height: 440,
      child: PageView.builder(
        controller: _pageController,
        itemCount: items.length,
        onPageChanged: (index) => setState(() => _slide = index),
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 54),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.backdropUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: item.backdropUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: _panel),
                    )
                  else
                    Container(color: _panel),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [Colors.black.withValues(alpha: .05), Colors.black.withValues(alpha: .94)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 54,
                    bottom: 56,
                    width: MediaQuery.sizeOf(context).width * .48,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.type == 'movie' ? 'FEATURED MOVIE' : 'FEATURED SERIES',
                            style: const TextStyle(color: _gold, letterSpacing: 2, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        Text(item.overview, maxLines: 3, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4)),
                        const SizedBox(height: 12),
                        Text('★ ${item.rating.toStringAsFixed(1)}',
                            style: const TextStyle(color: _gold, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 18),
                        Row(children: [
                          _heroAction('Details', Icons.info_outline, true, () => _showDetails(item)),
                          const SizedBox(width: 12),
                          _heroAction('Watch Now', Icons.play_arrow_rounded, false, () => _showDetails(item)),
                        ]),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 30,
                    bottom: 24,
                    child: Row(
                      children: List.generate(items.length.clamp(0, 12), (i) =>
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == index ? 24 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == index ? _gold : Colors.white38,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        )),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _heroAction(String label, IconData icon, bool primary, VoidCallback action) =>
      ElevatedButton.icon(
        onPressed: action,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: primary ? _gold : Colors.white.withValues(alpha: .12),
          foregroundColor: primary ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        ),
      );

  Widget _section(String title, List<TvTitle> items) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(54, 26, 54, 0),
        sliver: SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 15),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return SizedBox(
                    width: 145,
                    child: InkWell(
                      onTap: () => _showDetails(item),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: item.posterUrl.isEmpty
                                ? Container(color: _panel)
                                : CachedNetworkImage(imageUrl: item.posterUrl, fit: BoxFit.cover, width: 145),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      );

  void _showDetails(TvTitle item) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: Text(item.name),
        content: Text(item.overview.isEmpty ? 'No description available.' : item.overview),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Playback source not connected yet'),
          ),
        ],
      ),
    );
  }
}
