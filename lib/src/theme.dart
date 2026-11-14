import 'package:flutter/material.dart';

/// Material 3 in the brand's two colours: black and white, with greys
/// for surfaces. Errors keep a red so a failed payment never looks like
/// a successful one.
ThemeData nullTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final ink = dark ? Colors.white : Colors.black;
  final paper = dark ? Colors.black : Colors.white;
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.grey,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
  ).copyWith(primary: ink, onPrimary: paper, surface: paper, onSurface: ink);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: paper,
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}
