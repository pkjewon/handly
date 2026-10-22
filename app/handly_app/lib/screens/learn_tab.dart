import 'package:flutter/material.dart';
import 'package:handly_core/handly_core.dart';

import '../main.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lesson_screen.dart';
import 'read_screen.dart';

/// 학습 탭: 주제별 단원과 레슨(M4-1·M4-2), 단어 목록, 읽기 연습(M3)
class LearnTab extends StatelessWidget {
  const LearnTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Handly.of(context);
    final p = app.progress;
    final words = app.playable;
    final learned = p.learnedCount(words.map((w) => w.name));
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(22, 14, 22, 110), children: [
        const Text('학습', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        const Text('짧은 레슨으로 하나씩 익혀요', style: TextStyle(fontSize: 13, color: C.inkSoft)),
        const SizedBox(height: 18),

        // 단원 카드
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Text('단원 1', style: TextStyle(fontSize: 12, color: C.onDarkSoft)),
              const Spacer(),
              Text('$learned / ${words.length}', style: sg(13, color: C.onDark)),
            ]),
            const SizedBox(height: 4),
            Text(app.lib.lesson.isEmpty ? '인사' : app.lib.lesson,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: C.onDark)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: words.isEmpty ? 0 : learned / words.length,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                color: C.teal,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: words.isEmpty
                  ? null
                  : () => open(LessonScreen(title: app.lib.lesson, words: words.map((w) => w.name).toList())),
              child: Text(learned == 0 ? '레슨 시작하기' : '레슨 이어 하기'),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        const Text('단어', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        for (final w in app.lib.words) ...[
          _WordRow(
            name: w.name,
            meaning: w.meaning,
            guide: w,
            accuracy: p.stats[w.name]?.accuracy,
            learned: (p.stats[w.name]?.correct ?? 0) > 0,
            onTap: w.refs.isEmpty ? null : () => open(LessonScreen(title: w.name, words: [w.name])),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        const Text('연습', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: QCard(
              icon: HIcons.eye,
              label: '읽기 연습',
              meta: '다른 사람의 수어 보고 뜻 고르기',
              onTap: () => open(const ReadScreen()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: QCard(
              icon: HIcons.arcade,
              iconColor: C.amber,
              label: '아케이드',
              meta: '게임으로 복습하기',
              onTap: () => Shell.goTab(context, 2),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _WordRow extends StatelessWidget {
  const _WordRow({
    required this.name,
    required this.meaning,
    required this.guide,
    required this.accuracy,
    required this.learned,
    required this.onTap,
  });

  final String name, meaning;
  final WordEntry guide;
  final double? accuracy;
  final bool learned;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: C.paperRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: C.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              SizedBox(
                width: 64,
                height: 64,
                child: DarkFrame(radius: 12, reticle: false, child: GuideView(seq: guide.guide, dark: true, showBody: false)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  Text(meaning, style: const TextStyle(fontSize: 12, color: C.inkSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (accuracy != null) Text('${(accuracy! * 100).round()}%', style: sg(13, color: C.inkSoft)),
              const SizedBox(width: 8),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: learned ? C.teal : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: learned ? C.teal : C.line, width: 2),
                ),
                child: learned ? const Center(child: HIcon(HIcons.check, size: 14, color: Colors.white, stroke: 2.4)) : null,
              ),
            ]),
          ),
        ),
      );
}
