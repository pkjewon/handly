import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 단어별 학습 기록 (M4-5 복습, 복습노트)
class WordStat {
  int attempts = 0;
  int correct = 0;
  int wrong = 0;
  int streakSinceWrong = 0; // 마지막으로 틀린 뒤 연속 정답 수
  DateTime? lastPracticed;

  double get accuracy => attempts == 0 ? 0 : correct / attempts;

  /// 틀린 적이 있고 그 뒤로 2번 연속 맞히기 전까지 복습 대상
  bool get needsReview => wrong > 0 && streakSinceWrong < 2;

  Map<String, dynamic> toJson() => {
        'a': attempts,
        'c': correct,
        'w': wrong,
        's': streakSinceWrong,
        'l': lastPracticed?.toIso8601String(),
      };

  static WordStat fromJson(Map<String, dynamic> j) => WordStat()
    ..attempts = j['a'] as int? ?? 0
    ..correct = j['c'] as int? ?? 0
    ..wrong = j['w'] as int? ?? 0
    ..streakSinceWrong = j['s'] as int? ?? 0
    ..lastPracticed = j['l'] == null ? null : DateTime.tryParse(j['l'] as String);
}

class Badge {
  final String title, desc;
  final bool earned;
  const Badge(this.title, this.desc, this.earned);
}

/// 학습 기록 (기기 안에 저장. Firebase 연결 후 계정에 동기화 예정)
class Progress extends ChangeNotifier {
  Progress._(this._prefs);

  static const _key = 'handly_progress_v1';
  final SharedPreferences _prefs;

  final Map<String, WordStat> stats = {};
  final Set<String> learnedDays = {};
  int stars = 0;
  int bestFalling = 0;
  int bestMatch = 0;
  String nickname = '';
  double guideSpeed = 1.0;
  bool flipOverlay = false; // 카메라 미리보기와 손 점 방향이 반대일 때 (기기마다 다름)

  static Future<Progress> load() async {
    final p = Progress._(await SharedPreferences.getInstance());
    final raw = p._prefs.getString(_key);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        (j['stats'] as Map<String, dynamic>? ?? {}).forEach((k, v) => p.stats[k] = WordStat.fromJson(v as Map<String, dynamic>));
        p.learnedDays.addAll(((j['days'] as List?) ?? const []).cast<String>());
        p.stars = j['stars'] as int? ?? 0;
        p.bestFalling = j['bestFalling'] as int? ?? 0;
        p.bestMatch = j['bestMatch'] as int? ?? 0;
        p.nickname = j['nickname'] as String? ?? '';
        p.guideSpeed = (j['guideSpeed'] as num?)?.toDouble() ?? 1.0;
        p.flipOverlay = j['flipOverlay'] as bool? ?? false;
      } catch (e) {
        debugPrint('학습 기록 읽기 실패: $e');
      }
    }
    return p;
  }

  Future<void> _save() async {
    await _prefs.setString(
        _key,
        jsonEncode({
          'stats': stats.map((k, v) => MapEntry(k, v.toJson())),
          'days': learnedDays.toList(),
          'stars': stars,
          'bestFalling': bestFalling,
          'bestMatch': bestMatch,
          'nickname': nickname,
          'guideSpeed': guideSpeed,
          'flipOverlay': flipOverlay,
        }));
  }

  void _changed() {
    notifyListeners();
    _save();
  }

  static String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  WordStat stat(String word) => stats.putIfAbsent(word, WordStat.new);

  /// 따라 하기·게임 판정 결과 기록. 정답이면 별 [starsOnCorrect]개.
  void record(String word, bool correct, {int starsOnCorrect = 1}) {
    final s = stat(word);
    s.attempts++;
    s.lastPracticed = DateTime.now();
    if (correct) {
      s.correct++;
      s.streakSinceWrong++;
      stars += starsOnCorrect;
    } else {
      s.wrong++;
      s.streakSinceWrong = 0;
    }
    learnedDays.add(_day(DateTime.now()));
    _changed();
  }

  void addStars(int n) {
    stars += n;
    learnedDays.add(_day(DateTime.now()));
    _changed();
  }

  void setBest({int? falling, int? match}) {
    if (falling != null && falling > bestFalling) bestFalling = falling;
    if (match != null && match > bestMatch) bestMatch = match;
    _changed();
  }

  void setNickname(String v) {
    nickname = v.trim();
    _changed();
  }

  void setGuideSpeed(double v) {
    guideSpeed = v;
    _changed();
  }

  void setFlipOverlay(bool v) {
    flipOverlay = v;
    _changed();
  }

  Future<void> reset() async {
    stats.clear();
    learnedDays.clear();
    stars = 0;
    bestFalling = 0;
    bestMatch = 0;
    _changed();
  }

  /// 연속 학습일: 오늘(또는 어제)부터 거꾸로 이어진 날 수
  int get streak {
    var d = DateTime.now();
    if (!learnedDays.contains(_day(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (learnedDays.contains(_day(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  bool get learnedToday => learnedDays.contains(_day(DateTime.now()));

  List<String> reviewWords(Iterable<String> words) =>
      [for (final w in words) if (stats[w]?.needsReview ?? false) w]..sort((a, b) => stats[b]!.wrong.compareTo(stats[a]!.wrong));

  int learnedCount(Iterable<String> words) => words.where((w) => (stats[w]?.correct ?? 0) > 0).length;

  /// M4-4 배지
  List<Badge> badges(List<String> words) => [
        Badge('첫 정답', '처음으로 수어를 맞혔어요', stats.values.any((s) => s.correct > 0)),
        Badge('인사 완성', '레슨의 모든 단어를 맞혔어요', words.isNotEmpty && learnedCount(words) == words.length),
        Badge('3일 연속', '3일 연속으로 학습했어요', streak >= 3),
        Badge('7일 연속', '일주일 연속으로 학습했어요', streak >= 7),
        Badge('별 50개', '별을 50개 모았어요', stars >= 50),
        Badge('낙하 500점', '수어 낙하에서 500점을 넘겼어요', bestFalling >= 500),
      ];
}
