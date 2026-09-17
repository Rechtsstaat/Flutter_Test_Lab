import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../android_layout.dart';
import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../fields.dart';
import '../models/listing.dart';
import '../remote_form.dart';
import 'home_page.dart';

typedef RemotePageBuilder =
    Widget Function(
      Map<String, dynamic> values,
      ListingPlatform platform,
      List<XFile> photos,
    );

/// 201 등록 진행 + 결과.
///
/// The 개선 notes split trust in two: 과정 신뢰 (the agent can see which channel
/// is being worked on right now) and 결과 신뢰 (per-channel outcomes afterwards,
/// including the ones that need another look). This page owns both halves and
/// drives the real mirror in between — the adapter fills the remote form, and
/// the 0914 note records that the agent still presses 등록하기 there themselves.
class PublishFlowPage extends StatefulWidget {
  const PublishFlowPage({
    super.key,
    required this.listing,
    required this.values,
    required this.photos,
    required this.channels,
    this.store,
    this.remotePageBuilder,
  });

  final Listing listing;
  final Map<String, dynamic> values;
  final List<XFile> photos;
  final List<ListingPlatform> channels;
  final AppStore? store;
  final RemotePageBuilder? remotePageBuilder;

  @override
  State<PublishFlowPage> createState() => _PublishFlowPageState();
}

class _PublishFlowPageState extends State<PublishFlowPage> {
  late final Map<ListingPlatform, ChannelState> _states = {
    for (final platform in widget.channels) platform: ChannelState.pending,
  };

  /// What each mirror's adapter said it could not fill. Surfaced verbatim on
  /// the result screen so "확인이 필요해요" always comes with a reason.
  final _notes = <ListingPlatform, List<String>>{};

