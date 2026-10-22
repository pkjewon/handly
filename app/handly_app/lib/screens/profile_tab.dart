import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import 'test_screen.dart';

/// 내정보: 학습 기록·배지(M4-4), 설정, 개인정보 안내(M8-1), 개발용 인식 테스트(10-8)
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  Future<void> _editName(BuildContext context, AppData app) async {
    final ctrl = TextEditingController(text: app.progress.nickname);
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.paper,
        title: const Text('이름'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: '홈 화면 인사에 쓰여요')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('저장')),
        ],
      ),
    );
    if (v != null) app.progress.setNickname(v);
  }

  @override
  Widget build(BuildContext context) {
    final app = Handly.of(context);
    final p = app.progress;
    final badges = p.badges(app.playable.map((w) => w.name).toList());

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(22, 14, 22, 110), children: [
        Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: C.teal, borderRadius: BorderRadius.circular(16)),
            child: const Center(child: HIcon(HIcons.hand, size: 28, color: Colors.white)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.nickname.isEmpty ? '이름을 정해 주세요' : p.nickname,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const Text('기록은 이 폰에 저장돼요', style: TextStyle(fontSize: 12, color: C.inkSoft)),
            ]),
          ),
          TextButton(onPressed: () => _editName(context, app), child: const Text('수정')),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          _Stat(value: '${p.streak}', label: '연속 학습일', color: C.amber),
          const SizedBox(width: 10),
          _Stat(value: '${p.stars}', label: '모은 별', color: C.teal),
          const SizedBox(width: 10),
          _Stat(value: '${p.learnedCount(app.words)}', label: '배운 단어', color: C.coral),
        ]),
        const SizedBox(height: 24),
        const Text('배지', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.92,
          children: [for (final b in badges) _BadgeTile(b.title, b.desc, b.earned)],
        ),
        const SizedBox(height: 24),
        const Text('설정', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _Panel(children: [
          ListTile(
            title: const Text('안내 동작 속도'),
            trailing: SegmentedButton<double>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0.5, label: Text('천천히')),
                ButtonSegment(value: 0.75, label: Text('조금')),
                ButtonSegment(value: 1.0, label: Text('보통')),
              ],
              selected: {p.guideSpeed},
              onSelectionChanged: (s) => p.setGuideSpeed(s.first),
            ),
          ),
          const Divider(height: 1, color: C.line),
          SwitchListTile(
            activeThumbColor: C.teal,
            title: const Text('손 점 표시 좌우 반전'),
            subtitle: const Text('카메라 화면의 점이 손과 반대쪽에 보일 때 켜세요', style: TextStyle(fontSize: 12)),
            value: p.flipOverlay,
            onChanged: p.setFlipOverlay,
          ),
        ]),
        const SizedBox(height: 16),
        _Panel(children: const [
          ListTile(
            leading: HIcon(HIcons.eye, color: C.teal),
            title: Text('카메라 영상은 폰 안에서만 처리돼요'),
            subtitle: Text('영상은 저장하거나 보내지 않고, 손 위치 좌표로만 동작을 확인해요.', style: TextStyle(fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 16),
        _Panel(children: [
          ListTile(
            title: const Text('인식 테스트 (개발용)'),
            subtitle: const Text('손·어깨 인식, 속도, 좌표 확인 (PRD 10-8)', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TestScreen())),
          ),
          const Divider(height: 1, color: C.line),
          ListTile(
            title: const Text('학습 기록 초기화', style: TextStyle(color: C.coral)),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  backgroundColor: C.paper,
                  title: const Text('학습 기록을 모두 지울까요?'),
                  content: const Text('연속 학습일, 별, 복습노트, 최고 점수가 지워져요.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('취소')),
                    TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('지우기', style: TextStyle(color: C.coral))),
                  ],
                ),
              );
              if (ok ?? false) await p.reset();
            },
          ),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});

  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: C.paperRaised,
            border: Border.all(color: C.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(height: 8),
            Text(value, style: sg(24)),
            Text(label, style: const TextStyle(fontSize: 11, color: C.inkSoft)),
          ]),
        ),
      );
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile(this.title, this.desc, this.earned);

  final String title, desc;
  final bool earned;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: desc,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: earned ? C.ink : C.paperRaised,
            border: Border.all(color: earned ? C.ink : C.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            HIcon(HIcons.star, size: 28, fill: true, color: earned ? C.amber : C.line),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: earned ? C.onDark : C.inkSoft)),
          ]),
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: C.paperRaised,
          border: Border.all(color: C.line),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(color: Colors.transparent, child: Column(children: children)),
      );
}
