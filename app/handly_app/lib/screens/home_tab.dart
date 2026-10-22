import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lesson_screen.dart';

/// 01 홈: 인사, 연속 학습일, 오늘의 수어, 아케이드·복습노트 바로가기
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Handly.of(context);
    final p = app.progress;
    final playable = app.playable;
    // 오늘의 수어: 아직 못 맞힌 단어를 먼저, 날짜마다 바뀜
    final notLearned = playable.where((w) => (p.stats[w.name]?.correct ?? 0) == 0).toList();
    final pool = notLearned.isNotEmpty ? notLearned : playable;
    final today = pool.isEmpty ? null : pool[DateTime.now().day % pool.length];
    final reviewCount = p.reviewWords(app.words).length;

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(22, 14, 22, 110), children: [
        Text(p.nickname.isEmpty ? '안녕하세요' : '안녕하세요, ${p.nickname}님',
            style: const TextStyle(fontSize: 13, color: C.inkSoft)),
        const SizedBox(height: 4),
        const Text('오늘도 손끝으로\n한마디 건네볼까요',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.28, letterSpacing: -0.2)),
        const SizedBox(height: 16),
        Align(alignment: Alignment.centerLeft, child: StreakPill(days: p.streak)),
        const SizedBox(height: 18),
        // 오늘의 수어 카드 (.today-card)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('오늘의 수어', style: TextStyle(fontSize: 12, color: C.onDarkSoft)),
            const SizedBox(height: 6),
            Text(today?.name ?? '준비 중', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: C.onDark)),
            const SizedBox(height: 14),
            DarkFrame(height: 150, child: GuideView(seq: today?.guide, dark: true, speed: p.guideSpeed)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: today == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LessonScreen(
                            title: '오늘의 레슨',
                            words: [today.name, ...playable.map((w) => w.name).where((n) => n != today.name)],
                          ))),
              child: const Text('학습 시작하기'),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: QCard(
              icon: HIcons.arcade,
              label: '아케이드',
              meta: '2개 게임 열림',
              onTap: () => Shell.goTab(context, 2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: QCard(
              icon: HIcons.review,
              iconColor: C.coral,
              label: '복습노트',
              badge: reviewCount > 0 ? '$reviewCount개 대기중' : null,
              meta: reviewCount > 0 ? null : '복습할 수어 없음',
              onTap: () => Shell.goTab(context, 3),
            ),
          ),
        ]),
      ]),
    );
  }
}
