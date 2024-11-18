import 'package:easy_localization/easy_localization.dart';
import 'package:fimber/fimber.dart';
import 'package:flutter/widgets.dart';

import 'plural_rules.dart';
import 'translations.dart';

class Localization {
  Translations? _translations, _fallbackTranslations;
  late Locale _locale;
  late List<Locale> _supportedLocales;
  late bool Function() _reportUntranslatedCallback;

  final RegExp _replaceArgRegex = RegExp('{}');
  final RegExp _linkKeyMatcher =
      RegExp(r'(?:@(?:\.[a-z]+)?:(?:[\w\-_|.]+|\([\w\-_|.]+\)))');
  final RegExp _linkKeyPrefixMatcher = RegExp(r'^@(?:\.([a-z]+))?:');
  final RegExp _bracketsMatcher = RegExp('[()]');
  final _modifiers = <String, String Function(String?)>{
    'upper': (String? val) => val!.toUpperCase(),
    'lower': (String? val) => val!.toLowerCase(),
    'capitalize': (String? val) => '${val![0].toUpperCase()}${val.substring(1)}'
  };

  Localization();

  static Localization? _instance;
  static Localization get instance => _instance ?? (_instance = Localization());
  static Localization? of(BuildContext context) =>
      Localizations.of<Localization>(context, Localization);

  static bool load(Locale locale, {
    required List<Locale> supportedLocales,
    Translations? translations,
    Translations? fallbackTranslations,
    required bool Function() reportUntranslatedCallback,
  }) {
    instance._locale = locale;
    instance._supportedLocales = supportedLocales;
    instance._translations = translations;
    instance._fallbackTranslations = fallbackTranslations;
    instance._reportUntranslatedCallback = reportUntranslatedCallback;
    return translations == null ? false : true;
  }

  String tr(
    String key, {
    List<String>? args,
    Map<String, String>? namedArgs,
    String? gender,
  }) {
    late String res;

    if (gender != null) {
      res = _gender(key, gender: gender);
    } else {
      res = _resolve(key);
    }

    res = _replaceLinks(res);

    res = _replaceNamedArgs(res, namedArgs);

    return _replaceArgs(res, args);
  }

  String _replaceLinks(String res, {bool logging = true}) {
    // TODO: add recursion detection and a resolve stack.
    final matches = _linkKeyMatcher.allMatches(res);
    var result = res;

    for (final match in matches) {
      final link = match[0]!;
      final linkPrefixMatches = _linkKeyPrefixMatcher.allMatches(link);
      final linkPrefix = linkPrefixMatches.first[0]!;
      final formatterName = linkPrefixMatches.first[1];

      // Remove the leading @:, @.case: and the brackets
      final linkPlaceholder =
          link.replaceAll(linkPrefix, '').replaceAll(_bracketsMatcher, '');

      var translated = _resolve(linkPlaceholder);

      if (formatterName != null) {
        if (_modifiers.containsKey(formatterName)) {
          translated = _modifiers[formatterName]!(translated);
        } else {
          if (logging) {
            Fimber.w(
              'Undefined modifier $formatterName, available modifiers: ${_modifiers.keys.toString()}',
              stacktrace: StackTrace.current,
            );
          }
        }
      }

      result =
          translated.isEmpty ? result : result.replaceAll(link, translated);
    }

    return result;
  }

  String _replaceArgs(String res, List<String>? args) {
    if (args == null || args.isEmpty) return res;
    for (var str in args) {
      res = res.replaceFirst(_replaceArgRegex, trNum(str));
    }
    return res;
  }

  String _replaceNamedArgs(String res, Map<String, String>? args) {
    if (args == null || args.isEmpty) return res;
    args.forEach((String key, String value) =>
        res = res.replaceAll(RegExp('{$key}'), trNum(value)));
    return res;
  }

  static PluralRule? _pluralRule(String? locale, num howMany) {
    startRuleEvaluation(howMany);
    return pluralRules[locale];
  }

  String plural(
    String key,
    num value, {
    List<String>? args,
    Map<String, String>? namedArgs,
    String? name,
    NumberFormat? format,
  }) {
    late PluralCase pluralCase;
    late String res;
    var pluralRule = _pluralRule(_locale.languageCode, value);
    switch (value) {
      case 0:
        pluralCase = PluralCase.ZERO;
        break;
      case 1:
        pluralCase = PluralCase.ONE;
        break;
      case 2:
        pluralCase = PluralCase.TWO;
        break;
      default:
        pluralCase = pluralRule!();
    }
    switch (pluralCase) {
      case PluralCase.ZERO:
        res = _resolvePlural(key, 'zero');
        break;
      case PluralCase.ONE:
        res = _resolvePlural(key, 'one');
        break;
      case PluralCase.TWO:
        res = _resolvePlural(key, 'two');
        break;
      case PluralCase.FEW:
        res = _resolvePlural(key, 'few');
        break;
      case PluralCase.MANY:
        res = _resolvePlural(key, 'many');
        break;
      case PluralCase.OTHER:
        res = _resolvePlural(key, 'other');
        break;
      default:
        throw ArgumentError.value(value, 'howMany', 'Invalid plural argument');
    }

    final formattedValue = format == null ? '$value' : format.format(value);

    if (name != null) {
      namedArgs = {...?namedArgs, name: formattedValue};
    }
    res = _replaceNamedArgs(res, namedArgs);

    return _replaceArgs(res, args ?? [formattedValue]);
  }

  String _gender(String key, {required String gender}) {
    return _resolve('$key.$gender');
  }

  String _resolvePlural(String key, String subKey) {
    if (subKey == 'other') return _resolve('$key.other');

    final tag = '$key.$subKey';
    var resource = _resolve(tag, logging: false, fallback: false);
    if (resource == tag) {
      resource = _resolve('$key.other');
    }
    return resource;
  }

  String _resolve(String key, {bool logging = true, bool fallback = true}) {
    var resource = _translations?.get(key);
    var l = logging && _reportUntranslatedCallback();
    if (l && _supportedLocales.length < 2) {
      l = false;
    }
    if (resource == null) {
      if (l) {
        Fimber.w('Localization key [$key] not found');
      }
      if (_fallbackTranslations == null || !fallback) {
        return key;
      } else {
        resource = _fallbackTranslations?.get(key);
        if (resource == null) {
          if (l) {
            Fimber.w('Fallback localization key [$key] not found');
          }
          return key;
        }
      }
    }
    return resource;
  }

  String trNum(String value) {
    switch (_locale.languageCode) {
      case 'ar':
      // Arabic digits
        return value
            .replaceAll('0', '٠')
            .replaceAll('1', '١')
            .replaceAll('2', '٢')
            .replaceAll('3', '٣')
            .replaceAll('4', '٤')
            .replaceAll('5', '٥')
            .replaceAll('6', '٦')
            .replaceAll('7', '٧')
            .replaceAll('8', '٨')
            .replaceAll('9', '٩');
      case 'fa':
      // Persian digits
      // !! All charcodes are different from the arabic ones. Do not combine Arabic and Persian digits in one number!!
        return value
            .replaceAll('0', '۰')
            .replaceAll('1', '۱')
            .replaceAll('2', '۲')
            .replaceAll('3', '۳')
            .replaceAll('4', '۴')
            .replaceAll('5', '۵')
            .replaceAll('6', '۶')
            .replaceAll('7', '۷')
            .replaceAll('8', '۸')
            .replaceAll('9', '۹');
      default:
        return value;
    }
  }
}
