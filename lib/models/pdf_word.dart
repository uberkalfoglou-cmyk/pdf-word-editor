import 'dart:ui';

/// One tappable word extracted from a PDF page.
///
/// [bounds] is in PDF points (72 points per inch), with the origin at the
/// top-left of the page — the same coordinate space `pdfx` uses for
/// [PdfPage.width]/[PdfPage.height] and Syncfusion uses for extracted text,
/// which is what lets us line up the tap overlay with the rendered image.
class PdfWord {
  PdfWord({
    required this.pageIndex,
    required this.text,
    required this.bounds,
    required this.fontName,
    required this.fontSize,
    required this.isBold,
    required this.isItalic,
    required this.wordIndexInPage,
  });

  /// 0-based page index.
  final int pageIndex;
  final String text;
  final Rect bounds;
  final String fontName;
  final double fontSize;
  final bool isBold;
  final bool isItalic;

  /// Position of this word within the page's word list — lets us tell two
  /// occurrences of the same word on a page apart.
  final int wordIndexInPage;
}
