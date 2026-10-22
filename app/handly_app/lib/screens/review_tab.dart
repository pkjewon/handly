import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lesson_screen.dart';

/// 06 복습노트 (M4-5): 틀렸던 수어만 모아 2번 연속 맞힐 때까지 반복
class ReviewTab extends StatefulWidget {
  const ReviewTab({super.key});

  @override
  State<ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends State<ReviewTab> {
  int _front = 0;

  String _ago(DateTime? d) {
    if (d == null) return '';
    final days = DateTime.now().difference(DateTime(d.year, d.month, d.day)).inDays;
    return switch (days) { 0 => '오늘 연습', 1 => '어제 연습', _ => '$days일 전 연습' };
  }

  @override
  Widget build(BuildContext context) {
    final app = Handly.of(context);
    final p = app.progress;
    final list = p.reviewWords(app.words);
    if (_front >= list.length) _front = 0;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (list.isEmpty) ...[
            const Text('복습할 수어가 없어요', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.3)),
            const SizedBox(height: 4),
            const Text('틀린 수어가 생기면 여기 모아 둘게요', style: TextStyle(fontSize: 13, color: C.inkSoft)),
            const Spacer(),
            const Center(child: HIcon(HIcons.review, size: 72, color: C.line, stroke: 1.2)),
            const Spacer(),
          ] else ...[
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: '오늘 '),
                TextSpan(text: '${list.length}개', style: sg(22, color: C.coral, weight: FontWeight.w700)),
                const TextSpan(text: '가\n복습을 기다리고 있어요'),
              ]),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.3),
            ),
            const SizedBox(height: 4),
            const Text('틀렸던 수어만 모아 다시 볼 때까지 반복해요', style: TextStyle(fontSize: 13, color: C.inkSoft)),
            const SizedBox(height: 18),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _front = (_front + 1) % list.length),
                child: Stack(children: [
                  if (list.length > 2) _card(null, 2),
                  if (list.length > 1) _card(null, 1),
                  _card(list[_front], 0, app: app, ago: _ago(p.stats[list[_front]]?.lastPracticed)),
                ]),
              ),
            ),
            if (list.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('카드를 누르면 다음 수어 (${_front + 1}/${list.length})',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: C.inkSoft)),
              ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => LessonScreen(title: '복습', words: list))),
              child: const Text('지금 복습하기'),
            ),
          ],
        ]),
      ),
    );
  }

  /// 겹친 카드 (.rcard front / back1 / back2)
  Widget _card(String? word, int depth, {AppData? app, String ago = ''}) {
    final card = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: C.line),
        borderRadius: BorderRadius.circular(22),
        boxShadow: depth == 0 ? const [BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 18), spreadRadius: -20)] : null,
      ),
      child: word == null || app == null
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: C.coralTint, borderRadius: BorderRadius.circular(999)),
                  child: Text('${app.progress.stats[word]?.wrong ?? 0}번 틀림',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.coral)),
                ),
                const Spacer(),
                Text(ago, style: const TextStyle(fontSize: 11, color: C.inkSoft)),
              ]),
              const SizedBox(height: 14),
              Expanded(
                child: DarkFrame(
                    reticle: false, child: GuideView(seq: app.lib.word(word)?.guide, dark: true, speed: app.progress.guideSpeed)),
              ),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(word, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const Spacer(),
                Text('정답률 ${((app.progress.stats[word]?.accuracy ?? 0) * 100).round()}%', style: sg(13, color: C.inkSoft)),
              ]),
            ]),
    );
    return Positioned.fill(
      child: Transform.translate(
        offset: Offset(0, depth * 7.0),
        child: Transform.scale(scale: 1 - depth * 0.02, child: Opacity(opacity: depth == 0 ? 1 : (depth == 1 ? 0.88 : 0.7), child: card)),
      ),
    );
  }
}
