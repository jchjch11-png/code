import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydration_app/app.dart';
import 'package:hydration_app/data/hydration_repository.dart';
import 'package:hydration_app/l10n/locale_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final now = DateTime(2026, 11, 25, 10);
  setUpAll(sqfliteFfiInit);

  test('locale resolution preserves scripts and follows preference order', () {
    expect(
      resolveAppLocale([const Locale('fr'), const Locale('ko')]),
      const Locale('ko'),
    );
    expect(resolveAppLocale([const Locale('zh', 'TW')]).scriptCode, 'Hant');
    expect(
      resolveAppLocale([
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'TW',
        ),
      ]).scriptCode,
      'Hans',
    );
    expect(resolveAppLocale([const Locale('fr')]), const Locale('en'));
    expect(parseMillilitres('२००'), 200);
    expect(parseMillilitres('２００'), 200);
    expect(parseMillilitres('0'), isNull);
    expect(parseMillilitres('20001'), isNull);
  });

  testWidgets('records two portions and restores data on app restart', (
    tester,
  ) async {
    final repository = await HydrationRepository.open(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
    await repository.updateGoal(1000, now: now);
    await repository.updateLocale('en');
    await tester.pumpWidget(
      HydrationApp(repository: repository, clock: () => now),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-200')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-100')));
    await tester.pumpAndSettle();
    expect(find.text('300 / 1,000 mL'), findsOneWidget);
    expect((await repository.day(now)).totalMl, 300);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      HydrationApp(repository: repository, clock: () => now),
    );
    await tester.pumpAndSettle();
    expect(find.text('300 / 1,000 mL'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await repository.close();
  });

  testWidgets('sets a first goal and saves a language choice', (tester) async {
    final repository = await HydrationRepository.open(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
    await repository.updateLocale('en');
    await tester.pumpWidget(
      HydrationApp(repository: repository, clock: () => now),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('set-goal')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount-input')), '1000');
    await tester.tap(find.byKey(const Key('save-amount')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect((await repository.day(now)).goalMl, 1000);
    expect(find.byKey(const Key('add-200')), findsOneWidget);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('한국어').last);
    await tester.pumpAndSettle();
    expect((await repository.settings()).localeTag, 'ko');
    expect(find.text('나의 하루 목표'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await repository.close();
  });

  for (final language in languageNames.keys) {
    testWidgets('$language renders today, calendar and language settings', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = await HydrationRepository.open(
        factory: databaseFactoryFfiNoIsolate,
        databasePath: inMemoryDatabasePath,
      );
      await repository.updateGoal(2000, now: now);
      await repository.updateLocale(language);
      await tester.pumpWidget(
        HydrationApp(repository: repository, clock: () => now),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('progress-summary')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.calendar_month));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(find.text(languageNames[language]!), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    });
  }
}
