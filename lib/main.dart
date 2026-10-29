import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Test build: the viewer prototype (assets/viewer/index.html) inside a
/// full-screen WebView, with the phone's own file picker behind "Open log…".
///
/// The native Flutter viewer in lib/ui is not wired in for this build.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The viewer is landscape-only, and only the two landscape directions.
  await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const ViewerTestApp());
}

class ViewerTestApp extends StatelessWidget {
  const ViewerTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'PWP datalogger',
      debugShowCheckedModeBanner: false,
      home: ViewerPage(),
    );
  }
}

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0D0F12));

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setAllowFileAccess(true);
      platform.setOnShowFileSelector(_pickFiles);
    }
    _controller.loadFlutterAsset('assets/viewer/index.html');
  }

  /// Answers the page's <input type="file"> with the system file picker.
  /// Any file type is allowed: logs come as .hpl, .ld, .xrk, .ftml, … which
  /// Android does not know.
  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    final List<XFile> files;
    if (params.mode == FileSelectorMode.openMultiple) {
      files = await openFiles();
    } else {
      final file = await openFile();
      files = file == null ? const <XFile>[] : <XFile>[file];
    }
    return files.map((f) => File(f.path).uri.toString()).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F12),
      body: WebViewWidget(controller: _controller),
    );
  }
}
