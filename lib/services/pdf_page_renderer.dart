import 'dart:typed_data';

import 'package:pdfx/pdfx.dart' as pdfx;

/// A page rasterized to a PNG, plus the numbers needed to translate a tap
/// in on-screen pixels back into PDF points (the unit [PdfEditService] and
/// the extracted [PdfWord] bounds use).
class RenderedPage {
  RenderedPage({
    required this.imageBytes,
    required this.pdfWidth,
    required this.pdfHeight,
  });

  final Uint8List imageBytes;

  /// Page size in PDF points (72/inch) — matches `PdfWord.bounds`.
  final double pdfWidth;
  final double pdfHeight;
}

/// Rasterizes PDF pages with `pdfx` (a pdfium wrapper) purely for on-screen
/// display. Text/word/font data comes from [PdfEditService] instead —
/// pdfx is only used here because it gives us full control over drawing a
/// tap-detection overlay in sync with the image, which the higher-level
/// `syncfusion_flutter_pdfviewer` widget doesn't expose.
class PdfPageRenderer {
  PdfPageRenderer(Uint8List bytes) : _documentFuture = pdfx.PdfDocument.openData(bytes);

  final Future<pdfx.PdfDocument> _documentFuture;

  Future<int> get pageCount async => (await _documentFuture).pagesCount;

  /// Renders 1-based [pageNumber] at [scale]x its native size (higher scale
  /// = sharper zoom-in, at the cost of memory/time).
  Future<RenderedPage> renderPage(int pageNumber, {double scale = 2}) async {
    final document = await _documentFuture;
    final page = await document.getPage(pageNumber);
    try {
      // IMPORTANT: pdfx renders PNG with a *transparent* background by
      // default ("As default PNG uses transparent background" — pdfx docs).
      // Any part of the page with no ink (which is most of a normal page)
      // comes back as RGBA(0,0,0,0) — raw RGB (0,0,0) with alpha 0, i.e.
      // literally black pixels that just happen to be invisible on screen
      // because they're also fully transparent. Our background-color
      // sampler in editor_screen.dart reads raw RGB and has no reason to
      // look at alpha, so it was picking up this transparent-black as the
      // "most common color" on the page — that's the repeated black-patch
      // bug, and it's unrelated to the earlier normalized-pixel-value fix.
      // Forcing an explicit white backgroundColor here makes pdfx paint
      // white first and then composite the page content on top, so every
      // pixel in the PNG is fully opaque and raw RGB is what a human
      // actually sees. Any part of the page that explicitly paints its own
      // off-white/cream background is unaffected (it was already opaque).
      final image = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: pdfx.PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      if (image == null) {
        throw StateError('Failed to render page $pageNumber');
      }
      return RenderedPage(
        imageBytes: image.bytes,
        pdfWidth: page.width,
        pdfHeight: page.height,
      );
    } finally {
      // pdfx only allows one open page at a time per document.
      await page.close();
    }
  }

  Future<void> dispose() async {
    final document = await _documentFuture;
    await document.close();
  }
}