  int _index = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runNext());
  }

  ListingPlatform? get _current =>
      _index < widget.channels.length ? widget.channels[_index] : null;

  Future<void> _runNext() async {
    final platform = _current;
    if (platform == null) {
      await _finish();
      return;
    }
    setState(() => _states[platform] = ChannelState.working);

    // A beat before the mirror opens: without it the progress screen flashes
    // past and the agent never sees which channel is starting.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    final limitations = <String>[];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            widget.remotePageBuilder?.call(
              widget.values,
              platform,
              widget.photos,
            ) ??
            RemoteFormPage(
              values: widget.values,
              platform: platform,
              photos: widget.photos,
              onListingResult: (_, result) => limitations
                ..clear()
                ..addAll([
                  ...List<String>.from(result['missing'] as List? ?? const []),
                  ...List<String>.from(
                    result['violations'] as List? ?? const [],
                  ),
                  ...List<String>.from(
                    result['unsupported'] as List? ?? const [],
                  ),
                ]),
            ),
      ),
    );
    if (!mounted) return;

    setState(() {
      _states[platform] = limitations.isEmpty
          ? ChannelState.published
          : ChannelState.failed;
      if (limitations.isNotEmpty) _notes[platform] = List.of(limitations);
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _index += 1);
    await _runNext();
  }

  Future<void> _finish() async {
    await widget.store?.save(
      widget.listing.copyWith(channels: Map.of(_states)),
    );
    if (mounted) setState(() => _done = true);
  }

  void _close() {
    final store = widget.store;
    if (store == null) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => HomePage(store: store)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Leaving mid-run would strand the listing between channels; the flow is
    // short and always ends on a screen with its own way out.
    canPop: _done,
    child: Scaffold(
      backgroundColor: Brand.canvas,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: Motion.base,
          switchInCurve: Motion.enter,
          child: _done
              ? _ResultView(
                  key: const ValueKey('result'),
                  states: _states,
                  notes: _notes,
                  monthlyCount: widget.store?.registeredThisMonth ?? 1,
                  onClose: _close,
                )
              : _ProgressView(
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

class _ProgressView extends StatelessWidget {
  const _ProgressView({
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
        .where(
          (state) =>
              state == ChannelState.published || state == ChannelState.failed,
        )
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
            Text('${current.label}에 올리는 중이에요', style: Type.title),
            const SizedBox(height: 12),
            WorkingDots(color: current.color),
            const SizedBox(height: 18),
            const Text(
              '조금만 기다려주세요.\n최대 2분 소요될 수 있어요.',
              textAlign: TextAlign.center,
              style: Type.bodyMuted,
            ),
            const SizedBox(height: 4),
            const Text(
              '앱을 종료하지 말고 기다려주세요!',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Brand.ink,
              ),
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
            Text(
              '${finished + 1} / ${channels.length}개 채널 진행 중',
              style: Type.caption,
            ),
            const Spacer(flex: 3),
            for (final platform in channels)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ChannelRow(
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

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.platform, required this.state});

  final ListingPlatform platform;
  final ChannelState state;

  @override
  Widget build(BuildContext context) {
    final active = state == ChannelState.working;
    final color = switch (state) {
      ChannelState.working => Brand.blue,
      ChannelState.published => Brand.success,
      ChannelState.failed => Brand.danger,
      _ => Brand.inkFaint,
    };
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
            dimmed: state == ChannelState.pending,
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
              state.publishLabel,
              key: ValueKey(state),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    super.key,
    required this.states,
    required this.notes,
    required this.monthlyCount,
    required this.onClose,
  });

  final Map<ListingPlatform, ChannelState> states;
  final Map<ListingPlatform, List<String>> notes;
  final int monthlyCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ok = states.values
        .where((state) => state == ChannelState.published)
        .length;
    final needsCheck = states.entries
        .where((entry) => entry.value == ChannelState.failed)
        .toList();
    // The lo-fi's "직접 올렸다면 약 3시간" sits next to 20 listings — roughly nine
    // minutes of manual re-typing per channel.
    final hours = (monthlyCount * 9 / 60).ceil().clamp(1, 999);

    return ListView(
      padding:
          const EdgeInsets.fromLTRB(Insets.gutter, 40, Insets.gutter, 28) +
          androidBottomInset(context),
      children: [
        const Center(child: SuccessTick()),
        const SizedBox(height: 26),
        Center(
          child: Text(
            ok == 0 ? '등록을 마치지 못했어요' : '$ok개 채널에 등록했어요',
            style: Type.title,
          ),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          delay: const Duration(milliseconds: 160),
          child: Center(
            child: Text(
              '이번 달, 한방이\n대신 $monthlyCount번 등록했어요',
              textAlign: TextAlign.center,
              style: Type.display.copyWith(color: Brand.blue),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text('직접 올렸다면 약 $hours시간이 걸렸을 일이에요.', style: Type.caption),
        ),
        const SizedBox(height: 28),
        for (final entry in states.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ResultRow(
              platform: entry.key,
              state: entry.value,
              note: notes[entry.key]?.take(3).join(', '),
            ),
          ),
        if (needsCheck.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Brand.dangerTint,
              borderRadius: BorderRadius.circular(Insets.radiusField),
            ),
            child: Text(
              '${needsCheck.map((e) => e.key.label).join(', ')}는 미러가 채우지 못한 항목이 있어요. '
              '해당 채널을 열어 남은 항목을 확인한 뒤 등록하기를 눌러주세요.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Brand.danger,
              ),
            ),
          ),
        ],
        const SizedBox(height: 28),
        BrandButton('확인', onPressed: onClose),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.platform, required this.state, this.note});

  final ListingPlatform platform;
  final ChannelState state;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final failed = state == ChannelState.failed;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(Insets.radiusField),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            failed ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            size: 20,
            color: failed ? Brand.danger : Brand.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  failed
                      ? '${platform.label} 추가 확인이 필요해요'
                      : '${platform.label} 등록 완료',
                  style: Type.body.copyWith(fontWeight: FontWeight.w700),
                ),
                if (note != null && note!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(note!, style: Type.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
