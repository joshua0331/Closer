import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _enabledKey = 'closer_proximity_alerts_enabled';
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;
  bool _initialized = false;
  bool _enabled = false;

  Future<void> init() async {
    if (_initialized) return;
    final initializing = _initializing ??= _initialize();
    await initializing;
  }

  Future<void> _initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _notifications.initialize(settings);
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'closer_place_alerts',
        'Saved place alerts',
        description:
            'Alerts when your partner arrives at or leaves a saved place.',
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'closer_chat_messages',
        'Closer messages',
        description: 'New messages and session invitations from your partner.',
        importance: Importance.high,
      ),
    );
    final preferences = await SharedPreferences.getInstance();
    _enabled = preferences.getBool(_enabledKey) ?? false;
    _initialized = true;
  }

  Future<bool> isEnabled() async {
    await init();
    return _enabled;
  }

  Future<bool> enable() async {
    await init();
    if (kIsWeb) return false;
    bool granted = true;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      granted = await android?.requestNotificationsPermission() ?? true;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      granted =
          await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    _enabled = granted;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, granted);
    return granted;
  }

  Future<void> disable() async {
    await init();
    _enabled = false;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, false);
    await _notifications.cancel(888);
  }

  Future<void> showPartnerDistance(
    String partnerName,
    String distanceText, {
    String yourName = 'You',
    DateTime? anniversary,
    String? yourAvatar,
    String? partnerAvatar,
  }) async {
    await init();
    if (!_enabled || kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final today = DateTime.now();
      final days = anniversary == null
          ? null
          : DateTime(today.year, today.month, today.day)
                .difference(
                  DateTime(
                    anniversary.year,
                    anniversary.month,
                    anniversary.day,
                  ),
                )
                .inDays;
      await const MethodChannel('com.jcm.closer/distance')
          .invokeMethod('show', {
            'yourName': yourName,
            'partnerName': partnerName,
            'yourAvatar': yourAvatar,
            'partnerAvatar': partnerAvatar,
            'distance': distanceText,
            'together': days == null
                ? 'Together with you'
                : 'Together for ${days < 0 ? 0 : days} days',
          });
      return;
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'closer_distance_channel',
        'Closer distance updates',
        channelDescription:
            'Quiet alerts when your shared distance changes noticeably.',
        importance: Importance.low,
        priority: Priority.low,
        showWhen: false,
        ongoing: true,
        onlyAlertOnce: true,
        largeIcon: partnerAvatar == null
            ? null
            : FilePathAndroidBitmap(partnerAvatar),
        styleInformation: MessagingStyleInformation(
          Person(
            name: 'You',
            icon: yourAvatar == null
                ? null
                : BitmapFilePathAndroidIcon(yourAvatar),
          ),
          conversationTitle: 'Closer · Our distance',
          messages: [
            Message(
              distanceText,
              DateTime.now(),
              Person(
                name: partnerName,
                icon: partnerAvatar == null
                    ? null
                    : BitmapFilePathAndroidIcon(partnerAvatar),
              ),
            ),
          ],
        ),
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: false),
    );
    await _notifications.show(
      888,
      'Closer · Connected',
      'You & $partnerName · $distanceText',
      details,
    );
  }

  Future<void> showRemoteAlert(
    String title,
    String body, {
    bool chat = false,
    DateTime? sentAt,
  }) async {
    await init();
    if (kIsWeb) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        chat ? 'closer_chat_messages' : 'closer_place_alerts',
        chat ? 'Closer messages' : 'Saved place alerts',
        channelDescription: chat
            ? 'Messages and Metherapy invitations.'
            : 'Saved place alerts.',
        showWhen: true,
        when: (sentAt ?? DateTime.now()).millisecondsSinceEpoch,
        styleInformation: BigTextStyleInformation(body),
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch % 2147483647,
      title,
      body,
      details,
    );
  }

  Future<void> clearDistanceNotification() async {
    await _notifications.cancel(888);
  }
}
