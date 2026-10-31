import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'screens/account_gate.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/couple_store.dart';
import 'screens/couple_home.dart';
import 'theme/closer_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  try {
    await Firebase.initializeApp(options: closerFirebaseOptions);
    runApp(CloserApp(store: CoupleStore(preferences), connected: true));
  } catch (_) {
    runApp(
      MaterialApp(
        theme: buildCloserTheme(),
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Could not start Closer. Check your internet connection and restart the app.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CloserApp extends StatelessWidget {
  const CloserApp({super.key, required this.store, this.connected = false});
  final CoupleStore store;
  final bool connected;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Closer',
    debugShowCheckedModeBanner: false,
    theme: buildCloserTheme(),
    home: connected
        ? AccountGate(preferences: store.preferences)
        : CoupleHome(store: store),
  );
}
