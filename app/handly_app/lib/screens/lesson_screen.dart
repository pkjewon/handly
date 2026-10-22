import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:handly_core/handly_core.dart';

import '../main.dart';
import '../recognizer.dart';
import '../theme.dart';
import '../widgets.dart';

enum _S { idle, countdown, record, judging, result }

/// 02 학습 · 카메라 촬영 (M1-1·M1-2 배우기 + M2 따라 하기 + M4-3 진행 표시)
/// [words] 순서대로 진행. 정답이면 다음 단어로 자동 이동.
class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key, required this.words, this.title = '레슨'});

  final List<String> words;
  final String title;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  final rec = Recognizer();
  StreamSubscription<FrameData>? _sub;
  String? _error;
  Timer? _ticker;

  int _idx = 0;
  final _done = <int>{};
  int _starsEarned = 0;
  bool _guideOpen = true; // 처음엔 안내(배우기)를 크게 보여 줌

  _S _s = _S.idle;
  DateTime _at = DateTime.now();
  RawTake? _take;
  Judgement? _result;

  AppData get app => Handly.of(context);
  WordEntry? get word => app.lib.word(widget.words[_idx]);

  @override
  void initState() {
    super.initState();
    rec.start().then((_) {
      _sub = rec.frames.listen(_onFrame);
      if (mounted) setState(() {});
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sub?.cancel();
    rec.dispose();
    super.dispose();
  }

  double get _el => DateTime.now().difference(_at).inMicroseconds / 1e6;

  void _onFrame(FrameData f) {
    if (_s == _S.record) _take?.add(_el, f);
    if (mounted) setState(() {});
  }

  void _start() {
    if (rec.controller == null) return;
    setState(() {
      _guideOpen = false;
      _s = _S.countdown;
      _at = DateTime.now();
      _result = null;
    });
  }

  void _tick() {
    if (!mounted) return;
    final cfg = app.lib.cfg;
    if (_s == _S.countdown && _el >= cfg.countdownSec) {
      _take = RawTake(rec.uprightWidth, rec.uprightHeight);
      _s = _S.record;
      _at = DateTime.now();
      HapticFeedback.lightImpact();
    } else if (_s == _S.record && _el >= cfg.recordSec) {
      _s = _S.judging;
      _judge();
    }
    if (_s == _S.countdown || _s == _S.record) setState(() {});
  }

  Future<void> _judge() async {
    final take = _take, w = word;
    if (take == null || w == null) return;
    final j = await app.worker.judge(take, w.name);
    if (!mounted) return;
    if (j.status != 'fail') app.progress.record(w.name, j.correct);
    setState(() {
      _result = j;
      _s = _S.result;
      if (j.correct) {
        _done.add(_idx);
        _starsEarned++;
      }
    });
    if (j.correct) {
      HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      if (mounted && _s == _S.result) _next();
    }
  }

  void _next() {
    if (_idx + 1 >= widget.words.length) {
      _finish();
      return;
    }
    setState(() {
      _idx++;
      _s = _S.idle;
      _result = null;
      _guideOpen = true;
    });
  }

  void _finish() {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      backgroundColor: C.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('레슨 완료!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('${widget.words.length}개 중 ${_done.length}개를 맞혔어요', style: const TextStyle(color: C.inkSoft)),
          const SizedBox(height: 16),
          StarsPill(stars: _starsEarned, dark: false),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              Navigator.of(context)
                ..pop()
                ..pop();
            },
            child: const Text('확인'),
          ),
        ]),
      ),
    );
  }

  Color get _accent => switch (_s) {
        _S.record => C.amber,
        _S.result when _result?.correct ?? false => C.teal,
        _S.result => C.coral,
        _ => C.teal,
      };

  @override
  Widget build(BuildContext context) {
    final w = word;
    final c = rec.controller;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: C.camBottom,
        body: Stack(fit: StackFit.expand, children: [
          // 배경: 카메라 (준비 전엔 목업의 격자 배경)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment(0, 0.4), colors: [C.camTop, C.camBottom]),
            ),
            child: const _CamGrid(),
          ),
          if (c != null && c.value.isInitialized)
            CameraFill(controller: c, frame: rec.latest, flipOverlay: app.progress.flipOverlay),
          // 위·아래를 살짝 어둡게 해서 글자가 잘 보이게
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xAA000000)],
                  stops: [0, 0.22, 0.6, 1],
                ),
              ),
            ),
          ),
          // 가운데 조준선 + 카운트다운
          Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: Reticle(color: _accent, child: Center(child: _centerContent())),
            ),
          ),
          SafeArea(
            child: Column(children: [
              _top(w),
              const Spacer(),
              _sheet(w),
            ]),
          ),
          if (_guideOpen && w != null) _guidePanel(w),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('카메라를 열 수 없어요\n$_error', textAlign: TextAlign.center, style: const TextStyle(color: C.onDark)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _centerContent() {
    const shadow = [Shadow(blurRadius: 12, color: Colors.black54)];
    switch (_s) {
      case _S.countdown:
        final n = app.lib.cfg.countdownSec - _el.floor();
        return Text('$n', style: sg(96, color: Colors.white).copyWith(shadows: shadow));
      case _S.judging:
        return const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3));
      default:
        final f = rec.latest;
        final noHands = f == null || !(f.handOk[0] || f.handOk[1]);
        return noHands && _s == _S.idle
            ? HIcon(HIcons.hand, size: 74, color: Colors.white.withValues(alpha: 0.85), stroke: 1.2)
            : const SizedBox.shrink();
    }
  }

  // 상단: 단어 알약 + 기준 동작 썸네일 (.cam-top)
  Widget _top(WordEntry? w) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _glass(
            child: IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.of(context).pop(),
              icon: const HIcon(HIcons.back, color: C.onDark, stroke: 2),
            ),
          ),
          const SizedBox(width: 8),
          _glass(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_idx + 1} / ${widget.words.length} 동작', style: const TextStyle(fontSize: 11, color: C.onDarkSoft)),
              Text(w?.name ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: C.onDark)),
            ]),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _guideOpen = true),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF3A3F5C), Color(0xFF22243A)]),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.teal, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GuideView(seq: w?.guide, dark: true, showBody: false, speed: app.progress.guideSpeed),
              ),
            ),
          ),
        ]),
      );

  Widget _glass({required Widget child, EdgeInsets padding = EdgeInsets.zero}) => Container(
        padding: padding,
        decoration: BoxDecoration(color: const Color(0x8C0C0C10), borderRadius: BorderRadius.circular(14)),
        child: child,
      );

  // 하단 시트 (.cam-sheet)
  Widget _sheet(WordEntry? w) {
    final r = _result;
    final List<Widget> body;
    if (_s == _S.result && r != null) {
      body = [
        _toast(r),
        if (!r.correct && r.hints.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final h in r.hints.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('· $h', style: const TextStyle(fontSize: 13, color: Color(0xFFD7D5E2))),
            ),
        ],
        if (!r.correct) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    foregroundColor: C.onDark,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
                onPressed: () => setState(() => _guideOpen = true),
                child: const Text('안내 다시 보기'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: _start, child: const Text('다시 하기'))),
          ]),
          TextButton(onPressed: _next, child: const Text('건너뛰기', style: TextStyle(color: C.onDarkSoft))),
        ],
      ];
    } else {
      final text = switch (_s) {
        _S.countdown => '준비하세요',
        _S.record => '● 동작 중 ${_el.toStringAsFixed(1)}초',
        _S.judging => '확인하는 중...',
        _ => (rec.latest != null && !rec.latest!.poseOk) ? '머리부터 허리까지 화면에 나오게 서 주세요' : '손 모양을 화면 중앙 가이드에 맞춰주세요',
      };
      body = [
        Text(text,
            style: TextStyle(
                fontSize: 14,
                color: _s == _S.record ? C.amber : const Color(0xFFD7D5E2),
                fontWeight: _s == _S.record ? FontWeight.w700 : FontWeight.w400)),
        if (_s == _S.idle) ...[
          const SizedBox(height: 12),
          FilledButton(onPressed: rec.controller == null ? null : _start, child: const Text('따라 하기 시작')),
        ],
      ];
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      decoration: BoxDecoration(
        color: const Color(0xB814151F),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        ProgressSquares(count: widget.words.length, current: _idx, done: _done),
        const SizedBox(height: 12),
        ...body,
      ]),
    );
  }

  // 피드백 알림 (.feedback-toast)
  Widget _toast(Judgement r) {
    final ok = r.correct;
    final last = _idx + 1 >= widget.words.length;
    final text = ok
        ? (last ? '정확해요! 레슨을 마칠게요' : '정확해요! 다음 동작으로 넘어갈게요')
        : (r.status == 'fail' ? r.message : '조금 달라요. ${r.message}');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: ok ? C.teal : C.coral, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        HIcon(ok ? HIcons.check : HIcons.cross, size: 16, color: Colors.white, stroke: 2.2),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
      ]),
    );
  }

  // 배우기: 입체 손 안내 크게 + 동작 설명 (M1-1, M1-2, M1-6)
  Widget _guidePanel(WordEntry w) {
    final p = app.progress;
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _guideOpen = false),
        child: Container(
          color: const Color(0xCC0C0C10),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(24)),
              child: SafeArea(
                top: false,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('먼저 동작을 살펴봐요', style: TextStyle(fontSize: 12, color: C.onDarkSoft)),
                        Text(w.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: C.onDark)),
                      ]),
                    ),
                    for (final s in [0.5, 1.0])
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(s == 1.0 ? '보통' : '천천히'),
                          selected: p.guideSpeed == s,
                          onSelected: (_) => p.setGuideSpeed(s),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  DarkFrame(height: 230, child: GuideView(seq: w.guide, dark: true, speed: p.guideSpeed)),
                  const SizedBox(height: 12),
                  if (w.meaning.isNotEmpty) Text(w.meaning, style: const TextStyle(color: C.onDarkSoft, fontSize: 13)),
                  const SizedBox(height: 8),
                  _desc('손 모양', w.shape),
                  _desc('위치', w.position),
                  _desc('움직임', w.movement),
                  const SizedBox(height: 14),
                  FilledButton(onPressed: _start, child: const Text('따라 해 보기')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _desc(String label, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 56, child: Text(label, style: const TextStyle(color: C.onDarkSoft, fontWeight: FontWeight.w700, fontSize: 13))),
          Expanded(child: Text(text, style: const TextStyle(color: C.onDark, fontSize: 13))),
        ]),
      );
}

/// 카메라 화면 격자 배경 (.cam-grid)
class _CamGrid extends StatelessWidget {
  const _CamGrid();

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _GridPainter(), size: Size.infinite);
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.025);
    for (var x = 0.0; x < s.width; x += 38) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), p);
    }
    for (var y = 0.0; y < s.height; y += 38) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
