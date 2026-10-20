import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Rounded tinted square holding an icon — the app's "graphic" building block.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
    this.filled = false,
  });

  final IconData icon;
  final Color color;
  final double size;

  /// Solid fill with a gradient instead of a soft tint.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        color: filled
            ? null
            : color.withValues(alpha: scheme.isDark ? 0.16 : 0.14),
        gradient: filled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[color, Color.lerp(color, Colors.black, 0.25)!],
              )
            : null,
      ),
      child:
          Icon(icon, size: size * 0.52, color: filled ? Colors.white : color),
    );
  }
}

/// A surface card with consistent padding, radius and optional tap/gradient.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.gradient,
    this.color,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BorderRadius radius = BorderRadius.circular(20);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = InkWell(onTap: onTap, borderRadius: radius, child: content);
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? scheme.surface) : null,
        gradient: gradient,
        borderRadius: radius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}

/// Section heading used between groups of cards.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.padding});

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Small rounded label with an optional icon.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color c = color ?? scheme.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: c)),
          ),
        ],
      ),
    );
  }
}

/// Circular progress ring with a gradient sweep and a centered child.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 96,
    this.stroke = 10,
    this.colors,
    this.child,
  });

  /// 0..1
  final double value;
  final double size;
  final double stroke;
  final List<Color>? colors;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double v, Widget? _) {
          return CustomPaint(
            painter: _RingPainter(
              value: v,
              stroke: stroke,
              track: scheme.surfaceContainerHighest,
              colors: colors ?? <Color>[scheme.secondary, scheme.primary],
            ),
            child: Center(child: child),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.track,
    required this.colors,
  });

  final double value;
  final double stroke;
  final Color track;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (value <= 0) return;
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + math.pi * 2,
        colors:
            colors.length == 1 ? <Color>[colors.first, colors.first] : colors,
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.colors != colors;
}

/// Compact metric: colored icon badge + big number + label.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          IconBadge(icon: icon, color: color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.1)),
                const SizedBox(height: 2),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.muted,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Friendly empty state: big icon halo, title, message, optional actions.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const <Widget>[],
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: <Color>[
                  scheme.primary.withValues(alpha: 0.22),
                  scheme.primary.withValues(alpha: 0.04),
                ]),
              ),
              child: Icon(icon, size: 52, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.muted, fontSize: 14.5)),
            if (actions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 22),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The brand gradient used on hero cards.
LinearGradient heroGradient(ColorScheme scheme) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: scheme.isDark
          ? <Color>[
              const Color(0xFF1B3A33),
              const Color(0xFF1A2B45),
            ]
          : <Color>[
              const Color(0xFFD9F5E8),
              const Color(0xFFDCE8FB),
            ],
    );


/// A grid whose rows size to their content (equal height per row).
/// Unlike [GridView] with a fixed aspect ratio it cannot overflow when the
/// user raises the system font size.
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.columns,
    required this.children,
    this.spacing = 10,
  });

  final int columns;
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i += columns) {
      final List<Widget> cells = <Widget>[];
      for (int c = 0; c < columns; c++) {
        if (c > 0) cells.add(SizedBox(width: spacing));
        cells.add(Expanded(
          child: i + c < children.length ? children[i + c] : const SizedBox(),
        ));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cells,
        ),
      ));
    }
    return Column(children: rows);
  }
}
