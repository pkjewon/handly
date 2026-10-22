import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auto_judge.dart';
import '../main.dart';
import '../recognizer.dart';
import '../theme.dart';

/// 게임 화면 공통: 카메라·자동 판정 시작/정리, 준비 카운트다운, 게임 종료 시트
mixin GameCamera<T extends StatefulWidget> on State<T> {
  final rec = Recognizer();
  AutoJudge? auto;
  String? cameraError;
  int readyCount = 3; // 0 이 되면 게임 시작
  Timer? _readyTimer;

  AppData get app => Handly.of(context);

  void onCorrect(String word);
  void onGameStart();

  void startCamera() {
    rec.start().then((_) {
      if (!mounted) return;
      auto = AutoJudge(rec: rec, worker: app.worker, cfg: app.lib.cfg, onCorrect: onCorrect)..start();
      rec.frames.listen((_) {
        if (mounted) setState(() {});
      });
      _readyTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => readyCount--);
        if (readyCount <= 0) {
          t.cancel();
          onGameStart();
        }
      });
    }).catchError((Object e) {
      if (mounted) setState(() => cameraError = '$e');
    });
  }

  void disposeCamera() {
    _readyTimer?.cancel();
    auto?.dispose();
    rec.dispose();
  }

  Widget readyOverlay() => readyCount > 0 && cameraError == null
      ? Positioned.fill(
          child: Container(
            color: const Color(0x99140F26),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(rec.controller == null ? '카메라 준비 중' : '준비', style: const TextStyle(color: Colors.white, fontSize: 18)),
              if (rec.controller != null) Text('$readyCount', style: sg(96, color: Colors.white)),
              const SizedBox(height: 8),
              Text('머리부터 허리까지 화면에 나오게 서 주세요', style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
            ]),
          ),
        )
      : const SizedBox.shrink();

  Future<void> showGameOver({required int score, required int best, required int stars, required VoidCallback onRetry}) {
    HapticFeedback.heavyImpact();
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: C.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('게임 끝!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text('$score', style: sg(48, color: C.ink)),
          Text(score >= best && score > 0 ? '최고 기록이에요!' : '최고 점수 $best', style: const TextStyle(color: C.inkSoft)),
          const SizedBox(height: 12),
          StarsPill(stars: stars, dark: false),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(sheet).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('나가기'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  Navigator.of(sheet).pop();
                  onRetry();
                },
                child: const Text('다시 하기'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// 하늘 화면 위쪽 닫기 버튼
class SkyBack extends StatelessWidget {
  const SkyBack({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const HIcon(HIcons.back, color: Color(0xFFF5F1E8), stroke: 2),
      );
}
