import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

ThemeData buildCloserTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'CoupleSans',
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF18F77)),
  scaffoldBackgroundColor: const Color(0xFFFFF9F0),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: Color(0xFF424A52),
    centerTitle: true,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    systemOverlayStyle: SystemUiOverlayStyle.dark,
  ),
  cardTheme: CardThemeData(
    color: const Color(0xFFFFFDF9),
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: const Color(0xFFB85842),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
    ),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
    filled: true,
    fillColor: Colors.white,
  ),
);
