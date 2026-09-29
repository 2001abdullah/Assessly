import 'dart:typed_data';

import 'package:assessly/utils/omr_frame_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Draws a synthetic answer sheet (white page, four corner squares and the two
/// timing tracks) into an upright 720x1280 image, then stores it the way a
/// phone camera would hand it over: a landscape 1280x720 sensor frame that
/// must be rotated 90 degrees clockwise to be upright.
LumaFrame syntheticFrame({
  double widthFrac = 0.90,
  bool withSheet = true,
  SheetProfile sheet = const SheetProfile(),
}) {
  const dw = 720;
  const dh = 1280;
  final disp = Uint8List(dw * dh)..fillRange(0, dw * dh, 60); // dark desk

  if (withSheet) {
    final s = dw * widthFrac / 210.0; // px per mm
    final left = (dw - 210 * s) / 2;
    final top = (dh - 297 * s) / 2;

    void rect(double cxMm, double cyMm, double wMm, double hMm, int v) {
      final x0 = (left + (cxMm - wMm / 2) * s).round();
      final x1 = (left + (cxMm + wMm / 2) * s).round();
      final y0 = (top + (cyMm - hMm / 2) * s).round();
      final y1 = (top + (cyMm + hMm / 2) * s).round();
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          disp[y * dw + x] = v;
        }
      }
    }

    rect(105, 148.5, 210, 297, 235); // paper
    for (final c in const [
      [10.0, 10.0],
      [200.0, 10.0],
      [200.0, 287.0],
      [10.0, 287.0],
    ]) {
      rect(c[0], c[1], 6, 6, 30); // corner squares
    }
    for (final x in const [17.0, 193.0]) {
      for (var i = 0; i < sheet.trackRows; i++) {
        // timing marks
        rect(x, sheet.trackFirstYmm + i * sheet.trackPitchMm, 4, 2.6, 30);
      }
    }
  }

  // display -> sensor frame (rotation 90: xf = yd, yf = fh - 1 - xd)
  const fw = dh;
  const fh = dw;
  final raw = Uint8List(fw * fh);
  for (var yd = 0; yd < dh; yd++) {
    for (var xd = 0; xd < dw; xd++) {
      raw[(fh - 1 - xd) * fw + yd] = disp[yd * dw + xd];
    }
  }
  return LumaFrame(
    bytes: raw,
    width: fw,
    height: fh,
    rowStride: fw,
    rotation: 90,
  );
}

void main() {
  test('finds a well-framed sheet and becomes ready once steady', () {
    final analyzer = OmrFrameAnalyzer();
    SheetAnalysis result = SheetAnalysis.none;
    for (var i = 0; i < 8; i++) {
      result = analyzer.analyze(syntheticFrame());
    }
    expect(result.found, isTrue);
    expect(result.turn, SheetTurn.upright);
    expect(result.lock, greaterThan(0.9));
    expect(result.ready, isTrue, reason: 'hint was ${result.hint}');
  });

  test('is not ready on the first frame (needs to be steady)', () {
    final result = OmrFrameAnalyzer().analyze(syntheticFrame());
    expect(result.found, isTrue);
    expect(result.ready, isFalse);
    expect(result.hint, ScanHint.holdStill);
  });

  test('tells the user to move closer when the sheet is small', () {
    final analyzer = OmrFrameAnalyzer();
    final result = analyzer.analyze(syntheticFrame(widthFrac: 0.62));
    expect(result.found, isTrue);
    expect(result.hint, ScanHint.tooFar);
  });

  test('reports nothing when there is no sheet', () {
    final result = OmrFrameAnalyzer().analyze(syntheticFrame(withSheet: false));
    expect(result.found, isFalse);
    expect(result.hint, ScanHint.searching);
  });

  test('detects a sideways sheet', () {
    // Same pixels, but interpreted without the 90 degree rotation.
    final f = syntheticFrame();
    final sideways = LumaFrame(
      bytes: f.bytes,
      width: f.width,
      height: f.height,
      rowStride: f.rowStride,
      rotation: 0,
    );
    final result = OmrFrameAnalyzer().analyze(sideways);
    expect(result.found, isTrue);
    expect(result.turn, SheetTurn.sideways);
    expect(result.hint, ScanHint.sideways);
  });

  group('SheetProfile.forExam', () {
    // (questions, rows, first mark y, pitch) as produced by the backend's
    // build_template() in omr_engine/layout.py.
    const pythonLayouts = [
      [25, 13, 108.702, 13.704],
      [50, 17, 107.090, 10.479],
      [75, 19, 106.538, 9.376],
      [100, 25, 105.413, 7.126],
    ];

    for (final l in pythonLayouts) {
      test('matches the backend layout for ${l[0]} questions', () {
        final p = SheetProfile.forExam(questions: l[0] as int);
        expect(p.trackRows, l[1]);
        expect(p.trackFirstYmm, closeTo(l[2] as double, 0.001));
        expect(p.trackPitchMm, closeTo(l[3] as double, 0.001));
      });
    }

    for (final q in const [25, 50, 75, 100]) {
      test('camera finds a $q-question sheet', () {
        final sheet = SheetProfile.forExam(questions: q);
        final result = OmrFrameAnalyzer(
          profile: sheet,
        ).analyze(syntheticFrame(sheet: sheet));
        expect(result.found, isTrue);
        expect(result.turn, SheetTurn.upright);
        expect(result.lock, greaterThan(0.9));
      });
    }

    test('falls back to the default sheet without a question count', () {
      final p = SheetProfile.forExamJson(const {'title': 'x'});
      expect(p.trackRows, 25);
    });
  });
}
