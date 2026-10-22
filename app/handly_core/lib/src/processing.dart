import 'dart:math' as math;
import 'dart:typed_data';

import 'config.dart';
import 'seq.dart';

/// PRD 10-3 좌표 처리 규칙. demo/processing.py 와 한 줄씩 대응한다.
/// ① 화면 비율 보정 → ② 어깨 기준점 → ③ 왼/오손 다시 정하기 → ④ 짧은 끊김 보간
/// → ⑤ 어깨 기준 정규화 → ⑥ 1초당 30개로 다시 샘플링
Seq processTake(RawTake take, [HandlyConfig cfg = const HandlyConfig()]) {
  final T = take.length;
  if (T < 2) return Seq.empty('too_short');
  final t = take.t;
  final aspect = take.width / take.height;
  final scale = [aspect, 1.0, aspect];

  final hands = Float64List(T * 2 * kPoints * kDims);
  for (var i = 0; i < hands.length; i++) {
    hands[i] = take.hands[i] * scale[i % 3];
  }
  double pose(int i, int p, int c) => take.pose[(i * 5 + p) * 3 + c] * scale[c];

  // 어깨 기준점: 중앙값 사용
  final okIdx = [for (var i = 0; i < T; i++) if (take.poseOk[i]) i];
  if (okIdx.length < math.max(3, 0.2 * T)) return Seq.empty('no_shoulder');
  double med(double Function(int i) f) => _median([for (final i in okIdx) f(i)]);
  final lsh = [med((i) => pose(i, kPoseLSh, 0)), med((i) => pose(i, kPoseLSh, 1))];
  final rsh = [med((i) => pose(i, kPoseRSh, 0)), med((i) => pose(i, kPoseRSh, 1))];
  final cx = (lsh[0] + rsh[0]) / 2, cy = (lsh[1] + rsh[1]) / 2;
  final sw = _hyp(lsh[0] - rsh[0], lsh[1] - rsh[1]);
  if (sw < 1e-3) return Seq.empty('no_shoulder');
  final nose = [med((i) => pose(i, kPoseNose, 0)), med((i) => pose(i, kPoseNose, 1))];
  final earW = med((i) => _hyp(pose(i, kPoseLEar, 0) - pose(i, kPoseREar, 0), pose(i, kPoseLEar, 1) - pose(i, kPoseREar, 1)));
  final r = math.max(earW / sw * 0.85, 0.25);
  final head = [(nose[0] - cx) / sw, (nose[1] - cy) / sw - 0.3 * r, r];

  final (X, ok) = _assignSlots(t, hands, take.handOk, cx, sw);
  _fillShortGaps(t, X, ok, cfg);

  for (var i = 0; i < T; i++) {
    for (var k = 0; k < 2; k++) {
      for (var j = 0; j < kPoints; j++) {
        final b = seqIndex(i, k, j, 0);
        if (!ok[i * 2 + k]) {
          X[b] = 0;
          X[b + 1] = 0;
          X[b + 2] = 0;
          continue;
        }
        X[b] = (X[b] - cx) / sw;
        X[b + 1] = (X[b + 1] - cy) / sw;
        X[b + 2] = X[b + 2] / sw;
      }
    }
  }
  return _resample(t, X, ok, cfg.targetFps, head);
}

double _hyp(double a, double b) => math.sqrt(a * a + b * b);

