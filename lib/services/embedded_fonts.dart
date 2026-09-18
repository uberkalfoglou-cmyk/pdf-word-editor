import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Loads the bundled NotoSans TTFs once and caches the bytes.
///
/// This exists because the PDF spec's 14 "standard" fonts (Helvetica,
/// Times, Courier, Symbol) only guarantee Latin (WinAnsi) glyph coverage.
/// Drawing Greek (or Cyrillic, etc.) text with a `PdfStandardFont` silently
/// renders nothing — which is exactly the "my edit disappeared" bug we hit
/// testing on a Greek PDF. Embedding a real TrueType font with proper
/// Unicode coverage (Noto Sans covers Latin + Greek + Cyrillic) fixes this
/// for any language, not just Greek.
class EmbeddedFonts {
  EmbeddedFonts._();
  static final EmbeddedFonts instance = EmbeddedFonts._();

  Uint8List? _regular;
  Uint8List? _bold;
  Uint8List? _italic;
  Uint8List? _boldItalic;

  bool get isLoaded => _regular != null;

  /// Call once (e.g. in `main()` or before the first edit) and await it.
  Future<void> load() async {
    if (isLoaded) return;
    _regular = await _loadAsset('assets/fonts/NotoSans-Regular.ttf');
    _bold = await _loadAsset('assets/fonts/NotoSans-Bold.ttf');
    _italic = await _loadAsset('assets/fonts/NotoSans-Italic.ttf');
    _boldItalic = await _loadAsset('assets/fonts/NotoSans-BoldItalic.ttf');
  }

  Future<Uint8List> _loadAsset(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// Raw TTF bytes for the requested weight/style — feed straight into
  /// `PdfTrueTypeFont(bytes, size)`.
  Uint8List bytesFor({required bool bold, required bool italic}) {
    if (!isLoaded) {
      throw StateError(
        'EmbeddedFonts.load() must complete before bytesFor() is used.',
      );
    }
    if (bold && italic) return _boldItalic!;
    if (bold) return _bold!;
    if (italic) return _italic!;
    return _regular!;
  }
}
