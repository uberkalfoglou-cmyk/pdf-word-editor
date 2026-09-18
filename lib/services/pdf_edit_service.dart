import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/pdf_word.dart';
import 'pdf_font_matcher.dart';

/// Wraps a Syncfusion [PdfDocument] to provide the two operations the app
/// needs on top of it: "what words are on this page, and where/what font",
/// and "replace this word's text, matching its font, then give me the
/// bytes back".
class PdfEditService {
  PdfEditService(Uint8List bytes) : _document = PdfDocument(inputBytes: bytes);

  final PdfDocument _document;

  int get pageCount => _document.pages.count;

  Size pageSize(int pageIndex) => _document.pages[pageIndex].size;

  /// All words on [pageIndex] (0-based), each with its bounds (in PDF
  /// points) and detected font.
  List<PdfWord> extractWords(int pageIndex) {
    final extractor = PdfTextExtractor(_document);
    final lines = extractor.extractTextLines(
      startPageIndex: pageIndex,
      endPageIndex: pageIndex,
    );

    final words = <PdfWord>[];
    var i = 0;
    for (final line in lines) {
      for (final word in line.wordCollection) {
        if (word.text.trim().isEmpty) continue;
        final b = word.bounds;
        words.add(
          PdfWord(
            pageIndex: pageIndex,
            text: word.text,
            bounds: Rect.fromLTWH(b.left, b.top, b.width, b.height),
            fontName: word.fontName,
            fontSize: word.fontSize,
            isBold: word.fontStyle.contains(PdfFontStyle.bold),
            isItalic: word.fontStyle.contains(PdfFontStyle.italic),
            wordIndexInPage: i++,
          ),
        );
      }
    }
    return words;
  }

  /// Replace [word] with [newText] in place, matching the original font as
  /// closely as possible (see [PdfFontMatcher] for the matching strategy
  /// and its current limitations).
  ///
  /// [background] is the color used to cover the original glyphs before
  /// drawing the replacement — pass the actual page background color
  /// (sampled from the rendered page; see `EditorScreen._pageBackground`)
  /// rather than assuming pure white, since most "white" pages are
  /// actually a slightly off-white tone and a pure-white patch stands out.
  ///
  /// [maxWidth] is how much horizontal room (in PDF points, starting from
  /// `word.bounds.left`) the replacement actually has before it would run
  /// into whatever comes next on the same line — see
  /// `EditorScreen._findNextWordOnLine`, which measures the real gap to
  /// the next word. If the replacement text would be wider than that, the
  /// font is shrunk (down to ~55% of the original size) until it fits, so
  /// the new word never overlaps the next one and its left edge always
  /// lands exactly where the old word's did. Pass null for "no neighbor
  /// on this line" (falls back to a generous fixed margin).
  ///
  /// [offsetX]/[offsetY] are a small fine-position nudge (in PDF points),
  /// applied only to where the replacement text is drawn. [marginX],
  /// [marginTop] and [marginBottom] cap how far the erase rectangle may
  /// extend beyond the original word — they are NOT added when the text
  /// hasn't actually been nudged that far. Extra erase is only the
  /// original glyphs, the new text's footprint, and a ~1.5pt pad.
  /// [eraseClamp] (from `EditorScreen._eraseClamp`) is an optional hard
  /// clip so the patch can never reach a neighboring word or line.
  ///
  /// Returns the [FontMatch] that was actually used (which may have a
  /// smaller size than [PdfWord.fontSize] if it had to shrink to fit), plus
  /// the exact [coverBounds] rectangle that got erased-and-redrawn — the
  /// caller (see `EditorScreen`'s live "move" preview) uses that rectangle
  /// to crop out a pixel-accurate snapshot of whatever was just drawn, so
  /// the on-screen drag preview always matches the real result exactly
  /// instead of approximating it with a substitute on-screen font.
  static const double _kNudgeMargin = 1.5;

