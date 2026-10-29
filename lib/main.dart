import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/couple_store.dart';
import 'screens/couple_home.dart';
import 'theme/us_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(CloserApp(store: CoupleStore(preferences)));
}

class CloserApp extends StatelessWidget {
  const CloserApp({super.key, required this.store});
  final CoupleStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Closer',
    debugShowCheckedModeBanner: false,
    theme: buildCloserTheme(),
    home: CoupleHome(store: store),
  );
}
