import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:handly_core/handly_core.dart';

import '../main.dart';
import '../theme.dart';
import '../widgets.dart';

/// M3-1 읽기 연습: 남의 수어(기준 테이크의 입체 손)를 보고 뜻 고르기. M3-4 속도 조절.
/// (농인 출연 영상이 준비되면 같은 자리에 실제 영상 재생)
class ReadScreen extends StatefulWidget {
  const ReadScreen({super.key});

  @override
  State<ReadScreen> createState() => _ReadScreenState();
}

class _ReadScreenState extends State<ReadScreen> {
  final _rng = math.Random();
  String? _answer;
  Seq? _seq;
  List<String> _choices = [];
  int? _picked;
  int _right = 0, _total = 0;
  double _speed = 0.5; // 천천히 → 보통 순으로 (M3-4)

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_answer == null) _next();
  }

  void _next() {
    final app = Handly.of(context);
    final pool = app.playable;
    if (pool.isEmpty) return;
    final w = pool[_rng.nextInt(pool.length)];
    final takes = w.refs.where((r) => r.kind != '안내').toList();
    final pickFrom = takes.isEmpty ? w.refs : takes;
    final others = app.words.where((n) => n != w.name).toList()..shuffle(_rng);
    setState(() {
      _answer = w.name;
      _seq = pickFrom[_rng.nextInt(pickFrom.length)].seq;
      _choices = [...others.take(3), w.name]..shuffle(_rng);
      _picked = null;
    });
  }

  void _pick(int i) {
    if (_picked != null) return;
    final ok = _choices[i] == _answer;
    HapticFeedback.selectionClick();
    if (ok) Handly.of(context).progress.addStars(1);
    setState(() {
      _picked = i;
      _total++;
      if (ok) _right++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ok = _picked != null && _choices[_picked!] == _answer;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const HIcon(HIcons.back, stroke: 2)),
        title: const Text('읽기 연습', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: Text('$_right / $_total', style: sg(15)))),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('이 수어는 무슨 뜻일까요?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('다른 사람이 한 수어를 보고 골라 보세요', style: TextStyle(fontSize: 13, color: C.inkSoft)),
            const SizedBox(height: 14),
            Expanded(child: DarkFrame(radius: 22, child: GuideView(seq: _seq, speed: _speed, dark: true))),
            const SizedBox(height: 10),
            Row(children: [
              const Text('재생 속도', style: TextStyle(color: C.inkSoft, fontSize: 13)),
              const Spacer(),
              for (final s in [0.5, 0.75, 1.0])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text('$s배'),
                    selected: _speed == s,
                    selectedColor: C.tealTint,
                    onSelected: (_) => setState(() => _speed = s),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            for (var i = 0; i < _choices.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: _picked == null
                        ? C.paperRaised
                        : (_choices[i] == _answer ? C.teal : (_picked == i ? C.coral : C.paperRaised)),
                    foregroundColor:
                        _picked != null && (_choices[i] == _answer || _picked == i) ? Colors.white : C.ink,
                  ),
                  onPressed: () => _pick(i),
                  child: Text(_choices[i], style: const TextStyle(fontSize: 17)),
                ),
              ),
            if (_picked != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text(ok ? '정답이에요! 별 1개' : "아쉬워요. 정답은 '$_answer'",
                      style: TextStyle(color: ok ? C.teal : C.coral, fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                SizedBox(width: 120, child: FilledButton(onPressed: _next, child: const Text('다음 문제'))),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
