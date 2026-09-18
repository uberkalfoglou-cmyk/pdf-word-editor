import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_word_editor/widgets/signature_pad.dart';

void main() {
  test('ink starts on the first touch, no curve required', () {
    final ink = SignatureInk();
    expect(ink.hasInk, isFalse);

    ink.start(const Offset(10, 10));
    ink.end();

    expect(ink.hasInk, isTrue);
    expect(ink.strokes.single, [const Offset(10, 10)]);
  });

  test('a straight line is recorded, not dropped', () {
    final ink = SignatureInk();
    ink.start(const Offset(0, 0));
    ink.append(const Offset(20, 0));
    ink.append(const Offset(40, 0));
    ink.end();

    expect(ink.strokes.single.length, greaterThanOrEqualTo(3));
  });
}
