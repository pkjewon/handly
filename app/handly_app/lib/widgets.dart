import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:handly_core/handly_core.dart';

import 'theme.dart';

// ---------------------------------------------------------------- M1-2 입체 손 안내

/// 기준 좌표로 그린 두 손 + 흐린 머리·어깨 선을 반복 재생 (demo/ui.py GuidePlayer 와 같은 그림)
class GuideView extends StatefulWidget {
  const GuideView({super.key, required this.seq, this.speed = 1.0, this.dark = false, this.showBody = true});

  final Seq? seq;
  final double speed;
  final bool dark; // 어두운 카드 위 (홈 오늘의 수어, 카메라 화면 썸네일)
  final bool showBody;

  @override
  State<GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends State<GuideView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => setState(() => _elapsed = d))..start();
  }

  @override
  void didUpdateWidget(GuideView old) {
    super.didUpdateWidget(old);
    if (old.seq != widget.seq || old.speed != widget.speed) {
      _ticker
        ..stop()
        ..start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  int _frame() {
    final s = widget.seq;
    if (s == null || s.length == 0) return 0;
    const hold = 0.7;
    final period = s.duration / widget.speed + hold;
    final t = ((_elapsed.inMicroseconds / 1e6) % period) * widget.speed;
    return math.min((t * 30).floor(), s.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.seq;
    if (s == null) {
      return Center(
          child: Text('기준 동작이 아직 없어요', style: TextStyle(color: widget.dark ? C.onDarkSoft : C.inkSoft, fontSize: 12)));
    }
    return CustomPaint(painter: GuidePainter(s, _frame(), dark: widget.dark, showBody: widget.showBody), size: Size.infinite);
  }
}

class GuidePainter extends CustomPainter {
  GuidePainter(this.seq, this.i, {this.dark = false, this.showBody = true});

  final Seq seq;
  final int i;
  final bool dark;
  final bool showBody;

  static const _slotLight = [C.teal, C.amber];
  static const _slotDark = [Color(0xFF5FD3C8), C.amber];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width * 0.30, size.height * 0.36);
    final ox = size.width / 2, oy = size.height * 0.52;
    Offset P(double x, double y) => Offset(ox + x * scale, oy + y * scale);

    if (showBody) {
      final faint = Paint()
        ..color = dark ? Colors.white.withValues(alpha: 0.18) : C.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final hx = seq.head[0], hy = seq.head[1], hr = seq.head[2];
      canvas.drawCircle(P(hx, hy), hr * scale, faint);
      canvas.drawLine(P(-0.5, 0), P(0.5, 0), faint..strokeWidth = 3);
      faint.strokeWidth = 2;
      canvas.drawLine(P(-0.5, 0), P(-0.45, 1.3), faint);
      canvas.drawLine(P(0.5, 0), P(0.45, 1.3), faint);
      canvas.drawLine(P(hx - 0.12, hy + hr), P(-0.12, -0.05), faint);
      canvas.drawLine(P(hx + 0.12, hy + hr), P(0.12, -0.05), faint);
    }

    // 손목 궤적
    final trail = Paint()
      ..color = dark ? Colors.white.withValues(alpha: 0.10) : C.line.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    for (var k = 0; k < 2; k++) {
      Offset? prev;
      for (var j = 0; j < seq.length; j++) {
        if (!seq.present(j, k)) {
          prev = null;
          continue;
        }
        final p = P(seq.get(j, k, 0, 0), seq.get(j, k, 0, 1));
        if (prev != null) canvas.drawLine(prev, p, trail);
        prev = p;
      }
    }

    // 두 손: z 로 굵기·크기·밝기를 바꿔 입체감
    final slotColors = dark ? _slotDark : _slotLight;
    final dot = dark ? C.ink : Colors.white;
    for (var k = 0; k < 2; k++) {
      if (!seq.present(i, k)) continue;
      final base = slotColors[k];
      double z(int j) => seq.get(i, k, j, 2) - seq.get(i, k, 0, 2);
      Offset pt(int j) => P(seq.get(i, k, j, 0), seq.get(i, k, j, 1));
      final edges = [...kHandEdges]..sort((a, b) => (z(b[0]) + z(b[1])).compareTo(z(a[0]) + z(a[1])));
      for (final e in edges) {
        final near = (-(z(e[0]) + z(e[1])) / 2 * 6).clamp(-1.0, 1.0);
        final col = Color.lerp(dark ? C.ink : Colors.white, base, 0.6 + 0.4 * (near + 1) / 2)!;
        canvas.drawLine(pt(e[0]), pt(e[1]), Paint()
          ..color = col
          ..strokeWidth = math.max(2, 5 + 3 * near)
          ..strokeCap = StrokeCap.round);
      }
      final order = List.generate(kPoints, (j) => j)..sort((a, b) => z(b).compareTo(z(a)));
      for (final j in order) {
        final near = (-z(j) * 6).clamp(-1.0, 1.0);
        final r = math.max(2.0, 4.0 + 2.5 * near);
        canvas.drawCircle(pt(j), r, Paint()..color = dot);
        canvas.drawCircle(pt(j), r, Paint()
          ..color = base
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
    }
  }

  @override
  bool shouldRepaint(GuidePainter old) => old.i != i || old.seq != seq || old.dark != dark;
}

// ---------------------------------------------------------------- 카메라 + 손 관절 (M2-3)

/// 화면을 꽉 채우는 카메라 미리보기 + 손 관절 표시. 좌표는 거울 모드(앞 카메라 좌우 반전) 기준.
class CameraFill extends StatelessWidget {
  const CameraFill({super.key, required this.controller, required this.frame, this.flipOverlay = false});

  final CameraController controller;
  final FrameData? frame;
  final bool flipOverlay;

  @override
  Widget build(BuildContext context) {
    final ps = controller.value.previewSize;
    if (ps == null) return const SizedBox.shrink();
    // 세로 화면: 미리보기 크기의 가로·세로가 바뀜
    final w = math.min(ps.width, ps.height), h = math.max(ps.width, ps.height);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: w,
          height: h,
          child: CameraPreview(
            controller,
            child: CustomPaint(painter: LandmarkPainter(frame, flipOverlay), size: Size.infinite),
          ),
        ),
      ),
    );
  }
}

