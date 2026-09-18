import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' show PdfColor;

import '../l10n/app_strings.dart';
import '../models/pdf_word.dart';
import '../services/pdf_edit_service.dart';
import '../services/pdf_font_matcher.dart';
import '../services/pdf_page_renderer.dart';
import '../services/signature_store.dart';
import '../widgets/pdf_page_overlay.dart';
import '../widgets/signature_pad.dart';
import '../widgets/type_signature_pad.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.fileBytes,
    required this.fileName,
  });

  final Uint8List fileBytes;
  final String fileName;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late PdfEditService _editService;
  late PdfPageRenderer _renderer;

  int _pageIndex = 0;
  late final int _pageCount;
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;

  RenderedPage? _rendered;
  List<PdfWord> _words = const [];
  PdfWord? _highlighted;
  PdfColor _pageBackground = PdfColor(255, 255, 255);

  // Fine-position ("move") state for the word currently being placed —
  // see _onWordTap/_confirmAdjust. Nothing touches the actual PDF until
  // the user confirms via the on-screen checkmark.
  PdfWord? _adjustingWord;
  String? _pendingText;
  Offset _adjustOffset = Offset.zero;

  // The drag preview itself: a pixel-accurate PNG snippet (see
  // _cropPngRegion) plus the PDF-point rectangle it was cropped from.
  // Populated synchronously for a plain move (cropped straight out of the
  // page that's already on screen) or asynchronously for a text change
  // (see _preparingAdjustPreview) since the new text has to be rendered
  // once, off-screen, before there's anything to cut.
  Uint8List? _adjustPreviewImageBytes;
  Rect? _adjustPreviewSourceRect;
  bool _preparingAdjustPreview = false;

  // --- Signature / stamp placement state ---
  // A separate mode from the word-adjust fields above: places a brand-new
  // free-floating image (a drawn signature or a picked photo) anywhere on
  // the page rather than replacing an existing word, so it needs its own
  // rect (draggable AND resizable, not just nudgeable) instead of an
  // offset from some word's bounds. Nothing touches the actual PDF until
  // [_confirmStamp]; see [_openStampMenu] for how this gets populated.
  Uint8List? _stampImageBytes;
  double _stampAspect = 1.0; // width / height, preserved while resizing
  Rect? _stampRect; // current placement rect, in PDF points
  static const double _kMinStampSize = 20.0;

  // Where signatures get saved for reuse across pages/documents (see
  // "Saved Signatures" in [_openStampMenu]) — just files on disk,
  // no database needed for "here are some PNGs, pick one".
  final SignatureStore _signatureStore = SignatureStore();

  /// True while any in-progress, not-yet-committed edit has the UI's
  /// normal controls (tap-to-edit, undo, share, save, page nav) suspended
  /// — fine-positioning a word, saving a straight text change, or placing
  /// a signature/stamp. Centralizing this in one getter means adding a new
  /// kind of "busy" mode (like the stamp placement below) only means
  /// adding it to this one place instead of hunting down every button.
  bool get _busy => _adjustingWord != null || _preparingAdjustPreview || _stampRect != null;

  // Undo support: `_currentBytes` is the fully-saved document as currently
  // shown on screen. Before every edit we push it onto `_history`, so
  // undo just means "throw away the latest edit and rebuild from the
  // bytes we saved right before it" — no need to replay individual edits.
  late Uint8List _currentBytes;
  final List<Uint8List> _history = [];

  @override
  void initState() {
    super.initState();
    _editService = PdfEditService(widget.fileBytes);
    _renderer = PdfPageRenderer(widget.fileBytes);
    _currentBytes = widget.fileBytes;
    _pageCount = _editService.pageCount;
    _loadPage(0);
  }

  Future<void> _loadPage(int index) async {
    setState(() => _loading = true);
    final rendered = await _renderer.renderPage(index + 1); // pdfx pages are 1-based
    final words = _editService.extractWords(index);
    final background = _computePageBackground(rendered.imageBytes);
    if (!mounted) return;
    setState(() {
      _pageIndex = index;
      _rendered = rendered;
      _words = words;
      _highlighted = null;
      _pageBackground = background;
      _loading = false;
    });
  }

  /// The single most common color across the rendered page — i.e. the
  /// real page background, whatever off-white/cream/gray tone it actually
  /// is. Computed once per page (not per word): sampling near each word
  /// individually turned out to be fragile — on a tightly-spaced page it
  /// can land on an adjacent line's ink (including a previous edit's own
  /// text), which is how we briefly got solid-black erase patches.
  PdfColor _computePageBackground(Uint8List pngBytes) {
    final fallback = PdfColor(255, 255, 255);
    try {
      final decoded = img.decodePng(pngBytes);
      if (decoded == null) {
        debugPrint('[background] decodePng returned null (${pngBytes.length} bytes)');
        return fallback;
      }

      debugPrint(
        '[background] decoded ${decoded.width}x${decoded.height}, '
        'format=${decoded.format}, numChannels=${decoded.numChannels}, '
        'hasPalette=${decoded.hasPalette}',
      );

      final counts = <int, int>{};
      var lowAlphaSamples = 0;
      var totalSamples = 0;
      const step = 7; // sparse grid is plenty and keeps this fast
      for (var y = 0; y < decoded.height; y += step) {
        for (var x = 0; x < decoded.width; x += step) {
          final p = decoded.getPixel(x, y);
          // Use the normalized (0..1) channel accessors and scale to
          // 0..255 ourselves — the raw r/g/b getters' range depends on the
          // image's internal pixel format (8-bit vs float vs 16-bit), and
          // treating a 0..1 float as if it were already 0..255 is exactly
          // how "almost white" (~0.98) rounded down to black (0) before.
          final r = (p.rNormalized * 255).round().clamp(0, 255);
          final g = (p.gNormalized * 255).round().clamp(0, 255);
          final b = (p.bNormalized * 255).round().clamp(0, 255);
          final key = (r << 16) | (g << 8) | b;
          counts[key] = (counts[key] ?? 0) + 1;
          totalSamples++;
          // DIAGNOSTIC: pdfx used to render PNG with a transparent
          // background by default, which showed up as raw-black
          // (0,0,0) pixels with alpha 0 — visually invisible but not
          // actually white. We now force an opaque white background in
          // PdfPageRenderer, so this should stay at 0; if it's ever
          // non-zero again, that's the smoking gun.
          if (decoded.numChannels == 4 && p.aNormalized < 0.99) {
            lowAlphaSamples++;
          }
        }
      }
      if (lowAlphaSamples > 0) {
        debugPrint(
          '[background] WARNING: $lowAlphaSamples / $totalSamples sampled '
          'pixels have alpha < 255 — PNG still has transparency despite '
          'the forced white backgroundColor in PdfPageRenderer.',
        );
      }
      if (counts.isEmpty) {
        debugPrint('[background] no samples collected');
        return fallback;
      }

      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      debugPrint(
        '[background] top colors (rgb:count): '
        '${sorted.take(5).map((e) => '(${(e.key >> 16) & 0xFF},${(e.key >> 8) & 0xFF},${e.key & 0xFF}):${e.value}').join(', ')} '
        'out of ${counts.length} distinct, ${sorted.fold<int>(0, (s, e) => s + e.value)} samples',
      );

      final mostCommon = sorted.first.key;
      final result = PdfColor((mostCommon >> 16) & 0xFF, (mostCommon >> 8) & 0xFF, mostCommon & 0xFF);
      debugPrint('[background] chosen = (${result.r},${result.g},${result.b})');
      return result;
    } catch (e, st) {
      debugPrint('[background] EXCEPTION: $e\n$st');
      return fallback;
    }
  }

  /// The nearest word to the right of [word] on the same visual line, if
  /// any. "Same line" is judged by vertical position being close (within
  /// ~60% of the word's own height) rather than exact equality, since
  /// baseline/ascent jitter between words on one line is normal.
  ///
  /// Used to measure the real gap between words, so a replacement can be
  /// sized to fit in that gap instead of blindly overlapping whatever
  /// comes next.
  PdfWord? _findNextWordOnLine(PdfWord word) {
    PdfWord? best;
    for (final candidate in _words) {
      if (candidate.wordIndexInPage == word.wordIndexInPage) continue;
      final sameLine = (candidate.bounds.top - word.bounds.top).abs() < word.bounds.height * 0.6;
      if (!sameLine) continue;
      if (candidate.bounds.left <= word.bounds.left) continue; // only look to the right
      if (best == null || candidate.bounds.left < best.bounds.left) {
        best = candidate;
      }
    }
    return best;
  }

  /// Mirror of [_findNextWordOnLine] looking left, so the erase patch
  /// never reaches into the previous word either.
  PdfWord? _findPrevWordOnLine(PdfWord word) {
    PdfWord? best;
    for (final candidate in _words) {
      if (candidate.wordIndexInPage == word.wordIndexInPage) continue;
      final sameLine = (candidate.bounds.top - word.bounds.top).abs() < word.bounds.height * 0.6;
      if (!sameLine) continue;
      if (candidate.bounds.right >= word.bounds.left) continue;
      if (best == null || candidate.bounds.right > best.bounds.right) {
        best = candidate;
      }
    }
    return best;
  }

  /// How much horizontal room [word] actually has to its right on the same
  /// line before it would run into whatever comes next — shared by the
  /// live preview (so its render matches) and [_confirmAdjust] (so the
  /// real edit does too).
  double _computeAvailableWidth(PdfWord word) {
    final nextWord = _findNextWordOnLine(word);
    if (nextWord != null) {
      final gapToNext = nextWord.bounds.left - word.bounds.right;
      // Leave a 1pt safety margin so we never touch the next word's glyphs.
      final usableGap = gapToNext > 1.0 ? gapToNext - 1.0 : 0.0;
      return word.bounds.width + usableGap;
    }
    // Last word on the line (or no other word detected there) — no
    // neighbor to bump into, so allow generous room.
    return word.bounds.width + 150;
  }

  /// How far [word] can move up and down before it would start overlapping
  /// whatever's on the line above/below — found by looking for the
  /// nearest OTHER word that horizontally overlaps [word]'s own left/right
  /// span (i.e. actually sits above or below it, not just anywhere on the
  /// page) and measuring the vertical gap. Used both to cap the live
  /// nudge and, at [_confirmAdjust] time, to size the real erase
  /// rectangle — so a bigger allowed move never risks touching a
  /// neighboring line's text.
  ({double up, double down}) _computeVerticalRoom(PdfWord word) {
    double? nearestAboveBottom;
    double? nearestBelowTop;
    for (final candidate in _words) {
      if (candidate.wordIndexInPage == word.wordIndexInPage) continue;
      final overlapsX =
          candidate.bounds.right > word.bounds.left && candidate.bounds.left < word.bounds.right;
      if (!overlapsX) continue;
      if (candidate.bounds.bottom <= word.bounds.top) {
        if (nearestAboveBottom == null || candidate.bounds.bottom > nearestAboveBottom) {
          nearestAboveBottom = candidate.bounds.bottom;
        }
      } else if (candidate.bounds.top >= word.bounds.bottom) {
        if (nearestBelowTop == null || candidate.bounds.top < nearestBelowTop) {
          nearestBelowTop = candidate.bounds.top;
        }
      }
    }
    const fallback = 40.0; // generous default when nothing is in the way
    const safety = 2.0; // keep a hair of breathing room from the neighbor
    double clampRoom(double value) {
      if (value < 0) return 0;
      if (value > fallback) return fallback;
      return value;
    }

    final upRoom = nearestAboveBottom == null
        ? fallback
        : clampRoom(word.bounds.top - nearestAboveBottom - safety);
    final downRoom = nearestBelowTop == null
        ? fallback
        : clampRoom(nearestBelowTop - word.bounds.bottom - safety);
    return (up: upRoom, down: downRoom);
  }

  /// Hard clip for the white erase patch: original word plus a tiny pad,
  /// cut short of any neighboring word or line. Using the full "nudge
  /// room" as erase (the old behaviour) is what covered the next words
  /// and the line below when changing «παρούσα» in place.
  Rect _eraseClamp(PdfWord word) {
    const pad = 1.5;
    const safety = 0.75;
    var left = word.bounds.left - pad;
    var top = word.bounds.top - pad;
    var right = word.bounds.left + _computeAvailableWidth(word);
    var bottom = word.bounds.bottom + pad;

    final prev = _findPrevWordOnLine(word);
    if (prev != null) {
      left = math.max(left, prev.bounds.right + safety);
    }
    final next = _findNextWordOnLine(word);
    if (next != null) {
      right = math.min(right, next.bounds.left - safety);
    }

    final midY = word.bounds.center.dy;
    double? nearestAboveBottom;
    double? nearestBelowTop;
    for (final candidate in _words) {
      if (candidate.wordIndexInPage == word.wordIndexInPage) continue;
      final overlapsX =
          candidate.bounds.right > word.bounds.left && candidate.bounds.left < word.bounds.right;
      if (!overlapsX) continue;
      if (candidate.bounds.center.dy < midY) {
        if (nearestAboveBottom == null || candidate.bounds.bottom > nearestAboveBottom) {
          nearestAboveBottom = candidate.bounds.bottom;
        }
      } else if (candidate.bounds.center.dy > midY) {
        if (nearestBelowTop == null || candidate.bounds.top < nearestBelowTop) {
          nearestBelowTop = candidate.bounds.top;
        }
      }
    }
    if (nearestAboveBottom != null) {
      top = math.max(top, nearestAboveBottom + safety);
    }
    if (nearestBelowTop != null) {
      bottom = math.min(bottom, nearestBelowTop - safety);
    }
    if (right < left) right = left;
    if (bottom < top) bottom = top;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Crops [pdfRect] (in PDF points, against a page rendered at
  /// [pdfWidth]x[pdfHeight]) out of [pngBytes], then makes every pixel
  /// that matches the page background fully transparent (see
  /// [_matteOutBackground]) — so what's actually dragged around is just
  /// the ink, "lifted" off the page, not a solid white box around it.
  Uint8List? _cropPngRegion(
    Uint8List pngBytes,
    double pdfWidth,
    double pdfHeight,
    Rect pdfRect,
  ) {
    try {
      final decoded = img.decodePng(pngBytes);
      if (decoded == null) {
        debugPrint('[cropPreview] decodePng returned null');
        return null;
      }
      final scaleX = decoded.width / pdfWidth;
      final scaleY = decoded.height / pdfHeight;
      var x = (pdfRect.left * scaleX).floor();
      var y = (pdfRect.top * scaleY).floor();
      var w = (pdfRect.width * scaleX).ceil();
      var h = (pdfRect.height * scaleY).ceil();
      x = x.clamp(0, decoded.width - 1);
      y = y.clamp(0, decoded.height - 1);
      w = w.clamp(1, decoded.width - x);
      h = h.clamp(1, decoded.height - y);
      final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
      final cutout = _matteOutBackground(cropped);
      return Uint8List.fromList(img.encodePng(cutout));
    } catch (e, st) {
      debugPrint('[cropPreview] EXCEPTION: $e\n$st');
      return null;
    }
  }

  /// Turns an opaque page-image snippet into a cutout of just the ink:
  /// pixels matching the sampled page background (see [_pageBackground])
  /// become fully transparent, and anti-aliased edge pixels get a
  /// proportional alpha instead of a hard on/off cutoff so glyph edges
  /// still look smooth. This is what makes the drag preview look like the
  /// letters were lifted off the page rather than a solid colored box.
  ///
  /// Rather than keeping each pixel's own (partly background-blended)
  /// color, every inked pixel is repainted in a single color: whatever
  /// the darkest/most-fully-inked pixel in this snippet turned out to be.
  /// Most pixels near a glyph's edge are actually a blend of ink and
  /// background, so using them as-is made the whole cutout look faded —
  /// noticeably lighter than the real text — instead of solid.
  img.Image _matteOutBackground(img.Image source) {
    final width = source.width;
    final height = source.height;
    final bgR = _pageBackground.r / 255.0;
    final bgG = _pageBackground.g / 255.0;
    final bgB = _pageBackground.b / 255.0;

    double inkiness(double channel, double bg) {
      if (bg <= 0.001) return channel > 0.001 ? 1.0 : 0.0;
      final v = 1 - (channel / bg);
      if (v < 0) return 0;
      if (v > 1) return 1;
      return v;
    }

    final alphas = List<double>.filled(width * height, 0);
    var inkR = 0.0, inkG = 0.0, inkB = 0.0, bestInkiness = -1.0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = source.getPixel(x, y);
        // .toDouble() because Pixel's *Normalized getters return `num`
        // (their exact numeric type depends on the image's internal pixel
        // format), but the blend math here needs plain `double`.
        final r = p.rNormalized.toDouble();
        final g = p.gNormalized.toDouble();
        final b = p.bNormalized.toDouble();
        final a = (inkiness(r, bgR) + inkiness(g, bgG) + inkiness(b, bgB)) / 3;
        alphas[y * width + x] = a;
        if (a > bestInkiness) {
          bestInkiness = a;
          inkR = r;
          inkG = g;
          inkB = b;
        }
      }
    }

    final inkR255 = (inkR * 255).round();
    final inkG255 = (inkG * 255).round();
    final inkB255 = (inkB * 255).round();

    final result = img.Image(width: width, height: height, numChannels: 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        // Boost mid-range alpha toward fully opaque so the body of each
        // glyph reads as solid ink instead of a semi-transparent wash —
        // only the thin anti-aliased rim right at the edge stays partial.
        var a = alphas[y * width + x] * 1.8;
        if (a > 1) a = 1;
        result.setPixelRgba(x, y, inkR255, inkG255, inkB255, (a * 255).round());
      }
    }
    return result;
  }

  /// Tapping a word (whether untouched or already edited by us earlier —
  /// after an edit we re-extract words from the freshly-saved PDF, so
  /// there's no difference between the two from here on) opens a small
  /// menu: "Edit Text" to retype it, or "Move" to just
  /// reposition whatever text is already there. A text change saves
  /// straight away (see [_applyReplacement]); only "Move" goes
  /// through the live nudge stage (see [_confirmAdjust]) where nothing is
  /// drawn into the actual PDF until the user taps the checkmark.
  Future<void> _onWordTap(PdfWord word) async {
    if (_busy) return; // one edit/placement at a time
    setState(() => _highlighted = word);

    final s = AppStrings.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(s.editText),
              onTap: () => Navigator.pop(context, 'change'),
            ),
            ListTile(
              leading: const Icon(Icons.open_with),
              title: Text(s.move),
              onTap: () => Navigator.pop(context, 'move'),
            ),
          ],
        ),
      ),
    );

    if (action == null) {
      if (mounted) setState(() => _highlighted = null);
      return;
    }

    if (action == 'move') {
      setState(() {
        _highlighted = null;
        _adjustingWord = word;
        _pendingText = word.text;
        _adjustOffset = Offset.zero;
        _adjustPreviewSourceRect = word.bounds;
        _adjustPreviewImageBytes = null;
      });
      return;
    }

    // action == 'change'
    final controller = TextEditingController(text: word.text);
    final extra = [
      if (word.isBold) ' · ${s.bold}',
      if (word.isItalic) ' · ${s.italic}',
    ].join();
    final newText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.edit_note, size: 32),
        title: Text(s.editWord),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.detected(
                '${word.fontName} · ${word.fontSize.toStringAsFixed(1)}pt$extra',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(s.continueLabel),
          ),
        ],
      ),
    );
    if (newText == null || newText.isEmpty) {
      if (mounted) setState(() => _highlighted = null);
      return;
    }

    // A plain text change saves straight away — no repositioning step.
    // Only an explicit "Move" goes through the live nudge stage
    // above; asking for both every single time turned out to be one
    // extra tap most edits don't actually need. Erase is clipped to
    // [_eraseClamp] so a shorter replacement never paints a white box
    // over the next words or the line below.
    setState(() => _preparingAdjustPreview = true);
    try {
      await _applyReplacement(word, newText);
    } finally {
      if (mounted) setState(() => _preparingAdjustPreview = false);
    }
    if (mounted) setState(() => _highlighted = null);
  }

  /// Actually writes [newText] into the PDF in place of [word] — the one
  /// place that calls [PdfEditService.replaceWord] for a REAL (not
  /// preview) edit. Used both for a straight text change (offsetX/offsetY
  /// stay 0, margins stay at the small default — there's no nudging to
  /// leave room for) and for confirming a "Move"/repositioned
  /// change from [_confirmAdjust] (which passes the actual offset and the
  /// per-word margins from [_computeVerticalRoom]).
  Future<void> _applyReplacement(
    PdfWord word,
    String newText, {
    double offsetX = 0,
    double offsetY = 0,
    double marginX = 1.5,
    double marginTop = 1.5,
    double marginBottom = 1.5,
    bool relocate = false,
  }) async {
    final availableWidth = _computeAvailableWidth(word);
    final eraseClamp = _eraseClamp(word);

    debugPrint(
      '[applyReplacement] using background=(${_pageBackground.r},${_pageBackground.g},${_pageBackground.b}) '
      'for word "${word.text}" -> "$newText" | '
      'availableWidth=${availableWidth.toStringAsFixed(1)} '
      'offset=(${offsetX.toStringAsFixed(1)},${offsetY.toStringAsFixed(1)})',
    );

    // Snapshot the document exactly as it is right now, BEFORE applying
    // this edit — that's what undo restores if the user taps it.
    _history.add(_currentBytes);

    final result = _editService.replaceWord(
      word,
      newText,
      background: _pageBackground,
      maxWidth: availableWidth,
      offsetX: offsetX,
      offsetY: offsetY,
      marginX: marginX,
      marginTop: marginTop,
      marginBottom: marginBottom,
      eraseClamp: eraseClamp,
      relocate: relocate,
    );

    // Re-render from the just-edited document so what's on screen always
    // matches what Save will produce, then re-extract words (bounds shift
    // once text changes length).
    final freshBytes = await _editService.save();
    _currentBytes = freshBytes;
    await _renderer.dispose();
    _renderer = PdfPageRenderer(freshBytes);
    setState(() => _dirty = true);
    await _loadPage(_pageIndex);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).editedUsing(result.match.familyLabel))),
      );
    }
  }

  /// Nudges the pending word by [delta] PDF points, clamped so it stays
  /// on the page. No tiny 8pt cap — that's why the arrows looked like
  /// they did nothing.
  void _nudge(Offset delta) {
    final word = _adjustingWord;
    final rendered = _rendered;
    final rect = _adjustPreviewSourceRect ?? word?.bounds;
    if (word == null || rendered == null || rect == null) return;
    setState(() {
      final next = _adjustOffset + delta;
      final maxLeft = math.max(0.0, rendered.pdfWidth - rect.width);
      final maxTop = math.max(0.0, rendered.pdfHeight - rect.height);
      final left = (rect.left + next.dx).clamp(0.0, maxLeft);
      final top = (rect.top + next.dy).clamp(0.0, maxTop);
      _adjustOffset = Offset(left - rect.left, top - rect.top);
    });
  }

  /// Backs out of "move" mode without touching the PDF at all.
  void _cancelAdjust() {
    setState(() {
      _adjustingWord = null;
      _pendingText = null;
      _adjustOffset = Offset.zero;
      _adjustPreviewSourceRect = null;
      _adjustPreviewImageBytes = null;
    });
  }

  /// Commits the pending text at its current nudged position via
  /// [_applyReplacement] — everything before this (the menu, the text
  /// dialog, every arrow tap) was just on-screen preview; this is the
  /// point where the PDF actually changes.
  Future<void> _confirmAdjust() async {
    final word = _adjustingWord;
    final newText = _pendingText;
    if (word == null || newText == null) return;
    final offset = _adjustOffset;

    await _applyReplacement(
      word,
      newText,
      offsetX: offset.dx,
      offsetY: offset.dy,
      relocate: true,
    );

    if (mounted) {
      setState(() {
        _adjustingWord = null;
        _pendingText = null;
        _adjustOffset = Offset.zero;
        _adjustPreviewSourceRect = null;
        _adjustPreviewImageBytes = null;
      });
    }
  }

  /// Opens the "Draw Signature" / "From Photo" menu and routes to
  /// whichever source the user picks — mirrors [_onWordTap]'s menu, but
  /// for adding a brand-new image rather than editing an existing word.
  Future<void> _openStampMenu() async {
    if (_busy) return;

    final s = AppStrings.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: Text(s.drawSignature),
              onTap: () => Navigator.pop(context, 'draw'),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: Text(s.typeSignature),
              onTap: () => Navigator.pop(context, 'type'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(s.fromPhoto),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: Text(s.savedSignatures),
              onTap: () => Navigator.pop(context, 'saved'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'draw') {
      // The pad's own canvas paints nothing but the strokes (see
      // SignaturePadPage), so what comes back is already a transparent
      // PNG — no background to remove. `persist: true` because this is a
      // brand-new signature — saved once here so it shows up under
      // "Saved Signatures" next time, without having to redraw it.
      final drawn = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => const SignaturePadPage()),
      );
      if (drawn != null) {
        await _beginStampPlacement(drawn, removeBackground: false, persist: true);
      }
      return;
    }

    if (choice == 'type') {
      // Same deal as drawing: TypeSignaturePadPage only ever paints the
      // rendered name onto a transparent RepaintBoundary, so what comes
      // back needs no background removal, and it's saved for reuse the
      // same way a hand-drawn signature is.
      final typed = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => const TypeSignaturePadPage()),
      );
      if (typed != null) {
        await _beginStampPlacement(typed, removeBackground: false, persist: true);
      }
      return;
    }

    if (choice == 'image') {
      // A real photo, so unlike the signature pad it comes with whatever
      // paper/background it was photographed against, which needs lifting
      // out the same way a cut-out edited word does.
      XFile? picked;
      try {
        picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95);
      } catch (e, st) {
        debugPrint('[stamp] image pick failed: $e\n$st');
      }
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await _beginStampPlacement(bytes, removeBackground: true, persist: true);
      return;
    }

    // choice == 'saved'
    await _pickSavedSignature();
  }

  /// Lets the user reuse a signature saved from an earlier session (see
  /// [SignatureStore]) instead of drawing or picking it again. A long
  /// press on any thumbnail deletes it.
  Future<void> _pickSavedSignature() async {
    final files = await _signatureStore.list();
    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).noSavedSignatures)),
      );
      return;
    }

    final s = AppStrings.of(context);
    final chosen = await showModalBottomSheet<File>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 340,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(s.savedSignatures, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: files.length,
                  itemBuilder: (context, i) {
                    final file = files[i];
                    return GestureDetector(
                      onTap: () => Navigator.pop(sheetContext, file),
                      onLongPress: () async {
                        final action = await showModalBottomSheet<String>(
                          context: sheetContext,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          builder: (actionContext) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.ios_share),
                                  title: Text(s.exportAsFile),
                                  onTap: () => Navigator.pop(actionContext, 'export'),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                                  title: Text(s.delete),
                                  onTap: () => Navigator.pop(actionContext, 'delete'),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (action == 'export') {
                          try {
                            final fileBytes = await file.readAsBytes();
                            await FilePicker.saveFile(
                              dialogTitle: s.saveSignature,
                              fileName: file.path.split(Platform.pathSeparator).last,
                              bytes: fileBytes,
                              mimeType: 'image/png',
                            );
                          } catch (e, st) {
                            debugPrint('[stamp] failed to export saved signature: $e\n$st');
                          }
                        } else if (action == 'delete') {
                          await _signatureStore.delete(file);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Image.file(file, fit: BoxFit.contain),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  s.longPressHint,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final bytes = await chosen.readAsBytes();
    // Already background-removed and already saved from when it was first
    // created — nothing more to strip out, nothing new to persist.
    await _beginStampPlacement(bytes, removeBackground: false, persist: false);
  }

  /// Common setup once we have raw image bytes for a signature/stamp,
  /// whether hand-drawn ([removeBackground] false, already transparent), a
  /// gallery photo ([removeBackground] true), or a previously saved
  /// signature (already processed, [removeBackground] false). Decodes the
  /// bytes, optionally saves the result for reuse (see [SignatureStore]),
  /// sizes and centers an initial placement rect on the current page, and
  /// enters placement mode — nothing touches the PDF until [_confirmStamp].
  Future<void> _beginStampPlacement(
    Uint8List rawBytes, {
    required bool removeBackground,
    bool persist = false,
  }) async {
    final rendered = _rendered;
    if (rendered == null) return;
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        debugPrint('[stamp] decodeImage returned null (${rawBytes.length} bytes)');
        return;
      }
      final backgroundRemoved = removeBackground ? _matteOutPickedImageBackground(decoded) : decoded;
      // Crop down to just the actual ink, not the whole canvas it was
      // drawn/photographed on — without this, the placement box (and its
      // resize handle) covered a lot of invisible transparent space well
      // beyond the visible signature, which both looked disconnected from
      // it and ate into how far down the page it could actually be
      // dragged before the (mostly invisible) box hit the page edge.
      final processed = _cropToInkBounds(backgroundRemoved);
      final pngBytes = Uint8List.fromList(img.encodePng(processed));
      final aspect = processed.width / processed.height;

      if (persist) {
        try {
          await _signatureStore.save(pngBytes);
        } catch (e, st) {
          // Not fatal — the user can still place this one, they just
          // won't see it again under "Saved Signatures".
          debugPrint('[stamp] failed to save signature for reuse: $e\n$st');
        }
      }

      // Default to a signature-sized box, not a third of the page —
      // 35% wide was large enough to look like a stamp covering the
      // document rather than a signature you drop onto a line.
      var width = rendered.pdfWidth * 0.22;
      var height = width / aspect;
      final maxHeight = rendered.pdfHeight * 0.12;
      if (height > maxHeight) {
        height = maxHeight;
        width = height * aspect;
      }
      final left = (rendered.pdfWidth - width) / 2;
      final top = (rendered.pdfHeight - height) / 2;

      if (!mounted) return;
      setState(() {
        _stampImageBytes = pngBytes;
        _stampAspect = aspect;
        _stampRect = Rect.fromLTWH(left, top, width, height);
      });
    } catch (e, st) {
      debugPrint('[stamp] EXCEPTION: $e\n$st');
    }
  }

  /// Like [_matteOutBackground] but for an arbitrary picked photo rather
  /// than a snippet cropped out of the current PDF page: there's no known
  /// page background to compare against here, so it's estimated instead
  /// from a thin strip around the image's own edges — the part of a
  /// photographed signature least likely to contain any actual ink. The
  /// rest of the technique (per-pixel "inkiness" against that estimated
  /// background, then repainting every inked pixel in one solid color with
  /// boosted alpha) is identical to the word cut-out version.
  img.Image _matteOutPickedImageBackground(img.Image source) {
    final width = source.width;
    final height = source.height;

    var sumR = 0.0, sumG = 0.0, sumB = 0.0, sampleCount = 0;
    const border = 6;
    void sampleAt(int x, int y) {
      final p = source.getPixel(x, y);
      sumR += p.rNormalized.toDouble();
      sumG += p.gNormalized.toDouble();
      sumB += p.bNormalized.toDouble();
      sampleCount++;
    }

    for (var x = 0; x < width; x += 3) {
      for (var b = 0; b < border && b < height; b++) {
        sampleAt(x, b);
        sampleAt(x, height - 1 - b);
      }
    }
    for (var y = 0; y < height; y += 3) {
      for (var b = 0; b < border && b < width; b++) {
        sampleAt(b, y);
        sampleAt(width - 1 - b, y);
      }
    }
    final bgR = sampleCount == 0 ? 1.0 : sumR / sampleCount;
    final bgG = sampleCount == 0 ? 1.0 : sumG / sampleCount;
    final bgB = sampleCount == 0 ? 1.0 : sumB / sampleCount;

    double inkiness(double channel, double bg) {
      if (bg <= 0.001) return channel > 0.001 ? 1.0 : 0.0;
      final v = 1 - (channel / bg);
      if (v < 0) return 0;
      if (v > 1) return 1;
      return v;
    }

    final alphas = List<double>.filled(width * height, 0);
    var inkR = 0.0, inkG = 0.0, inkB = 0.0, bestInkiness = -1.0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = source.getPixel(x, y);
        final r = p.rNormalized.toDouble();
        final g = p.gNormalized.toDouble();
        final b = p.bNormalized.toDouble();
        final a = (inkiness(r, bgR) + inkiness(g, bgG) + inkiness(b, bgB)) / 3;
        alphas[y * width + x] = a;
        if (a > bestInkiness) {
          bestInkiness = a;
          inkR = r;
          inkG = g;
          inkB = b;
        }
      }
    }

    final inkR255 = (inkR * 255).round();
    final inkG255 = (inkG * 255).round();
    final inkB255 = (inkB * 255).round();
    final result = img.Image(width: width, height: height, numChannels: 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var a = alphas[y * width + x] * 1.8;
        if (a > 1) a = 1;
        result.setPixelRgba(x, y, inkR255, inkG255, inkB255, (a * 255).round());
      }
    }
    return result;
  }

  /// Crops [source] down to the bounding box of its non-transparent
  /// ("inked") pixels, plus a small [padding] margin — used right after a
  /// signature is captured/background-removed so the placement box it
  /// travels in actually hugs the visible signature, instead of the much
  /// larger (fully transparent, invisible) canvas it was drawn on or
  /// photographed against. Returns [source] unchanged if nothing is inked
  /// at all (shouldn't normally happen — "Use" is disabled on an empty
  /// canvas).
  img.Image _cropToInkBounds(img.Image source, {int padding = 6}) {
    final width = source.width;
    final height = source.height;
    var minX = width, minY = height, maxX = -1, maxY = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = source.getPixel(x, y);
        if (!_isInkPixel(p)) continue;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    if (maxX < minX || maxY < minY) return _makeNearWhiteTransparent(source);

    final left = (minX - padding).clamp(0, width - 1);
    final top = (minY - padding).clamp(0, height - 1);
    final right = (maxX + padding).clamp(0, width - 1);
    final bottom = (maxY + padding).clamp(0, height - 1);
    final cropped = img.copyCrop(
      source,
      x: left,
      y: top,
      width: right - left + 1,
      height: bottom - top + 1,
    );
    return _makeNearWhiteTransparent(cropped);
  }

  bool _isInkPixel(img.Pixel p) {
    if (p.aNormalized <= 0.05) return false;
    final luma = (p.rNormalized + p.gNormalized + p.bNormalized) / 3;
    if (p.aNormalized > 0.92 && luma > 0.92) return false;
    return true;
  }

  /// Syncfusion's [PdfBitmap] treats leftover opaque white as a solid
  /// rectangle on the page. Clear it so only ink is baked in.
  img.Image _makeNearWhiteTransparent(img.Image source) {
    final result = img.Image(width: source.width, height: source.height, numChannels: 4);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final p = source.getPixel(x, y);
        if (!_isInkPixel(p)) {
          result.setPixelRgba(x, y, 255, 255, 255, 0);
          continue;
        }
        result.setPixelRgba(
          x,
          y,
          (p.rNormalized * 255).round(),
          (p.gNormalized * 255).round(),
          (p.bNormalized * 255).round(),
          (p.aNormalized * 255).round(),
        );
      }
    }
    return result;
  }

  /// Drags the pending stamp by [deltaPdfPoints] (already converted from
  /// screen pixels back to PDF points by PdfPageOverlay), clamped so it
  /// can never be dragged off the page entirely.
  void _dragStamp(Offset deltaPdfPoints) {
    final rendered = _rendered;
    final rect = _stampRect;
    if (rendered == null || rect == null) return;
    setState(() {
      final maxLeft = (rendered.pdfWidth - rect.width).clamp(0.0, rendered.pdfWidth);
      final maxTop = (rendered.pdfHeight - rect.height).clamp(0.0, rendered.pdfHeight);
      final left = (rect.left + deltaPdfPoints.dx).clamp(0.0, maxLeft);
      final top = (rect.top + deltaPdfPoints.dy).clamp(0.0, maxTop);
      _stampRect = Rect.fromLTWH(left, top, rect.width, rect.height);
    });
  }

  /// Resizes the pending stamp from its bottom-right handle, always
  /// keeping [_stampAspect] so a signature never ends up stretched out of
  /// shape, clamped to a sensible minimum and to whatever room is left on
  /// the page from the box's current top-left corner.
  void _resizeStamp(Offset deltaPdfPoints) {
    final rendered = _rendered;
    final rect = _stampRect;
    if (rendered == null || rect == null) return;
    setState(() {
      var width = rect.width + deltaPdfPoints.dx;
      if (width < _kMinStampSize) width = _kMinStampSize;
      final maxWidthOnPage = rendered.pdfWidth - rect.left;
      if (width > maxWidthOnPage) width = maxWidthOnPage;

      var height = width / _stampAspect;
      final maxHeightOnPage = rendered.pdfHeight - rect.top;
      if (height > maxHeightOnPage) {
        height = maxHeightOnPage;
        width = height * _stampAspect;
      }
      _stampRect = Rect.fromLTWH(rect.left, rect.top, width, height);
    });
  }

  /// Backs out of stamp placement without touching the PDF at all.
  void _cancelStamp() {
    setState(() {
      _stampImageBytes = null;
      _stampRect = null;
    });
  }

  /// Bakes the placed image into the actual PDF at [_stampRect] via
  /// [PdfEditService.addImage] — the one point where the signature/stamp
  /// actually touches the document; everything before this (drawing or
  /// picking, dragging, resizing) was on-screen only.
  Future<void> _confirmStamp() async {
    final bytes = _stampImageBytes;
    final rect = _stampRect;
    if (bytes == null || rect == null) return;

    setState(() => _preparingAdjustPreview = true);
    try {
      _history.add(_currentBytes);
      _editService.addImage(_pageIndex, bytes, rect);

      final freshBytes = await _editService.save();
      _currentBytes = freshBytes;
      await _renderer.dispose();
      _renderer = PdfPageRenderer(freshBytes);
      setState(() {
        _dirty = true;
        _stampImageBytes = null;
        _stampRect = null;
      });
      await _loadPage(_pageIndex);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).signatureAdded)),
        );
      }
    } finally {
      if (mounted) setState(() => _preparingAdjustPreview = false);
    }
  }

  /// Undo the most recent edit by rebuilding the document from the bytes
  /// we snapshotted right before it. Repeatable — each tap goes one step
  /// further back, all the way to the untouched original.
  Future<void> _undo() async {
    if (_history.isEmpty) return;
    final previousBytes = _history.removeLast();
    await _restoreFromBytes(previousBytes);
  }

  /// Shared plumbing for [_undo]: throw away the current
  /// [_editService]/[_renderer] (they wrap whatever bytes were current
  /// before) and rebuild both from [bytes].
  Future<void> _restoreFromBytes(Uint8List bytes) async {
    setState(() => _loading = true);
    _editService.dispose();
    _editService = PdfEditService(bytes);
    await _renderer.dispose();
    _renderer = PdfPageRenderer(bytes);
    _currentBytes = bytes;
    await _loadPage(_pageIndex);
    if (mounted) {
      // Back to the exact original bytes (same object, not just equal
      // content) only when the undo stack has fully unwound — that's the
      // one case where there's nothing left to save.
      setState(() => _dirty = !identical(bytes, widget.fileBytes));
    }
  }

  /// If the document has more than one page, asks the user whether they
  /// want the whole thing or just the page they're currently looking at.
  /// Returns true for "whole document", false for "just this page", and
  /// null if the user backed out — callers should treat null as "cancel
  /// the whole save/share flow", not as "whole document".
  ///
  /// Single-page documents skip the question entirely (nothing to choose).
  Future<bool?> _choosePageScope() async {
    if (_pageCount <= 1) return true;
    final s = AppStrings.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.whichPages),
        content: Text(s.whichPagesBody(_pageCount, _pageIndex + 1)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.justPage(_pageIndex + 1)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.wholeDocument),
          ),
        ],
      ),
    );
  }

  /// A sensible export filename for [wholeDocument] — either the whole
  /// document ("edited_<name>.pdf") or a specific page
  /// ("<name>_page_<N>.pdf") — derived from the file the user opened.
  String _exportFileName({required bool wholeDocument}) {
    final name = widget.fileName;
    final base = name.toLowerCase().endsWith('.pdf')
        ? name.substring(0, name.length - 4)
        : name;
    return wholeDocument ? 'edited_$name' : '${base}_page_${_pageIndex + 1}.pdf';
  }

  /// Runs the "which pages?" prompt (see [_choosePageScope]) and produces
  /// the bytes + a suggested filename for whichever scope the user picked.
  /// Returns null if the user cancelled that prompt, in which case the
  /// caller (save or share) should just stop — no dialog, no snackbar.
  Future<({Uint8List bytes, String fileName})?> _resolveExport() async {
    final wholeDocument = await _choosePageScope();
    if (wholeDocument == null) return null;
    final bytes = wholeDocument
        ? await _editService.save()
        : await _editService.exportSinglePage(_pageIndex);
    return (bytes: bytes, fileName: _exportFileName(wholeDocument: wholeDocument));
  }

  /// Opens the OS "save as" dialog (via file_picker's Storage Access
  /// Framework integration on Android) so the user picks exactly where
  /// the PDF goes, instead of only being able to go through a share
  /// sheet. `bytes` is handed straight to file_picker, which writes the
  /// file at the chosen location itself.
  Future<void> _saveToDevice() async {
    final export = await _resolveExport();
    if (export == null) return;
    setState(() => _saving = true);
    try {
      final savedUri = await FilePicker.saveFile(
        dialogTitle: AppStrings.of(context).savePdf,
        fileName: export.fileName,
        bytes: export.bytes,
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(savedUri != null ? AppStrings.of(context).saved : AppStrings.of(context).saveCancelled),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Separate from [_saveToDevice]: hands the PDF to the share sheet
  /// (WhatsApp, email, Drive, etc.) instead of writing it to a
  /// user-chosen folder.
  Future<void> _share() async {
    final export = await _resolveExport();
    if (export == null) return;
    setState(() => _saving = true);
    try {
      final dir = await getTemporaryDirectory();
      final outPath = '${dir.path}/${export.fileName}';
      final file = File(outPath);
      await file.writeAsBytes(export.bytes, flush: true);
      if (!mounted) return;
      await Share.shareXFiles([XFile(outPath)], text: 'Edited PDF');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _editService.dispose();
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // While placing a signature/stamp, the app bar swaps to a dedicated
    // Cancel/Place pair instead of the usual actions — pinned at the very
    // top of the screen rather than floating next to the box (which used
    // to land uncomfortably low whenever the signature itself was near
    // the bottom of the page, e.g. right where a real signature usually
    // goes), so it's always in the exact same easy-to-reach spot.
    final placingStamp = _stampRect != null;
    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !placingStamp,
        leading: placingStamp
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: s.cancel,
                onPressed: _cancelStamp,
              )
            : null,
        title: Text(
          placingStamp ? s.placeSignature : widget.fileName,
          overflow: TextOverflow.ellipsis,
        ),
        actions: placingStamp
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: IconButton(
                    icon: const Icon(Icons.check_circle),
                    tooltip: s.place,
                    onPressed: _confirmStamp,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green.shade50,
                      foregroundColor: Colors.green.shade700,
                      shape: const CircleBorder(),
                    ),
                  ),
                ),
              ]
            : [
                const LanguagePickerButton(compact: true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: IconButton(
                    icon: const Icon(Icons.draw_outlined),
                    tooltip: s.addSignature,
                    onPressed: !_busy ? _openStampMenu : null,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.purple.shade50,
                      foregroundColor: Colors.purple.shade700,
                      shape: const CircleBorder(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: IconButton(
                    icon: const Icon(Icons.undo),
                    tooltip: s.undo,
                    onPressed: !_busy && _history.isNotEmpty
                        ? _undo
                        : null,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.grey.shade800,
                      disabledBackgroundColor: Colors.grey.shade100,
                      disabledForegroundColor: Colors.grey.shade400,
                      shape: const CircleBorder(),
                    ),
                  ),
                ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: IconButton(
                      icon: const Icon(Icons.share),
                      tooltip: s.share,
                      onPressed: !_busy ? _share : null,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue.shade50,
                        foregroundColor: Colors.blue.shade700,
                        shape: const CircleBorder(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 12),
                    child: IconButton(
                      icon: const Icon(Icons.save),
                      tooltip: s.save,
                      onPressed: !_busy ? _saveToDevice : null,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.green.shade50,
                        foregroundColor: Colors.green.shade700,
                        shape: const CircleBorder(),
                      ),
                    ),
                  ),
                ],
              ],
      ),
      body: Container(
        color: const Color(0xFFE7E9F0),
        child: _loading || _rendered == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      panEnabled: _stampRect == null && _adjustingWord == null,
                      scaleEnabled: _stampRect == null && _adjustingWord == null,
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: PdfPageOverlay(
                              imageBytes: _rendered!.imageBytes,
                              pdfWidth: _rendered!.pdfWidth,
                              pdfHeight: _rendered!.pdfHeight,
                              words: _words,
                              highlightedWord: _highlighted,
                              onWordTap: _onWordTap,
                              adjustingWord: _adjustingWord,
                              adjustPreviewText: _pendingText,
                              adjustPreviewImageBytes: _adjustPreviewImageBytes,
                              adjustPreviewSourceRect: _adjustPreviewSourceRect,
                              adjustOffset: _adjustOffset,
                              adjustPreviewBackground: Color.fromARGB(
                                255,
                                _pageBackground.r.toInt(),
                                _pageBackground.g.toInt(),
                                _pageBackground.b.toInt(),
                              ),
                              stampRect: _stampRect,
                              stampImageBytes: _stampImageBytes,
                              onStampDrag: _dragStamp,
                              onStampResize: _resizeStamp,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_adjustingWord != null)
                    SafeArea(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: WordNudgePad(
                            onNudge: _nudge,
                            onConfirm: _confirmAdjust,
                            onCancel: _cancelAdjust,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: !_busy && _pageIndex > 0
                  ? () => _loadPage(_pageIndex - 1)
                  : null,
            ),
            Text(AppStrings.of(context).pageOf(_pageIndex + 1, _pageCount)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed:
                  !_busy && _pageIndex < _pageCount - 1
                      ? () => _loadPage(_pageIndex + 1)
                      : null,
            ),
          ],
        ),
      ),
    );
  }
}
