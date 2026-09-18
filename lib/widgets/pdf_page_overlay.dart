import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/pdf_word.dart';

/// Shows one rasterized PDF page and turns taps into word hit-tests.
///
/// The page image is laid out at exactly [pdfWidth] x [pdfHeight]'s aspect
/// ratio, so a single scale factor (`renderedSize / pdfSize`) converts
/// every tap position and every [PdfWord.bounds] between screen pixels and
/// PDF points — no matter how the surrounding [InteractiveViewer] has
/// zoomed/panned, since that transform is applied *outside* this widget.
class PdfPageOverlay extends StatelessWidget {
  const PdfPageOverlay({
    super.key,
    required this.imageBytes,
    required this.pdfWidth,
    required this.pdfHeight,
    required this.words,
    required this.onWordTap,
    this.highlightedWord,
    this.adjustingWord,
    this.adjustPreviewText,
    this.adjustPreviewImageBytes,
    this.adjustPreviewSourceRect,
    this.adjustOffset = Offset.zero,
    this.adjustPreviewBackground = Colors.white,
    this.onNudge,
    this.onConfirmAdjust,
    this.onCancelAdjust,
    this.stampRect,
    this.stampImageBytes,
    this.onStampDrag,
    this.onStampResize,
  });

  final Uint8List imageBytes;
  final double pdfWidth;
  final double pdfHeight;
  final List<PdfWord> words;
  final ValueChanged<PdfWord> onWordTap;
  final PdfWord? highlightedWord;

  /// Non-null while the user is in "fine position" mode for this word
  /// (reached via the tap menu's "Move", or right after typing new
  /// text via "Edit Text") — normal tap handling is suspended and a
  /// live, movable preview + arrow controls are shown instead of the
  /// static amber highlight. Nothing is drawn into the actual PDF until
  /// [onConfirmAdjust] fires; [onCancelAdjust] discards it entirely.
  final PdfWord? adjustingWord;

  /// Fallback-only: plain text shown if [adjustPreviewImageBytes] is ever
  /// null (a crop/render failure). Normal operation always has an image.
  final String? adjustPreviewText;

  /// A pixel-accurate snapshot of the word as it will actually look —
  /// either literally cut out of the current page (plain move, no text
  /// change) or a one-off render of the new text in its matched font
  /// (after a text change). This is what actually gets dragged around;
  /// see [PdfEditService.replaceWord]'s `coverBounds` for where it comes
  /// from.
  final Uint8List? adjustPreviewImageBytes;

  /// The PDF-point rectangle [adjustPreviewImageBytes] was cropped from —
  /// its position (shifted by [adjustOffset]) and size on screen are both
  /// derived from this, so the preview lines up with the real page
  /// geometry no matter how far it's nudged.
  final Rect? adjustPreviewSourceRect;

  final Offset adjustOffset;
  final Color adjustPreviewBackground;
  final ValueChanged<Offset>? onNudge;
  final VoidCallback? onConfirmAdjust;
  final VoidCallback? onCancelAdjust;

  /// Non-null while a signature/stamp image is being positioned (see
  /// `EditorScreen`'s stamp-placement flow) — a separate mode from
  /// [adjustingWord] since this places a brand-new free-floating image
  /// rather than replacing an existing word, and needs a resize handle in
  /// addition to dragging. [stampRect] is in PDF points; nothing touches
  /// the actual PDF until `EditorScreen` commits it — its confirm/cancel
  /// controls live in the app bar (always in the same reachable spot)
  /// rather than floating near the box, which is why there's no
  /// onStampConfirm/onStampCancel here the way [onConfirmAdjust]/
  /// [onCancelAdjust] exist for the word-adjust pad above.
  final Rect? stampRect;
  final Uint8List? stampImageBytes;
  final ValueChanged<Offset>? onStampDrag;
  final ValueChanged<Offset>? onStampResize;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: pdfWidth / pdfHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaleX = constraints.maxWidth / pdfWidth;
          final scaleY = constraints.maxHeight / pdfHeight;
          final adjusting = adjustingWord;
          final placingStamp = stampRect != null;

