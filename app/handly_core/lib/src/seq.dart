import 'dart:typed_data';

/// 손 21점 × 좌표 3개 (x, y, z)
const int kPoints = 21;
const int kDims = 3;

/// Pose 점 5개: 코, 왼귀, 오른귀, 왼어깨, 오른어깨 (demo/landmarks.py POSE_IDS = [0, 7, 8, 11, 12])
const int kPoseNose = 0, kPoseLEar = 1, kPoseREar = 2, kPoseLSh = 3, kPoseRSh = 4;

/// 손 관절 연결선 (그리기용)
const List<List<int>> kHandEdges = [
  [0, 1], [1, 2], [2, 3], [3, 4],
  [0, 5], [5, 6], [6, 7], [7, 8],
  [5, 9], [9, 10], [10, 11], [11, 12],
  [9, 13], [13, 14], [14, 15], [15, 16],
  [13, 17], [0, 17], [17, 18], [18, 19], [19, 20],
];

int _xi(int i, int k, int j, int c) => ((i * 2 + k) * kPoints + j) * kDims + c;

/// 한 프레임의 인식 결과. 좌표는 화면 기준 0~1 (손: hand_landmarker, 어깨: ML Kit 픽셀 ÷ 이미지 크기).
class FrameData {
  /// [2][21][3], 감지 순서 그대로 (왼/오 구분은 processing 이 함)
  final List<List<List<double>>> hands;
  final List<bool> handOk;

  /// [5][3]: 코, 왼귀, 오른귀, 왼어깨, 오른어깨
  final List<List<double>> pose;
  final bool poseOk;

  FrameData(this.hands, this.handOk, this.pose, this.poseOk);
}

/// 녹화 한 번의 원본 좌표 (demo/landmarks.py RawTake 와 같은 형식)
class RawTake {
  final int width;
  final int height;
  final List<double> t = [];
  final List<double> hands = []; // T*2*21*3
  final List<bool> handOk = []; // T*2
  final List<double> pose = []; // T*5*3
  final List<bool> poseOk = []; // T

  RawTake(this.width, this.height);

  int get length => t.length;

  void add(double tSec, FrameData f) {
    t.add(tSec);
    for (var k = 0; k < 2; k++) {
      for (var j = 0; j < kPoints; j++) {
        for (var c = 0; c < kDims; c++) {
          hands.add(f.hands[k][j][c]);
        }
      }
      handOk.add(f.handOk[k]);
    }
    for (var p = 0; p < 5; p++) {
      for (var c = 0; c < kDims; c++) {
        pose.add(f.pose[p][c]);
      }
    }
    poseOk.add(f.poseOk);
  }

  /// demo/export_app_assets.py 의 golden "raw" 형식에서 읽기
  factory RawTake.fromJson(Map<String, dynamic> j) {
    final r = RawTake(j['width'] as int, j['height'] as int);
    final ts = (j['t'] as List).cast<num>();
    final hs = j['hands'] as List;
    final ho = j['hand_ok'] as List;
    final ps = j['pose'] as List;
    final po = j['pose_ok'] as List;
    for (var i = 0; i < ts.length; i++) {
      r.t.add(ts[i].toDouble());
      for (var k = 0; k < 2; k++) {
        for (var p in (hs[i][k] as List)) {
          for (var c in (p as List)) {
            r.hands.add((c as num).toDouble());
          }
        }
        r.handOk.add(ho[i][k] == 1 || ho[i][k] == true);
      }
      for (var p in (ps[i] as List)) {
        for (var c in (p as List)) {
          r.pose.add((c as num).toDouble());
        }
      }
      r.poseOk.add(po[i] == 1 || po[i] == true);
    }
    return r;
  }
}

/// 정리된 좌표 시퀀스. slot 0 = 화면 왼쪽 손, slot 1 = 화면 오른쪽 손.
/// 좌표는 어깨 가운데가 원점, 어깨 너비가 1.
class Seq {
  final Float64List t; // (n)
  final Float64List x; // (n*2*21*3)
  final List<bool> p; // (n*2)
  final List<double> head; // x, y, 반지름 (그리기용)
  final String? error;

  Seq(this.t, this.x, this.p, this.head, [this.error]);

  factory Seq.empty(String error) => Seq(Float64List(0), Float64List(0), const [], const [0, 0, 0], error);

  int get length => t.length;

  double get duration => length > 1 ? t[length - 1] - t[0] : 0.0;

  double get(int i, int k, int j, int c) => x[_xi(i, k, j, c)];

  bool present(int i, int k) => p[i * 2 + k];

  double noHandRatio() {
    if (length == 0) return 1.0;
    var none = 0;
    for (var i = 0; i < length; i++) {
      if (!p[i * 2] && !p[i * 2 + 1]) none++;
    }
    return none / length;
  }

  List<double> presenceRatio() {
    if (length == 0) return [0, 0];
    final r = [0.0, 0.0];
    for (var i = 0; i < length; i++) {
      for (var k = 0; k < 2; k++) {
        if (p[i * 2 + k]) r[k] += 1;
      }
    }
    return [r[0] / length, r[1] / length];
  }

  /// 앞뒤로 손이 하나도 없는 프레임을 잘라냄 (동작 구간만 남김)
  Seq trimmed() {
    var a = -1, b = -1;
    for (var i = 0; i < length; i++) {
      if (p[i * 2] || p[i * 2 + 1]) {
        if (a < 0) a = i;
        b = i + 1;
      }
    }
    if (a < 0) return this;
    final n = b - a;
    final tt = Float64List(n);
    for (var i = 0; i < n; i++) {
      tt[i] = t[a + i] - t[a];
    }
    const stride = 2 * kPoints * kDims;
    return Seq(tt, Float64List.fromList(x.sublist(a * stride, b * stride)), p.sublist(a * 2, b * 2), head, error);
  }

  /// handly_refs.json 의 기준 좌표 {n, P, X, head} 에서 읽기. X 가 x, y 만 있으면 z = 0.
  factory Seq.fromRefJson(Map<String, dynamic> j, int fps) {
    final n = j['n'] as int;
    final t = Float64List(n);
    for (var i = 0; i < n; i++) {
      t[i] = i / fps;
    }
    final x = Float64List(n * 2 * kPoints * kDims);
    final p = List<bool>.filled(n * 2, false);
    final xs = j['X'] as List;
    final ps = j['P'] as List;
    for (var i = 0; i < n; i++) {
      for (var k = 0; k < 2; k++) {
        p[i * 2 + k] = ps[i][k] == 1 || ps[i][k] == true;
        final pts = xs[i][k] as List;
        for (var jj = 0; jj < kPoints; jj++) {
          final c = pts[jj] as List;
          for (var d = 0; d < c.length && d < kDims; d++) {
            x[_xi(i, k, jj, d)] = (c[d] as num).toDouble();
          }
        }
      }
    }
    final head = ((j['head'] as List?) ?? const [0, 0, 0]).map((e) => (e as num).toDouble()).toList();
    return Seq(t, x, p, head);
  }
}

int seqIndex(int i, int k, int j, int c) => _xi(i, k, j, c);
