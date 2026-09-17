import 'package:flutter/material.dart';

import '../android_layout.dart';
import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../fields.dart';
import '../models/listing.dart';
import 'home_page.dart';

/// 301 광고 종료 (내리기).
///
/// The 확정 note asks this to mirror 201 exactly — 과정 신뢰 while it runs, 결과
/// 신뢰 when it lands — so the agent sees a channel actually come down instead
/// of a listing quietly changing state.
///
/// The mirror lab only publishes registration forms; there is no takedown
/// endpoint to drive, so each channel here advances on a timer. Everything the
/// screen reports about the listing itself (which channels, what state, where
/// it moved to) is real and persisted.
class TakedownFlowPage extends StatefulWidget {
  const TakedownFlowPage({
    super.key,
    required this.store,
    required this.listing,
    required this.reason,
    required this.channels,
  });

  final AppStore store;
  final Listing listing;
  final ClosedReason reason;
  final List<ListingPlatform> channels;

  @override
  State<TakedownFlowPage> createState() => _TakedownFlowPageState();
}

class _TakedownFlowPageState extends State<TakedownFlowPage> {
  late final Map<ListingPlatform, ChannelState> _states = {
    for (final platform in widget.channels) platform: ChannelState.pending,
  };

  int _index = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    for (final (index, platform) in widget.channels.indexed) {
      if (!mounted) return;
      setState(() {
        _index = index;
        _states[platform] = ChannelState.working;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      if (!mounted) return;
      setState(() => _states[platform] = ChannelState.removed);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (!mounted) return;
    await widget.store.close(
      widget.listing,
      reason: widget.reason,
      channels: widget.channels.toSet(),
    );
    if (mounted) setState(() => _done = true);
  }

  void _close() => Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => HomePage(store: widget.store)),
    (route) => false,
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _done,
    child: Scaffold(
      backgroundColor: Brand.canvas,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: Motion.base,
          switchInCurve: Motion.enter,
          child: _done
              ? _TakedownResult(
                  key: const ValueKey('result'),
                  channels: widget.channels,
                  reason: widget.reason,
                  onClose: _close,
                )
              : _TakedownProgress(
                  key: const ValueKey('progress'),
                  channels: widget.channels,
                  states: _states,
                  index: _index,
                ),
        ),
      ),
    ),
  );
}

class _TakedownProgress extends StatelessWidget {
  const _TakedownProgress({
    super.key,
    required this.channels,
    required this.states,
    required this.index,
  });

  final List<ListingPlatform> channels;
  final Map<ListingPlatform, ChannelState> states;
  final int index;

  @override
  Widget build(BuildContext context) {
    final current = channels[index.clamp(0, channels.length - 1)];
    final finished = states.values
        .where((state) => state == ChannelState.removed)
        .length;

    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
        child: Column(
          children: [
            const Spacer(flex: 3),
            PulseHalo(
              color: current.color,
              child: PlatformBadge(current, size: 96),
            ),
            const SizedBox(height: 28),
            Text('${current.label}에서 내리는 중이에요', style: Type.title),
            const SizedBox(height: 12),
            WorkingDots(color: current.color),
            const SizedBox(height: 18),
            const Text(
              '조금만 기다려주세요.\n앱을 종료하지 말고 기다려주세요!',
              textAlign: TextAlign.center,
              style: Type.bodyMuted,
            ),
            const SizedBox(height: 26),
            TweenAnimationBuilder<double>(
              duration: Motion.slow,
              curve: Motion.enter,
              tween: Tween(begin: 0, end: finished / channels.length),
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: Brand.hairline,
                  valueColor: const AlwaysStoppedAnimation(Brand.blue),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('$finished / ${channels.length}개 채널 완료', style: Type.caption),
            const Spacer(flex: 3),
            for (final platform in channels)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TakedownRow(
                  platform: platform,
                  state: states[platform] ?? ChannelState.pending,
                ),
              ),
            SizedBox(height: 20 + androidBottomInset(context).bottom),
          ],
        ),
      ),
    );
  }
}

class _TakedownRow extends StatelessWidget {
  const _TakedownRow({required this.platform, required this.state});

  final ListingPlatform platform;
  final ChannelState state;

  @override
  Widget build(BuildContext context) {
    final active = state == ChannelState.working;
    return AnimatedContainer(
      duration: Motion.base,
      curve: Motion.enter,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: active ? Brand.blueFaint : Brand.surface,
        borderRadius: BorderRadius.circular(Insets.radiusField),
        border: Border.all(
          color: active ? Brand.blue : Brand.hairline,
          width: active ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          PlatformBadge(
            platform,
            size: 30,
            dimmed: state != ChannelState.working,
          ),
          const SizedBox(width: 12),
          Text(
            platform.label,
            style: Type.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: Motion.quick,
            child: Text(
              state.takedownLabel,
              key: ValueKey(state),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: switch (state) {
                  ChannelState.working => Brand.blue,
                  ChannelState.removed => Brand.success,
                  _ => Brand.inkFaint,
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TakedownResult extends StatelessWidget {
  const _TakedownResult({
    super.key,
    required this.channels,
    required this.reason,
    required this.onClose,
  });

  final List<ListingPlatform> channels;
  final ClosedReason reason;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
    child: Column(
      children: [
        const Spacer(flex: 3),
        const Icon(
          Icons.trending_down_rounded,
          size: 44,
          color: Brand.inkMuted,
        ),
        const SizedBox(height: 22),
        FadeSlideIn(
          child: Text(
            '광고가 ${channels.map((p) => p.label).join(', ')}에서\n내려갔어요',
            textAlign: TextAlign.center,
            style: Type.display,
          ),
        ),
        const SizedBox(height: 10),
        FadeSlideIn(
          delay: const Duration(milliseconds: 120),
          child: Text(
            reason == ClosedReason.dealDone
                ? '성사된 광고 목록으로 옮겼어요.'
                : '성사된 광고 목록에서 다시 볼 수 있어요.',
            style: Type.caption,
          ),
        ),
        const SizedBox(height: 20),
        FadeSlideIn(
          delay: const Duration(milliseconds: 200),
          child: Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [for (final platform in channels) PlatformChip(platform)],
          ),
        ),
        const Spacer(flex: 2),
        BrandButton('확인', onPressed: onClose),
        SizedBox(height: 24 + androidBottomInset(context).bottom),
      ],
    ),
  );
}
