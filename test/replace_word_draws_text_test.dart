import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:pdf_word_editor/services/embedded_fonts.dart';
import 'package:pdf_word_editor/services/pdf_edit_service.dart';

Future<Uint8List> _pdfWithHello() async {
  final doc = PdfDocument();
  doc.pageSettings.size = const Size(400, 600);
  doc.pageSettings.margins.all = 0;
  final page = doc.pages.add();
  page.graphics.drawString(
    'hello there',
    PdfStandardFont(PdfFontFamily.helvetica, 14),
    brush: PdfSolidBrush(PdfColor(0, 0, 0)),
    bounds: const Rect.fromLTWH(50, 80, 250, 24),
  );
  final bytes = Uint8List.fromList(await doc.save());
  doc.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await EmbeddedFonts.instance.load();
  });

  test('replaceWord paints the new word, not only a blank erase', () async {
    final service = PdfEditService(await _pdfWithHello());
    final words = service.extractWords(0);
    expect(words, isNotEmpty, reason: 'source PDF must have extractable words');
    final hello = words.firstWhere(
      (w) => w.text.toLowerCase().contains('hello'),
      orElse: () => words.first,
    );

    service.replaceWord(hello, 'world');
    final out = await service.save();
    service.dispose();

    final verify = PdfDocument(inputBytes: out);
    final extracted = PdfTextExtractor(verify).extractText();
    verify.dispose();

    expect(
      extracted.toLowerCase(),
      contains('world'),
      reason: 'replacement must be visible text, not an empty white patch',
    );
  });
}
