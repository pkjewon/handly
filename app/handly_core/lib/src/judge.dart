import 'dart:convert';

import 'config.dart';
import 'dtw.dart';
import 'seq.dart';

class RefTake {
  final String name;
  final String kind;
  final Seq seq; // 이미 trimmed
  RefTake(this.name, this.kind, this.seq);
}

/// 단어 카드(M1-1) + 판정 기준
class WordEntry {
  final String name, meaning, shape, position, movement;
  final double threshold;
  final List<int> slots; // 쓰는 손 (0: 화면 왼쪽, 1: 화면 오른쪽)
  final Seq? guide; // 입체 손 안내(M1-2) 좌표 (x, y, z)
  final List<RefTake> refs;

  WordEntry({
    required this.name,
    required this.meaning,
    required this.shape,
    required this.position,
    required this.movement,
    required this.threshold,
    required this.slots,
    required this.guide,
    required this.refs,
  });
}

class Judgement {
  final String status; // correct / wrong / fail
  final String message;
  final List<String> hints;
  final Map<String, double> distances;
  final double? targetDist;
  final double? threshold;

  Judgement(this.status, this.message,
      {this.hints = const [], this.distances = const {}, this.targetDist, this.threshold});

  bool get correct => status == 'correct';
}

/// handly_refs.json (demo/export_app_assets.py 가 만듦)을 읽어 판정. demo/dtw.py Library 와 같은 규칙.
class RefLibrary {
  final HandlyConfig cfg;
  final String lesson;
  final List<WordEntry> words;

  RefLibrary(this.cfg, this.lesson, this.words);

  factory RefLibrary.fromJsonString(String s) => RefLibrary.fromJson(jsonDecode(s) as Map<String, dynamic>);

  factory RefLibrary.fromJson(Map<String, dynamic> j) {
    final cfg = HandlyConfig.fromJson((j['config'] as Map?)?.cast<String, dynamic>() ?? const {});
    final words = <WordEntry>[];
    for (final w in (j['words'] as List).cast<Map<String, dynamic>>()) {
      final guide = w['guide'] == null ? null : Seq.fromRefJson((w['guide'] as Map).cast<String, dynamic>(), cfg.targetFps);
      words.add(WordEntry(
        name: w['name'] as String,
        meaning: (w['meaning'] ?? '') as String,
        shape: (w['shape'] ?? '') as String,
        position: (w['position'] ?? '') as String,
        movement: (w['movement'] ?? '') as String,
        threshold: (w['threshold'] as num?)?.toDouble() ?? cfg.defaultThreshold,
        slots: ((w['slots'] as List?) ?? const []).cast<int>(),
        guide: guide,
        refs: [
          for (final r in ((w['refs'] as List?) ?? const []).cast<Map<String, dynamic>>())
            RefTake(r['name'] as String, r['kind'] as String, Seq.fromRefJson(r, cfg.targetFps)),
        ],
      ));
    }
    return RefLibrary(cfg, (j['lesson'] ?? '') as String, words);
  }

  WordEntry? word(String name) {
    for (final w in words) {
      if (w.name == name) return w;
    }
    return null;
  }

  Iterable<WordEntry> get _judgeable => words.where((w) => w.refs.isNotEmpty);

  /// 단어까지 거리 = 기준 테이크 중 가장 가까운 TOP_K개의 평균
  (double, RefTake?) wordDistance(Seq seq, WordEntry w) {
    final scored = <(double, RefTake)>[
      for (final rt in w.refs) (dtw(frameCosts(seq, rt.seq, w.slots, cfg)).distance, rt),
    ];
    if (scored.isEmpty) return (double.infinity, null);
    _stableSortByDist(scored);
    final top = scored.take(cfg.topK).toList();
    final mean = top.fold<double>(0, (s, e) => s + e.$1) / top.length;
    return (mean, scored.first.$2);
  }

