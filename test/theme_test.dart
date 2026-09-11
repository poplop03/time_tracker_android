import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tally/core/theme/organic_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final TextTheme text = buildOrganicTheme().textTheme;

  final Map<String, TextStyle?> headings = <String, TextStyle?>{
    'displayLarge': text.displayLarge,
    'displayMedium': text.displayMedium,
    'displaySmall': text.displaySmall,
    'headlineMedium': text.headlineMedium,
    'headlineSmall': text.headlineSmall,
  };

  final Map<String, TextStyle?> everything = <String, TextStyle?>{
    ...headings,
    'titleMedium': text.titleMedium,
    'titleSmall': text.titleSmall,
    'bodyLarge': text.bodyLarge,
    'bodyMedium': text.bodyMedium,
    'bodySmall': text.bodySmall,
    'labelLarge': text.labelLarge,
  };

  test('every style the app uses is set in Comfortaa', () {
    everything.forEach((String name, TextStyle? style) {
      expect(style?.fontFamily, startsWith('Comfortaa'), reason: name);
    });
  });

  test('headings use the bold cut', () {
    headings.forEach((String name, TextStyle? style) {
      expect(style?.fontWeight, FontWeight.w700, reason: name);
    });
  });

  test('body text stays above regular weight on the cream ground', () {
    for (final TextStyle? style in <TextStyle?>[
      text.bodyLarge,
      text.bodyMedium,
      text.bodySmall,
    ]) {
      expect(style!.fontWeight!.value, greaterThanOrEqualTo(500));
    }
  });
}