/// 카드 안에 들어가는 카메라 (테스트 화면용, 잘리지 않게)
class CameraWithLandmarks extends StatelessWidget {
  const CameraWithLandmarks({super.key, required this.controller, required this.frame, this.flipOverlay = false});

  final CameraController controller;
  final FrameData? frame;
  final bool flipOverlay;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CameraPreview(
          controller,
          child: CustomPaint(painter: LandmarkPainter(frame, flipOverlay), size: Size.infinite),
        ),
      );
}

class LandmarkPainter extends CustomPainter {
  LandmarkPainter(this.f, this.flip);

  final FrameData? f;
  final bool flip;

  @override
  void paint(Canvas canvas, Size size) {
    final fd = f;
    if (fd == null) return;
    Offset P(double x, double y) => Offset((flip ? 1 - x : x) * size.width, y * size.height);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 2; k++) {
      if (!fd.handOk[k]) continue;
      final h = fd.hands[k];
      for (final e in kHandEdges) {
        canvas.drawLine(P(h[e[0]][0], h[e[0]][1]), P(h[e[1]][0], h[e[1]][1]), line);
      }
      for (final p in h) {
        canvas.drawCircle(P(p[0], p[1]), 4, Paint()..color = const Color(0xFF5FD3C8));
      }
    }
    if (fd.poseOk) {
      final g = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = 3;
      final ls = P(fd.pose[kPoseLSh][0], fd.pose[kPoseLSh][1]);
      final rs = P(fd.pose[kPoseRSh][0], fd.pose[kPoseRSh][1]);
      canvas.drawLine(ls, rs, g);
      canvas.drawCircle(ls, 6, g);
      canvas.drawCircle(rs, 6, g);
    }
  }

  @override
  bool shouldRepaint(LandmarkPainter old) => true;
}

/// 어두운 그라데이션 틀 (.frame / .illus)
class DarkFrame extends StatelessWidget {
  const DarkFrame({super.key, required this.child, this.height, this.radius = 16, this.reticle = true});

  final Widget child;
  final double? height;
  final double radius;
  final bool reticle;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(gradient: kFrameGradient, borderRadius: BorderRadius.circular(radius)),
        child: Stack(fit: StackFit.expand, children: [
          if (reticle)
            const Padding(padding: EdgeInsets.all(14), child: Reticle(corner: 14, stroke: 2)),
          child,
        ]),
      );
}
