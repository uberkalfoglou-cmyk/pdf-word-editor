import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_word_editor/models/pdf_word.dart';
import 'package:pdf_word_editor/widgets/pdf_page_overlay.dart';

Uint8List _whitePng({int width = 200, int height = 400}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodePng(image));
}

PdfWord _word(String text, Rect bounds, {int index = 0}) {
  return PdfWord(
    pageIndex: 0,
    text: text,
    bounds: bounds,
    fontName: 'Arial',
    fontSize: 12,
    isBold: false,
    isItalic: false,
    wordIndexInPage: index,
  );
}

Widget _host({required Widget child}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 200, height: 400, child: child),
      ),
    ),
  );
}

void main() {
  final page = _whitePng();
  final word = _word('test', const Rect.fromLTWH(20, 40, 50, 16));

  testWidgets('moving preview shows the word letters, not only a frame', (tester) async {
    await tester.pumpWidget(
      _host(
        child: PdfPageOverlay(
          imageBytes: page,
          pdfWidth: 200,
          pdfHeight: 400,
          words: [word],
          onWordTap: (_) {},
          adjustingWord: word,
          adjustPreviewText: 'test',
        ),
      ),
    );

    expect(find.text('test'), findsOneWidget);
  });

  testWidgets('arrow offset moves the letters with the preview', (tester) async {
    await tester.pumpWidget(
      _host(
        child: PdfPageOverlay(
          imageBytes: page,
          pdfWidth: 200,
          pdfHeight: 400,
          words: [word],
          onWordTap: (_) {},
          adjustingWord: word,
          adjustPreviewText: 'test',
        ),
      ),
    );
    final before = tester.getTopLeft(find.text('test'));

    await tester.pumpWidget(
      _host(
        child: PdfPageOverlay(
          imageBytes: page,
          pdfWidth: 200,
          pdfHeight: 400,
          words: [word],
          onWordTap: (_) {},
          adjustingWord: word,
          adjustPreviewText: 'test',
          adjustOffset: const Offset(30, 12),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final after = tester.getTopLeft(find.text('test'));

    expect(after.dx, closeTo(before.dx + 30, 1.5));
    expect(after.dy, closeTo(before.dy + 12, 1.5));
  });

  testWidgets('pad is not glued to the bottom of the PDF page overlay', (tester) async {
    await tester.pumpWidget(
      _host(
        child: PdfPageOverlay(
          imageBytes: page,
          pdfWidth: 200,
          pdfHeight: 400,
          words: [word],
          onWordTap: (_) {},
          adjustingWord: word,
          adjustPreviewText: 'test',
        ),
      ),
    );

    expect(find.byType(WordNudgePad), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_right), findsNothing);
  });

    testWidgets('pad arrows emit a sub-millimeter 1pt step', (tester) async {
    Offset? delta;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: WordNudgePad(
              onNudge: (value) => delta = value,
              onConfirm: () {},
              onCancel: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
    expect(delta, const Offset(1, 0));
  });

  testWidgets('tap on an edited word selects the replacement, not the covered original', (tester) async {
    final original = _word('παρούσα', const Rect.fromLTWH(20, 40, 50, 16), index: 0);
    final replacement = _word('test', const Rect.fromLTWH(22, 40, 36, 16), index: 1);
    PdfWord? tapped;

    await tester.pumpWidget(
      _host(
        child: PdfPageOverlay(
          imageBytes: page,
          pdfWidth: 200,
          pdfHeight: 400,
          words: [original, replacement],
          onWordTap: (word) => tapped = word,
        ),
      ),
    );

    final overlay = tester.getTopLeft(find.byType(PdfPageOverlay));
    await tester.tapAt(overlay + const Offset(30, 48));
    await tester.pump();

    expect(tapped?.text, 'test');
  });
}
