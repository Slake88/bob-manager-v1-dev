import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../repositories/activity_repository.dart';

class PushMessageEvent {
  const PushMessageEvent({
    required this.title,
    required this.body,
    this.actionRoute,
  });

  final String title;
  final String body;
  final String? actionRoute;
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final ActivityRepository _repository = ActivityRepository();
  final StreamController<PushMessageEvent> _foregroundController =
      StreamController<PushMessageEvent>.broadcast();
  final StreamController<String> _openedController =
      StreamController<String>.broadcast();

  bool _initialized = false;
  String? _initialActionRoute;

  Stream<PushMessageEvent> get foregroundMessages =>
      _foregroundController.stream;
  Stream<String> get openedRoutes => _openedController.stream;

  bool get configured => AppConfig.hasFirebaseConfiguration;

  Future<bool> initialize() async {
    if (_initialized) return configured;
    _initialized = true;
    if (AppConfig.demoMode || !configured) return false;
    if (_platformCode == null) return false;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: AppConfig.firebaseApiKey,
            appId: AppConfig.firebaseAppId,
            messagingSenderId: AppConfig.firebaseMessagingSenderId,
            projectId: AppConfig.firebaseProjectId,
            authDomain: AppConfig.firebaseAuthDomain.isEmpty
                ? null
                : AppConfig.firebaseAuthDomain,
            storageBucket: AppConfig.firebaseStorageBucket.isEmpty
                ? null
                : AppConfig.firebaseStorageBucket,
          ),
        );
      }

      final messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onMessage.listen((message) {
        final event = _eventFromMessage(message);
        _foregroundController.add(event);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final route = _actionRoute(message);
        if (route != null) _openedController.add(route);
      });
      messaging.onTokenRefresh.listen((token) async {
        try {
          await _registerToken(token);
        } catch (_) {
          // O próximo arranque volta a tentar sem bloquear a aplicação.
        }
      });

      final initial = await messaging.getInitialMessage();
      if (initial != null) _initialActionRoute = _actionRoute(initial);

      final settings = await messaging.getNotificationSettings();
      if (_isAuthorized(settings.authorizationStatus)) {
        await _registerCurrentToken();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermissionAndRegister() async {
    if (!await initialize()) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      if (!_isAuthorized(settings.authorizationStatus)) return false;
      await _registerCurrentToken();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isPermissionGranted() async {
    if (!configured || AppConfig.demoMode) return false;
    try {
      await initialize();
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      return _isAuthorized(settings.authorizationStatus);
    } catch (_) {
      return false;
    }
  }

  Future<void> disableCurrentDevice() async {
    if (!configured || AppConfig.demoMode) return;
    final deviceId = await _deviceId();
    try {
      await _repository.deactivatePushDevice(deviceId);
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // O estado local da caixa de notificações continua funcional.
    }
  }

  String? takeInitialActionRoute() {
    final result = _initialActionRoute;
    _initialActionRoute = null;
    return result;
  }

  Future<void> _registerCurrentToken() async {
    final messaging = FirebaseMessaging.instance;
    final token = await messaging.getToken(
      vapidKey: kIsWeb && AppConfig.firebaseVapidKey.isNotEmpty
          ? AppConfig.firebaseVapidKey
          : null,
    );
    if (token == null || token.trim().isEmpty) return;
    await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    final platform = _platformCode;
    if (platform == null) return;
    await _repository.registerPushDevice(
      platform: platform,
      deviceId: await _deviceId(),
      pushToken: token,
      appVersion: AppConfig.appVersion.isEmpty ? null : AppConfig.appVersion,
    );
  }

  Future<String> _deviceId() async {
    const key = 'bob_push_device_id';
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await preferences.setString(key, created);
    return created;
  }

  String? get _platformCode {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
  }

  bool _isAuthorized(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  PushMessageEvent _eventFromMessage(RemoteMessage message) {
    return PushMessageEvent(
      title: message.notification?.title ?? 'BOB Manager',
      body: message.notification?.body ?? 'Nova notificação',
      actionRoute: _actionRoute(message),
    );
  }

  String? _actionRoute(RemoteMessage message) {
    final route = message.data['action_route']?.toString().trim() ?? '';
    return route.isEmpty ? null : route;
  }
}
