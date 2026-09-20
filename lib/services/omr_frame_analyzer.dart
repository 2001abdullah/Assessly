// Live OMR sheet detection for camera frames.
//
// Pure Dart (no Flutter imports) so it can be unit-tested with `flutter test`.
// It is a line-by-line port of a Python prototype that was validated against
// synthetic phone frames and real photos of answer sheets.
//
// What it does, per frame (about 5-10 ms in a release build):
//   1. Sub-samples the luminance plane into a ~360 px wide portrait grid.
//   2. Adaptive-thresholds it (integral image, local mean) so shadows and pale
//      floors do not break detection.
//   3. Finds square-ish dark blobs (candidate corner markers).
//   4. Scores every set of four by geometry (convex, sheet aspect ratio,
//      similar sizes, marker size relative to sheet size).
//   5. VERIFIES the best sets against the printed timing marks (the same idea
//      the backend engine uses). This is what rejects random clutter and tells
//      us whether the sheet is upright, upside-down or sideways.
//   6. Derives coaching signals: distance, centring, tilt, keystone, light,
//      glare, focus, steadiness.
//
// The geometry constants in [SheetProfile] describe the printed sheet and must
// match the template the sheets were printed from (defaults: the backend's
// sample_template.json). Timing marks are matched with a few mm of tolerance
// so small printer offsets do not matter.

import 'dart:math' as math;
import 'dart:typed_data';

/// How the sheet is turned relative to the phone.
enum SheetTurn { upright, upsideDown, sideways }

/// What the user should do next, most important first.
enum ScanHint {
  searching,
  sideways,
  edge,
  tooFar,
  offCenter,
  tilted,
  keystone,
  tooDark,
  glare,
  unfocused,
  holdStill,
  ready,
}

/// Physical layout of the printed sheet (millimetres, origin top-left).
class SheetProfile {
  const SheetProfile({
    this.pageWidthMm = 210.0,
    this.pageHeightMm = 297.0,
    this.fiducialSizeMm = 6.0,
    this.fiducialSpanWidthMm = 190.0,
    this.fiducialSpanHeightMm = 277.0,
    this.fiducialCorners = const [
      [10.0, 10.0],
      [200.0, 10.0],
      [200.0, 287.0],
      [10.0, 287.0],
    ],
    this.trackXmm = const [17.0, 193.0],
    this.trackFirstYmm = 105.413,
    this.trackPitchMm = 7.126,
    this.trackRows = 25,
    this.trackTolXmm = 4.0,
    this.trackTolYmm = 2.6,
  });

  final double pageWidthMm;
  final double pageHeightMm;
  final double fiducialSizeMm;
  final double fiducialSpanWidthMm;
  final double fiducialSpanHeightMm;

  /// Marker centres in page order: top-left, top-right, bottom-right, bottom-left.
  final List<List<double>> fiducialCorners;
  final List<double> trackXmm;
  final double trackFirstYmm;
  final double trackPitchMm;
  final int trackRows;
  final double trackTolXmm;
  final double trackTolYmm;

  double get aspect => fiducialSpanWidthMm / fiducialSpanHeightMm;
  double get fiducialToWidth => fiducialSizeMm / fiducialSpanWidthMm;
}

/// Tunable thresholds. Defaults were chosen on synthetic and real photos;
/// adjust after trying real devices.
class AnalyzerConfig {
  const AnalyzerConfig({
    this.gridWidth = 360,
    this.blockFrac = 0.055,
    this.darkRatio = 0.72,
    this.lockMin = 0.55,
    this.edgeMargin = 0.025,
    this.minSheetWidthFrac = 0.70,
    this.maxOffCenterX = 0.08,
    this.maxOffCenterY = 0.10,
    this.maxTiltDeg = 5.0,
    this.maxKeystone = 0.10,
    this.minPaperLevel = 90,
    this.maxGlareFrac = 0.25,
    this.minFocus = 0.03,
    this.steadyFrames = 4,
    this.steadyMove = 0.006,
  });

  final int gridWidth;

