import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets.dart';
import 'game_common.dart';

/// 05 아케이드 · 단어 맞추기: 제한 시간 안에 화면의 단어를 수어로 표현 (자동 판정)
class MatchGame extends StatefulWidget {
  const MatchGame({super.key});

  @override
  State<MatchGame> createState() => _MatchGameState();
}

class _MatchGameState extends State<MatchGame> with GameCamera, SingleTickerProviderStateMixin {
  static const roundSec = 12.0;
  static const maxLives = 3;

  final _rng = math.Random();
  late final Ticker _ticker;
  Duration _now = Duration.zero;
  Duration _roundStart = Duration.zero;

  bool _running = false;
  String? _word;
  int _score = 0, _lives = maxLives, _stars = 0;
  String? _flash; // 'ok' / 'miss'
  String? _answerShown; // 시간 초과 때 정답 동작 보여 주기

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    startCamera();
  }

  @override
  void dispose() {
    _ticker.dispose();
    disposeCamera();
    super.dispose();
  }

  double get _left => math.max(0, roundSec - (_now - _roundStart).inMilliseconds / 1000);

  @override
  void onGameStart() {
    setState(() {
      _running = true;
      _score = 0;
      _lives = maxLives;
      _stars = 0;
    });
    _nextWord();
  }

  void _nextWord() {
    final words = app.playable.map((w) => w.name).toList();
    var w = words[_rng.nextInt(words.length)];
    if (words.length > 1) {
      while (w == _word) {
        w = words[_rng.nextInt(words.length)];
      }
    }
    setState(() {
      _word = w;
      _flash = null;
      _answerShown = null;
      _roundStart = _now;
    });
    auto?.setTarget(w);
  }

  @override
  void onCorrect(String word) {
    if (!_running || word != _word) return;
    HapticFeedback.mediumImpact();
    app.progress.record(word, true);
    auto?.setTarget(null);
    setState(() {
      _score++;
      _stars++;
      _flash = 'ok';
    });
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted && _running) _nextWord();
    });
  }

  void _onTick(Duration d) {
    _now = d;
    if (!_running || _word == null || _flash != null) {
      if (mounted) setState(() {});
      return;
    }
    if (_left <= 0) {
      // 시간 초과: 목숨 하나 잃고 정답 동작을 잠깐 보여 줌
      app.progress.record(_word!, false);
      auto?.setTarget(null);
      setState(() {
        _lives--;
        _flash = 'miss';
        _answerShown = _word;
      });
      HapticFeedback.heavyImpact();
      Future<void>.delayed(const Duration(milliseconds: 2200), () {
        if (!mounted) return;
        if (_lives <= 0) {
          _gameOver();
        } else {
          _nextWord();
        }
      });
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _gameOver() async {
    _running = false;
    auto?.setTarget(null);
    app.progress.setBest(match: _score);
    await showGameOver(score: _score, best: app.progress.bestMatch, stars: _stars, onRetry: onGameStart);
  }

  @override
  Widget build(BuildContext context) {
    final c = rec.controller;
    final frac = _left / roundSec;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kSky),
        child: Stack(children: [
          const SkyNoise(),
          SafeArea(
            child: Column(children: [
              // .match-top
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 22, 0),
                child: Row(children: [
                  const SkyBack(),
                  _TimerRing(fraction: _running ? frac : 1, label: _running ? _left.toStringAsFixed(1) : '-'),
                  const Spacer(),
                  Text('$_score', style: sg(20, color: Colors.white)),
                  const SizedBox(width: 14),
                  for (var i = 0; i < maxLives; i++)
                    Container(
                      margin: const EdgeInsets.only(left: 5),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _lives ? C.paper : Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                ]),
              ),
              // .prompt-block
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                child: Column(children: [
                  Text('이 단어를 수어로 표현해보세요',
                      style: TextStyle(fontSize: 13, color: const Color(0xFFE7E3F2).withValues(alpha: 0.85))),
                  const SizedBox(height: 8),
                  Text(_word ?? '', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white)),
                ]),
              ),
              // .match-cam
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(26, 22, 26, 0),
                  decoration: BoxDecoration(
                    color: const Color(0x4D0A0916),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(19),
                    child: Stack(fit: StackFit.expand, children: [
                      if (c != null && c.value.isInitialized)
                        CameraFill(controller: c, frame: rec.latest, flipOverlay: app.progress.flipOverlay),
                      Center(
                        child: SizedBox(
                          width: 180,
                          height: 180,
                          child: Reticle(
                            color: switch (_flash) { 'ok' => C.teal, 'miss' => C.coral, _ => C.paper },
                            child: _flash == 'ok'
                                ? const Center(child: HIcon(HIcons.check, size: 80, color: Colors.white, stroke: 2.4))
                                : null,
                          ),
                        ),
                      ),
                      if (_answerShown != null)
                        Container(
                          color: const Color(0xD91C2033),
                          padding: const EdgeInsets.all(16),
                          child: Column(children: [
                            Text("시간 초과! 정답 동작: $_answerShown",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            Expanded(child: GuideView(seq: app.lib.word(_answerShown!)?.guide, dark: true)),
                          ]),
                        ),
                      if (cameraError != null)
                        Center(child: Text('카메라 오류: $cameraError', style: const TextStyle(color: Colors.white))),
                    ]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 14, 30, 18),
                child: Text('손 모양이 인식되면 자동으로 정답을 확인해요',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: const Color(0xFFE7E3F2).withValues(alpha: 0.85))),
              ),
            ]),
          ),
          readyOverlay(),
        ]),
      ),
    );
  }
}

/// .timer-ring (conic-gradient)
class _TimerRing extends StatelessWidget {
  const _TimerRing({required this.fraction, required this.label});

  final double fraction;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 44,
        child: CustomPaint(
          painter: _RingPainter(fraction),
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(color: Color(0xD9141226), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(label, style: sg(11, color: Colors.white)),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.f);

  final double f;

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawArc(rect, 0, 2 * math.pi, true, Paint()..color = Colors.white.withValues(alpha: 0.18));
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * f, true, Paint()..color = f < 0.25 ? C.coral : C.amber);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.f != f;
}
