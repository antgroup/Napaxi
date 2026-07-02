import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart' as share;
import 'package:webview_flutter/webview_flutter.dart';

class WebPreviewPage extends StatefulWidget {
  const WebPreviewPage({
    super.key,
    required this.displayUrl,
    this.title = 'Preview',
    this.initialUrl,
    this.initialFilePath,
    this.shareText,
    this.shareFilePath,
    this.shareFileName,
    this.shareFileMimeType,
  }) : assert(
         initialUrl != null || initialFilePath != null,
         'Provide either initialUrl or initialFilePath.',
       );

  final String title;
  final String displayUrl;
  final Uri? initialUrl;
  final String? initialFilePath;

  /// Plain-text payload to share (e.g. a web URL). Mutually useful with
  /// [shareFilePath]; when both are null no share action is shown.
  final String? shareText;

  /// Local file path to share as a file (e.g. a generated HTML document).
  final String? shareFilePath;
  final String? shareFileName;
  final String? shareFileMimeType;

  @override
  State<WebPreviewPage> createState() => _WebPreviewPageState();
}

class _WebPreviewPageState extends State<WebPreviewPage> {
  late final WebViewController _controller;
  var _progress = 0;
  String? _blockedNavigation;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) => setState(() => _progress = progress),
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            final scheme = uri?.scheme;
            final allowed =
                scheme == 'http' ||
                scheme == 'https' ||
                scheme == 'file' ||
                scheme == 'about' ||
                scheme == 'data';
            if (!allowed) {
              setState(() => _blockedNavigation = request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Web preview failed: ${error.description}'),
              ),
            );
          },
        ),
      );
    final initialUrl = widget.initialUrl;
    if (initialUrl != null) {
      _controller.loadRequest(initialUrl);
    } else {
      _controller.loadFile(widget.initialFilePath!);
    }
  }

  Future<void> _shareFile() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final name = widget.shareFileName ?? widget.title;
    await share.Share.shareXFiles(
      [
        share.XFile(
          widget.shareFilePath!,
          name: name,
          mimeType: widget.shareFileMimeType,
        ),
      ],
      subject: name,
      sharePositionOrigin: origin,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.shareFilePath != null)
            IconButton(
              tooltip: 'Share',
              onPressed: _shareFile,
              icon: const Icon(Icons.ios_share_rounded),
            )
          else if (widget.shareText != null)
            IconButton(
              tooltip: 'Share',
              onPressed: () => share.Share.share(widget.shareText!),
              icon: const Icon(Icons.ios_share_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            key: const Key('web_preview_address_bar'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFFF9FAFB),
            child: Text(
              widget.displayUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF4B5563), fontSize: 12),
            ),
          ),
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          if (_blockedNavigation != null)
            MaterialBanner(
              content: Text('Blocked unsupported link: $_blockedNavigation'),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _blockedNavigation = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
