import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'provider_catalog.dart';

/// A dedicated in-app surface for provider-owned HTTPS embed players.
/// Direct MP4/HLS playback continues to use FLIXORA's existing media_kit player.
class ProviderEmbedPlayer extends StatefulWidget {
  const ProviderEmbedPlayer({
    super.key,
    required this.source,
    required this.onClose,
    required this.onFailure,
  });

  final ProviderEmbedSource source;
  final VoidCallback onClose;
  final VoidCallback onFailure;

  @override
  State<ProviderEmbedPlayer> createState() => _ProviderEmbedPlayerState();
}

class _ProviderEmbedPlayerState extends State<ProviderEmbedPlayer> {
  late final WebViewController _controller;
  bool _isLoading = true;
  int _progress = 0;
  bool _showingFullscreenWidget = false;
  bool _failureReported = false;
  bool _disposed = false;
  Timer? _loadTimeout;
  String? _errorMessage;

  void _startLoadTimeout() {
    _loadTimeout?.cancel();
    _loadTimeout = Timer(const Duration(seconds: 30), () {
      if (!mounted || _disposed || _failureReported) return;
      _reportProviderFailure(
        'This provider took too long to open. Trying another available stream.',
      );
    });
  }

  void _cancelLoadTimeout() {
    _loadTimeout?.cancel();
    _loadTimeout = null;
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    _configureAndLoad();
  }

  Future<void> _configureAndLoad() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (widget.source.loadInIframe) {
        await _controller.addJavaScriptChannel(
          'FlixoraBridge',
          onMessageReceived: (message) {
            if (message.message == 'exit' && mounted && !_disposed) {
              widget.onClose();
            }
          },
        );
      }
      await _controller.setBackgroundColor(Colors.black);
      await _controller.enableZoom(false);
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted || _disposed || _failureReported) return;
            _cancelLoadTimeout();
            setState(() {
              _isLoading = false;
              _progress = 100;
            });
          },
          onWebResourceError: (error) {
            if (!mounted || _disposed || error.isForMainFrame == false) return;
            _reportProviderFailure(
              'This provider page could not load. Check your internet connection or try another stream.',
            );
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
              return NavigationDecision.prevent;
            }

            // Providers commonly host the player in a separate HTTPS iframe.
            // Permit secure subframes, but keep top-level navigation on the
            // selected provider's approved domain.
            if (!request.isMainFrame) {
              return uri.scheme.toLowerCase() == 'https'
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            }

            return ProviderCatalog.allowsNavigation(widget.source, uri)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );

      final platformController = _controller.platform;
      if (platformController is AndroidWebViewController) {
        // Provider embeds often use cross-site player iframes and cookies.
        final cookieManager = WebViewCookieManager().platform;
        if (cookieManager is AndroidWebViewCookieManager) {
          await cookieManager.setAcceptThirdPartyCookies(platformController, true);
        }
        await platformController.setUseWideViewPort(true);
        await platformController.setMediaPlaybackRequiresUserGesture(false);
        await platformController.setCustomWidgetCallbacks(
          onShowCustomWidget: (customWidget, onCustomWidgetHidden) {
            if (!mounted || _disposed || _showingFullscreenWidget) {
              onCustomWidgetHidden();
              return;
            }
            _showingFullscreenWidget = true;
            unawaited(SystemChrome.setPreferredOrientations([
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]));
            unawaited(SystemChrome.setEnabledSystemUIMode(
              SystemUiMode.immersiveSticky,
            ));
            Navigator.of(context)
                .push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => Scaffold(
                      backgroundColor: Colors.black,
                      body: SizedBox.expand(child: customWidget),
                    ),
                  ),
                )
                .whenComplete(() {
                  _showingFullscreenWidget = false;
                  unawaited(SystemChrome.setPreferredOrientations([
                    DeviceOrientation.portraitUp,
                  ]));
                  unawaited(SystemChrome.setEnabledSystemUIMode(
                    SystemUiMode.edgeToEdge,
                  ));
                  // Notify Android that the custom video view is now removed.
                  onCustomWidgetHidden();
                });
          },
          onHideCustomWidget: () {
            if (!mounted || !_showingFullscreenWidget) return;
            _showingFullscreenWidget = false;
            Navigator.of(context).maybePop();
            unawaited(SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
            ]));
            unawaited(SystemChrome.setEnabledSystemUIMode(
              SystemUiMode.edgeToEdge,
            ));
          },
        );
      }

      _startLoadTimeout();
      if (widget.source.loadInIframe) {
        // VidRift documents iframe embedding as its supported integration.
        // Keep it inside FLIXORA's WebView so its full player controls and
        // episode navigation work without opening an external browser.
        final html = '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#000}
iframe{position:fixed;inset:0;width:100%;height:100%;border:0;background:#000}
</style>
</head>
<body>
<iframe src="${widget.source.url}" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>
<script>
window.addEventListener('message', function(event) {
  if (event.origin !== 'https://embed.vidrift.net' &&
      event.origin !== 'https://embed.vidrift.in') return;
  if (event.data && event.data.type === 'vidrift:exit') {
    FlixoraBridge.postMessage('exit');
  }
});
</script>
</body>
</html>
''';
        await _controller.loadHtmlString(html);
      } else {
        await _controller.loadRequest(Uri.parse(widget.source.url));
      }
    } catch (_) {
      if (!mounted) return;
      _reportProviderFailure(
        'Could not start ' + widget.source.name + '. Try another available stream.',
      );
    }
  }

  void _reportProviderFailure(String message) {
    if (!mounted || _disposed || _failureReported) return;
    _cancelLoadTimeout();
    setState(() {
      _isLoading = false;
      _errorMessage = message;
    });
    _failureReported = true;
    widget.onFailure();
  }

  Future<void> _retry() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _progress = 0;
      _errorMessage = null;
      _failureReported = false;
    });
    _startLoadTimeout();
    try {
      await _controller.reload();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Retry failed. Please choose another stream.';
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelLoadTimeout();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress / 100 : null,
                minHeight: 2,
                backgroundColor: Colors.white12,
                color: const Color(0xFFE50914),
              ),
            ),
          Positioned(
            top: 7,
            left: 8,
            right: 8,
            child: Row(
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: Text(
                        widget.source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _controlButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Reload stream',
                  onPressed: _retry,
                ),
                const SizedBox(width: 5),
                _controlButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Back to FLIXORA player',
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          if (_errorMessage != null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.88),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          color: Color(0xFFE50914),
                          size: 38,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 19),
      ),
    );
  }
}
