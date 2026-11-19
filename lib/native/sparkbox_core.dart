import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Error returned by the native MovieBox/WeFeed client.
class SparkBoxCoreException implements Exception {
  const SparkBoxCoreException(this.message);

  final String message;

  @override
  String toString() => 'SparkBoxCoreException: $message';
}

/// JSON-over-FFI bridge to the MIT-licensed SparkBoxCore library.
///
/// All blocking network calls run on a background isolate. The Android
/// library is built by the FLIXORA GitHub Actions workflow and packaged in
/// android/app/src/main/jniLibs for each supported ABI.
class SparkBoxCore {
  SparkBoxCore._();

  static DynamicLibrary _openLibrary() {
    return DynamicLibrary.open('libsparkbox_ffi.so');
  }

  static Future<T> _run<T>(T Function() action) => Isolate.run(action);

  static void _free(DynamicLibrary library, Pointer<Utf8> pointer) {
    if (pointer == nullptr) return;
    library
        .lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>(
          'sparkbox_free_string',
        )(pointer);
  }

  static Map<String, dynamic> _readObject(
    DynamicLibrary library,
    Pointer<Utf8> pointer,
  ) {
    if (pointer == nullptr) {
      throw const SparkBoxCoreException('MovieBoxCore returned an empty response.');
    }
    try {
      final envelope = jsonDecode(pointer.toDartString());
      if (envelope is! Map) {
        throw const SparkBoxCoreException('MovieBoxCore returned an invalid response.');
      }
      if (envelope['ok'] != true) {
        throw SparkBoxCoreException(
          (envelope['error'] ?? 'MovieBox request failed.').toString(),
        );
      }
      final data = envelope['data'];
      if (data is! Map) {
        throw const SparkBoxCoreException('MovieBoxCore returned unexpected data.');
      }
      return Map<String, dynamic>.from(data);
    } finally {
      _free(library, pointer);
    }
  }

  static List<dynamic> _readList(
    DynamicLibrary library,
    Pointer<Utf8> pointer,
  ) {
    if (pointer == nullptr) {
      throw const SparkBoxCoreException('MovieBoxCore returned an empty response.');
    }
    try {
      final envelope = jsonDecode(pointer.toDartString());
      if (envelope is! Map) {
        throw const SparkBoxCoreException('MovieBoxCore returned an invalid response.');
      }
      if (envelope['ok'] != true) {
        throw SparkBoxCoreException(
          (envelope['error'] ?? 'MovieBox request failed.').toString(),
        );
      }
      final data = envelope['data'];
      if (data is! List) {
        throw const SparkBoxCoreException('MovieBoxCore returned unexpected list data.');
      }
      return data;
    } finally {
      _free(library, pointer);
    }
  }

  static Map<String, dynamic> _encodeMap(Map<String, dynamic> value) {
    return Map<String, dynamic>.from(value);
  }

  /// Core version and the current adult-content-filter state.
  static Future<Map<String, dynamic>> version() => _run(() {
        final library = _openLibrary();
        final call = library.lookupFunction<
            Pointer<Utf8> Function(),
            Pointer<Utf8> Function()>('sparkbox_core_version');
        return _readObject(library, call());
      });

  /// Keep the core's adult-content filter enabled by default.
  static Future<void> setBlockAdult(bool blocked) => _run(() {
        final library = _openLibrary();
        final call = library.lookupFunction<
            Pointer<Utf8> Function(Int32),
            Pointer<Utf8> Function(int)>('sparkbox_set_block_adult');
        _readObject(library, call(blocked ? 1 : 0));
      });

  /// MovieBox/WeFeed home feed.
  static Future<List<Map<String, dynamic>>> home() => _run(() {
        final library = _openLibrary();
        final call = library.lookupFunction<
            Pointer<Utf8> Function(),
            Pointer<Utf8> Function()>('sparkbox_home');
        return _readList(library, call())
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      });

  /// Paginated Short TV catalogue from the dedicated WeFeed endpoint.
  static Future<Map<String, dynamic>> shorts({
    int perPage = 24,
    int maxPages = 10,
  }) =>
      _run(() {
        final library = _openLibrary();
        final call = library.lookupFunction<
            Pointer<Utf8> Function(Int32, Int32),
            Pointer<Utf8> Function(int, int)>('sparkbox_shorts');
        return _readObject(library, call(perPage, maxPages));
      });

