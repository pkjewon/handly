/// demo/config.py 의 판정 관련 숫자 (PRD 10-3, M2). handly_refs.json 의 config 로 덮어쓸 수 있음.
class HandlyConfig {
  final int targetFps;
  final double shortGapSec;
  final double handUsedRatio;
  final double noHandFailRatio;
  final double missingHandRatio;
  final double absentPenalty;
  final int topK;
  final double defaultThreshold;
  final double hintPosDiff;
  final double hintFastRatio;
  final double hintSlowRatio;
  final int countdownSec;
  final double recordSec;
  final bool mirror;

  const HandlyConfig({
    this.targetFps = 30,
    this.shortGapSec = 0.2,
    this.handUsedRatio = 0.5,
    this.noHandFailRatio = 0.5,
    this.missingHandRatio = 0.4,
    this.absentPenalty = 1.0,
    this.topK = 3,
    this.defaultThreshold = 0.35,
    this.hintPosDiff = 0.25,
    this.hintFastRatio = 0.6,
    this.hintSlowRatio = 1.6,
    this.countdownSec = 3,
    this.recordSec = 3.5,
    this.mirror = true,
  });

  factory HandlyConfig.fromJson(Map<String, dynamic> j) {
    const d = HandlyConfig();
    double f(String k, double v) => (j[k] as num?)?.toDouble() ?? v;
    int i(String k, int v) => (j[k] as num?)?.toInt() ?? v;
    return HandlyConfig(
      targetFps: i('TARGET_FPS', d.targetFps),
      shortGapSec: f('SHORT_GAP_SEC', d.shortGapSec),
      handUsedRatio: f('HAND_USED_RATIO', d.handUsedRatio),
      noHandFailRatio: f('NO_HAND_FAIL_RATIO', d.noHandFailRatio),
      missingHandRatio: f('MISSING_HAND_RATIO', d.missingHandRatio),
      absentPenalty: f('ABSENT_PENALTY', d.absentPenalty),
      topK: i('TOP_K', d.topK),
      defaultThreshold: f('DEFAULT_THRESHOLD', d.defaultThreshold),
      hintPosDiff: f('HINT_POS_DIFF', d.hintPosDiff),
      hintFastRatio: f('HINT_FAST_RATIO', d.hintFastRatio),
      hintSlowRatio: f('HINT_SLOW_RATIO', d.hintSlowRatio),
      countdownSec: i('COUNTDOWN_SEC', d.countdownSec),
      recordSec: f('RECORD_SEC', d.recordSec),
      mirror: (j['MIRROR'] as bool?) ?? d.mirror,
    );
  }
}
