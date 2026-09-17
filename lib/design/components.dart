import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../fields.dart';
import 'tokens.dart';

/// The small rounded square that names a platform in lists: its glyph in the
/// platform colour over a 10% tint of the same colour.
class PlatformIcon extends StatelessWidget {
  const PlatformIcon(this.platform, {super.key, this.size = 36});

  final ListingPlatform platform;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: platform.tint,
      borderRadius: BorderRadius.circular(size * 0.25),
    ),
    child: Text(
      platform.glyph,
      style: TextStyle(
        color: platform.color,
        fontSize: size * 0.38,
        fontWeight: FontWeight.w600,
        height: 1,
      ),
    ),
  );
}

/// The solid platform block at the centre of the 202/203 Process Hub. It
/// breathes while that platform is being worked on — the hub's only "the app
/// is busy elsewhere" signal.
class PlatformTile extends StatefulWidget {
  const PlatformTile(
    this.platform, {
    super.key,
    this.size = 64,
    this.active = true,
  });

  final ListingPlatform platform;
  final double size;
  final bool active;

  @override
  State<PlatformTile> createState() => _PlatformTileState();
}

class _PlatformTileState extends State<PlatformTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _pulse.repeat();
  }

  @override
  void didUpdateWidget(PlatformTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.active && _pulse.isAnimating) _pulse.reset();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final radius = size * 0.22;
    return SizedBox(
      width: size * 1.6,
      height: size * 1.6,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = _pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.active)
                Opacity(
                  opacity: (1 - t) * 0.4,
                  child: Container(
                    width: size * (1 + 0.55 * t),
                    height: size * (1 + 0.55 * t),
                    decoration: BoxDecoration(
                      color: widget.platform.color.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(radius * (1 + t)),
                    ),
                  ),
                ),
              child!,
            ],
          );
        },
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.platform.color,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Text(
            widget.platform.label,
            style: const TextStyle(
              color: AppColor.textOnColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// 001 and 301's selectable row: a leading mark, a name, and a check circle.
class SelectCard extends StatelessWidget {
  const SelectCard({
    super.key,
    required this.platform,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final ListingPlatform platform;
  final bool selected;
  final VoidCallback onTap;

  /// Shown before the check circle, e.g. "연동됨".
  final String? trailing;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.quick,
        curve: Motion.enter,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s16,
          vertical: Space.s12,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColor.bgBrandSubtle : AppColor.bgSurface,
          borderRadius: BorderRadius.circular(Radii.r12),
          border: Border.all(
            color: selected ? AppColor.borderFocus : AppColor.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            PlatformIcon(platform, size: 32),
            const SizedBox(width: Space.s12),
            Expanded(
              child: Text(
                platform.label,
                style: AppText.body.copyWith(color: AppColor.textPrimary),
              ),
            ),
            if (trailing != null) ...[
              Text(trailing!, style: AppText.caption),
              const SizedBox(width: Space.s8),
            ],
            CheckCircle(checked: selected),
          ],
        ),
      ),
    ),
  );
}

/// The round check the selection rows end on: filled brand when on, an empty
/// ring when off.
class CheckCircle extends StatelessWidget {
  const CheckCircle({super.key, required this.checked, this.size = 22});

  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: Motion.quick,
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: checked ? AppColor.actionPrimary : AppColor.bgSurface,
      border: checked
          ? null
          : Border.all(color: AppColor.borderDefault, width: 1.5),
    ),
    child: AnimatedScale(
      duration: Motion.quick,
      curve: Motion.settle,
      scale: checked ? 1 : 0,
      child: Icon(
        Icons.check_rounded,
        size: size * 0.7,
        color: AppColor.actionPrimaryContent,
      ),
    ),
  );
}

enum BrandButtonKind { filled, outlined, text }

