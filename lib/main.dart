import 'package:flutter/material.dart';

import 'ui/home_page.dart';
import 'ui/theme.dart';

void main() {
  runApp(const DatalogViewerApp());
}

class DatalogViewerApp extends StatelessWidget {
  const DatalogViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4EA1FF),
        brightness: Brightness.dark,
      ),
    );

    return MaterialApp(
      title: 'Datalog Viewer',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: kBackground,
        dividerColor: kBorder,
        dividerTheme: const DividerThemeData(color: kBorder, space: 1),
      ),
      home: const HomePage(),
    );
  }
}