  /// Half-size of the local-mean window as a fraction of grid width.
  final double blockFrac;

  /// A pixel is "ink" when darker than this fraction of its local mean.
  final double darkRatio;

  /// Minimum fraction of the 50 timing marks that must be found.
  final double lockMin;

  /// Markers closer than this (fraction of frame) to the edge -> "fit the sheet".
  final double edgeMargin;

  /// Marker span / frame width below this -> "move closer".
  final double minSheetWidthFrac;
  final double maxOffCenterX;
  final double maxOffCenterY;
  final double maxTiltDeg;

  /// Max relative difference between opposite sides (perspective).
  final double maxKeystone;

  /// Paper brightness (0-255) below this -> "too dark".
  final int minPaperLevel;

  /// Fraction of paper samples saturated above which -> "glare".
  final double maxGlareFrac;

  /// Normalised focus score below this -> "focusing".
  final double minFocus;

  /// Consecutive steady analyses required before auto-capture.
  final int steadyFrames;

  /// Max corner movement between analyses (fraction of frame width).
  final double steadyMove;
}

/// A point in normalised display coordinates (0..1, origin top-left, portrait).
class NormPoint {
  const NormPoint(this.x, this.y);
  final double x;
  final double y;
}

/// One camera frame's luminance, plus how to rotate it upright.
class LumaFrame {
  const LumaFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.rowStride,
    this.pixelStride = 1,
    this.rotation = 0,
    this.bgra = false,
  });

  /// Plane 0 of the frame (Y for YUV, or interleaved BGRA).
  final Uint8List bytes;
  final int width;
  final int height;
  final int rowStride;

  /// Bytes per pixel in [bytes] (1 for a Y plane, 4 for BGRA).
  final int pixelStride;

  /// Clockwise degrees (0/90/180/270) that turn the raw frame upright.
  final int rotation;
  final bool bgra;

  int get displayWidth => (rotation == 90 || rotation == 270) ? height : width;
  int get displayHeight => (rotation == 90 || rotation == 270) ? width : height;

  /// Luminance at a pixel of the upright (display) image.
  int lum(int xd, int yd) {
    int xf;
    int yf;
    switch (rotation) {
      case 90:
        xf = yd;
        yf = height - 1 - xd;
        break;
      case 180:
        xf = width - 1 - xd;
        yf = height - 1 - yd;
        break;
      case 270:
        xf = width - 1 - yd;
        yf = xd;
        break;
      default:
        xf = xd;
        yf = yd;
    }
    final i = yf * rowStride + xf * pixelStride;
    if (!bgra) return bytes[i];
    return (bytes[i] * 29 + bytes[i + 1] * 150 + bytes[i + 2] * 77) >> 8;
  }
}

/// Result of analysing one frame.
class SheetAnalysis {
  const SheetAnalysis({
    required this.hint,
    this.corners = const [],
    this.turn,
    this.lock = 0,
    this.focus,
    this.steady = false,
    this.ready = false,
  });

  final ScanHint hint;

  /// Marker centres in page order (tl, tr, br, bl), empty when no sheet.
  final List<NormPoint> corners;
  final SheetTurn? turn;

  /// Fraction of timing marks matched (0..1).
  final double lock;

  /// Normalised focus score, null when the view has too little content.
  final double? focus;
  final bool steady;

  /// True when every check passes and the sheet has been steady.
  final bool ready;

  bool get found => corners.length == 4;

  static const SheetAnalysis none = SheetAnalysis(hint: ScanHint.searching);
}

class _Comp {
  _Comp(this.cx, this.cy, this.bw, this.bh, this.area, this.x, this.y);
  final double cx;
  final double cy;
  final int bw;
  final int bh;
  final int area;
  final int x;
  final int y;
  double get fill => area / (bw * bh);
}

class _Quad {
  _Quad(this.penalty, this.pts);
  final double penalty;

  /// Clockwise from the top-left-most point, in grid coordinates.
  final List<List<double>> pts;
}

class OmrFrameAnalyzer {
  OmrFrameAnalyzer({
    this.config = const AnalyzerConfig(),
    this.profile = const SheetProfile(),
  });