  ({FontMatch match, Rect coverBounds}) replaceWord(
    PdfWord word,
    String newText, {
    PdfColor? background,
    double? maxWidth,
    double offsetX = 0,
    double offsetY = 0,
    double marginX = _kNudgeMargin,
    double marginTop = _kNudgeMargin,
    double marginBottom = _kNudgeMargin,
    Rect? eraseClamp,
    bool relocate = false,
  }) {
    final page = _document.pages[word.pageIndex];
    var match = PdfFontMatcher.match(
      fontName: word.fontName,
      fontSize: word.fontSize,
      bold: word.isBold,
      italic: word.isItalic,
    );

    // In-place edits must fit the gap to the next word. A Move can land
    // anywhere on the page, so don't shrink the font to that old gap.
    final availableWidth = relocate
        ? (page.size.width - (word.bounds.left + offsetX)).clamp(8.0, page.size.width)
        : (maxWidth ?? (word.bounds.width + 150));
    final minFontSize = word.fontSize * 0.55;

    var measuredWidth = match.font.measureString(newText).width;
    if (!relocate && measuredWidth > availableWidth) {
      var size = word.fontSize;
      for (var i = 0; i < 6 && measuredWidth > availableWidth && size > minFontSize; i++) {
        final scale = availableWidth / measuredWidth;
        var nextSize = size * scale * 0.97; // small safety margin per step
        if (nextSize < minFontSize) nextSize = minFontSize;
        size = nextSize;
        match = PdfFontMatcher.match(
          fontName: word.fontName,
          fontSize: size,
          bold: word.isBold,
          italic: word.isItalic,
        );
        measuredWidth = match.font.measureString(newText).width;
      }
      debugPrint(
        '[replaceWord] shrunk font ${word.fontSize.toStringAsFixed(1)}pt -> '
        '${size.toStringAsFixed(1)}pt so "$newText" (measured '
        '${measuredWidth.toStringAsFixed(1)}pt) fits in '
        '${availableWidth.toStringAsFixed(1)}pt of available room',
      );
    }

    // Cover the original glyphs with an opaque patch before drawing the
    // new text over it. The patch is the union of the original word and
    // the replacement text's actual footprint, plus a tiny anti-alias
    // pad — NOT the full neighbor-gap "room" the word could theoretically
    // be moved into. Adding that room as erase (the old behaviour) is
    // what painted a white box over the next words and the line below
    // when replacing a word in place (offset 0).
    //
    // [marginX]/[marginTop]/[marginBottom] are a *maximum* extra extent
    // (used when the text has actually been nudged), not a size that is
    // always added. [maxWidth] still caps how far right the patch may
    // go, so it never reaches the next word on the line.
    //
    // KNOWN v1 LIMITATION: one sampled color is used for every word on the
    // page. A document with mixed backgrounds (shaded table rows, a
    // colored header band, ...) will still show a mismatched patch for
    // words outside the sampled area. Phase 2: sample locally around each
    // word instead of once per page.
    const pad = 1.5;
    final orig = word.bounds;
    final dest = Rect.fromLTWH(
      orig.left + offsetX,
      orig.top + offsetY,
      math.max(measuredWidth, orig.width),
      orig.height,
    );

    // In-place: one tight patch. Move: two patches (old spot + landing
    // spot) so the new letters never stack on whatever was already there
    // — the "txoito" mess. Never union origin+destination into one
    // corridor (that wiped the whole paragraph in between).
    var coverLeft = orig.left - pad;
    var coverTop = orig.top - pad;
    var coverRight = orig.right + pad;
    var coverBottom = orig.bottom + pad;

    if (!relocate) {
      coverLeft = math.min(orig.left, dest.left) - pad;
      coverTop = math.min(orig.top, dest.top) - pad;
      coverRight = math.max(orig.right, dest.right) + pad;
      coverBottom = math.max(orig.bottom, dest.bottom) + pad;
      coverLeft = math.max(coverLeft, orig.left - marginX - pad);
      coverTop = math.max(coverTop, orig.top - marginTop - pad);
      coverRight = math.min(coverRight, orig.left + availableWidth);
      coverBottom = math.min(coverBottom, orig.bottom + marginBottom + pad);
    }

    if (!relocate && eraseClamp != null) {
      coverLeft = math.max(coverLeft, eraseClamp.left);
      coverTop = math.max(coverTop, eraseClamp.top);
      coverRight = math.min(coverRight, eraseClamp.right);
      coverBottom = math.min(coverBottom, eraseClamp.bottom);
    }
    if (coverRight < coverLeft) coverRight = coverLeft;
    if (coverBottom < coverTop) coverBottom = coverTop;

    final coverBounds = Rect.fromLTRB(coverLeft, coverTop, coverRight, coverBottom);
    final resolvedBackground = background ?? PdfColor(255, 255, 255);
    final brush = PdfSolidBrush(resolvedBackground);
    page.graphics.drawRectangle(brush: brush, bounds: coverBounds);
    if (relocate && (offsetX.abs() > 0.2 || offsetY.abs() > 0.2)) {
      page.graphics.drawRectangle(
        brush: brush,
        bounds: Rect.fromLTWH(
          dest.left - pad,
          dest.top - pad,
          dest.width + pad * 2,
          dest.height + pad * 2,
        ),
      );
    }

    // DIAGNOSTIC: print exact numbers so we can see in the `flutter run`
    // terminal exactly where we think the word is vs. what we draw.
    debugPrint(
      '[replaceWord] "${word.text}" -> "$newText" | '
      'bounds=(l:${word.bounds.left.toStringAsFixed(1)}, '
      't:${word.bounds.top.toStringAsFixed(1)}, '
      'w:${word.bounds.width.toStringAsFixed(1)}, '
      'h:${word.bounds.height.toStringAsFixed(1)}) | '
      'availableWidth=${availableWidth.toStringAsFixed(1)} '
      'measuredWidth=${measuredWidth.toStringAsFixed(1)} | '
      'font=${word.fontName} size=${word.fontSize} '
      'matchedSize=${match.font.size} matchedFontHeight=${match.font.height} '
      'pageSize=${page.size}',
    );

    // Center the text vertically on the ORIGINAL word's vertical midpoint
    // instead of top-aligning it. Top-alignment assumes the replacement
    // font's ascent matches the original font's — but Noto Sans (needed
    // for full Unicode/Greek coverage) has noticeably taller line metrics
    // than typical document fonts like Arial, so top-aligned text landed
    // visibly lower than the erased word. Centering on the midpoint is
    // far less sensitive to that ascent/descent mismatch.
    //
    // The text box starts at the ORIGINAL word's left edge (never moved)
    // and is exactly [availableWidth] wide — the real measured gap to the
    // next word on the line — so left-aligned text always lands precisely
    // where the old word was and never overlaps whatever comes after it.
    // [offsetX]/[offsetY] shift that landing spot by the user's fine-tune
    // nudge, always within the extra margin reserved above.
    final centerY = dest.top + dest.height / 2;
    // Noto's line metrics are taller than the extracted word box. A short
    // draw rect clips every glyph — the user sees only the white erase.
    // Keep the layout box tall enough to paint, while the erase rect
    // above stays tight so we don't wipe the next line.
    final boxHeight = math.max(dest.height * 3, match.font.size * 2.4);
    final drawWidth = relocate
        ? math.max(measuredWidth + 8, dest.width + 4)
        : math.max(availableWidth, measuredWidth + 4);
    final textBounds = Rect.fromLTWH(
      dest.left,
      centerY - boxHeight / 2,
      drawWidth,
      boxHeight,
    );
    page.graphics.drawString(
      newText,
      match.font,
      brush: PdfSolidBrush(PdfColor(0, 0, 0)),
      bounds: textBounds,
      format: PdfStringFormat(
        alignment: PdfTextAlignment.left,
        lineAlignment: PdfVerticalAlignment.middle,
      ),
    );

    return (match: match, coverBounds: coverBounds);
  }

