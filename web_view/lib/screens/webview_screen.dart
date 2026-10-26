import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/gyroscope_service.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.url, this.serverUrl});

  final String url;
  final String? serverUrl;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  late final GyroscopeService _gyroscope;
  StreamSubscription<GyroReading>? _frameSubscription;

  final ValueNotifier<GyroReading?> _latestReading =
      ValueNotifier<GyroReading?>(null);

  bool _pageReady = false;
  bool _isLoading = true;
  int _progress = 0;
  String? _loadError;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            _pageReady = false;
            if (mounted) {
              setState(() {
                _isLoading = true;
                _progress = 0;
                _loadError = null;
              });
            }
          },
          onProgress: (int progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
          onPageFinished: (String url) {
            _pageReady = true;
            if (mounted) {
              setState(() {
                _isLoading = false;
                _progress = 100;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame ?? true) {
              _pageReady = false;
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _loadError = error.description;
                });
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    _gyroscope = GyroscopeService(serverUrl: widget.serverUrl)..start();
    _frameSubscription = _gyroscope.frames.listen(_onReading);
  }

  void _onReading(GyroReading reading) {
    _latestReading.value = reading;
    if (!_pageReady) {
      return;
    }
    _controller.runJavaScript(_gyroScript(reading)).ignore();
  }

  String _gyroScript(GyroReading reading) {
    final String timestamp = reading.timestamp.toUtc().toIso8601String();
    return '''
(function () {
  var data = {
    x: ${reading.x},
    y: ${reading.y},
    z: ${reading.z},
    timestamp: '$timestamp'
  };
  window.__gyroData = data;
  if (typeof window.onGyroscope === 'function') {
    try { window.onGyroscope(data); } catch (e) {}
  }
  try {
    window.dispatchEvent(new CustomEvent('gyroscope', { detail: data }));
  } catch (e) {}
})();
''';
  }

  Future<void> _reload() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
      _progress = 0;
    });
    await _controller.reload();
  }

  void _exit() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _frameSubscription?.cancel();
    unawaited(_gyroscope.dispose());
    _latestReading.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 64, left: 16, right: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress > 0 && _progress < 100
                          ? _progress / 100
                          : null,
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              minimum: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _HudButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back to URL',
                    onTap: _exit,
                  ),
                  const SizedBox(width: 10),
                  _HudButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Reload page',
                    onTap: _reload,
                  ),
                  const Spacer(),
                  ValueListenableBuilder<GyroReading?>(
                    valueListenable: _latestReading,
                    builder:
                        (
                          BuildContext context,
                          GyroReading? reading,
                          Widget? child,
                        ) {
                          return _GyroHud(
                            reading: reading,
                            hasServer: widget.serverUrl != null,
                          );
                        },
                  ),
                ],
              ),
            ),
          ),
          if (_loadError != null)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141B30),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 40,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Could not load page',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          OutlinedButton(
                            onPressed: _exit,
                            child: const Text('Change URL'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: _reload,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _GyroHud extends StatelessWidget {
  const _GyroHud({required this.reading, required this.hasServer});

  final GyroReading? reading;
  final bool hasServer;

  @override
  Widget build(BuildContext context) {
    final bool live = reading != null;
    final Color accent = live
        ? const Color(0xFF00E5A0)
        : const Color(0xFFFFB300);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.7),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                live ? 'GYRO LIVE' : 'WAITING',
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              if (hasServer) ...<Widget>[
                const SizedBox(width: 10),
                Icon(
                  Icons.cloud_upload_outlined,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reading == null
                ? 'x  --     y  --     z  --'
                : 'x ${reading!.x.toStringAsFixed(2)}   '
                      'y ${reading!.y.toStringAsFixed(2)}   '
                      'z ${reading!.z.toStringAsFixed(2)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