/// One button for the whole app — the hi-fi's purple CTA and its quiet
/// siblings. A disabled filled button turns grey rather than pale purple, as
/// 301 draws "플랫폼을 선택해주세요".
class BrandButton extends StatelessWidget {
  const BrandButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.kind = BrandButtonKind.filled,
    this.expand = true,
    this.foreground,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final BrandButtonKind kind;
  final bool expand;
  final Color? foreground;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fill = switch (kind) {
      BrandButtonKind.filled =>
        enabled ? AppColor.actionPrimary : AppColor.bgSubtle,
      BrandButtonKind.outlined => AppColor.bgSurface,
      BrandButtonKind.text => Colors.transparent,
    };
    final text =
        foreground ??
        switch (kind) {
          BrandButtonKind.filled =>
            enabled ? AppColor.actionPrimaryContent : AppColor.textDisabled,
          BrandButtonKind.outlined => AppColor.textSecondary,
          BrandButtonKind.text => AppColor.textSecondary,
        };
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.r12),
      side: kind == BrandButtonKind.outlined
          ? const BorderSide(color: AppColor.borderSubtle)
          : BorderSide.none,
    );
    final button = Material(
      color: fill,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        highlightColor: kind == BrandButtonKind.filled
            ? AppColor.actionPrimaryPressed.withValues(alpha: 0.4)
            : null,
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Space.s16),
          child: Text(
            label,
            style: TextStyle(
              fontSize: kind == BrandButtonKind.text ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: enabled ? text : AppColor.textDisabled,
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// "광고 등록 2 / 3" — one segment per step, filled up to [current].
class StepProgress extends StatelessWidget {
  const StepProgress({
    super.key,
    required this.total,
    required this.current,
    required this.label,
    this.onBack,
  });

  final int total;
  final int current;
  final String label;

  /// Adds a chevron before the label, for screens whose only chrome is this
  /// bar (the WebView lifted out of the Process Hub).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s8, Space.gutter, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < total; i++) ...[
              if (i > 0) const SizedBox(width: Space.s4),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  duration: Motion.base,
                  curve: Motion.enter,
                  tween: Tween(end: i < current ? 1 : 0),
                  builder: (context, t, _) => Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColor.borderSubtle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: t,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColor.actionPrimary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (onBack == null) ...[
          const SizedBox(height: Space.s8),
          Text(label, style: AppText.caption),
        ] else
          Row(
            children: [
              IconButton(
                tooltip: '진행 상황으로',
                onPressed: onBack,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  size: 22,
                  color: AppColor.iconTertiary,
                ),
              ),
              Text(label, style: AppText.caption),
            ],
          ),
      ],
    ),
  );
}

/// The hi-fi's native top bar: a chevron and a left-aligned title.
class BackTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const BackTitleBar({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
    this.background = AppColor.bgPage,
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Color background;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: preferredSize.height,
        child: Row(
          children: [
            IconButton(
              tooltip: '뒤로',
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.chevron_left_rounded,
                size: 30,
                color: AppColor.textPrimary,
              ),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.title.copyWith(fontSize: 18),
              ),
            ),
            ...actions,
            const SizedBox(width: Space.s8),
          ],
        ),
      ),
    ),
  );
}

/// A small text action for [BackTitleBar] — "수정", "임시 저장".
class BarAction extends StatelessWidget {
  const BarAction(this.label, {super.key, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: AppColor.textSecondary,
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: Space.s8),
    ),
    child: Text(label, style: AppText.bodySmall),
  );
}

enum OutcomeKind { success, warning, error }

/// The large centred mark every result screen lands on: a purple tick for 002,
/// 204, 2062 and 303, a brown "!" for 205, a red cross for 206.
class OutcomeMark extends StatefulWidget {
  const OutcomeMark(this.kind, {super.key, this.size = 40});

  final OutcomeKind kind;
  final double size;

  @override
  State<OutcomeMark> createState() => _OutcomeMarkState();
}

class _OutcomeMarkState extends State<OutcomeMark>
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
  Widget build(BuildContext context) {
    final (color, icon) = switch (widget.kind) {
      OutcomeKind.success => (AppColor.actionPrimary, Icons.check_rounded),
      OutcomeKind.warning => (
        AppColor.statusWarning,
        Icons.priority_high_rounded,
      ),
      OutcomeKind.error => (AppColor.statusError, Icons.close_rounded),
    };
    return ScaleTransition(
      scale: CurvedAnimation(parent: _controller, curve: Motion.settle),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: Icon(
          icon,
          size: widget.size * 0.62,
          color: AppColor.textOnColor,
        ),
      ),
    );
  }
}

/// The dot that pulses in the "정보를 입력하고 있어요" row (Motion / Pulse).
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, this.color = AppColor.actionLinkSubtle});

  final Color color;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20,
    height: 20,
    child: Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Container(
            width: 8 + 4 * t,
            height: 8 + 4 * t,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(widget.color, AppColor.actionPrimary, t),
            ),
          );
        },
      ),
    ),
  );
}

