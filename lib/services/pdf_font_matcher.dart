import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'embedded_fonts.dart';

/// Result of matching an extracted PDF word's style to the font we'll
/// actually draw the replacement with.
class FontMatch {
  FontMatch(this.font, this.familyLabel);

  final PdfFont font;

  /// Human-readable label shown in the edit dialog (e.g. "Noto Sans Bold").
  final String familyLabel;
}

class PdfFontMatcher {
  /// Builds a [PdfTrueTypeFont] from the bundled Noto Sans (see
  /// [EmbeddedFonts]) at the original word's size, in the matching
  /// bold/italic variant.
  ///
  /// v1 limitation: every replacement uses Noto Sans regardless of the
  /// original font's family (serif vs. sans vs. monospace) — Noto Sans has
  /// full Greek/Latin/Cyrillic coverage, which matters far more than
  /// matching serif-vs-sans for legibility. Phase 2: bundle a serif +
  /// monospace Noto variant too and pick between them the way the old
  /// PdfStandardFont-based matcher did by family name.
  static FontMatch match({
    required String fontName,
    required double fontSize,
    required bool bold,
    required bool italic,
  }) {
    final name = fontName.toLowerCase();
    final wantsBold = bold || _containsAny(name, const ['bold', 'black', 'heavy', 'semibold']);
    final wantsItalic = italic || _containsAny(name, const ['italic', 'oblique']);

    final safeSize = fontSize.isFinite && fontSize > 0 ? fontSize : 12.0;
    final bytes = EmbeddedFonts.instance.bytesFor(bold: wantsBold, italic: wantsItalic);

    // No `style`/`multiStyle` here on purpose: we already picked the TTF
    // file that IS bold/italic, so asking Syncfusion to also synthesize
    // bold/italic on top would double it up.
    final font = PdfTrueTypeFont(bytes, safeSize);

    final label = StringBuffer('Noto Sans');
    if (wantsBold) label.write(' Bold');
    if (wantsItalic) label.write(' Italic');
    return FontMatch(font, label.toString());
  }

  static bool _containsAny(String haystack, List<String> needles) =>
      needles.any(haystack.contains);
}
