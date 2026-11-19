import 'package:supabase_flutter/supabase_flutter.dart';

import '../streaming/catalog_source_policy.dart';

/// Checks catalogue candidates against the latest FLIXORA Admin publication
/// state without exposing unpublished rows or any video/source URLs.
class CatalogVisibilityService {
  static Future<Set<String>> blockedKeys({
    required SupabaseClient client,
    required List<Map<String, dynamic>> candidates,
  }) async {
    if (candidates.isEmpty) return <String>{};

    // Only exact Admin row IDs are sent to the function. This protects
    // MovieBox cards even if an older deployed function returns broad keys.
    final safeCandidates = <Map<String, dynamic>>[];
    for (final candidate in candidates) {
      final sourceId = int.tryParse(
            (candidate['sourceId'] ?? '').toString(),
          ) ??
          0;
      final expectedKey = CatalogSourcePolicy.adminVisibilityKey(
        isAdmin: candidate['source']?.toString() == 'admin',
        sourceId: sourceId,
      );
      if (expectedKey != null &&
          candidate['key']?.toString() == expectedKey) {
        safeCandidates.add(Map<String, dynamic>.from(candidate));
      }
    }
    if (safeCandidates.isEmpty) return <String>{};

    final requestedKeys =
        safeCandidates.map((item) => item['key'].toString()).toSet();
    final response = await client.functions.invoke(
      'catalog-visibility',
      body: {'candidates': safeCandidates},
    );

    final data = response.data;
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Admin publication lookup failed (${response.status}).');
    }
    if (data is! Map) {
      throw const FormatException('Invalid Admin publication response.');
    }

    final rawKeys = data['blockedKeys'];
    if (rawKeys is! List) {
      throw const FormatException('Admin publication response has no blockedKeys list.');
    }

    return CatalogSourcePolicy.filterBlockedAdminKeys(
      requestedKeys: requestedKeys,
      blockedKeys: rawKeys.map((value) => value.toString()),
    );
  }
}
