import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'localization/closer_localizations.dart';
import 'screens/account_gate.dart';
import 'screens/app_loading.dart';
import 'services/notification_service.dart';
import 'theme/closer_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFFFF9F0),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const CloserApp());
}

class CloserApp extends StatefulWidget {
  const CloserApp({super.key});

  @override
  State<CloserApp> createState() => _CloserAppState();
}

class _CloserAppState extends State<CloserApp> {
  late Future<SharedPreferences> _startup;
  StreamSubscription<RemoteMessage>? _foregroundMessages;

  @override
  void initState() {
    super.initState();
    _startup = _initialize();
  }

  Future<SharedPreferences> _initialize() async {
    await Firebase.initializeApp(options: closerFirebaseOptions);
    await NotificationService.instance.init();
    _foregroundMessages ??= FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification != null) {
        NotificationService.instance.showRemoteAlert(
          notification.title ?? 'Closer · Place alert',
          notification.body ?? 'You have a new update from your partner.',
          chat: message.data['type'] == 'chat',
        );
      }
    });
    final preferences = await SharedPreferences.getInstance();
    await CloserLocaleController.load(preferences);
    return preferences;
  }

  void _retry() => setState(() => _startup = _initialize());

  @override
  void dispose() {
    _foregroundMessages?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Locale>(
    valueListenable: CloserLocaleController.locale,
    builder: (context, locale, _) => MaterialApp(
      title: 'Closer',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: CloserLocaleController.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildCloserTheme(),
      home: FutureBuilder<SharedPreferences>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return AccountGate(preferences: snapshot.data!);
          }
          return CloserLoadingScreen(
            error: snapshot.hasError
                ? 'Closer could not finish loading.'
                : null,
            onRetry: snapshot.hasError ? _retry : null,
          );
        },
      ),
    ),
  );
}
