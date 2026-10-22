import 'dart:math' as math;
import 'dart:typed_data';

import 'config.dart';
import 'seq.dart';

/// (N, M) 프레임 거리. 손 21점 위치 차이 + 손목 기준 손 모양 차이 (x, y만). demo/dtw.py frame_costs
List<Float64List> frameCosts(Seq a, Seq b, List<int> slots, HandlyConfig cfg) {
  final N = a.length, M = b.length;
  final total = List.generate(N, (_) => Float64List(M));
  if (slots.isEmpty) return total;
  for (final k in slots) {
    for (var i = 0; i < N; i++) {
      final pa = a.present(i, k);
      final ai = seqIndex(i, k, 0, 0);
      final awx = a.x[ai], awy = a.x[ai + 1];
      for (var j = 0; j < M; j++) {
        final pb = b.present(j, k);
        double c;
        if (pa && pb) {
          final bj = seqIndex(j, k, 0, 0);
          final bwx = b.x[bj], bwy = b.x[bj + 1];
          var pos = 0.0, shape = 0.0;
          for (var p = 0; p < kPoints; p++) {
            final ax = a.x[ai + p * kDims], ay = a.x[ai + p * kDims + 1];
            final bx = b.x[bj + p * kDims], by = b.x[bj + p * kDims + 1];
            pos += math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));
            final rx = (ax - awx) - (bx - bwx), ry = (ay - awy) - (by - bwy);
            shape += math.sqrt(rx * rx + ry * ry);
          }
          c = pos / kPoints + shape / kPoints;
        } else if (pa || pb) {
          c = cfg.absentPenalty;
        } else {
          c = 0.0;
        }
        total[i][j] += c;
      }
    }
  }
  for (final row in total) {
    for (var j = 0; j < M; j++) {
      row[j] /= slots.length;
    }
  }
  return total;
}

class DtwResult {
  final double distance; // 경로 길이로 나눈 거리
  final List<(int, int)> path; // 짝지어진 프레임 (학습자 i, 기준 j)
  DtwResult(this.distance, this.path);
}

/// 기본 DTW. demo/dtw.py dtw() 와 같은 경로 선택 (대각선 → 위 → 왼쪽 순으로 같은 값이면 앞의 것)
DtwResult dtw(List<Float64List> cost) {
  final N = cost.length;
  final M = N == 0 ? 0 : cost[0].length;
  if (N == 0 || M == 0) return DtwResult(double.infinity, const []);
  final D = List.generate(N + 1, (_) => Float64List(M + 1)..fillRange(0, M + 1, double.infinity));
  D[0][0] = 0.0;
  for (var i = 1; i <= N; i++) {
    final ci = cost[i - 1], up = D[i - 1], cur = D[i];
    for (var j = 1; j <= M; j++) {
      var m = up[j - 1];
      if (up[j] < m) m = up[j];
      if (cur[j - 1] < m) m = cur[j - 1];
      cur[j] = ci[j - 1] + m;
    }
  }
  var i = N, j = M;
  final path = <(int, int)>[];
  while (i > 0 && j > 0) {
    path.add((i - 1, j - 1));
    final diag = D[i - 1][j - 1], up = D[i - 1][j], left = D[i][j - 1];
    if (diag <= up && diag <= left) {
      i -= 1;
      j -= 1;
    } else if (up <= left) {
      i -= 1;
    } else {
      j -= 1;
    }
  }
  final rev = path.reversed.toList();
  return DtwResult(D[N][M] / rev.length, rev);
}
