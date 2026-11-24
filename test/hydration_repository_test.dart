import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hydration_app/data/hydration_repository.dart';
import 'package:hydration_app/domain/models.dart';

void main() {
  late Directory directory;
  late String databasePath;
  late HydrationRepository repository;
  final today = DateTime(2026, 7, 16, 10, 30);
  final tomorrow = DateTime(2026, 7, 17, 10, 30);

  ReminderOccurrence reminder({
    String id = 'cup',
    int revision = 1,
    DateTime? date,
    int amountMl = 251,
  }) {
    final scheduledAt = date ?? today;
    return ReminderOccurrence(
      id: id,
      revision: revision,
      dayKey: localDayKey(scheduledAt),
      scheduledAt: scheduledAt,
      amountMl: amountMl,
    );
  }

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hydration_test_');
    databasePath = path.join(directory.path, 'hydration.db');
    repository = await HydrationRepository.open(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
  });

  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  test('rejects intake without a goal and validates settings', () async {
    expect((await repository.settings()).goalMl, isNull);
    expect((await repository.day(today)).goalMl, isNull);
    await expectLater(
      repository.addIntake(id: 'manual', amountMl: 150, at: today),
      throwsStateError,
    );
    for (final amount in [0, -1, 20001]) {
      await expectLater(
        repository.updateGoal(amount, now: today),
        throwsRangeError,
      );
    }
    await expectLater(repository.updateLocale('fr'), throwsArgumentError);
    await repository.updateLocale('zh-Hant');
    expect((await repository.settings()).localeTag, 'zh-Hant');
    await repository.updateLocale(null);
    expect((await repository.settings()).localeTag, isNull);
  });

  test('keeps past goals and applies new goals starting today', () async {
    final earlier = DateTime(2026, 7, 14, 10);
    final unvisited = DateTime(2026, 7, 15, 10);
    await repository.updateGoal(1000, now: earlier);
    await repository.addIntake(id: 'old', amountMl: 800, at: earlier);
    expect((await repository.day(earlier)).rewardTier, RewardTier.cute);

    await repository.updateGoal(1800, now: today);
    expect((await repository.settings()).goalMl, 1800);
    expect((await repository.day(today)).goalMl, 1800);
    expect((await repository.day(tomorrow)).goalMl, 1800);
    expect((await repository.day(unvisited)).goalMl, 1000);
    expect((await repository.day(earlier)).goalMl, 1000);
    expect((await repository.day(earlier)).rewardTier, RewardTier.cute);

    await repository.updateGoal(1600, now: today);
    expect((await repository.day(today)).goalMl, 1600);
    expect((await repository.day(earlier)).goalMl, 1000);
  });

  test(
    'manual retries preserve the original intake and its tombstone',
    () async {
      await repository.updateGoal(1000, now: today);
      final nextDay = DateTime(2026, 7, 17);
      final at = nextDay.subtract(const Duration(microseconds: 1));

      await repository.addIntake(id: 'manual', amountMl: 125, at: at.toUtc());
      await repository.addIntake(id: 'manual', amountMl: 500, at: nextDay);
      final entry = (await repository.day(today)).entries.single;
      expect(entry.amountMl, 125);
      expect(entry.at, at.toUtc());
      expect(entry.dayKey, '2026-07-16');
      expect((await repository.day(nextDay)).entries, isEmpty);

      await repository.deleteIntake('manual');
      await repository.addIntake(id: 'manual', amountMl: 125, at: at);
      expect((await repository.day(today)).totalMl, 0);
      expect((await repository.day(today)).entries, isEmpty);
    },
  );

  test('calculates reward boundaries and retains over-goal totals', () async {
    await repository.updateGoal(1000, now: today);
    final cases = {
      499: RewardTier.none,
      500: RewardTier.quirky,
      799: RewardTier.quirky,
      800: RewardTier.cute,
      999: RewardTier.cute,
      1000: RewardTier.special,
      1001: RewardTier.special,
    };

    for (final MapEntry(key: amount, value: tier) in cases.entries) {
      final id = amount.toString();
      await repository.addIntake(id: id, amountMl: amount, at: today);
      final summary = await repository.day(today);
      expect(summary.totalMl, amount);
      expect(summary.rewardTier, tier);
      if (amount < 1000) {
        expect(summary.progress, lessThan(1));
        expect(summary.remainingMl, 1000 - amount);
      } else {
        expect(summary.progress, 1);
        expect(summary.remainingMl, 0);
      }
      await repository.deleteIntake(id);
    }
    expect((await repository.day(today)).rewardTier, RewardTier.none);
  });

  test('rounds half cups and consumes competing actions only once', () async {
    await repository.updateGoal(1000, now: today);
    await repository.saveReminder(reminder());
    final results = await Future.wait([
      repository.consumeReminder(
        id: 'cup',
        revision: 1,
        half: true,
        now: today,
      ),
      repository.consumeReminder(
        id: 'cup',
        revision: 1,
        half: false,
        now: today,
      ),
    ]);

    expect(
      results,
      unorderedEquals([ConsumeResult.recorded, ConsumeResult.duplicate]),
    );
    final entry = (await repository.day(today)).entries.single;
    expect(entry.amountMl, results.first == ConsumeResult.recorded ? 126 : 251);
    await repository.deleteIntake(entry.id);
    await repository.saveReminder(reminder(revision: 2));
    expect(await repository.pendingReminders(localDayKey(today)), isEmpty);
    expect(
      await repository.consumeReminder(
        id: 'cup',
        revision: 1,
        half: true,
        now: today,
      ),
      ConsumeResult.duplicate,
    );
    expect((await repository.day(today)).entries, isEmpty);
  });

  test(
    'rejects unknown, stale, past, future, and cancelled occurrences',
    () async {
      await repository.updateGoal(1000, now: today);
      await repository.saveReminder(reminder(revision: 2));
      await repository.saveReminder(reminder(revision: 1, amountMl: 100));
      await repository.saveReminder(
        reminder(id: 'past', date: DateTime(2026, 7, 15)),
      );
      await repository.saveReminder(reminder(id: 'future', date: tomorrow));

      Future<ConsumeResult> consume(String id, int revision) => repository
          .consumeReminder(id: id, revision: revision, half: true, now: today);

      final active = (await repository.pendingReminders(localDayKey(today)))
          .single;
      expect(active.revision, 2);
      expect(active.amountMl, 251);
      expect(await consume('unknown', 1), ConsumeResult.invalid);
      expect(await consume('cup', 1), ConsumeResult.expired);
      expect(await consume('past', 1), ConsumeResult.expired);
      expect(await consume('future', 1), ConsumeResult.expired);

      await repository.cancelPendingReminders(localDayKey(today));
      await repository.saveReminder(reminder(revision: 2));
      expect(await consume('cup', 2), ConsumeResult.expired);
      expect((await repository.day(today)).entries, isEmpty);
      expect(await repository.pendingReminders(localDayKey(today)), isEmpty);
      expect(
        await repository.pendingReminders(localDayKey(tomorrow)),
        hasLength(1),
      );
    },
  );

  test('rolls back intake if updating the reminder state fails', () async {
    await repository.updateGoal(1000, now: today);
    await repository.saveReminder(reminder());
    final database = await databaseFactoryFfi.openDatabase(databasePath);
    await database.execute('''
      CREATE TRIGGER fail_reminder_update
      BEFORE UPDATE ON reminders
      BEGIN
        SELECT RAISE(ABORT, 'test failure');
      END
    ''');

    Future<ConsumeResult> consume() => repository.consumeReminder(
      id: 'cup',
      revision: 1,
      half: true,
      now: today,
    );

    await expectLater(consume(), throwsA(isA<DatabaseException>()));
    expect((await repository.day(today)).entries, isEmpty);
    expect(await repository.pendingReminders(localDayKey(today)), hasLength(1));
    await database.execute('DROP TRIGGER fail_reminder_update');

    expect(await consume(), ConsumeResult.recorded);
    expect((await repository.day(today)).entries.single.amountMl, 126);
  });

  test(
    'restores settings, entries and reminder state after reopening',
    () async {
      await repository.updateGoal(1000, now: today);
      await repository.updateLocale('hi');
      await repository.addIntake(id: 'manual', amountMl: 300, at: today);
      await repository.saveReminder(reminder());
      expect(
        await repository.consumeReminder(
          id: 'cup',
          revision: 1,
          half: true,
          now: today,
        ),
        ConsumeResult.recorded,
      );
      await repository.saveReminder(reminder(id: 'tomorrow', date: tomorrow));
      await repository.close();
      repository = await HydrationRepository.open(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );

      final settings = await repository.settings();
      expect(settings.goalMl, 1000);
      expect(settings.localeTag, 'hi');
      expect((await repository.day(today)).totalMl, 426);
      expect(await repository.pendingReminders(localDayKey(today)), isEmpty);
      expect(
        (await repository.pendingReminders(localDayKey(tomorrow))).single.id,
        'tomorrow',
      );
      expect(
        await repository.consumeReminder(
          id: 'cup',
          revision: 1,
          half: false,
          now: today,
        ),
        ConsumeResult.duplicate,
      );
    },
  );
}