/// The dark rounded toast that rises from the bottom of a WebView screen.
class GuideToast extends StatelessWidget {
  const GuideToast({super.key, required this.title, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(
      horizontal: Space.s16,
      vertical: Space.s12,
    ),
    decoration: BoxDecoration(
      color: AppColor.bgOverlay.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(Radii.r12),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppText.bodySmall.copyWith(
            color: AppColor.textOnColor,
            fontWeight: detail == null ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
        if (detail != null)
          Text(
            detail!,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(
              color: AppColor.textOnColor.withValues(alpha: 0.86),
            ),
          ),
      ],
    ),
  );
}

/// Holds a [GuideToast] for [Motion.toastHold], sliding it up on arrival and
/// back down afterwards. A new [toastKey] replays the sequence — that is how
/// 2021's first toast hands over to 2023's second one.
class TimedToast extends StatefulWidget {
  const TimedToast({
    super.key,
    required this.toastKey,
    required this.title,
    this.detail,
  });

  final Object toastKey;
  final String title;
  final String? detail;

  @override
  State<TimedToast> createState() => _TimedToastState();
}

class _TimedToastState extends State<TimedToast> {
  bool _shown = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _play();
  }

  @override
  void didUpdateWidget(TimedToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.toastKey != widget.toastKey) _play();
  }

  void _play() {
    final generation = ++_generation;
    setState(() => _shown = false);
    Future<void>.delayed(Motion.quick, () {
      if (!mounted || generation != _generation) return;
      setState(() => _shown = true);
      Future<void>.delayed(Motion.toastHold, () {
        if (mounted && generation == _generation) {
          setState(() => _shown = false);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedSlide(
      duration: Motion.base,
      curve: _shown ? Motion.enter : Motion.exit,
      offset: _shown ? Offset.zero : const Offset(0, 1.6),
      child: AnimatedOpacity(
        duration: Motion.base,
        opacity: _shown ? 1 : 0,
        child: GuideToast(title: widget.title, detail: widget.detail),
      ),
    ),
  );
}

/// The white rounded sheet a WebView lives in (0011, 2021, 2022, 2051, 3021).
class WebSheet extends StatelessWidget {
  const WebSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: Space.s12),
    decoration: const BoxDecoration(
      color: AppColor.bgSurface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.r24)),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

/// 한방's mark: a brand-coloured rounded square.
class HanbangLogo extends StatelessWidget {
  const HanbangLogo({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppColor.actionPrimary,
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
  );
}

/// The checkerboard the hi-fi draws wherever a listing photo will sit.
class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({super.key, this.radius = Radii.r8, this.cell = 12});

  final double radius;
  final double cell;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: CustomPaint(
      painter: _CheckerPainter(cell),
      child: const SizedBox.expand(),
    ),
  );
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter(this.cell);

  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColor.bgSurface);
    final dark = Paint()..color = AppColor.bgSubtle;
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        if ((x + y).isOdd) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), dark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter oldDelegate) =>
      oldDelegate.cell != cell;
}

/// Staggered entrance for stacked blocks.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 12,
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

/// Motion / Splash Merge: three dots gather into one, the dot swells, and it
/// settles into the 한방 mark with its wordmark.
class SplashMerge extends StatefulWidget {
  const SplashMerge({
    super.key,
    this.duration = const Duration(milliseconds: 2000),
  });

  final Duration duration;

  @override
  State<SplashMerge> createState() => _SplashMergeState();
}

