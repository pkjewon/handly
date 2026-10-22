import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets.dart';
import 'game_common.dart';

/// 04 아케이드 · 수어 낙하: 떨어지는 단어가 캐치 라인에 닿기 전에 수어로 표현 (자동 판정)
class FallingGame extends StatefulWidget {
  const FallingGame({super.key});

  @override
  State<FallingGame> createState() => _FallingGameState();
}

class _FallingGameState extends State<FallingGame> with GameCamera, SingleTickerProviderStateMixin {
  static const maxLives = 3;
  static const startFallSec = 10.0;
  static const minFallSec = 5.0;

  final _rng = math.Random();
  late final Ticker _ticker;
  Duration _now = Duration.zero;

  bool _running = false;
  String? _word;
  int _lane = 0;
  Duration _spawnAt = Duration.zero;
  double _fallSec = startFallSec;
  int _score = 0, _lives = maxLives, _combo = 0, _stars = 0;
  String? _flash; // 'ok' / 'miss'
  double _flashY = 0;

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

  double get _progress => _word == null ? 0 : ((_now - _spawnAt).inMilliseconds / 1000) / _fallSec;

  @override
  void onGameStart() {
    setState(() {
      _running = true;
      _score = 0;
      _lives = maxLives;
      _combo = 0;
      _stars = 0;
      _fallSec = startFallSec;
    });
    _spawn();
  }

  void _spawn() {
    final words = app.playable.map((w) => w.name).toList();
    var w = words[_rng.nextInt(words.length)];
    if (words.length > 1) {
      while (w == _word) {
        w = words[_rng.nextInt(words.length)];
      }
    }
    setState(() {
      _word = w;
      _lane = _rng.nextInt(3);
      _spawnAt = _now;
      _flash = null;
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
      _score += 100 + 20 * _combo;
      _combo++;
      _stars++;
      _flash = 'ok';
      _flashY = _progress;
      _word = null;
      _fallSec = math.max(minFallSec, _fallSec * 0.93);
    });
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted && _running) _spawn();
    });
  }

  void _onTick(Duration d) {
    _now = d;
    if (_running && _word != null && _progress >= 1) {
      app.progress.record(_word!, false);
      auto?.setTarget(null);
      HapticFeedback.heavyImpact();
      setState(() {
        _lives--;
        _combo = 0;
        _flash = 'miss';
        _flashY = 1;
        _word = null;
      });
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        if (_lives <= 0) {
          _gameOver();
        } else {
          _spawn();
        }
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _gameOver() async {
    _running = false;
    auto?.setTarget(null);
    app.progress.setBest(falling: _score);
    await showGameOver(score: _score, best: app.progress.bestFalling, stars: _stars, onRetry: onGameStart);
  }

  @override
  Widget build(BuildContext context) {
    final c = rec.controller;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kSky),
        child: Stack(children: [
          const SkyNoise(),
          SafeArea(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // .hud
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 22, 0),
                child: Row(children: [
                  const SkyBack(),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('점수', style: TextStyle(fontSize: 10, color: Color(0xFFD9D5EA))),
                    Text(_fmt(_score), style: sg(22, color: Colors.white)),
                  ]),
                  const Spacer(),
                  for (var i = 0; i < maxLives; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: HIcon(HIcons.heart, size: 16, fill: true, color: C.coral, opacity: i < _lives ? 1 : 0.3),
                    ),
                ]),
              ),
              if (_combo >= 2)
                Container(
                  margin: const EdgeInsets.fromLTRB(22, 10, 0, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: C.coral.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(999)),
                  child: Text('$_combo COMBO', style: sg(11, color: Colors.white)),
                )
              else
                const SizedBox(height: 32),
              // .lane-field
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  decoration: BoxDecoration(
                    color: const Color(0x470A0916),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: LayoutBuilder(builder: (context, box) {
                    const hitFromBottom = 40.0, itemH = 40.0;
                    final travel = box.maxHeight - hitFromBottom - itemH / 2 - 10;
                    final laneW = box.maxWidth / 3;
                    return Stack(children: [
                      Row(children: [
                        for (var i = 0; i < 3; i++)
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                border: i < 2
                                    ? Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.14), style: BorderStyle.solid))
                                    : null,
                              ),
                            ),
                          ),
                      ]),
                      // .hitline
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: hitFromBottom,
                        child: Container(
                          height: 2,
                          decoration: const BoxDecoration(
                              color: C.amber, boxShadow: [BoxShadow(color: Color(0xB3F0A94E), blurRadius: 10, spreadRadius: 1)]),
                        ),
                      ),
                      if (_word != null)
                        Positioned(
                          left: _lane * laneW + 6,
                          width: laneW - 12,
                          top: 10 + travel * _progress.clamp(0.0, 1.0),
                          height: itemH,
                          child: _Glyph(text: _word!),
                        ),
                      if (_flash != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 10 + travel * _flashY.clamp(0.0, 1.0) - 10,
                          child: Center(
                            child: Text(_flash == 'ok' ? '+ 정확해요!' : '놓쳤어요',
                                style: TextStyle(
                                    color: _flash == 'ok' ? const Color(0xFF7FE3D9) : C.coral,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    shadows: const [Shadow(blurRadius: 8, color: Colors.black45)])),
                          ),
                        ),
                    ]);
                  }),
                ),
              ),
              // .cam-strip
              Container(
                margin: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                height: 170,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [C.frameA, Color(0xFF181A28)]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: C.amber, width: 2),
                ),
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: c != null && c.value.isInitialized
                          ? CameraFill(controller: c, frame: rec.latest, flipOverlay: app.progress.flipOverlay)
                          : const Center(child: HIcon(HIcons.hand, size: 36, color: C.onDark)),
                    ),
                  ),
                  Positioned(
                    top: -11,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: C.amber, borderRadius: BorderRadius.circular(999)),
                      child: const Text('캐치 라인', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF20182E))),
                    ),
                  ),
                  if (cameraError != null)
                    Center(child: Text('카메라 오류: $cameraError', style: const TextStyle(color: Colors.white))),
                ]),
              ),
            ]),
          ),
          readyOverlay(),
        ]),
      ),
    );
  }

  String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// 떨어지는 단어 (.lane .glyph)
class _Glyph extends StatelessWidget {
  const _Glyph({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: C.paper.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, color: C.skyMid, fontSize: 15)),
          ),
        ),
      );
}
