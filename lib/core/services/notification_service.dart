import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/subscription_local.dart';

class NotificationService {
  NotificationService();

  static const String _channelId = 'renewal_reminders';
  static const String _channelName = 'Renewal reminders';
  static const String _channelDescription =
      'Alerts before a subscription renews.';

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Local hour of day at which reminders fire.
  static const int reminderHour = 9;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void>? _initializing;

  /// Idempotent: safe to call more than once.
  Future<void> init() => _initializing ??= _init();

  Future<void> _init() async {
    tzdata.initializeTimeZones();
    try {
      final zoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zoneName));
    } catch (e) {
      debugPrint(
        'NotificationService: timezone lookup failed ($e); using UTC.',
      );
      tz.setLocalLocation(tz.UTC);
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
  }

  /// Ask for notification + exact-alarm permission. Call once the UI is up,
  /// not before the first frame.
  Future<bool> requestPermissions() async {
    await init();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    var granted = true;
    if (android != null) {
      granted = await android.requestNotificationsPermission() ?? false;
      if (await android.canScheduleExactNotifications() != true) {
        await android.requestExactAlarmsPermission();
      }
    }
    if (ios != null) {
      granted =
          await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return granted;
  }

  /// Deterministic 31-bit id derived from the subscription uuid, so a
  /// reminder can be cancelled or replaced without storing its id.
  static int notificationIdFor(String uuid) {
    var hash = 0x811C9DC5; // FNV-1a
    for (final unit in uuid.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  /// The moment the reminder should fire: [reminderHour] local time,
  /// `reminderDaysBefore` days before the billing date.
  tz.TZDateTime reminderTimeFor(SubscriptionLocal sub) {
    final due = sub.nextBillingDate;
    return tz.TZDateTime(
      tz.local,
      due.year,
      due.month,
      due.day - sub.reminderDaysBefore,
      reminderHour,
    );
  }

  /// Schedules (or replaces) the reminder for [sub].
  /// Returns false when the reminder time has already passed.
  Future<bool> scheduleRenewalReminder(SubscriptionLocal sub) async {
    await init();

    final id = notificationIdFor(sub.uuid);
    await _plugin.cancel(id);

    final fireAt = reminderTimeFor(sub);
    if (!fireAt.isAfter(tz.TZDateTime.now(tz.local))) return false;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final canExact = await android?.canScheduleExactNotifications() ?? true;

    final days = sub.reminderDaysBefore;
    final when = switch (days) {
      0 => 'today',
      1 => 'tomorrow',
      _ => 'in $days days',
    };
    final amount = NumberFormat.simpleCurrency().format(sub.cost);

    await _plugin.zonedSchedule(
      id,
      '${sub.name} renews $when',
      '$amount will be charged on '
          '${DateFormat.MMMd().format(sub.nextBillingDate)}.',
      fireAt,
      _details,
      androidScheduleMode: canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: sub.uuid,
    );
    return true;
  }

  Future<void> cancelReminder(String uuid) async {
    await init();
    await _plugin.cancel(notificationIdFor(uuid));
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}
