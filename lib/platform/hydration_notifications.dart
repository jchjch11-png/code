import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../data/hydration_repository.dart';
import '../domain/models.dart';
import '../l10n/generated/app_localizations.dart';

const _fullAction = 'drink_full';
const _halfAction = 'drink_half';
const _category = 'hydration_drink';
const _notificationId = 1001;

enum ReminderScheduleResult { scheduled, denied, notNeeded }

/// The OS starts a separate engine for an action that does not open the app.
@pragma('vm:entry-point')
void hydrationNotificationBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final repository = await HydrationRepository.open();
  await consumeNotificationResponse(repository, response);
  // Do not close a shared sqflite connection also used by the foreground engine.
  final today = await repository.day(DateTime.now());
  if (today.goalMl != null && today.remainingMl == 0) {
    await repository.cancelPendingReminders(today.dayKey);
    await FlutterLocalNotificationsPlugin().cancelAll();
  }
}

Future<void> consumeNotificationResponse(
  HydrationRepository repository,
  NotificationResponse response,
) async {
  if (response.actionId != _fullAction && response.actionId != _halfAction) {
    return;
  }
  Object? data;
  try {
    data = jsonDecode(response.payload ?? '');
  } on FormatException {
    return;
  }
  if (data is! Map<String, dynamic> ||
      data['id'] is! String ||
      data['revision'] is! int) {
    return;
  }
  await repository.consumeReminder(
    id: data['id'] as String,
    revision: data['revision'] as int,
    half: response.actionId == _halfAction,
    now: DateTime.now(),
  );
}

class HydrationNotifications {
  HydrationNotifications(this.repository);

  final HydrationRepository repository;
  final _plugin = FlutterLocalNotificationsPlugin();
  VoidCallback? onChanged;
  VoidCallback? onError;
  bool _launchHandled = false;

  Future<void> configure(AppLocalizations strings, {int? amountMl}) async {
    final pending = await repository.pendingReminders(
      localDayKey(DateTime.now()),
    );
    final actionAmount = amountMl ?? pending.firstOrNull?.amountMl ?? 200;
    tz_data.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_water'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _category,
              actions: [
                DarwinNotificationAction.plain(
                  _fullAction,
                  strings.reminderFull(actionAmount),
                ),
                DarwinNotificationAction.plain(
                  _halfAction,
                  strings.reminderHalf((actionAmount + 1) ~/ 2),
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: (response) async {
        try {
          await consumeNotificationResponse(repository, response);
          await cancelIfComplete();
          onChanged?.call();
        } catch (_) {
          onError?.call();
        }
      },
      onDidReceiveBackgroundNotificationResponse:
          hydrationNotificationBackground,
    );
    if (!_launchHandled) {
      _launchHandled = true;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.notificationResponse case final response?) {
        await consumeNotificationResponse(repository, response);
        onChanged?.call();
      }
    }
  }

  Future<ReminderScheduleResult> scheduleDemo(AppLocalizations strings) async {
    final initialDay = await repository.day(DateTime.now());
    if (initialDay.goalMl == null || initialDay.remainingMl == 0) {
      return ReminderScheduleResult.notNeeded;
    }
    await configure(strings);
    final granted = Platform.isAndroid
        ? await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission()
        : await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: true);
    if (granted != true) return ReminderScheduleResult.denied;
    // The permission dialog can stay open across minutes or midnight.
    final now = DateTime.now();
    final today = await repository.day(now);
    if (today.goalMl == null || today.remainingMl == 0) {
      return ReminderScheduleResult.notNeeded;
    }
    final amount = today.remainingMl.clamp(1, 200);
    await configure(strings, amountMl: amount);
    final scheduledAt = now.add(const Duration(minutes: 1));
    // This first prototype schedules within the current local calendar day.
    if (localDayKey(scheduledAt) != today.dayKey) {
      return ReminderScheduleResult.notNeeded;
    }
    await _plugin.cancelAll();
    await repository.cancelPendingReminders(today.dayKey);
    final occurrence = ReminderOccurrence(
      id: const Uuid().v4(),
      revision: 1,
      dayKey: today.dayKey,
      scheduledAt: scheduledAt,
      amountMl: amount,
    );
    await repository.saveReminder(occurrence);
    await _schedule(occurrence, strings);
    return ReminderScheduleResult.scheduled;
  }

  Future<void> _schedule(
    ReminderOccurrence occurrence,
    AppLocalizations strings,
  ) => _plugin.zonedSchedule(
    id: _notificationId,
    title: strings.reminderTitle,
    body: strings.reminderBody(occurrence.amountMl),
    scheduledDate: tz.TZDateTime.from(occurrence.scheduledAt, tz.local),
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'hydration_reminders',
        strings.reminderTitle,
        importance: Importance.high,
        priority: Priority.high,
        actions: [
          AndroidNotificationAction(
            _fullAction,
            strings.reminderFull(occurrence.amountMl),
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            _halfAction,
            strings.reminderHalf((occurrence.amountMl + 1) ~/ 2),
            cancelNotification: true,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(categoryIdentifier: _category),
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    payload: jsonEncode({'id': occurrence.id, 'revision': occurrence.revision}),
  );

  Future<void> cancelIfComplete() async {
    final today = await repository.day(DateTime.now());
    if (today.goalMl != null && today.remainingMl == 0) {
      await repository.cancelPendingReminders(today.dayKey);
      await _plugin.cancelAll();
    }
  }

  Future<void> refreshLanguage(AppLocalizations strings) async {
    final now = DateTime.now();
    final pending = await repository.pendingReminders(localDayKey(now));
    await configure(strings, amountMl: pending.firstOrNull?.amountMl ?? 200);
    await cancelIfComplete();
    for (final previous in pending) {
      if (!previous.scheduledAt.isAfter(now)) continue;
      final today = await repository.day(now);
      if (today.remainingMl == 0) break;
      final updated = ReminderOccurrence(
        id: previous.id,
        revision: previous.revision + 1,
        dayKey: previous.dayKey,
        scheduledAt: previous.scheduledAt,
        amountMl: previous.amountMl,
      );
      await repository.saveReminder(updated);
      await _schedule(updated, strings);
    }
  }
}
