import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// handly-app-mockup.html 의 디자인 토큰
class C {
  static const ink = Color(0xFF1C2033);
  static const inkSoft = Color(0xFF5A5E73);
  static const paper = Color(0xFFF1EEE6);
  static const paperRaised = Color(0xFFFBFAF6);
  static const line = Color(0xFFDAD5C8);
  static const teal = Color(0xFF14807A);
  static const tealDeep = Color(0xFF0B5E5A);
  static const tealTint = Color(0xFFDCEEEA);
  static const coral = Color(0xFFFF6152);
  static const coralTint = Color(0xFFFFE2DE);
  static const amber = Color(0xFFF0A94E);
  static const skyTop = Color(0xFF231E45);
  static const skyMid = Color(0xFF6A4E86);
  static const skyHorizon = Color(0xFFE98A55);
  static const skyLow = Color(0xFFF7C873);
  static const camTop = Color(0xFF20233A);
  static const camBottom = Color(0xFF14151F);
  static const frameA = Color(0xFF2B2F45);
  static const onDark = Color(0xFFF1EEE6);
  static const onDarkSoft = Color(0xFFB9B6C9);
}

const kSky = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [C.skyTop, C.skyMid, C.skyHorizon, C.skyLow],
  stops: [0, 0.45, 0.78, 1],
);

const kFrameGradient = LinearGradient(
  begin: Alignment(-0.6, -1),
  end: Alignment(0.6, 1),
  colors: [C.frameA, C.ink],
);

/// 숫자는 Space Grotesk (목업 .num)
TextStyle sg(double size, {FontWeight weight = FontWeight.w700, Color? color}) =>
    TextStyle(fontFamily: 'SpaceGrotesk', fontSize: size, fontWeight: weight, color: color);

ThemeData handlyTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.teal, primary: C.teal, surface: C.paper),
    scaffoldBackgroundColor: C.paper,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
    appBarTheme: const AppBarTheme(backgroundColor: C.paper, foregroundColor: C.ink, elevation: 0, scrolledUnderElevation: 0),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.teal,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: C.paper,
        foregroundColor: C.ink,
        side: const BorderSide(color: C.line),
        minimumSize: const Size.fromHeight(48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

// ---------------------------------------------------------------- 아이콘 (목업 SVG 그대로)

class HIcons {
  static const hand =
      'M8 13V6a1.4 1.4 0 0 1 2.8 0v5.2M10.8 11V4.6a1.4 1.4 0 0 1 2.8 0V11M13.6 11.2V6a1.4 1.4 0 0 1 2.8 0v6.4M16.4 12.4v-2a1.3 1.3 0 0 1 2.6 0v5.6c0 3-2.1 5.5-5.6 5.5-2.3 0-3.5-.7-4.6-2L6.2 15.8c-.6-.8-.4-1.8.4-2.3.7-.4 1.5-.2 2 .4l1.4 1.6';
  static const home = 'M4 11.5 12 5l8 6.5V19a1 1 0 0 1-1 1h-4v-5h-6v5H5a1 1 0 0 1-1-1Z';
  static const learn =
      'M8 13V6a1.4 1.4 0 0 1 2.8 0v5.2M13.6 11.2V6a1.4 1.4 0 0 1 2.8 0v6.4M16.4 12.4v5.6c0 3-2.1 5.5-5.6 5.5-2.3 0-3.5-.7-4.6-2L4.2 17.8';
  static const arcade = 'M4 20V10l8-6 8 6v10a1 1 0 0 1-1 1h-5v-6h-4v6H5a1 1 0 0 1-1-1Z';
  static const review = 'M4 12a8 8 0 1 1 2.5 5.8M4 12v5.8h5.8';
  static const profile = 'M12 4.8a3.2 3.2 0 1 1 0 6.4a3.2 3.2 0 1 1 0-6.4ZM5 20c1-3.6 3.8-5.4 7-5.4s6 1.8 7 5.4';
  static const check = 'M5 12.5 9.5 17 19 7';
  static const cross = 'M6 6 18 18M18 6 6 18';
  static const star = 'M12 3.5 14.5 9l6 .8-4.3 4.1 1 6-5.2-2.9-5.2 2.9 1-6L3.5 9.8l6-.8Z';
  static const heart = 'M12 20 4.5 12.8a4.6 4.6 0 0 1 6.9-6.1l.6.6.6-.6a4.6 4.6 0 0 1 6.9 6.1Z';
  static const eye = 'M2.5 12s3.5-6.5 9.5-6.5S21.5 12 21.5 12s-3.5 6.5-9.5 6.5S2.5 12 2.5 12ZM12 9.2a2.8 2.8 0 1 1 0 5.6a2.8 2.8 0 1 1 0-5.6Z';
  static const back = 'M15 5 8 12l7 7';
}

class HIcon extends StatelessWidget {
  const HIcon(this.path, {super.key, this.size = 20, this.color, this.fill = false, this.stroke = 1.6, this.opacity = 1});

  final String path;
  final double size;
  final Color? color;
  final bool fill;
  final double stroke;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? C.ink;
    final hex = '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final attrs = fill
        ? 'fill="$hex" fill-opacity="$opacity"'
        : 'fill="none" stroke="$hex" stroke-opacity="$opacity" stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round"';
    return SvgPicture.string('<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="$path" $attrs/></svg>',
        width: size, height: size);
  }
}

