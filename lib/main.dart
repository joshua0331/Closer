import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'screens/account_gate.dart';
import 'theme/closer_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: closerFirebaseOptions);
  final preferences = await SharedPreferences.getInstance();
  runApp(CloserApp(preferences: preferences));
}

class CloserApp extends StatelessWidget {
  const CloserApp({super.key, required this.preferences});
  final SharedPreferences preferences;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Closer',
    debugShowCheckedModeBanner: false,
    theme: buildCloserTheme(),
    home: AccountGate(preferences: preferences),
  );
}
