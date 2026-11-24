import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite/sqflite.dart'
    show
        ConflictAlgorithm,
        Database,
        DatabaseExecutor,
        DatabaseFactory,
        OpenDatabaseOptions;

import '../domain/models.dart';

class HydrationRepository {
  HydrationRepository._(this._db);

  static const _supportedLocales = {
    'en',
    'zh-Hans',
    'zh-Hant',
    'ja',
    'ko',
    'hi',
  };
  static const _reminderEntryPrefix = 'reminder:';
  static final _dayKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  final Database _db;

  static Future<HydrationRepository> open({
    DatabaseFactory? factory,
    String? databasePath,
  }) async {
    final databaseFactory = factory ?? sqflite.databaseFactory;
    final database = await databaseFactory.openDatabase(
      databasePath ??
          path.join(await databaseFactory.getDatabasesPath(), 'hydration.db'),
      options: OpenDatabaseOptions(version: 1, onCreate: _createSchema),
    );
    return HydrationRepository._(database);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        goal_ml INTEGER,
        locale_tag TEXT
      )
    ''');
    await db.insert('settings', {'id': 1});
    await db.execute('''
      CREATE TABLE goal_history (
        day_key TEXT PRIMARY KEY,
        goal_ml INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE daily_ledger (
        day_key TEXT PRIMARY KEY,
        goal_ml INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE intake_entries (
        id TEXT PRIMARY KEY,
        amount_ml INTEGER NOT NULL CHECK (amount_ml > 0),
        at_utc_us INTEGER NOT NULL,
        offset_minutes INTEGER NOT NULL,
        day_key TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        source_occurrence_id TEXT UNIQUE
      )
    ''');
    await db.execute('''
      CREATE INDEX intake_entries_by_day
      ON intake_entries (day_key, deleted, at_utc_us)
    ''');
    await db.execute('''
      CREATE TABLE reminders (
        id TEXT PRIMARY KEY,
        revision INTEGER NOT NULL CHECK (revision >= 0),
        day_key TEXT NOT NULL,
        scheduled_at_utc_us INTEGER NOT NULL,
        amount_ml INTEGER NOT NULL CHECK (amount_ml > 0),
        state TEXT NOT NULL CHECK (state IN ('pending', 'consumed', 'cancelled'))
      )
    ''');
    await db.execute('''
      CREATE INDEX reminders_by_day
      ON reminders (day_key, state, scheduled_at_utc_us)
    ''');
  }

  Future<AppSettings> settings() async {
    final row = (await _db.query('settings')).single;
    return AppSettings(
      goalMl: row['goal_ml'] as int?,
      localeTag: row['locale_tag'] as String?,
    );
  }

  Future<void> updateGoal(int goalMl, {required DateTime now}) async {
    _validateAmount(goalMl, 'goalMl');
    final dayKey = localDayKey(now);
    await _db.transaction((txn) async {
      await txn.update('settings', {'goal_ml': goalMl}, where: 'id = 1');
      await txn.insert('goal_history', {
        'day_key': dayKey,
        'goal_ml': goalMl,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('daily_ledger', {
        'day_key': dayKey,
        'goal_ml': goalMl,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> updateLocale(String? localeTag) async {
    if (localeTag != null && !_supportedLocales.contains(localeTag)) {
      throw ArgumentError.value(localeTag, 'localeTag', 'Unsupported locale');
    }
    await _db.update('settings', {'locale_tag': localeTag}, where: 'id = 1');
  }

  Future<DaySummary> day(DateTime now) async {
    final dayKey = localDayKey(now);
    return _db.transaction((txn) async {
      final goal = await _goalForDay(txn, dayKey);
      final rows = await txn.query(
        'intake_entries',
        where: 'day_key = ? AND deleted = 0',
        whereArgs: [dayKey],
        orderBy: 'at_utc_us DESC, id ASC',
      );
      return DaySummary(
        dayKey: dayKey,
        goalMl: goal,
        entries: List.unmodifiable(rows.map(_readIntake)),
      );
    });
  }

  Future<void> addIntake({
    required String id,
    required int amountMl,
    required DateTime at,
  }) async {
    if (id.trim().isEmpty || id.startsWith(_reminderEntryPrefix)) {
      throw ArgumentError.value(id, 'id', 'Invalid manual intake identifier');
    }
    _validateAmount(amountMl, 'amountMl');
    final dayKey = localDayKey(at);
    await _db.transaction((txn) async {
      final existing = await _findById(txn, 'intake_entries', id);
      if (existing != null) return;

      if (await _goalForDay(txn, dayKey) == null) {
        throw StateError('An intake requires a daily goal');
      }
      await _insertIntake(
        txn,
        id: id,
        amountMl: amountMl,
        at: at,
        dayKey: dayKey,
      );
    });
  }

  Future<void> deleteIntake(String id) async {
    await _db.update(
      'intake_entries',
      {'deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> saveReminder(ReminderOccurrence occurrence) async {
    if (occurrence.id.trim().isEmpty) {
      throw ArgumentError.value(occurrence.id, 'id', 'Expected an identifier');
    }
    if (occurrence.revision < 0) {
      throw ArgumentError.value(
        occurrence.revision,
        'revision',
        'Expected a nonnegative revision',
      );
    }
    _validateAmount(occurrence.amountMl, 'amountMl');
    final date = DateTime.tryParse(occurrence.dayKey);
    if (!_dayKeyPattern.hasMatch(occurrence.dayKey) ||
        date == null ||
        localDayKey(date) != occurrence.dayKey) {
      throw ArgumentError.value(
        occurrence.dayKey,
        'dayKey',
        'Expected a calendar date',
      );
    }

    await _db.transaction((txn) async {
      final existing = await _findById(txn, 'reminders', occurrence.id);
      if (existing != null &&
          (existing['state'] == 'consumed' ||
              (existing['revision'] as int) >= occurrence.revision)) {
        return;
      }

      await txn.insert('reminders', {
        'id': occurrence.id,
        'revision': occurrence.revision,
        'day_key': occurrence.dayKey,
        'scheduled_at_utc_us': occurrence.scheduledAt.microsecondsSinceEpoch,
        'amount_ml': occurrence.amountMl,
        'state': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<ConsumeResult> consumeReminder({
    required String id,
    required int revision,
    required bool half,
    required DateTime now,
  }) async {
    final dayKey = localDayKey(now);
    return _db.transaction((txn) async {
      final row = await _findById(txn, 'reminders', id);
      if (row == null) return ConsumeResult.invalid;
      if (row['revision'] != revision) return ConsumeResult.expired;
      if (row['state'] == 'consumed') return ConsumeResult.duplicate;
      if (row['day_key'] != dayKey || row['state'] == 'cancelled') {
        return ConsumeResult.expired;
      }

      if (await _goalForDay(txn, dayKey) == null) return ConsumeResult.invalid;

      final amount = row['amount_ml'] as int;
      await _insertIntake(
        txn,
        id: '$_reminderEntryPrefix$id',
        amountMl: half ? (amount + 1) ~/ 2 : amount,
        at: now,
        dayKey: dayKey,
        sourceOccurrenceId: id,
      );
      await txn.update(
        'reminders',
        {'state': 'consumed'},
        where: 'id = ?',
        whereArgs: [id],
      );
      return ConsumeResult.recorded;
    });
  }

  Future<List<ReminderOccurrence>> pendingReminders(String dayKey) async {
    final rows = await _db.query(
      'reminders',
      where: "day_key = ? AND state = 'pending'",
      whereArgs: [dayKey],
      orderBy: 'scheduled_at_utc_us ASC, id ASC',
    );
    return List.unmodifiable(rows.map(_readReminder));
  }

  Future<void> cancelPendingReminders(String dayKey) async {
    await _db.update(
      'reminders',
      {'state': 'cancelled'},
      where: "day_key = ? AND state = 'pending'",
      whereArgs: [dayKey],
    );
  }

  Future<void> close() => _db.close();

  static void _validateAmount(int amount, String parameter) {
    RangeError.checkValueInInterval(amount, 1, 20000, parameter);
  }

  static Future<int?> _goalForDay(DatabaseExecutor db, String dayKey) async {
    final ledger = await _findById(
      db,
      'daily_ledger',
      dayKey,
      column: 'day_key',
    );
    if (ledger != null) return ledger['goal_ml'] as int;

    final history = await db.query(
      'goal_history',
      columns: ['goal_ml'],
      where: 'day_key <= ?',
      whereArgs: [dayKey],
      orderBy: 'day_key DESC',
      limit: 1,
    );
    if (history.isEmpty) return null;

    final goal = history.single['goal_ml'] as int;
    await db.insert('daily_ledger', {'day_key': dayKey, 'goal_ml': goal});
    return goal;
  }

  static Future<Map<String, Object?>?> _findById(
    DatabaseExecutor db,
    String table,
    String id, {
    String column = 'id',
  }) async {
    final rows = await db.query(
      table,
      where: '$column = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  static Future<void> _insertIntake(
    DatabaseExecutor db, {
    required String id,
    required int amountMl,
    required DateTime at,
    required String dayKey,
    String? sourceOccurrenceId,
  }) async {
    await db.insert('intake_entries', {
      'id': id,
      'amount_ml': amountMl,
      'at_utc_us': at.microsecondsSinceEpoch,
      'offset_minutes': at.toLocal().timeZoneOffset.inMinutes,
      'day_key': dayKey,
      'source_occurrence_id': sourceOccurrenceId,
    });
  }

  static IntakeEntry _readIntake(Map<String, Object?> row) => IntakeEntry(
    id: row['id'] as String,
    amountMl: row['amount_ml'] as int,
    at: _readUtc(row['at_utc_us'] as int),
    dayKey: row['day_key'] as String,
    deleted: row['deleted'] == 1,
  );

  static ReminderOccurrence _readReminder(Map<String, Object?> row) =>
      ReminderOccurrence(
        id: row['id'] as String,
        revision: row['revision'] as int,
        dayKey: row['day_key'] as String,
        scheduledAt: _readUtc(row['scheduled_at_utc_us'] as int),
        amountMl: row['amount_ml'] as int,
      );

  static DateTime _readUtc(int microseconds) =>
      DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
}