  final AnalyzerConfig config;
  final SheetProfile profile;

  List<NormPoint>? _prev;
  int _steady = 0;

  void reset() {
    _prev = null;
    _steady = 0;
  }

  SheetAnalysis analyze(LumaFrame f) {
    final dw = f.displayWidth;
    final dh = f.displayHeight;
    final step = math.max(1, (dw / config.gridWidth).round());
    final gw = dw ~/ step;
    final gh = dh ~/ step;
    if (gw < 40 || gh < 40) return _lost();

    // 1. sub-sampled grid ---------------------------------------------------
    final g = Uint8List(gw * gh);
    for (var y = 0; y < gh; y++) {
      final row = y * gw;
      for (var x = 0; x < gw; x++) {
        g[row + x] = f.lum(x * step, y * step);
      }
    }

    // 2. adaptive "ink" mask ------------------------------------------------
    final mask = _darkMask(g, gw, gh);

    // 3. blobs ----------------------------------------------------------------
    final comps = _components(mask, gw, gh);
    final fids = _fiducialCandidates(comps, gw, gh);
    if (fids.length < 4) return _lost();

    // 4 + 5. geometry ranking, then timing-mark verification -----------------
    final marks = comps
        .where(
          (c) =>
              c.area >= 4 &&
              c.area <= 160 &&
              c.bw <= 16 &&
              c.bh <= 12 &&
              c.fill >= 0.55,
        )
        .toList();
    List<List<double>>? bestPage;
    var bestShift = 0;
    var bestLock = -1.0;
    for (final q in _rankedQuads(fids)) {
      for (var shift = 0; shift < 4; shift++) {
        final page = [for (var i = 0; i < 4; i++) q.pts[(i + shift) % 4]];
        final lock = _timingLock(page, marks);
        if (lock > bestLock) {
          bestLock = lock;
          bestPage = page;
          bestShift = shift;
        }
      }
    }
    if (bestPage == null || bestLock < config.lockMin) return _lost();

    // 6. coaching signals ------------------------------------------------------
    final page = bestPage;
    final turn = bestShift == 0
        ? SheetTurn.upright
        : (bestShift == 2 ? SheetTurn.upsideDown : SheetTurn.sideways);
    final corners = [
      for (final p in page) NormPoint(p[0] * step / dw, p[1] * step / dh),
    ];

    // steadiness
    final prev = _prev;
    if (prev != null) {
      var move = 0.0;
      for (var i = 0; i < 4; i++) {
        final dx = corners[i].x - prev[i].x;
        final dy = (corners[i].y - prev[i].y) * dh / dw;
        move = math.max(move, math.sqrt(dx * dx + dy * dy));
      }
      _steady = move <= config.steadyMove ? _steady + 1 : 0;
    } else {
      _steady = 0;
    }
    _prev = corners;
    final steady = _steady >= config.steadyFrames;

    if (turn == SheetTurn.sideways) {
      return SheetAnalysis(
        hint: ScanHint.sideways,
        corners: corners,
        turn: turn,
        lock: bestLock,
        steady: steady,
      );
    }

    // geometry in grid pixels
    double dist(List<double> a, List<double> b) =>
        math.sqrt(math.pow(a[0] - b[0], 2) + math.pow(a[1] - b[1], 2));
    final top = dist(page[0], page[1]);
    final right = dist(page[1], page[2]);
    final bottom = dist(page[3], page[2]);
    final left = dist(page[0], page[3]);
    final widthFrac = (top + bottom) / 2 / gw;
    final keystone = math.max(
      (top - bottom).abs() / ((top + bottom) / 2),
      (left - right).abs() / ((left + right) / 2),
    );
    var tilt =
        math.atan2(page[1][1] - page[0][1], page[1][0] - page[0][0]) *
        180 /
        math.pi;
    tilt = ((tilt + 90) % 180) - 90; // fold so upside-down reads as ~0
    final cx = corners.map((c) => c.x).reduce((a, b) => a + b) / 4;
    final cy = corners.map((c) => c.y).reduce((a, b) => a + b) / 4;
    final nearEdge = corners.any(
      (c) =>
          c.x < config.edgeMargin ||
          c.x > 1 - config.edgeMargin ||
          c.y < config.edgeMargin ||
          c.y > 1 - config.edgeMargin,
    );

    // light
    final light = _light(g, gw, gh, page);
    // focus (full resolution)
    final focus = _focus(f, page, step);

    ScanHint hint;
    if (nearEdge) {
      hint = ScanHint.edge;
    } else if (widthFrac < config.minSheetWidthFrac) {
      hint = ScanHint.tooFar;
    } else if ((cx - 0.5).abs() > config.maxOffCenterX ||
        (cy - 0.5).abs() > config.maxOffCenterY) {
      hint = ScanHint.offCenter;
    } else if (tilt.abs() > config.maxTiltDeg) {
      hint = ScanHint.tilted;
    } else if (keystone > config.maxKeystone) {
      hint = ScanHint.keystone;
    } else if (light.$1 < config.minPaperLevel) {
      hint = ScanHint.tooDark;
    } else if (light.$2 > config.maxGlareFrac) {
      hint = ScanHint.glare;
    } else if (focus != null && focus < config.minFocus) {
      hint = ScanHint.unfocused;
    } else if (!steady) {
      hint = ScanHint.holdStill;
    } else {
      hint = ScanHint.ready;
    }

    return SheetAnalysis(
      hint: hint,
      corners: corners,
      turn: turn,
      lock: bestLock,
      focus: focus,
      steady: steady,
      ready: hint == ScanHint.ready,
    );
  }

