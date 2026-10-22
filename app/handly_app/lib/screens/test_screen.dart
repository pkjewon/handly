import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:handly_core/handly_core.dart';

import '../recognizer.dart';
import '../theme.dart';
import '../widgets.dart';

/// PRD 10-8 앱 개발 전 테스트
/// 1. 두 패키지 동시 실행 (손 점·어깨 점 동시 표시)
/// 2. 속도 (초당 15프레임 이상, 실제 폰 release 모드)
/// 3. Python 과 어깨 기준 차이: 같은 자세에서 정규화한 손목 좌표를 demo/measure_pose.py 결과와 비교
class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  final rec = Recognizer();
  StreamSubscription<FrameData>? _sub;
  String? _error;
  bool _flip = false;
  Timer? _timer;

  // 3초 측정
  bool _measuring = false;
  final _samples = <List<double?>>[];
  String _measureResult = '';

  @override
  void initState() {
    super.initState();
    rec.start().then((_) {
      _sub = rec.frames.listen(_onFrame);
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
      setState(() {});
    }).catchError((Object e) => setState(() => _error = '$e'));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    rec.dispose();
    super.dispose();
  }

  /// 현재 프레임의 손목 좌표를 어깨 기준으로 정규화 (processing 과 같은 방식: 화면 비율 보정 → 어깨 가운데 원점, 어깨 너비 1)
  List<double?> _normWrists(FrameData f) {
    if (!f.poseOk || rec.uprightHeight == 0) return [null, null, null, null];
    final a = rec.uprightWidth / rec.uprightHeight;
    final lx = f.pose[kPoseLSh][0] * a, ly = f.pose[kPoseLSh][1];
    final rx = f.pose[kPoseRSh][0] * a, ry = f.pose[kPoseRSh][1];
    final cx = (lx + rx) / 2, cy = (ly + ry) / 2;
    final sw = math.sqrt((lx - rx) * (lx - rx) + (ly - ry) * (ly - ry));
    final out = <double?>[null, null, null, null]; // 화면 왼쪽 손 x,y / 오른쪽 손 x,y
    for (var k = 0; k < 2; k++) {
      if (!f.handOk[k]) continue;
      final x = (f.hands[k][0][0] * a - cx) / sw, y = (f.hands[k][0][1] - cy) / sw;
      final slot = f.hands[k][0][0] * a < cx ? 0 : 1;
      out[slot * 2] = x;
      out[slot * 2 + 1] = y;
    }
    return out;
  }

  void _onFrame(FrameData f) {
    if (_measuring) _samples.add(_normWrists(f));
  }

  Future<void> _measure() async {
    _samples.clear();
    setState(() {
      _measuring = true;
      _measureResult = '측정 중... 3초 동안 자세를 유지하세요';
    });
    await Future<void>.delayed(const Duration(seconds: 3));
    _measuring = false;
    String fmt(int idx) {
      final v = _samples.map((s) => s[idx]).whereType<double>().toList();
      if (v.isEmpty) return '  -  ';
      return (v.reduce((a, b) => a + b) / v.length).toStringAsFixed(3);
    }

    setState(() => _measureResult = '화면 왼쪽 손목 (${fmt(0)}, ${fmt(1)})   화면 오른쪽 손목 (${fmt(2)}, ${fmt(3)})\n'
        '프레임 ${_samples.length}개 · demo/measure_pose.py 결과와 비교 (차이 0.1 이내면 통과)');
  }

  @override
  Widget build(BuildContext context) {
    final c = rec.controller;
    final f = rec.latest;
    final handFps = rec.stats.fps(rec.stats.hand);
    final poseFps = rec.stats.fps(rec.stats.pose);
    final camFps = rec.stats.fps(rec.stats.camera);
    final w = f == null ? null : _normWrists(f);
    String n(double? v) => v == null ? '-' : v.toStringAsFixed(2);
    final pass1 = f != null && f.poseOk && (f.handOk[0] || f.handOk[1]);

    return Scaffold(
      appBar: AppBar(title: const Text('인식 테스트 (10-8)')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('카메라 오류: $_error')))
          : c == null || !c.value.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(12), children: [
                  CameraWithLandmarks(controller: c, frame: f, flipOverlay: _flip),
                  const SizedBox(height: 8),
                  _row('1. 손·어깨 동시 표시', pass1 ? '통과 (둘 다 인식 중)' : '손과 어깨가 모두 화면에 나오게', pass1),
                  _row('2. 속도', '손 ${handFps.toStringAsFixed(1)}fps · 어깨 ${poseFps.toStringAsFixed(1)}fps · 카메라 ${camFps.toStringAsFixed(1)}fps',
                      handFps >= 15),
                  _row('어깨 기준 손목', '왼(${n(w?[0])}, ${n(w?[1])})  오(${n(w?[2])}, ${n(w?[3])})', null),
                  _row('영상 크기', '${rec.uprightWidth}×${rec.uprightHeight} · 앞 카메라 반전 ${rec.mirror ? '켬' : '끔'}'
                      ' · 손 인식 ${rec.gpu ? 'GPU' : 'CPU'}', null),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: FilledButton(onPressed: _measuring ? null : _measure, child: const Text('3. 손목 좌표 3초 측정')),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => setState(() => _flip = !_flip),
                      child: Text(_flip ? '표시 반전 켬' : '표시 반전 끔'),
                    ),
                  ]),
                  if (_measureResult.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(_measureResult)),
                  const SizedBox(height: 8),
                  const Text(
                    '확인 방법: 오른손만 들면 "오른쪽 손목"에 값이 나와야 함 (거울 모드). '
                    '점이 손과 반대쪽에 그려지면 "표시 반전"을 켜서 맞춰 보고 결과를 알려 주세요. '
                    '속도는 실제 폰에서 flutter run --release 로 확인.',
                    style: TextStyle(color: C.inkSoft, fontSize: 13),
                  ),
                ]),
    );
  }

  Widget _row(String label, String value, bool? ok) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value)),
          if (ok != null) Icon(ok ? Icons.check_circle : Icons.error_outline, color: ok ? C.teal : C.amber, size: 20),
        ]),
      );
}
