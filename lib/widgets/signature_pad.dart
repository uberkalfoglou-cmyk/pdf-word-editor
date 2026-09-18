import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// In-memory ink: a stroke starts on the first touch (even a dot or a
/// straight line). No minimum curve / point-threshold.
class SignatureInk {
  final List<List<Offset>> strokes = [];
  List<Offset>? _current;

  bool get hasInk => strokes.any((s) => s.isNotEmpty);

  void start(Offset point) {
    _current = [point];
    strokes.add(_current!);
  }

  void append(Offset point) {
    final stroke = _current;
    if (stroke == null) return;
    if (stroke.isEmpty) {
      stroke.add(point);
      return;
    }
    if ((point - stroke.last).distance < 0.8) return;
    stroke.add(point);
  }

  void end() {
    _current = null;
  }

  void clear() {
    strokes.clear();
    _current = null;
  }

  Rect? bounds({double padding = 16}) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    var any = false;
    for (final stroke in strokes) {
      for (final p in stroke) {
        any = true;
        minX = math.min(minX, p.dx);
        minY = math.min(minY, p.dy);
        maxX = math.max(maxX, p.dx);
        maxY = math.max(maxY, p.dy);
      }
    }
    if (!any) return null;
    return Rect.fromLTRB(minX - padding, minY - padding, maxX + padding, maxY + padding);
  }
}

/// Full-screen finger signature. Ink appears on the first contact.
class SignaturePadPage extends StatefulWidget {
  const SignaturePadPage({super.key});

  @override
  State<SignaturePadPage> createState() => _SignaturePadPageState();
}

class _SignaturePadPageState extends State<SignaturePadPage> {
  final SignatureInk _ink = SignatureInk();

  static const List<Color> _inkColors = [
    Colors.black,
    Color(0xFF1A3FAE),
    Color(0xFFB3261E),
  ];

  Color _inkColor = _inkColors.first;
  static const double _strokeWidth = 3.2;

  void _clear() {
    setState(_ink.clear);
  }

  Future<void> _use() async {
    if (!_ink.hasInk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).drawFirst)),
      );
      return;
    }
    try {
      final bytes = await _exportPng();
      if (bytes == null) return;
      if (mounted) Navigator.pop(context, bytes);
    } catch (e, st) {
      debugPrint('[SignaturePad] capture failed: $e\n$st');
    }
  }

  Future<Uint8List?> _exportPng() async {
    final bounds = _ink.bounds();
    if (bounds == null) return null;
    const scale = 3.0;
    final width = math.max(1, (bounds.width * scale).ceil());
    final height = math.max(1, (bounds.height * scale).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.translate(-bounds.left, -bounds.top);
    _paintStrokes(canvas, _ink.strokes, _inkColor, _strokeWidth);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: s.cancel,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(s.drawSignature),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: s.clear,
            onPressed: _clear,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              icon: const Icon(Icons.check_circle),
              tooltip: s.use,
              onPressed: _use,
              style: IconButton.styleFrom(
                backgroundColor: Colors.green.shade50,
                foregroundColor: Colors.green.shade700,
                shape: const CircleBorder(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (final color in _inkColors) _buildInkSwatch(color)],
            ),
          ),
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                _ink.start(event.localPosition);
                setState(() {});
              },
              onPointerMove: (event) {
                _ink.append(event.localPosition);
                setState(() {});
              },
              onPointerUp: (_) => _ink.end(),
              onPointerCancel: (_) => _ink.end(),
              child: CustomPaint(
                painter: _SignaturePainter(
                  strokes: _ink.strokes,
                  color: _inkColor,
                  strokeWidth: _strokeWidth,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInkSwatch(Color color) {
    final selected = color == _inkColor;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _inkColor = color),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: selected ? 30 : 24,
            height: selected ? 30 : 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.grey.shade800 : Colors.grey.shade300,
                width: selected ? 2.5 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _paintStrokes(Canvas canvas, List<List<Offset>> strokes, Color color, double width) {
  final strokePaint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  final fillPaint = Paint()
    ..color = color
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  for (final stroke in strokes) {
    if (stroke.isEmpty) continue;
    if (stroke.length == 1) {
      canvas.drawCircle(stroke.first, width / 2, fillPaint);
      continue;
    }
    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    if (stroke.length == 2) {
      path.lineTo(stroke.last.dx, stroke.last.dy);
    } else {
      for (var i = 1; i < stroke.length - 1; i++) {
        final current = stroke[i];
        final next = stroke[i + 1];
        final mid = Offset((current.dx + next.dx) / 2, (current.dy + next.dy) / 2);
        path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
      }
      path.lineTo(stroke.last.dx, stroke.last.dy);
    }
    canvas.drawPath(path, strokePaint);
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({
    required this.strokes,
    required this.color,
    required this.strokeWidth,
  });

  final List<List<Offset>> strokes;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    _paintStrokes(canvas, strokes, color, strokeWidth);
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
