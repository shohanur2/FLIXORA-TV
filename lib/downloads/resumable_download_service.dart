import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../native/rust_playback_core.dart';

typedef DownloadProgressCallback = void Function(int received, int total);

/// Resumable direct-file downloader. Range resume is enabled only when the
/// server confirms the requested byte range.
class ResumableDownloadService {
  ResumableDownloadService._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: Duration.zero,
      sendTimeout: const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 8,
    ),
  );

  static final Map<int, CancelToken> _active = <int, CancelToken>{};
  static final Map<int, String> _cancelReasons = <int, String>{};
  static const int maxConcurrentDownloads = 2;
  static int _runningDownloads = 0;
  static final Queue<_DownloadQueueTicket> _waiting =
      Queue<_DownloadQueueTicket>();

  static Future<bool> _acquireSlot(
    CancelToken token,
    void Function() onQueued,
  ) async {
    if (_runningDownloads < maxConcurrentDownloads) {
      _runningDownloads++;
      return true;
    }

    final ticket = _DownloadQueueTicket();
    _waiting.addLast(ticket);
    onQueued();

    token.whenCancel.then((_) {
      if (!ticket.ready.isCompleted) {
        ticket.cancelled = true;
        _waiting.remove(ticket);
        ticket.ready.complete();
      }
    });

    await ticket.ready.future;
    if (ticket.cancelled) return false;
    if (token.isCancelled) {
      _releaseSlot();
      return false;
    }
    return true;
  }

  static void _releaseSlot() {
    while (_waiting.isNotEmpty) {
      final next = _waiting.removeFirst();
      if (next.cancelled) continue;
      if (!next.ready.isCompleted) {
        next.ready.complete();
        return;
      }
    }
    if (_runningDownloads > 0) _runningDownloads--;
  }

  static String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  static String _extension(String url) {
    switch (RustPlaybackCore.detectStreamKind(url)) {
      case 3:
        return '.mp4';
      case 4:
        return '.mkv';
      case 5:
        return '.webm';
      case 6:
        return '.mov';
      case 7:
        return '.avi';
      case 8:
        return '.m4v';
      default:
        final uri = Uri.tryParse(url);
        final match = RegExp(r'\.(mp4|mkv|webm|mov|avi|m4v)$',
                caseSensitive: false)
            .firstMatch(uri?.path ?? '');
        return match?.group(0) ?? '.mp4';
    }
  }

  static Future<String> partialPath({
    required String url,
    required String fileName,
    required int uniqueId,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/${_safeName(fileName)}_$uniqueId${_extension(url)}.part';
  }

  static Future<void> download({
    required String url,
    required String fileName,
    required int uniqueId,
    Map<String, String> headers = const <String, String>{},
    String? existingPartialPath,
    required DownloadProgressCallback onProgress,
    required void Function(String path, int offset) onQueued,
    required void Function(String path, int offset) onStarted,
    required void Function(String path, int received, int total) onPaused,
    required Future<void> Function(String path) onComplete,
    required void Function(String message) onError,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !RustPlaybackCore.isValidHttpUrl(url)) {
      onError('Invalid download URL.');
      return;
    }

    final streamKind = RustPlaybackCore.detectStreamKind(url);
    if (streamKind == 1 || streamKind == 2) {
      onError(
        'This is an adaptive HLS/DASH stream. Choose a direct downloadable video source.',
      );
      return;
    }
    if (_active.containsKey(uniqueId)) {
      onError('This download is already active.');
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    final safeName = _safeName(fileName);
    final extension = _extension(url);
    final finalPath = '${directory.path}/${safeName}_$uniqueId$extension';
    final partPath = existingPartialPath ?? '$finalPath.part';
    final partFile = File(partPath);

    var offset = 0;
    if (await partFile.exists()) offset = await partFile.length();

    final token = CancelToken();
    _active[uniqueId] = token;
    _cancelReasons.remove(uniqueId);

    var hasSlot = false;
    var received = offset;
    var total = 0;
    IOSink? sink;

    try {
      hasSlot = await _acquireSlot(
        token,
        () => onQueued(partPath, offset),
      );
      if (!hasSlot) {
        if ((_cancelReasons[uniqueId] ?? '') == 'pause') {
          onPaused(partPath, offset, 0);
        } else {
          onError('Download cancelled.');
        }
        return;
      }
      onStarted(partPath, offset);

      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: <String, String>{
            ...headers,
            'Accept-Encoding': 'identity',
            if (offset > 0) 'Range': 'bytes=$offset-',
          },
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
        cancelToken: token,
      );

      final contentRange =
          response.headers.value('content-range')?.trim() ?? '';
      final rangeMatch =
          RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$').firstMatch(contentRange);

      if (offset > 0 && response.statusCode == 206) {
        final rangeStart = int.tryParse(rangeMatch?.group(1) ?? '');
        if (rangeStart != offset) {
          throw StateError('The server returned an invalid resume range.');
        }
        total = int.tryParse(rangeMatch?.group(3) ?? '') ?? 0;
      } else if (offset > 0 && response.statusCode == 200) {
        // The server ignored Range. Restart from byte zero to avoid corruption.
        offset = 0;
        received = 0;
      } else if (response.statusCode != 200 &&
          response.statusCode != 206) {
        throw StateError('The server returned HTTP ${response.statusCode}.');
      }

      final contentLength = int.tryParse(
            response.headers.value('content-length') ?? '',
          ) ??
          0;
      if (total <= 0) total = offset + contentLength;

      sink = partFile.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );

      final body = response.data;
      if (body == null) throw StateError('The server returned an empty body.');

      await for (final chunk in body.stream) {
        if (token.isCancelled) break;
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (token.isCancelled) {
        if ((_cancelReasons[uniqueId] ?? '') == 'pause') {
          onPaused(partPath, received, total);
        } else {
          onError('Download cancelled.');
        }
        return;
      }

      if (total > 0 && received < total) {
        throw StateError('The download ended before the file was complete.');
      }

      if (await File(finalPath).exists()) await File(finalPath).delete();
      final completedFile = await partFile.rename(finalPath);
      await onComplete(completedFile.path);
    } on DioException catch (error) {
      if (sink != null) {
        await sink.flush();
        await sink.close();
        sink = null;
      }
      if (token.isCancelled && (_cancelReasons[uniqueId] ?? '') == 'pause') {
        final size = await _existingLength(partPath);
        onPaused(partPath, size, total);
      } else {
        onError(
          error.type == DioExceptionType.connectionTimeout
              ? 'Connection timed out. You can retry this download.'
              : error.type == DioExceptionType.receiveTimeout
                  ? 'The server stopped sending data. You can resume the download.'
                  : 'Download failed. Check the connection and retry.',
        );
      }
    } catch (error) {
      if (sink != null) {
        await sink.flush();
        await sink.close();
      }
      onError(error is StateError
          ? error.message
          : 'Download failed. You can retry from the saved partial file.');
    } finally {
      if (hasSlot) _releaseSlot();
      _active.remove(uniqueId);
      _cancelReasons.remove(uniqueId);
    }
  }

  static Future<int> _existingLength(String path) async {
    try {
      final file = File(path);
      return await file.exists() ? await file.length() : 0;
    } catch (_) {
      return 0;
    }
  }

  static void pause(int uniqueId) {
    final token = _active[uniqueId];
    if (token == null) return;
    _cancelReasons[uniqueId] = 'pause';
    token.cancel('pause');
  }

  static void cancel(int uniqueId) {
    final token = _active[uniqueId];
    if (token == null) return;
    _cancelReasons[uniqueId] = 'cancel';
    token.cancel('cancel');
  }
}


class _DownloadQueueTicket {
  final Completer<void> ready = Completer<void>();
  bool cancelled = false;
}