          PdfWord? hitTest(Offset localPosition) {
            final pdfPoint = Offset(
              localPosition.dx / scaleX,
              localPosition.dy / scaleY,
            );
            // Last match wins: after an edit the original glyphs are only
            // covered, not removed, so extractWords still returns the old
            // word under the replacement. Tapping the changed word must
            // pick the new one (drawn later), not revive the previous text.
            for (final word in words.reversed) {
              if (word.bounds.contains(pdfPoint)) return word;
            }
            return null;
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // While fine-tuning a word's position, or placing a signature/
            // stamp, taps elsewhere on the page are ignored — only that
            // mode's own controls (arrow pad, or drag/resize/confirm below)
            // are live.
            onTapUp: adjusting != null || placingStamp
                ? null
                : (details) {
                    final hit = hitTest(details.localPosition);
                    if (hit != null) onWordTap(hit);
                  },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  imageBytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
                if (highlightedWord != null && adjusting == null && !placingStamp)
                  Positioned(
                    left: highlightedWord!.bounds.left * scaleX,
                    top: highlightedWord!.bounds.top * scaleY,
                    width: highlightedWord!.bounds.width * scaleX,
                    height: highlightedWord!.bounds.height * scaleY,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.35),
                        border: Border.all(color: Colors.deepOrange, width: 1.5),
                      ),
                    ),
                  ),
                if (adjusting != null)
                  ..._buildAdjustOverlay(adjusting, scaleX, scaleY),
                if (placingStamp) ..._buildStampOverlay(scaleX, scaleY),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Hides the original glyphs and shows the word at [adjustOffset].
  /// The letters themselves (not just a blue frame) live in this moving
  /// box. The arrow pad is *not* here — it sits on the screen in
  /// [EditorScreen], outside [InteractiveViewer], so it stays visible
  /// without zooming out to the bottom of the PDF page.
  List<Widget> _buildAdjustOverlay(
    PdfWord word,
    double scaleX,
    double scaleY,
  ) {
    final rect = word.bounds;
    final left = (rect.left + adjustOffset.dx) * scaleX;
    final top = (rect.top + adjustOffset.dy) * scaleY;
    final width = rect.width * scaleX;
    final height = rect.height * scaleY;
    final label = adjustPreviewText ?? word.text;

    return [
      Positioned(
        left: rect.left * scaleX,
        top: rect.top * scaleY,
        width: width,
        height: height,
        child: ColoredBox(color: adjustPreviewBackground),
      ),
      AnimatedPositioned(
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        left: left,
        top: top,
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: adjustPreviewBackground,
            border: Border.all(color: Colors.blue, width: 1.5),
          ),
          child: Center(
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.black,
                    fontFamily: 'NotoSansPreview',
                    fontWeight: word.isBold ? FontWeight.w700 : FontWeight.w400,
                    fontStyle: word.isItalic ? FontStyle.italic : FontStyle.normal,
                    fontSize: word.fontSize,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// The live signature/stamp placement box: draggable anywhere on its
  /// body, resizable (aspect-ratio preserved, see `EditorScreen._resizeStamp`)
  /// from the small handle at its bottom-right corner, plus a floating
  /// confirm/cancel pair — mirrors [_buildAdjustOverlay]'s shape but for a
  /// free-floating image rather than a fixed word position.
  List<Widget> _buildStampOverlay(double scaleX, double scaleY) {
    final rect = stampRect!;
    final left = rect.left * scaleX;
    final top = rect.top * scaleY;
    final width = rect.width * scaleX;
    final height = rect.height * scaleY;
    const handleSize = 28.0;

    final bytes = stampImageBytes;

    return [
      Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        // No visible border around the image itself — just the bare
        // signature, draggable by touching anywhere on it. The small
        // handle at the corner (below) is the only visual chrome, so
        // there's no frame sitting on top of the actual signature.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => onStampDrag?.call(
            Offset(details.delta.dx / scaleX, details.delta.dy / scaleY),
          ),
          child: bytes != null
              ? Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true)
              : const SizedBox.shrink(),
        ),
      ),
      // Bottom-right resize handle — dragging it scales the box, with
      // EditorScreen keeping width/height locked to the image's own aspect
      // ratio so a signature never ends up stretched out of shape.
      Positioned(
        left: left + width - handleSize / 2,
        top: top + height - handleSize / 2,
        width: handleSize,
        height: handleSize,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => onStampResize?.call(
            Offset(details.delta.dx / scaleX, details.delta.dy / scaleY),
          ),
          child: Material(
            color: Colors.purple,
            shape: const CircleBorder(),
            elevation: 3,
            child: Icon(Icons.open_in_full, size: 14, color: Colors.white),
          ),
        ),
      ),
    ];
  }
}

/// Small floating control cluster shown while fine-tuning a word's
/// position: four arrows to nudge it, a green check to save, a red X to
/// cancel without touching the PDF.
class WordNudgePad extends StatelessWidget {
  const WordNudgePad({
    super.key,
    required this.onNudge,
    required this.onConfirm,
    required this.onCancel,
  });

  final ValueChanged<Offset> onNudge;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  static const double _step = 1.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _icon(Icons.close, Colors.red, onCancel),
            _icon(Icons.keyboard_arrow_left, Colors.black87, () => onNudge(const Offset(-_step, 0))),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _icon(Icons.keyboard_arrow_up, Colors.black87, () => onNudge(const Offset(0, -_step))),
                _icon(Icons.keyboard_arrow_down, Colors.black87, () => onNudge(const Offset(0, _step))),
              ],
            ),
            _icon(Icons.keyboard_arrow_right, Colors.black87, () => onNudge(const Offset(_step, 0))),
            _icon(Icons.check, Colors.green.shade700, onConfirm),
          ],
        ),
      ),
    );
  }

  Widget _icon(IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        icon: Icon(icon, size: 20, color: color),
        onPressed: onTap,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      ),
    );
  }
}