double _median(List<double> v) {
  final s = [...v]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// MediaPipe 왼/오 라벨 대신, 손목이 몸 중심의 어느 쪽에 있는지로 정함.
/// 손목이 몸 중심 가까이(애매한 구역)에 있을 때만 직전 위치를 이어 봄.
(Float64List, List<bool>) _assignSlots(List<double> t, Float64List hands, List<bool> handOk, double cx, double sw) {
  final N = t.length;
  final out = Float64List(N * 2 * kPoints * kDims);
  final ok = List<bool>.filled(N * 2, false);
  final lastT = <double?>[null, null];
  final lastW = [
    [0.0, 0.0],
    [0.0, 0.0],
  ];
  const recentSec = 0.3;
  final ambiguous = 0.25 * sw;
  final nearDist = 0.4 * sw;

  double wx(int i, int d) => hands[seqIndex(i, d, 0, 0)];
  double wy(int i, int d) => hands[seqIndex(i, d, 0, 1)];
  double dist(int i, int d, int k) => _hyp(wx(i, d) - lastW[k][0], wy(i, d) - lastW[k][1]);

  for (var i = 0; i < N; i++) {
    final det = [for (var d = 0; d < 2; d++) if (handOk[i * 2 + d]) d];
    final recent = [for (var k = 0; k < 2; k++) if (lastT[k] != null && t[i] - lastT[k]! <= recentSec) k];
    var slots = <int>[];
    if (det.length == 2) {
      if (wx(i, det[1]) < wx(i, det[0])) det.setAll(0, [det[1], det[0]]); // 손목 x 순서 (같으면 그대로)
      slots = [0, 1];
      if (recent.length == 2 && wx(i, det[1]) - wx(i, det[0]) < ambiguous) {
        final straight = dist(i, det[0], 0) + dist(i, det[1], 1);
        final swapped = dist(i, det[0], 1) + dist(i, det[1], 0);
        if (swapped < straight) slots = [1, 0];
      }
    } else if (det.length == 1) {
      final d = det[0];
      slots = [wx(i, d) < cx ? 0 : 1];
      if ((wx(i, d) - cx).abs() < ambiguous) {
        final near = [for (final k in recent) if (dist(i, d, k) < nearDist) k];
        if (near.isNotEmpty) {
          var best = near[0];
          for (final k in near) {
            if (dist(i, d, k) < dist(i, d, best)) best = k;
          }
          slots = [best];
        }
      }
    }
    for (var q = 0; q < det.length; q++) {
      final d = det[q], k = slots[q];
      final src = seqIndex(i, d, 0, 0), dst = seqIndex(i, k, 0, 0);
      for (var e = 0; e < kPoints * kDims; e++) {
        out[dst + e] = hands[src + e];
      }
      ok[i * 2 + k] = true;
      lastT[k] = t[i];
      lastW[k] = [wx(i, d), wy(i, d)];
    }
  }
  return (out, ok);
}

/// slot별로 짧게(≤0.2초) 끊긴 구간을 앞뒤 프레임으로 선형 보간
void _fillShortGaps(List<double> t, Float64List X, List<bool> ok, HandlyConfig cfg) {
  final tol = cfg.shortGapSec + 0.5 / cfg.targetFps;
  final N = t.length;
  for (var k = 0; k < 2; k++) {
    final valid = [for (var i = 0; i < N; i++) if (ok[i * 2 + k]) i];
    for (var v = 0; v + 1 < valid.length; v++) {
      final a = valid[v], b = valid[v + 1];
      if (b - a > 1 && t[b] - t[a] <= tol) {
        for (var i = a + 1; i < b; i++) {
          final w = (t[i] - t[a]) / (t[b] - t[a]);
          final ia = seqIndex(a, k, 0, 0), ib = seqIndex(b, k, 0, 0), ii = seqIndex(i, k, 0, 0);
          for (var e = 0; e < kPoints * kDims; e++) {
            X[ii + e] = (1 - w) * X[ia + e] + w * X[ib + e];
          }
          ok[i * 2 + k] = true;
        }
      }
    }
  }
}

/// numpy.interp 와 같은 선형 보간 (양 끝은 끝값으로 고정)
double _interp(double x, List<double> xp, List<double> fp) {
  final n = xp.length;
  if (n == 1 || x <= xp[0]) return fp[0];
  if (x >= xp[n - 1]) return fp[n - 1];
  var lo = 0, hi = n - 1; // xp[lo] <= x < xp[hi]
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (xp[mid] <= x) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final slope = (fp[hi] - fp[lo]) / (xp[hi] - xp[lo]);
  return slope * (x - xp[lo]) + fp[lo];
}

int _searchLeft(List<double> a, double v) {
  var lo = 0, hi = a.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (a[mid] < v) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// 실제 시간 위치 기준으로 1초당 fps개로 다시 샘플링
Seq _resample(List<double> t, Float64List X, List<bool> ok, int fps, List<double> head) {
  final T = t.length;
  final n = (t[T - 1] * fps).floor() + 1;
  final tt = Float64List(n);
  for (var i = 0; i < n; i++) {
    tt[i] = i / fps;
  }
  final nearest = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    var nr = math.min(math.max(_searchLeft(t, tt[i]), 0), T - 1);
    final pv = math.min(math.max(nr - 1, 0), T - 1);
    if ((t[pv] - tt[i]).abs() < (t[nr] - tt[i]).abs()) nr = pv;
    nearest[i] = nr;
  }
  final Xo = Float64List(n * 2 * kPoints * kDims);
  final Po = List<bool>.filled(n * 2, false);
  for (var k = 0; k < 2; k++) {
    final v = [for (var i = 0; i < T; i++) if (ok[i * 2 + k]) i];
    if (v.isEmpty) continue;
    final xp = [for (final i in v) t[i]];
    for (var e = 0; e < kPoints * kDims; e++) {
      final fp = [for (final i in v) X[seqIndex(i, k, 0, 0) + e]];
      for (var i = 0; i < n; i++) {
        Xo[seqIndex(i, k, 0, 0) + e] = _interp(tt[i], xp, fp);
      }
    }
    for (var i = 0; i < n; i++) {
      Po[i * 2 + k] = ok[nearest[i] * 2 + k];
      if (!Po[i * 2 + k]) {
        final b = seqIndex(i, k, 0, 0);
        for (var e = 0; e < kPoints * kDims; e++) {
          Xo[b + e] = 0;
        }
      }
    }
  }
  return Seq(tt, Xo, Po, head);
}
