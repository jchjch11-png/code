import 'dart:async';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'data/hydration_repository.dart';
import 'domain/models.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/locale_settings.dart';
import 'platform/hydration_notifications.dart';

int? parseMillilitres(String input) {
  final normalized = String.fromCharCodes(
    input.trim().runes.map((rune) {
      for (final zero in [0x0966, 0x0660, 0x06f0, 0xff10]) {
        if (rune >= zero && rune <= zero + 9) return 0x30 + rune - zero;
      }
      return rune;
    }),
  );
  final amount = int.tryParse(normalized);
  return amount != null && amount >= 1 && amount <= 20000 ? amount : null;
}

class HydrationApp extends StatefulWidget {
  const HydrationApp({
    super.key,
    required this.repository,
    this.notifications,
    this.clock = DateTime.now,
  });

  final HydrationRepository repository;
  final HydrationNotifications? notifications;
  final DateTime Function() clock;

  @override
  State<HydrationApp> createState() => _HydrationAppState();
}

class _HydrationAppState extends State<HydrationApp>
    with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  AppSettings _settings = const AppSettings();
  DaySummary? _today;
  DaySummary? _selectedDay;
  late DateTime _selectedDate;
  Timer? _dayTimer;
  int _tab = 0;
  bool _busy = false;
  bool _loadFailed = false;

  Locale get _effectiveLocale =>
      localeForTag(_settings.localeTag) ??
      resolveAppLocale(PlatformDispatcher.instance.locales);

  AppLocalizations get _strings => lookupAppLocalizations(_effectiveLocale);

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.clock();
    WidgetsBinding.instance.addObserver(this);
    widget.notifications?.onChanged = () => unawaited(_reload());
    widget.notifications?.onError = () => _message(_strings.genericError);
    unawaited(_start());
    _dayTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_today?.dayKey != localDayKey(widget.clock())) {
        unawaited(_reload());
      }
    });
  }

  Future<void> _start() async {
    await _reload();
    if (!mounted) return;
    try {
      await widget.notifications?.configure(_strings);
      await widget.notifications?.cancelIfComplete();
    } catch (_) {
      _message(_strings.reminderFailed);
    }
  }

  Future<void> _reload() async {
    try {
      final now = widget.clock();
      final settings = await widget.repository.settings();
      final today = await widget.repository.day(now);
      final selected = localDayKey(_selectedDate) == today.dayKey
          ? today
          : await widget.repository.day(_selectedDate);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _today = today;
        _selectedDay = selected;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reload());
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_settings.localeTag == null) {
      setState(() {});
      unawaited(_refreshNotificationLanguage());
    }
  }

  Future<void> _refreshNotificationLanguage() async {
    try {
      await widget.notifications?.refreshLanguage(_strings);
    } catch (_) {
      _message(_strings.reminderFailed);
    }
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.notifications?.onChanged = null;
    widget.notifications?.onError = null;
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;
    _messenger.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
    } catch (_) {
      _message(_strings.genericError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    try {
      await widget.notifications?.cancelIfComplete();
    } catch (_) {
      _message(_strings.reminderFailed);
    }
  }

  Future<void> _record(int amount) => _perform(
    () => widget.repository.addIntake(
      id: const Uuid().v4(),
      amountMl: amount,
      at: widget.clock(),
    ),
  );

  Future<void> _amountDialog(BuildContext context, {bool goal = false}) async {
    final strings = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: goal ? _today?.goalMl?.toString() ?? '' : '',
    );
    final form = GlobalKey<FormState>();
    final amount = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(goal ? strings.goalPrompt : strings.customAmount),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (goal) ...[Text(strings.goalHelp), const SizedBox(height: 16)],
              TextFormField(
                key: const Key('amount-input'),
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9०-९٠-٩۰-۹０-９]'),
                  ),
                ],
                decoration: InputDecoration(
                  labelText: strings.amountHint,
                  hintText: goal ? strings.goalHint : null,
                  border: const OutlineInputBorder(),
                ),
                validator: (text) => parseMillilitres(text ?? '') == null
                    ? strings.invalidAmount
                    : null,
              ),
              if (goal) ...[
                const SizedBox(height: 12),
                Text(strings.goalAppliesToday),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('save-amount'),
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, parseMillilitres(controller.text));
              }
            },
            child: Text(strings.save),
          ),
        ],
      ),
    );
    // The dialog's reverse transition must finish before its controller dies.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (amount == null || !mounted) return;
    if (goal) {
      await _perform(
        () => widget.repository.updateGoal(amount, now: widget.clock()),
      );
    } else {
      await _record(amount);
    }
  }

  Future<void> _remind() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.notifications?.scheduleDemo(_strings);
      _message(switch (result) {
        ReminderScheduleResult.scheduled => _strings.reminderScheduled,
        ReminderScheduleResult.denied => _strings.permissionDenied,
        _ => _strings.reminderFailed,
      });
    } catch (_) {
      _message(_strings.reminderFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    scaffoldMessengerKey: _messenger,
    locale: localeForTag(_settings.localeTag),
    supportedLocales: supportedAppLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    localeListResolutionCallback: (preferred, supported) =>
        resolveAppLocale(preferred),
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff147c77)),
      scaffoldBackgroundColor: const Color(0xfff4f8f5),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: Builder(
      builder: (context) {
        final strings = AppLocalizations.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(strings.appTitle),
            actions: [
              IconButton(
                tooltip: strings.language,
                onPressed: () => setState(() => _tab = 2),
                icon: const Icon(Icons.language),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: _loadFailed
                    ? Center(
                        child: TextButton(
                          onPressed: _reload,
                          child: Text(strings.genericError),
                        ),
                      )
                    : _today == null
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: switch (_tab) {
                          0 => _todayPage(context, strings),
                          1 => _calendarPage(context, strings),
                          _ => _settingsPage(context, strings),
                        },
                      ),
              ),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (value) => setState(() => _tab = value),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.water_drop_outlined),
                label: strings.today,
              ),
              NavigationDestination(
                icon: const Icon(Icons.calendar_month),
                label: strings.calendar,
              ),
              NavigationDestination(
                icon: const Icon(Icons.tune),
                label: strings.settings,
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _todayPage(BuildContext context, AppLocalizations strings) {
    final today = _today!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          DateFormat.yMMMMd(Localizations.localeOf(context).toString())
              .format(widget.clock()),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        _progressCard(context, strings, today),
        const SizedBox(height: 20),
        if (today.goalMl == null)
          FilledButton.icon(
            key: const Key('set-goal'),
            onPressed: _busy ? null : () => _amountDialog(context, goal: true),
            icon: const Icon(Icons.flag_outlined),
            label: Text(strings.goalPrompt),
          )
        else ...[
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final amount in [200, 100])
                FilledButton.icon(
                  key: Key('add-$amount'),
                  onPressed: _busy ? null : () => _record(amount),
                  icon: const Icon(Icons.add),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(strings.amountMl(amount)),
                  ),
                ),
              OutlinedButton(
                onPressed: _busy ? null : () => _amountDialog(context),
                child: Text(strings.customAmount),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.reminderTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(strings.reminderHelp),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed:
                        _busy ||
                            today.remainingMl == 0 ||
                            widget.notifications == null
                        ? null
                        : _remind,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: Text(strings.reminderDemo),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(strings.history, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (today.entries.isEmpty) Text(strings.noEntries),
        for (final entry in today.entries)
          Card(
            child: ListTile(
              leading: const Icon(Icons.water_drop_outlined),
              title: Text(strings.amountMl(entry.amountMl)),
              subtitle: Text(
                MaterialLocalizations.of(context).formatTimeOfDay(
                  TimeOfDay.fromDateTime(entry.at.toLocal()),
                  alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                    context,
                  ),
                ),
              ),
              trailing: IconButton(
                tooltip: strings.delete,
                onPressed: _busy
                    ? null
                    : () => _perform(
                        () => widget.repository.deleteIntake(entry.id),
                      ),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
      ],
    );
  }

  Widget _progressCard(
    BuildContext context,
    AppLocalizations strings,
    DaySummary day,
  ) {
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 132,
                height: 160,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.07),
                  border: Border.all(
                    color: color.withValues(alpha: 0.3),
                    width: 3,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                    bottom: Radius.circular(44),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      height: 160 * day.progress,
                      color: color.withValues(alpha: 0.6),
                    ),
                    const Center(
                      child: Icon(
                        Icons.water_drop,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              day.goalMl == null
                  ? strings.goalNotSet
                  : strings.progressSummary(day.totalMl, day.goalMl!),
              key: const Key('progress-summary'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (day.goalMl != null) ...[
              const SizedBox(height: 8),
              Text(
                day.remainingMl == 0
                    ? strings.complete
                    : strings.remainingMl(day.remainingMl),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: day.progress,
                semanticsLabel: strings.progressSummary(
                  day.totalMl,
                  day.goalMl!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _calendarPage(BuildContext context, AppLocalizations strings) {
    final day = _selectedDay!;
    final label = switch (day.rewardTier) {
      RewardTier.none => strings.noReward,
      RewardTier.quirky => strings.rewardQuirky,
      RewardTier.cute => strings.rewardCute,
      RewardTier.special => strings.rewardSpecial,
    };
    return Column(
      children: [
        CalendarDatePicker(
          initialDate: _selectedDate,
          firstDate: DateTime(widget.clock().year - 2),
          lastDate: widget.clock(),
          onDateChanged: (value) {
            _selectedDate = value;
            unawaited(_reload());
          },
        ),
        const SizedBox(height: 16),
        _progressCard(context, strings, day),
        const SizedBox(height: 16),
        Text(
          strings.stickerPreview,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (day.rewardTier != RewardTier.none)
          Text(
            switch (day.rewardTier) {
              RewardTier.quirky => '🐣',
              RewardTier.cute => '🌷',
              _ => '🌟',
            },
            style: const TextStyle(fontSize: 64),
            semanticsLabel: label,
          ),
        Text(label),
      ],
    );
  }

  Widget _settingsPage(
    BuildContext context,
    AppLocalizations strings,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(strings.language, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: ValueKey('language-${_settings.localeTag}'),
        initialValue: _settings.localeTag ?? 'system',
        isExpanded: true,
        decoration: InputDecoration(labelText: strings.language),
        items: [
          DropdownMenuItem(
            value: 'system',
            child: Text(strings.systemLanguage),
          ),
          for (final language in languageNames.entries)
            DropdownMenuItem(value: language.key, child: Text(language.value)),
        ],
        onChanged: _busy
            ? null
            : (tag) async {
                await _perform(
                  () => widget.repository.updateLocale(
                    tag == 'system' ? null : tag,
                  ),
                );
                await _refreshNotificationLanguage();
              },
      ),
      const SizedBox(height: 28),
      Text(strings.goalTitle, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(strings.goalHelp),
      const SizedBox(height: 16),
      if (_today?.goalMl case final goal?) Text(strings.amountMl(goal)),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _amountDialog(context, goal: true),
        icon: const Icon(Icons.edit_outlined),
        label: Text(strings.editGoal),
      ),
    ],
  );
}