// ---------------------------------------------------------------- 공통 위젯

/// 목업의 모서리 조준선 (.reticle / .big-reticle)
class Reticle extends StatelessWidget {
  const Reticle({super.key, this.color = C.teal, this.corner = 26, this.stroke = 3, this.child});

  final Color color;
  final double corner, stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _ReticlePainter(color, corner, stroke), child: child);
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter(this.color, this.c, this.w);

  final Color color;
  final double c, w;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = w
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final r = c * 0.3;
    void corner(Offset o, double dx, double dy) {
      final path = Path()
        ..moveTo(o.dx, o.dy + dy * c)
        ..lineTo(o.dx, o.dy + dy * r)
        ..quadraticBezierTo(o.dx, o.dy, o.dx + dx * r, o.dy)
        ..lineTo(o.dx + dx * c, o.dy);
      canvas.drawPath(path, p);
    }

    corner(Offset.zero, 1, 1);
    corner(Offset(s.width, 0), -1, 1);
    corner(Offset(0, s.height), 1, -1);
    corner(Offset(s.width, s.height), -1, -1);
  }

  @override
  bool shouldRepaint(_ReticlePainter o) => o.color != color;
}

/// 연속 학습 알약 (.streak-pill)
class StreakPill extends StatelessWidget {
  const StreakPill({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
        decoration: BoxDecoration(
          color: C.paperRaised,
          border: Border.all(color: C.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: C.amber, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$days', style: sg(14)),
          const SizedBox(width: 3),
          Text(days > 0 ? '일 연속 학습 중' : '오늘 첫 학습을 시작해 보세요', style: const TextStyle(fontSize: 12, color: C.inkSoft)),
        ]),
      );
}

/// 별 알약 (.stars-pill)
class StarsPill extends StatelessWidget {
  const StarsPill({super.key, required this.stars, this.dark = true});

  final int stars;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: dark ? const Color(0x520C0A14) : C.paperRaised,
          border: dark ? null : Border.all(color: C.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          HIcon(HIcons.star, size: 14, fill: true, color: dark ? const Color(0xFFF5F1E8) : C.amber),
          const SizedBox(width: 5),
          Text('$stars', style: sg(13, color: dark ? const Color(0xFFF5F1E8) : C.ink)),
        ]),
      );
}

/// 둥근 정보 카드 (.qcard)
class QCard extends StatelessWidget {
  const QCard({super.key, required this.icon, required this.label, this.meta, this.badge, this.iconColor = C.teal, this.onTap});

  final String icon, label;
  final String? meta, badge;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: C.paperRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: C.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              HIcon(icon, size: 18, color: iconColor),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              if (meta != null) Text(meta!, style: const TextStyle(fontSize: 11, color: C.inkSoft)),
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: C.coralTint, borderRadius: BorderRadius.circular(999)),
                  child: Text(badge!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.coral)),
                ),
            ]),
          ),
        ),
      );
}

/// 진행 사각 점 (.progress-dots)
class ProgressSquares extends StatelessWidget {
  const ProgressSquares({super.key, required this.count, required this.current, required this.done});

  final int count, current;
  final Set<int> done;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.only(right: 8),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              color: done.contains(i)
                  ? C.teal
                  : i == current
                      ? C.teal.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                  color: done.contains(i) || i == current ? C.teal : Colors.white.withValues(alpha: 0.14)),
            ),
          ),
      ]);
}

/// 난이도 점 (.diff-dots)
class DiffDots extends StatelessWidget {
  const DiffDots({super.key, required this.level});

  final int level;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < 3; i++)
          Container(
            margin: const EdgeInsets.only(right: 4),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: i < level ? 0.9 : 0.28),
            ),
          ),
      ]);
}

/// 하늘 배경의 별 점 (.sky-noise)
class SkyNoise extends StatelessWidget {
  const SkyNoise({super.key});

  @override
  Widget build(BuildContext context) => const IgnorePointer(child: CustomPaint(painter: _SkyNoisePainter(), size: Size.infinite));
}

class _SkyNoisePainter extends CustomPainter {
  const _SkyNoisePainter();

  @override
  void paint(Canvas canvas, Size s) {
    const dots = [(0.20, 0.15, 2.0, 0.35), (0.70, 0.08, 1.5, 0.25), (0.85, 0.22, 1.5, 0.3), (0.40, 0.05, 1.0, 0.2),
      (0.10, 0.30, 1.0, 0.2), (0.55, 0.18, 1.2, 0.25), (0.92, 0.04, 1.0, 0.3)];
    for (final (x, y, r, a) in dots) {
      canvas.drawCircle(Offset(x * s.width, y * s.height), r, Paint()..color = Colors.white.withValues(alpha: a));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
