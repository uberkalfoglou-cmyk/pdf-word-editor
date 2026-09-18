import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdf_word_editor/l10n/app_strings.dart';
import 'package:pdf_word_editor/screens/how_it_works_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('how it works is one page with Skip, not a carousel', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var done = false;
    final locale = LocaleController();

    await tester.pumpWidget(
      LocaleScope(
        controller: locale,
        child: MaterialApp(
          home: HowItWorksPage(onDone: () => done = true),
        ),
      ),
    );

    expect(find.text('How it works'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(done, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(howItWorksSeenKey), isTrue);
  });
}
