import 'package:flutter/widgets.dart';

const supportedAppLocales = [
  Locale('en'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  Locale('ja'),
  Locale('ko'),
  Locale('hi'),
];

const languageNames = {
  'en': 'English',
  'zh-Hans': '简体中文',
  'zh-Hant': '繁體中文',
  'ja': '日本語',
  'ko': '한국어',
  'hi': 'हिन्दी',
};

Locale? localeForTag(String? tag) {
  for (final locale in supportedAppLocales) {
    if (locale.toLanguageTag() == tag) return locale;
  }
  return null;
}

Locale resolveAppLocale(List<Locale>? preferred) {
  for (final locale in preferred ?? const <Locale>[]) {
    if (locale.languageCode == 'zh') {
      final script = locale.scriptCode;
      final traditional =
          script == 'Hant' ||
          (script != 'Hans' &&
              const ['TW', 'HK', 'MO'].contains(locale.countryCode));
      return supportedAppLocales[traditional ? 2 : 1];
    }
    for (final supported in supportedAppLocales) {
      if (supported.languageCode == locale.languageCode) return supported;
    }
  }
  return supportedAppLocales.first;
}