  /// Bakes [pngBytes] into the page at [bounds] (PDF points) — used for
  /// placing a signature/stamp image (see `EditorScreen`'s stamp-placement
  /// flow). Unlike [replaceWord] there's no erase-and-redraw here: the
  /// image is simply drawn on top of whatever is already on the page, and
  /// a PNG with an alpha channel — either the transparent capture straight
  /// out of the on-screen signature pad, or a gallery photo that's had its
  /// paper/background lifted out the same way a "cut" word is (see
  /// `EditorScreen._matteOutPickedImageBackground`) — draws with real
  /// transparency, so only the ink itself actually lands on the page.
  void addImage(int pageIndex, Uint8List pngBytes, Rect bounds) {
    final page = _document.pages[pageIndex];
    final bitmap = PdfBitmap(pngBytes);
    page.graphics.drawImage(bitmap, bounds);
  }

  Future<Uint8List> save() async {
    final bytes = await _document.save();
    return Uint8List.fromList(bytes);
  }

  /// Exports a single page (0-based [pageIndex]) as its own standalone
  /// PDF, at the same page size as the original.
  ///
  /// This works by rendering the page as a reusable [PdfTemplate] and
  /// drawing it onto a fresh one-page document — Syncfusion has no direct
  /// "copy this one page out" API, so this template approach is the
  /// standard workaround. It flattens the page's content, so if this
  /// exported single-page file is reopened in this app later, its words
  /// may no longer be individually tappable — that's an acceptable
  /// trade-off since the point here is a clean one-page export to save or
  /// share, not further editing.
  Future<Uint8List> exportSinglePage(int pageIndex) async {
    final sourcePage = _document.pages[pageIndex];
    final template = sourcePage.createTemplate();

    final singleDoc = PdfDocument();
    singleDoc.pageSettings.size = sourcePage.size;
    singleDoc.pageSettings.margins = PdfMargins()..all = 0;
    final newPage = singleDoc.pages.add();
    newPage.graphics.drawPdfTemplate(template, const Offset(0, 0));

    final bytes = await singleDoc.save();
    singleDoc.dispose();
    return Uint8List.fromList(bytes);
  }

  void dispose() {
    _document.dispose();
  }
}
