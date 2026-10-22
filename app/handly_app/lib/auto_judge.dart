import 'dart:async';

import 'package:handly_core/handly_core.dart';

import 'judge_worker.dart';
import 'recognizer.dart';

/// 게임용 자동 판정: 최근 RECORD_SEC 초의 동작을 일정 간격으로 목표 단어와 비교.
/// 녹화 버튼 없이 "손 모양이 인식되면 자동으로 정답을 확인" (목업 05).
class AutoJudge {
  AutoJudge({required this.rec, required this.worker, required HandlyConfig cfg, required this.onCorrect})
      : window = FrameWindow(cfg.recordSec);

  final Recognizer rec;
  final JudgeWorker worker;
  final FrameWindow window;
  final void Function(String word) onCorrect;

  String? target;
  bool _busy = false;
  Timer? _timer;
  StreamSubscription<FrameData>? _sub;

  /// 마지막 판정의 목표 단어 거리 (화면에 "얼마나 가까운지" 표시용)
  double? lastDistance;
  double? lastThreshold;

  void start() {
    _sub = rec.frames.listen(window.add);
    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) => _check());
  }

  void setTarget(String? word) {
    target = word;
    window.clear();
    lastDistance = null;
  }

  Future<void> _check() async {
    final t = target;
    if (t == null || _busy || window.span < 1.2 || !window.handsVisible) return;
    _busy = true;
    try {
      final j = await worker.judge(window.toTake(rec.uprightWidth, rec.uprightHeight), t);
      if (target != t) return; // 판정하는 동안 문제가 바뀜
      lastDistance = j.targetDist;
      lastThreshold = j.threshold;
      if (j.correct) {
        window.clear();
        onCorrect(t);
      }
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
  }
}
