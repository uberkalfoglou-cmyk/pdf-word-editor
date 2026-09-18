import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdf_word_editor/l10n/app_strings.dart';
import 'package:pdf_word_editor/screens/home_screen.dart';
import 'package:pdf_word_editor/screens/how_it_works_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home shows English name by default', (tester) async {
    SharedPreferences.setMockInitialValues({howItWorksSeenKey: true});
    final locale = LocaleController();

    await tester.pumpWidget(
      LocaleScope(
        controller: locale,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit PDF Words & Sign'), findsOneWidget);
    expect(find.text('Open PDF'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
  });
}