  SheetAnalysis _lost() {
    _prev = null;
    _steady = 0;
    return SheetAnalysis.none;
  }

  // --------------------------------------------------------------------------
  // Stage 2: adaptive ink mask
  // --------------------------------------------------------------------------
  Uint8List _darkMask(Uint8List g, int gw, int gh) {
    final w1 = gw + 1;
    final ii = Int32List(w1 * (gh + 1));
    for (var y = 0; y < gh; y++) {
      var rowSum = 0;
      for (var x = 0; x < gw; x++) {
        rowSum += g[y * gw + x];
        ii[(y + 1) * w1 + (x + 1)] = ii[y * w1 + (x + 1)] + rowSum;
      }
    }
    final r = math.max(4, (config.blockFrac * gw).round());
    final ratio100 = (config.darkRatio * 100).round();
    final mask = Uint8List(gw * gh);
    for (var y = 0; y < gh; y++) {
      final y0 = math.max(0, y - r);
      final y1 = math.min(gh, y + r + 1);
      for (var x = 0; x < gw; x++) {
        final x0 = math.max(0, x - r);
        final x1 = math.min(gw, x + r + 1);
        final area = (y1 - y0) * (x1 - x0);
        final s =
            ii[y1 * w1 + x1] -
            ii[y0 * w1 + x1] -
            ii[y1 * w1 + x0] +
            ii[y0 * w1 + x0];
        final v = g[y * gw + x];
        if (s > 50 * area && v * area * 100 < ratio100 * s) {
          mask[y * gw + x] = 1;
        }
      }
    }
    return mask;
  }

