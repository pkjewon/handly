import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import 'falling_game.dart';
import 'match_game.dart';

/// 03 아케이드 허브 (M4-4 게임 요소)
class ArcadeTab extends StatelessWidget {
  const ArcadeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Handly.of(context);
    final p = app.progress;
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final canPlay = app.playable.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(gradient: kSky),
      child: Stack(children: [
        const SkyNoise(),
        SafeArea(
          bottom: false,
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 6, 20, 110), children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              child: Row(children: [
                const Text('아케이드', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFFF5F1E8))),
                const Spacer(),
                StarsPill(stars: p.stars),
              ]),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              title: '수어 낙하',
              desc: '하늘에서 내려오는 수어를 놓치지 말고 따라 해보세요',
              best: p.bestFalling,
              level: 2,
              strong: true,
              deco: true,
              onPlay: canPlay ? () => open(const FallingGame()) : null,
            ),
            const SizedBox(height: 14),
            _ModeCard(
              title: '단어 맞추기',
              desc: '화면의 단어에 맞는 수어를 직접 표현해보세요',
              best: p.bestMatch,
              level: 1,
              onPlay: canPlay ? () => open(const MatchGame()) : null,
            ),
            const SizedBox(height: 18),
            Text('게임에서 맞히면 별을 받아요. 카메라 영상은 폰 안에서만 처리돼요.',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75))),
          ]),
        ),
      ]),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.desc,
    required this.best,
    required this.level,
    required this.onPlay,
    this.strong = false,
    this.deco = false,
  });

  final String title, desc;
  final int best, level;
  final VoidCallback? onPlay;
  final bool strong, deco;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: strong ? const Color(0x6B141226) : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: strong ? 0.16 : 0.22)),
        ),
        child: Stack(children: [
          if (deco)
            Positioned(
              top: 0,
              right: 0,
              child: Column(children: [
                _glyph(0.9),
                const SizedBox(height: 16),
                _glyph(0.6),
              ]),
            ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFFF5F1E8))),
            const SizedBox(height: 4),
            SizedBox(
              width: 200,
              child: Text(desc, style: TextStyle(fontSize: 13, height: 1.5, color: const Color(0xFFEDE9F5).withValues(alpha: 0.85))),
            ),
            if (best > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('최고 점수 $best', style: sg(12, color: C.skyLow)),
              ),
            const SizedBox(height: 14),
            Row(children: [
              DiffDots(level: level),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: C.paper,
                  foregroundColor: C.ink,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onPlay,
                child: const Text('플레이'),
              ),
            ]),
          ]),
        ]),
      );

  Widget _glyph(double a) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: C.paper.withValues(alpha: a), borderRadius: BorderRadius.circular(6)),
      );
}