class _SplashMergeState extends State<SplashMerge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static double _phase(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    height: 56,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // 0.00–0.35: the dots wait, breathing in turn.
        // 0.35–0.55: they slide into the centre.
        // 0.55–0.75: the single dot swells and pales.
        // 0.75–1.00: it squares off into the mark; the wordmark fades in.
        final gather = Curves.easeInOutCubic.transform(_phase(t, 0.35, 0.55));
        final swell = Curves.easeOut.transform(_phase(t, 0.55, 0.75));
        final settle = Curves.easeOutBack.transform(_phase(t, 0.75, 1));
        const dot = 10.0;
        final children = <Widget>[];
        if (swell == 0) {
          for (var i = -1; i <= 1; i++) {
            final breath =
                0.5 + 0.5 * math.sin((t * 6 - (i + 1) * 0.6) * math.pi);
            children.add(
              Transform.translate(
                offset: Offset(i * 16 * (1 - gather), 0),
                child: Opacity(
                  opacity: gather > 0 ? 1 : 0.55 + 0.45 * breath,
                  child: Container(
                    width: dot,
                    height: dot,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColor.actionPrimary,
                    ),
                  ),
                ),
              ),
            );
          }
        } else {
          final size = dot + (34 - dot) * swell;
          final shift = -24 * settle;
          children.add(
            Transform.translate(
              offset: Offset(shift, 0),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    AppColor.actionPrimary,
                    AppColor.actionLinkSubtle,
                    swell * (1 - settle),
                  ),
                  borderRadius: BorderRadius.circular(
                    size / 2 - (size / 2 - size * 0.28) * settle,
                  ),
                ),
              ),
            ),
          );
          children.add(
            Transform.translate(
              offset: Offset(22 + 8 * (1 - settle), 0),
              child: Opacity(
                opacity: settle.clamp(0.0, 1.0),
                child: const Text(
                  '한방',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColor.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ),
          );
        }
        return Stack(alignment: Alignment.center, children: children);
      },
    ),
  );
}

/// A thick, soft rule between the long form's and the detail page's sections.
class SectionRule extends StatelessWidget {
  const SectionRule({super.key, this.vertical = Space.s24});

  final double vertical;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: vertical),
    child: Container(
      height: 6,
      decoration: BoxDecoration(
        color: AppColor.borderFaint,
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );
}

enum RowMark { done, working, waiting, warning, error }

/// One platform in the Process Hub's Channel Status Summary (and in 303):
/// a state mark, the platform name with its status, an optional action on the
/// right and an optional second line.
class ChannelRow extends StatelessWidget {
  const ChannelRow({
    super.key,
    required this.mark,
    required this.name,
    required this.status,
    this.action,
    this.actionIcon,
    this.onAction,
    this.subline,
  });

  final RowMark mark;
  final String name;
  final String status;
  final String? action;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final String? subline;

  @override
  Widget build(BuildContext context) {
    final highlighted = mark == RowMark.working;
    final leading = switch (mark) {
      RowMark.done => const _RowBadge(
        color: AppColor.statusSuccess,
        icon: Icons.check_rounded,
      ),
      RowMark.working => const PulseDot(),
      RowMark.waiting => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColor.borderDefault, width: 1.5),
        ),
      ),
      RowMark.warning => const _RowBadge(
        color: AppColor.statusWarning,
        icon: Icons.priority_high_rounded,
      ),
      RowMark.error => const _RowBadge(
        color: AppColor.statusError,
        icon: Icons.close_rounded,
      ),
    };
    final actionColor = highlighted
        ? AppColor.actionLinkSubtle
        : AppColor.actionLink;
    return AnimatedContainer(
      duration: Motion.base,
      curve: Motion.enter,
      padding: const EdgeInsets.fromLTRB(Space.s16, 14, Space.s12, 14),
      decoration: BoxDecoration(
        color: highlighted ? AppColor.bgBrandSubtle : AppColor.bgSurface,
        borderRadius: BorderRadius.circular(Radii.r16),
        border: Border.all(
          color: highlighted ? AppColor.borderFocus : AppColor.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leading,
              const SizedBox(width: Space.s12),
              Text(name, style: AppText.bodyStrong),
              const SizedBox(width: Space.s8),
              Expanded(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: AppColor.textSecondary,
                  ),
                ),
              ),
              if (action != null)
                Semantics(
                  button: true,
                  child: InkWell(
                    onTap: onAction,
                    borderRadius: BorderRadius.circular(Radii.r8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.s4,
                        vertical: Space.s8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            action!,
                            style: AppText.bodySmall.copyWith(
                              color: actionColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Icon(
                            actionIcon ?? Icons.chevron_right_rounded,
                            size: actionIcon == null ? 18 : 14,
                            color: actionColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (subline != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subline!, style: AppText.caption),
            ),
        ],
      ),
    );
  }
}

class _RowBadge extends StatelessWidget {
  const _RowBadge({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    child: Icon(icon, size: 14, color: AppColor.textOnColor),
  );
}