  // --------------------------------------------------------------------------
  // Stage 3: connected components (8-connectivity), small blobs only
  // --------------------------------------------------------------------------
  List<_Comp> _components(Uint8List mask, int gw, int gh) {
    final out = <_Comp>[];
    final stack = Int32List(gw * gh);
    for (var start = 0; start < gw * gh; start++) {
      if (mask[start] != 1) continue;
      var sp = 0;
      stack[sp++] = start;
      mask[start] = 2;
      var area = 0;
      var minX = gw;
      var maxX = -1;
      var minY = gh;
      var maxY = -1;
      var sx = 0.0;
      var sy = 0.0;
      while (sp > 0) {
        final p = stack[--sp];
        final py = p ~/ gw;
        final px = p - py * gw;
        area++;
        sx += px;
        sy += py;
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = py + dy;
          if (ny < 0 || ny >= gh) continue;
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = px + dx;
            if (nx < 0 || nx >= gw) continue;
            final ni = ny * gw + nx;
            if (mask[ni] == 1) {
              mask[ni] = 2;
              stack[sp++] = ni;
            }
          }
        }
      }
      final bw = maxX - minX + 1;
      final bh = maxY - minY + 1;
      if (area >= 4 && area <= 400 && bw <= 24 && bh <= 24) {
        out.add(_Comp(sx / area, sy / area, bw, bh, area, minX, minY));
      }
    }
    return out;
  }

  List<_Comp> _fiducialCandidates(List<_Comp> comps, int gw, int gh) {
    final out = <_Comp>[];
    for (final c in comps) {
      if (c.area < 9 || c.bw < 4 || c.bh < 4 || c.bw > 22 || c.bh > 22) {
        continue;
      }
      if (c.x <= 0 || c.y <= 0 || c.x + c.bw >= gw || c.y + c.bh >= gh) {
        continue;
      }
      final asp = c.bw / c.bh;
      if (c.fill < 0.68 || asp < 0.7 || asp > 1.45) continue;
      out.add(c);
    }
    return out;
  }

  // --------------------------------------------------------------------------
  // Stage 4: rank four-marker sets by geometry
  // --------------------------------------------------------------------------
  List<_Quad> _rankedQuads(List<_Comp> fids) {
    final pool = List<_Comp>.of(fids)
      ..sort((a, b) => (b.area * b.fill).compareTo(a.area * a.fill));
    if (pool.length > 16) pool.removeRange(16, pool.length);
    final n = pool.length;
    final res = <_Quad>[];
    final target = profile.aspect;
    for (var a = 0; a < n - 3; a++) {
      for (var b = a + 1; b < n - 2; b++) {
        for (var c = b + 1; c < n - 1; c++) {
          for (var d = c + 1; d < n; d++) {
            final q = _scoreQuad([pool[a], pool[b], pool[c], pool[d]], target);
            if (q != null) res.add(q);
          }
        }
      }
    }
    res.sort((x, y) => x.penalty.compareTo(y.penalty));
    return res.length > 6 ? res.sublist(0, 6) : res;
  }

  _Quad? _scoreQuad(List<_Comp> four, double target) {
    final cxm = four.map((c) => c.cx).reduce((a, b) => a + b) / 4;
    final cym = four.map((c) => c.cy).reduce((a, b) => a + b) / 4;
    final idx = [0, 1, 2, 3]
      ..sort((i, j) {
        final ai = math.atan2(four[i].cy - cym, four[i].cx - cxm);
        final aj = math.atan2(four[j].cy - cym, four[j].cx - cxm);
        return ai.compareTo(aj);
      });
    var ordered = [for (final i in idx) four[i]];
    var first = 0;
    var bestSum = double.infinity;
    for (var i = 0; i < 4; i++) {
      final s = ordered[i].cx + ordered[i].cy;
      if (s < bestSum) {
        bestSum = s;
        first = i;
      }
    }
    ordered = [for (var i = 0; i < 4; i++) ordered[(i + first) % 4]];
    final pts = [
      for (final c in ordered) [c.cx, c.cy],
    ];

    // convex: every turn has the same sign
    var pos = 0;
    var neg = 0;
    for (var a = 0; a < 4; a++) {
      final p = pts[a];
      final q = pts[(a + 1) % 4];
      final r = pts[(a + 2) % 4];
      final cross =
          (q[0] - p[0]) * (r[1] - q[1]) - (q[1] - p[1]) * (r[0] - q[0]);
      if (cross > 0) pos++;
      if (cross < 0) neg++;
    }
    if (pos != 4 && neg != 4) return null;

    double dist(List<double> a, List<double> b) =>
        math.sqrt(math.pow(a[0] - b[0], 2) + math.pow(a[1] - b[1], 2));
    final top = dist(pts[0], pts[1]);
    final right = dist(pts[1], pts[2]);
    final bottom = dist(pts[2], pts[3]);
    final left = dist(pts[3], pts[0]);
    if (math.min(math.min(top, right), math.min(bottom, left)) < 10) {
      return null;
    }

    // aspect: allow a quarter turn (ratio or its inverse)
    final ratio = (top + bottom) / (left + right);
    final penA = math.min(
      (math.log(ratio / target)).abs(),
      (math.log(ratio * target)).abs(),
    );
    if (penA > 0.30) return null;

    var amin = double.infinity;
    var amax = 0.0;
    var asum = 0.0;
    for (final c in ordered) {
      amin = math.min(amin, c.area.toDouble());
      amax = math.max(amax, c.area.toDouble());
      asum += c.area;
    }
    final penS = math.log(amax / math.max(amin, 1.0));
    if (penS > 1.5) return null;

    final spanW = math.min((top + bottom) / 2, (left + right) / 2);
    final rel = math.sqrt(asum / 4) / spanW;
    final f2w = profile.fiducialToWidth;
    if (rel < 0.45 * f2w || rel > 2.2 * f2w) return null;

    return _Quad(3 * penA + 0.6 * penS + (math.log(rel / f2w)).abs(), pts);
  }

  // --------------------------------------------------------------------------
  // Stage 5: timing-mark verification
  // --------------------------------------------------------------------------
  /// Fraction of the printed timing marks that have a mark-like blob near where
  /// the four markers predict them. [page] is in page order.
  double _timingLock(List<List<double>> page, List<_Comp> marks) {
    if (marks.isEmpty) return 0.0;
    final h = _homography(profile.fiducialCorners, page);
    if (h == null) return 0.0;
    var hits = 0;
    final total = profile.trackXmm.length * profile.trackRows;
    for (final tx in profile.trackXmm) {
      for (var row = 0; row < profile.trackRows; row++) {
        final ty = profile.trackFirstYmm + row * profile.trackPitchMm;
        final p = _apply(h, tx, ty);
        final px = _apply(h, tx + 1, ty);
        final py = _apply(h, tx, ty + 1);
        final exx = px[0] - p[0];
        final exy = px[1] - p[1];
        final eyx = py[0] - p[0];
        final eyy = py[1] - p[1];
        final lx = math.sqrt(exx * exx + exy * exy);
        final ly = math.sqrt(eyx * eyx + eyy * eyy);
        if (lx < 1e-6 || ly < 1e-6) continue;
        for (final m in marks) {
          final vx = m.cx - p[0];
          final vy = m.cy - p[1];
          final u = (vx * exx + vy * exy) / (lx * lx); // mm along sheet x
          final w = (vx * eyx + vy * eyy) / (ly * ly); // mm along sheet y
          if (u.abs() <= profile.trackTolXmm &&
              w.abs() <= profile.trackTolYmm) {
            hits++;
            break;
          }
        }
      }
    }
    return hits / total;
  }

  /// Solves the 3x3 homography mapping [src] (mm) to [dst] (grid px).
  List<double>? _homography(List<List<double>> src, List<List<double>> dst) {
    final a = List.generate(8, (_) => List<double>.filled(9, 0.0));
    for (var i = 0; i < 4; i++) {
      final x = src[i][0];
      final y = src[i][1];
      final u = dst[i][0];
      final v = dst[i][1];
      a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
      a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
    }
    for (var col = 0; col < 8; col++) {
      var piv = col;
      for (var r = col + 1; r < 8; r++) {
        if (a[r][col].abs() > a[piv][col].abs()) piv = r;
      }
      if (a[piv][col].abs() < 1e-9) return null;
      final tmp = a[col];
      a[col] = a[piv];
      a[piv] = tmp;
      for (var r = 0; r < 8; r++) {
        if (r == col) continue;
        final k = a[r][col] / a[col][col];
        if (k == 0) continue;
        for (var c = col; c < 9; c++) {
          a[r][c] -= k * a[col][c];
        }
      }
    }
    return [for (var i = 0; i < 8; i++) a[i][8] / a[i][i]];
  }

  List<double> _apply(List<double> h, double x, double y) {
    final w = h[6] * x + h[7] * y + 1.0;
    return [(h[0] * x + h[1] * y + h[2]) / w, (h[3] * x + h[4] * y + h[5]) / w];
  }

  // --------------------------------------------------------------------------
  // Light: paper level and glare, sampled on a lattice inside the sheet
  // --------------------------------------------------------------------------
  /// Returns (paper level 0-255, fraction of saturated samples).
  (int, double) _light(Uint8List g, int gw, int gh, List<List<double>> page) {
    final vals = <int>[];
    var glare = 0;
    for (var iv = 1; iv <= 13; iv++) {
      final v = 0.06 + 0.88 * (iv - 1) / 12;
      for (var iu = 1; iu <= 9; iu++) {
        final u = 0.06 + 0.88 * (iu - 1) / 8;
        final p = _bilinear(page, u, v);
        final x = p[0].round();
        final y = p[1].round();
        if (x < 0 || y < 0 || x >= gw || y >= gh) continue;
        final value = g[y * gw + x];
        vals.add(value);
        if (value >= 250) glare++;
      }
    }
    if (vals.isEmpty) return (0, 0.0);
    vals.sort();
    final p90 = vals[((vals.length - 1) * 0.9).round()];
    return (p90, glare / vals.length);
  }

  List<double> _bilinear(List<List<double>> page, double u, double v) {
    final tl = page[0];
    final tr = page[1];
    final br = page[2];
    final bl = page[3];
    final topx = tl[0] + (tr[0] - tl[0]) * u;
    final topy = tl[1] + (tr[1] - tl[1]) * u;
    final botx = bl[0] + (br[0] - bl[0]) * u;
    final boty = bl[1] + (br[1] - bl[1]) * u;
    return [topx + (botx - topx) * v, topy + (boty - topy) * v];
  }

  // --------------------------------------------------------------------------
  // Focus: Laplacian variance / intensity variance on full-resolution patches
  // --------------------------------------------------------------------------
  /// Normalised, exposure-independent focus measure; null when the view has too
  /// little printed content to judge.
  double? _focus(LumaFrame f, List<List<double>> pageGrid, int step) {
    const half = 24;
    final dw = f.displayWidth;
    final dh = f.displayHeight;
    final scores = <double>[];
    final page = [
      for (final p in pageGrid) [p[0] * step, p[1] * step],
    ];
    for (final v in const [0.50, 0.62, 0.74, 0.86]) {
      for (final u in const [0.18, 0.40, 0.62, 0.84]) {
        final p = _bilinear(page, u, v);
        final cx = p[0].round();
        final cy = p[1].round();
        if (cx - half < 1 ||
            cy - half < 1 ||
            cx + half >= dw - 1 ||
            cy + half >= dh - 1) {
          continue;
        }
        // variance of intensity
        var sum = 0.0;
        var sum2 = 0.0;
        var n = 0;
        for (var y = cy - half; y < cy + half; y++) {
          for (var x = cx - half; x < cx + half; x++) {
            final l = f.lum(x, y).toDouble();
            sum += l;
            sum2 += l * l;
            n++;
          }
        }
        final mean = sum / n;
        final variance = sum2 / n - mean * mean;
        if (variance < 100) continue; // blank paper: nothing to judge
        // variance of the 4-neighbour Laplacian
        var ls = 0.0;
        var ls2 = 0.0;
        var ln = 0;
        for (var y = cy - half + 1; y < cy + half - 1; y++) {
          for (var x = cx - half + 1; x < cx + half - 1; x++) {
            final lap =
                f.lum(x - 1, y) +
                f.lum(x + 1, y) +
                f.lum(x, y - 1) +
                f.lum(x, y + 1) -
                4 * f.lum(x, y);
            ls += lap;
            ls2 += lap * lap;
            ln++;
          }
        }
        final lm = ls / ln;
        final lv = ls2 / ln - lm * lm;
        scores.add(lv / variance);
      }
    }
    if (scores.length < 3) return null;
    scores.sort();
    return scores[scores.length ~/ 2];
  }
}
