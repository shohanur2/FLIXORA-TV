import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android Picture-in-Picture bridge. Other platforms safely no-op.
class PictureInPictureService {
  PictureInPictureService._();

  static const MethodChannel _channel =
      MethodChannel('com.flixora.flixora/pip');

  static Future<void> setEnabled(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('setEnabled', <String, Object>{
        'enabled': enabled,
      });
    } on PlatformException {
      // PiP is optional; playback must continue if the OS rejects it.
    } on MissingPluginException {
      // Older installed builds do not have the native bridge yet.
    }
  }
}
