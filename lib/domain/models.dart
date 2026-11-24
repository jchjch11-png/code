class AppSettings {
  const AppSettings({this.goalMl, this.localeTag});

  final int? goalMl;
  final String? localeTag;
}

class IntakeEntry {
  const IntakeEntry({
    required this.id,
    required this.amountMl,
    required this.at,
    required this.dayKey,
    this.deleted = false,
  });

  final String id;
  final int amountMl;
  final DateTime at;
  final String dayKey;
  final bool deleted;
}

enum RewardTier { none, quirky, cute, special }

class DaySummary {
  const DaySummary({
    required this.dayKey,
    required this.goalMl,
    required this.entries,
  });

  final String dayKey;
  final int? goalMl;
  final List<IntakeEntry> entries;

  int get totalMl => entries.fold(
    0,
    (total, entry) => entry.deleted ? total : total + entry.amountMl,
  );

  int get remainingMl {
    final remaining = (goalMl ?? 0) - totalMl;
    return remaining > 0 ? remaining : 0;
  }

  double get progress {
    final goal = goalMl;
    if (goal == null || goal <= 0) return 0;
    return (totalMl / goal).clamp(0.0, 1.0).toDouble();
  }

  RewardTier get rewardTier {
    final goal = goalMl;
    if (goal == null || goal <= 0) return RewardTier.none;

    final total = totalMl;
    if (total >= goal) return RewardTier.special;
    if (total * 5 >= goal * 4) return RewardTier.cute;
    if (total * 2 >= goal) return RewardTier.quirky;
    return RewardTier.none;
  }
}

class ReminderOccurrence {
  const ReminderOccurrence({
    required this.id,
    required this.revision,
    required this.dayKey,
    required this.scheduledAt,
    required this.amountMl,
  });

  final String id;
  final int revision;
  final String dayKey;
  final DateTime scheduledAt;
  final int amountMl;
}

enum ConsumeResult { recorded, duplicate, expired, invalid }

String localDayKey(DateTime time) {
  final local = time.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
