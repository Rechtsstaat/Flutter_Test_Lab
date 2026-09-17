import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../fields.dart';
import 'tokens.dart';

/// The rounded-square platform mark the lo-fi repeats on every screen that
/// names a channel.
class PlatformBadge extends StatelessWidget {
  const PlatformBadge(
    this.platform, {
    super.key,
    this.size = 36,
    this.dimmed = false,
  });

  final ListingPlatform platform;
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final color = dimmed
        ? Color.lerp(platform.color, Brand.canvas, 0.62)!
        : platform.color;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        platform.glyph,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.44,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

/// 광고중 / 성사됨 — the state pill on a listing card and on the detail sheet.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.color = Brand.blue});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

/// The tinted channel pill under a listing title.
class PlatformChip extends StatelessWidget {
  const PlatformChip(this.platform, {super.key});

  final ListingPlatform platform;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: platform.tint,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: platform.color.withValues(alpha: 0.28)),
    ),
    child: Text(
      platform.label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: platform.color,
      ),
    ),
  );
}

enum BrandButtonKind { filled, outlined, quiet }

/// One button for the whole app. The lo-fi only ever varies fill colour, so
/// the platform-coloured login CTA and the blue primary share this widget.
class BrandButton extends StatelessWidget {
  const BrandButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.kind = BrandButtonKind.filled,
    this.color = Brand.blue,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final BrandButtonKind kind;
  final Color color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fill = switch (kind) {
      BrandButtonKind.filled =>
        enabled ? color : Color.lerp(color, Brand.canvas, 0.62)!,
      BrandButtonKind.outlined => Brand.surface,
      BrandButtonKind.quiet => Colors.transparent,
    };
    final text = switch (kind) {
      BrandButtonKind.filled => Colors.white,
      BrandButtonKind.outlined => Brand.ink,
      BrandButtonKind.quiet => Brand.inkMuted,
    };
    final button = Material(
      color: fill,
      borderRadius: BorderRadius.circular(Insets.radiusField),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(Insets.radiusField),
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Insets.radiusField),
            border: kind == BrandButtonKind.outlined
                ? Border.all(color: Brand.hairline)
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: text,
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// The small bold caption that opens each block of the 광고 등록 form.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Text(text, style: Type.label),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}

/// The hatched grey rectangle the lo-fi uses wherever a photo will go.
class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({super.key, this.label = '매물사진', this.radius = 10});

  final String label;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: CustomPaint(
      painter: _HatchPainter(),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: Brand.inkFaint),
        ),
      ),
    ),
  );
}

class _HatchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Brand.placeholder);
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 7;
    for (var x = -size.height; x < size.width; x += 18) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HatchPainter oldDelegate) => false;
}

/// "플랫폼 연동 1 / 2" — one filled segment per completed step, the segments
/// growing into place so the step change is legible without reading the label.
class StepBar extends StatelessWidget {
  const StepBar({super.key, required this.total, required this.current});

  final int total;
  final int current;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < total; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(
          child: TweenAnimationBuilder<double>(
            duration: Motion.base,
            curve: Motion.enter,
            tween: Tween(begin: 0, end: i < current ? 1 : 0),
            builder: (context, t, _) => Stack(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Brand.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: t,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Brand.blue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

/// Staggered entrance. The lo-fi screens are stacked blocks, so letting them
/// arrive in reading order costs nothing and makes each screen legible as it
/// appears instead of all at once.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.base,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Motion.enter);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, widget.offset * (1 - curved.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// A ring that breathes outward from a platform badge while that channel is
/// being worked on. This is the lo-fi's only "please wait, the app is doing
/// something off-screen" signal, and the notes ask for that wait to feel
/// accounted for rather than frozen.
class PulseHalo extends StatefulWidget {
  const PulseHalo({
    super.key,
    required this.child,
    required this.color,
    this.active = true,
  });

  final Widget child;
  final Color color;
  final bool active;

  @override
  State<PulseHalo> createState() => _PulseHaloState();
}

class _PulseHaloState extends State<PulseHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(PulseHalo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final t = _controller.value;
      return Stack(
        alignment: Alignment.center,
        children: [
          for (final phase in const [0.0, 0.5])
            Builder(
              builder: (context) {
                final p = (t + phase) % 1;
                return Opacity(
                  opacity: widget.active ? (1 - p) * 0.35 : 0,
                  child: Container(
                    width: 108 + 52 * p,
                    height: 108 + 52 * p,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(34 + 16 * p),
                    ),
                  ),
                );
              },
            ),
          child!,
        ],
      );
    },
    child: widget.child,
  );
}

/// The three dots printed under "직방에 올리는 중이에요".
class WorkingDots extends StatefulWidget {
  const WorkingDots({super.key, this.color = Brand.blue});

  final Color color;

  @override
  State<WorkingDots> createState() => _WorkingDotsState();
}

class _WorkingDotsState extends State<WorkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Builder(
            builder: (context) {
              final phase = (_controller.value - i * 0.18) % 1;
              final lift = math.max(0.0, math.sin(phase * math.pi * 2));
              return Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(
                    widget.color.withValues(alpha: 0.25),
                    widget.color,
                    lift,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    ),
  );
}

/// The circled tick every "…했어요" screen lands on. It draws itself once so
/// the completion reads as an event rather than a static illustration.
class SuccessTick extends StatefulWidget {
  const SuccessTick({super.key, this.color = Brand.blue, this.size = 84});

  final Color color;
  final double size;

  @override
  State<SuccessTick> createState() => _SuccessTickState();
}

class _SuccessTickState extends State<SuccessTick>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.slow,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final pop = Curves.easeOutBack.transform(
        Curves.easeOut.transform(_controller.value.clamp(0.0, 0.6) / 0.6),
      );
      return Transform.scale(
        scale: 0.6 + 0.4 * pop,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.13),
          ),
          child: Icon(
            Icons.check_rounded,
            size: widget.size * 0.44,
            color: widget.color,
          ),
        ),
      );
    },
  );
}
