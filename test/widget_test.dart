import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyforge/theme/app_theme.dart';

// NOTE: `flutter create .` in CI regenerates any missing file with its
// default template (which references a MyApp class this project does not
// have). Committing this file keeps that from reintroducing a broken test.
void main() {
  testWidgets('all app themes render a basic screen', (tester) async {
    for (final ThemeData theme in <ThemeData>[
      AppThemes.dark(),
      AppThemes.oled(),
      AppThemes.light(),
    ]) {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(body: Text('PyForge')),
      ));
      expect(find.text('PyForge'), findsOneWidget);
    }
  });
}
