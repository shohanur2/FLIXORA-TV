import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Optional native Rust helpers. Dart fallbacks keep startup safe if the
/// native library is unavailable on a development or older installed build.
class RustPlaybackCore {
  RustPlaybackCore._();

  static DynamicLibrary? _library;
  static bool _attempted = false;
  static int Function(Pointer<Utf8>)? _detectStreamKind;
  static int Function(Pointer<Utf8>)? _qualityRank;
  static int Function(Pointer<Utf8>)? _validateUrl;
  static Pointer<Utf8> Function()? _version;
  static Pointer<Utf8> Function(int)? _playbackError;
  static void Function(Pointer<Utf8>)? _freeString;

  static bool get isAvailable {
    _load();
    return _library != null && _detectStreamKind != null;
  }

  static void _load() {
    if (_attempted) return;
    _attempted = true;
    if (!Platform.isAndroid) return;
    try {
      final library = DynamicLibrary.open('libflixora_core.so');
      _library = library;
      _detectStreamKind = library.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('flixora_detect_stream_kind');
      _qualityRank = library.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('flixora_quality_rank');
      _validateUrl = library.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('flixora_validate_http_url');
      _version = library.lookupFunction<
          Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('flixora_core_version');
      _playbackError = library.lookupFunction<
          Pointer<Utf8> Function(Int32),
          Pointer<Utf8> Function(int)>('flixora_playback_error');
      _freeString = library.lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('flixora_free_string');
    } catch (_) {
      _library = null;
    }
  }

  static int detectStreamKind(String url) {
    _load();
    final function = _detectStreamKind;
    if (function != null) {
      final input = url.toNativeUtf8();
      try {
        return function(input);
      } finally {
        malloc.free(input);
      }
    }
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    if (path.endsWith('.m3u8')) return 1;
    if (path.endsWith('.mpd')) return 2;
    if (path.endsWith('.mp4')) return 3;
    if (path.endsWith('.mkv')) return 4;
    if (path.endsWith('.webm')) return 5;
    if (path.endsWith('.mov')) return 6;
    if (path.endsWith('.avi')) return 7;
    if (path.endsWith('.m4v')) return 8;
    if (path.endsWith('.ts')) return 9;
    return 0;
  }

  static int qualityRank(String label) {
    _load();
    final function = _qualityRank;
    if (function != null) {
      final input = label.toNativeUtf8();
      try {
        return function(input);
      } finally {
        malloc.free(input);
      }
    }
    final normalized = label.trim().toLowerCase();
    if (normalized == '4k' || normalized == 'uhd') return 2160;
    if (normalized == '2k' || normalized == 'qhd') return 1440;
    final match = RegExp(r'(\d{3,4})\s*p?').firstMatch(normalized);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  static bool isValidHttpUrl(String value) {
    _load();
    final function = _validateUrl;
    if (function != null) {
      final input = value.toNativeUtf8();
      try {
        return function(input) == 1;
      } finally {
        malloc.free(input);
      }
    }
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  static String? get version {
    _load();
    final function = _version;
    if (function == null) return null;
    final pointer = function();
    if (pointer == nullptr) return null;
    try {
      return pointer.toDartString();
    } finally {
      _freeString?.call(pointer);
    }
  }

  static String playbackError(int code) {
    _load();
    final function = _playbackError;
    if (function == null) {
      return switch (code) {
        1 => 'Unsupported media format',
        2 => 'The video source is unavailable',
        3 => 'The connection timed out',
        4 => 'The stream was interrupted',
        5 => 'The video could not be decoded',
        6 => 'The server rejected the request',
        7 => 'The selected subtitle could not be loaded',
        _ => 'Playback failed. Please try another source',
      };
    }
    final pointer = function(code);
    if (pointer == nullptr) return 'Playback failed';
    try {
      return pointer.toDartString();
    } finally {
      _freeString?.call(pointer);
    }
  }
}