  /// M2-5 판정: ① 목표 단어 거리 ≤ 기준값 ② 목표 단어가 가장 가까움 → 정답
  Judgement judge(Seq rawSeq, String target) {
    if (rawSeq.error == 'no_shoulder') return Judgement('fail', '어깨까지 화면에 나오게 해 주세요');
    if (rawSeq.error != null || rawSeq.noHandRatio() >= cfg.noHandFailRatio) {
      return Judgement('fail', '손이 잘 보이지 않아요', hints: ['두 손이 화면에 나오게 해 주세요']);
    }
    final tw = word(target);
    if (tw == null || tw.refs.isEmpty) return Judgement('fail', "'$target' 기준 동작이 아직 없어요");

    final seq = rawSeq.trimmed();
    if (tw.slots.length == 2) {
      final pr = seq.presenceRatio();
      if (1 - pr[0] >= cfg.missingHandRatio || 1 - pr[1] >= cfg.missingHandRatio) {
        return Judgement('fail', '두 손이 화면에 나오게 해 주세요');
      }
    }

    final dists = <String, double>{};
    final bests = <String, RefTake?>{};
    for (final w in _judgeable) {
      final (d, best) = wordDistance(seq, w);
      dists[w.name] = d;
      bests[w.name] = best;
    }
    final thr = tw.threshold;
    final dT = dists[target]!;
    var closest = dists.keys.first;
    dists.forEach((k, v) {
      if (v < dists[closest]!) closest = k;
    });
    if (dT <= thr && closest == target) {
      return Judgement('correct', '잘했어요!', distances: dists, targetDist: dT, threshold: thr);
    }
    final hints = makeHints(seq, bests[target], tw.slots, cfg);
    if (closest != target) hints.add("'$closest' 동작과 더 비슷해요");
    if (hints.isEmpty) hints.add('왼쪽 안내를 다시 보고 해 보세요');
    return Judgement('wrong', '다시 해 볼까요?', hints: hints, distances: dists, targetDist: dT, threshold: thr);
  }
}

void _stableSortByDist(List<(double, RefTake)> l) {
  // List.sort 는 안정 정렬이 아니라서 삽입 정렬 (기준 테이크는 수십 개 정도)
  for (var i = 1; i < l.length; i++) {
    final cur = l[i];
    var j = i - 1;
    while (j >= 0 && l[j].$1 > cur.$1) {
      l[j + 1] = l[j];
      j--;
    }
    l[j + 1] = cur;
  }
}

double _maxAbs(List<double> v) {
  var best = v.first;
  for (final x in v) {
    if (x.abs() > best.abs()) best = x;
  }
  return best;
}

/// M2-7 틀린 이유 힌트: DTW가 짝지은 프레임끼리 손목 위치·동작 시간 비교
List<String> makeHints(Seq seq, RefTake? ref, List<int> slots, HandlyConfig cfg) {
  if (ref == null) return [];
  final path = dtw(frameCosts(seq, ref.seq, slots, cfg)).path;
  final hints = <String>[];
  final dys = <double>[], dxs = <double>[];
  for (final k in slots) {
    var n = 0;
    var sy = 0.0, sx = 0.0;
    for (final (i, j) in path) {
      if (!(seq.present(i, k) && ref.seq.present(j, k))) continue;
      final li = seqIndex(i, k, 0, 0), rj = seqIndex(j, k, 0, 0);
      sy += seq.x[li + 1] - ref.seq.x[rj + 1]; // +: 학습자 손이 더 아래
      sx += seq.x[li].abs() - ref.seq.x[rj].abs(); // +: 더 바깥쪽
      n++;
    }
    if (n < 3) continue;
    dys.add(sy / n);
    dxs.add(sx / n);
  }
  if (dys.isNotEmpty) {
    final dy = _maxAbs(dys), dx = _maxAbs(dxs);
    if (dy > cfg.hintPosDiff) {
      hints.add('손 위치가 낮아요. 조금 더 위로 올려 보세요');
    } else if (dy < -cfg.hintPosDiff) {
      hints.add('손 위치가 높아요. 조금 더 아래로 내려 보세요');
    }
    if (dx > cfg.hintPosDiff) {
      hints.add('손을 더 몸 쪽으로 가져와 보세요');
    } else if (dx < -cfg.hintPosDiff) {
      hints.add('손을 더 바깥쪽으로 벌려 보세요');
    }
  }
  if (ref.seq.duration > 0) {
    final ratio = seq.duration / ref.seq.duration;
    if (ratio < cfg.hintFastRatio) {
      hints.add('동작이 너무 빨라요. 천천히 해 보세요');
    } else if (ratio > cfg.hintSlowRatio) {
      hints.add('동작이 너무 느려요. 조금 더 빠르게 해 보세요');
    }
  }
  return hints;
}