  /// Search suggestions from the central MovieBox content system.
  static Future<List<String>> suggest(String query) => _run(() {
        final library = _openLibrary();
        final call = library.lookupFunction<
            Pointer<Utf8> Function(Pointer<Utf8>),
            Pointer<Utf8> Function(Pointer<Utf8>)>('sparkbox_suggest');
        final input = query.toNativeUtf8();
        try {
          return _readList(library, call(input))
              .map((item) => item.toString())
              .toList(growable: false);
        } finally {
          malloc.free(input);
        }
      });

  /// Paginated MovieBox search.
  static Future<Map<String, dynamic>> search(
    String query, {
    int page = 1,
    int perPage = 20,
  }) =>
      _run(() {
        final library = _openLibrary();
        final call = library.lookupFunction<
            Pointer<Utf8> Function(Pointer<Utf8>, Int32, Int32),
            Pointer<Utf8> Function(Pointer<Utf8>, int, int)>('sparkbox_search');
        final input = query.toNativeUtf8();
        try {
          return _readObject(library, call(input, page, perPage));
        } finally {
          malloc.free(input);
        }
      });

  /// Enriched title details, including dub/language variants and cast.
  static Future<Map<String, dynamic>> detailRich(
    Map<String, dynamic> item,
  ) =>
      _run(() {
        final library = _openLibrary();
        final call = library.lookupFunction<
            Pointer<Utf8> Function(Pointer<Utf8>),
            Pointer<Utf8> Function(Pointer<Utf8>)>('sparkbox_detail_rich');
        final input = jsonEncode(_encodeMap(item)).toNativeUtf8();
        try {
          return _readObject(library, call(input));
        } finally {
          malloc.free(input);
        }
      });

  /// Resolve the play-flow detail handle for a MovieBox title.
  static Future<Map<String, dynamic>> playDetail(
    Map<String, dynamic> item,
  ) =>
      _run(() {
        final library = _openLibrary();
        final call = library.lookupFunction<
            Pointer<Utf8> Function(Pointer<Utf8>),
            Pointer<Utf8> Function(Pointer<Utf8>)>('sparkbox_play_detail');
        final input = jsonEncode(_encodeMap(item)).toNativeUtf8();
        try {
          return _readObject(library, call(input));
        } finally {
          malloc.free(input);
        }
      });

  /// Seasons and episode numbers for a series.
  static Future<List<Map<String, dynamic>>> seasons(String subjectId) =>
      _run(() {
        final library = _openLibrary();
        final call = library.lookupFunction<
            Pointer<Utf8> Function(Pointer<Utf8>),
            Pointer<Utf8> Function(Pointer<Utf8>)>('sparkbox_seasons');
        final input = subjectId.toNativeUtf8();
        try {
          return _readList(library, call(input))
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false);
        } finally {
          malloc.free(input);
        }
      });

  /// Resolve Original stream first, without waiting for dub or external subtitle discovery.
  static Future<Map<String, dynamic>> streamsFast(
    Map<String, dynamic> detail, {
    required int season,
    required int episode,
    required bool isSeries,
  }) =>
      _run(() {
        final library = _openLibrary();
        final call = library.lookupFunction<
            Pointer<Utf8> Function(Pointer<Utf8>, Int32, Int32, Int32),
            Pointer<Utf8> Function(Pointer<Utf8>, int, int, int)>(
          'sparkbox_streams_fast',
        );
        final input = jsonEncode(_encodeMap(detail)).toNativeUtf8();
        try {
          return _readObject(
            library,
            call(input, season, episode, isSeries ? 1 : 0),
          );
        } finally {
          malloc.free(input);
        }
      });

  /// Resolve playable HLS/DASH/MP4 links and external subtitle links.
  static Future<Map<String, dynamic>> streams(
    Map<String, dynamic> detail, {
    required int season,
    required int episode,
    required bool isSeries,
  }) =>
      _run(() {
        final library = _openLibrary();
        final call = library.lookupFunction<
            Pointer<Utf8> Function(Pointer<Utf8>, Int32, Int32, Int32),
            Pointer<Utf8> Function(Pointer<Utf8>, int, int, int)>(
          'sparkbox_streams',
        );
        final input = jsonEncode(_encodeMap(detail)).toNativeUtf8();
        try {
          return _readObject(
            library,
            call(input, season, episode, isSeries ? 1 : 0),
          );
        } finally {
          malloc.free(input);
        }
      });

  static Future<String> typeLabel(int subjectType) => _run(() {
        final library = _openLibrary();
        final call = library.lookupFunction<
            Pointer<Utf8> Function(Int32),
            Pointer<Utf8> Function(int)>('sparkbox_type_label');
        final data = _readObject(library, call(subjectType));
        return (data['label'] ?? 'MEDIA').toString();
      });
}
