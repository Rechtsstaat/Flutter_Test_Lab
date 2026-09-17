import 'dart:io';

import 'package:flutter/material.dart';

import '../android_layout.dart';
import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../models/listing.dart';
import 'listing_detail_page.dart';
import 'listing_form_page.dart';

/// 101 메인 — the hero register card over two tabs of listings.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});

  final AppStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  /// Set when a listing leaves 나의 광고 without the agent doing anything, so
  /// the count can show its own change instead of silently dropping by one.
  int _delta = 0;
  String? _autoClosedTitle;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    if (!widget.store.loaded) widget.store.load();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _register() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListingFormPage(store: widget.store),
      ),
    );
  }

  /// 테스트용: stands in for the push that tells us another agent closed the
  /// deal. The lo-fi keeps this switch on the home screen precisely because
  /// the auto-takedown is otherwise impossible to see during review.
  Future<void> _simulateExternalDeal() async {
    final open = widget.store.advertising;
    if (open.isEmpty) return;
    final victim = open.last;
    await widget.store.close(
      victim,
      reason: ClosedReason.takenByOthers,
      channels: victim.channels.keys.toSet(),
    );
    if (!mounted) return;
    setState(() {
      _delta = -1;
      _autoClosedTitle = victim.title;
    });
    Future<void>.delayed(const Duration(seconds: 6), () {
      if (mounted) setState(() => _delta = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.store.advertising;
    final done = widget.store.closed;
    final shown = _tab == 0 ? mine : done;

    return Scaffold(
      backgroundColor: Brand.canvas,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding:
              const EdgeInsets.fromLTRB(Insets.gutter, 8, Insets.gutter, 28) +
              androidBottomInset(context),
          children: [
            const _HomeHeader(),
            const SizedBox(height: 18),
            _HeroCard(channels: widget.store.linked.length, onTap: _register),
            const SizedBox(height: 18),
            _Tabs(
              labels: ['나의 광고 ${mine.length}', '성사된 광고 ${done.length}'],
              index: _tab,
              delta: _delta,
              onChanged: (index) => setState(() => _tab = index),
            ),
            const SizedBox(height: 14),
            if (_autoClosedTitle != null && _tab == 0)
              _AutoClosedBanner(
                title: _autoClosedTitle!,
                onDismiss: () => setState(() => _autoClosedTitle = null),
              ),
            AnimatedSwitcher(
              duration: Motion.base,
              switchInCurve: Motion.enter,
              child: shown.isEmpty
                  ? _EmptyState(key: ValueKey('empty-$_tab'), tab: _tab)
                  : Column(
                      key: ValueKey('list-$_tab-${shown.length}'),
                      children: [
                        for (final (index, listing) in shown.indexed)
                          FadeSlideIn(
                            delay: Duration(milliseconds: 40 * index),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ListingCard(
                                listing: listing,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ListingDetailPage(
                                      store: widget.store,
                                      listingId: listing.id,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            _TestPanel(enabled: mine.isNotEmpty, onTap: _simulateExternalDeal),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Brand.blue,
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Text(
          '한방',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const SizedBox(width: 9),
      const Text(
        '한방',
        style: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: Brand.ink,
        ),
      ),
      const Spacer(),
      Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Brand.surface,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.notifications_none_rounded,
          size: 21,
          color: Brand.ink,
        ),
      ),
    ],
  );
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.channels, required this.onTap});

  final int channels;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Brand.blue,
    borderRadius: BorderRadius.circular(Insets.radiusCard),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Insets.radiusCard),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '광고 등록하기',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    channels == 0
                        ? '플랫폼을 연동하면 한 번에 올릴 수 있어요'
                        : '한 번 입력하면 $channels개 채널에 한 번에',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.24),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.labels,
    required this.index,
    required this.delta,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final int delta;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 8) / labels.length;
      return SizedBox(
        height: 48,
        child: Stack(
          children: [
            // The dark pill slides between tabs rather than cutting, so the
            // list swap underneath reads as the same surface changing.
            AnimatedPositioned(
              duration: Motion.base,
              curve: Motion.enter,
              left: index * (width + 8),
              width: width,
              top: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Brand.ink,
                  borderRadius: BorderRadius.circular(Insets.radiusField),
                ),
              ),
            ),
            Row(
              children: [
                for (final (i, label) in labels.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  SizedBox(
                    width: width,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedDefaultTextStyle(
                              duration: Motion.base,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: i == index
                                    ? Colors.white
                                    : Brand.inkMuted,
                              ),
                              child: Text(label),
                            ),
                            if (i == 0 && delta != 0) ...[
                              const SizedBox(width: 6),
                              const _DeltaBadge(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// The red "-1" that pops next to 나의 광고 when a listing leaves by itself.
class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge();

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    duration: Motion.slow,
    curve: Motion.settle,
    tween: Tween(begin: 0, end: 1),
    builder: (context, t, child) =>
        Transform.scale(scale: 0.4 + 0.6 * t, child: child),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Brand.danger,
        borderRadius: BorderRadius.circular(Insets.radiusPill),
      ),
      child: const Text(
        '-1',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _AutoClosedBanner extends StatelessWidget {
  const _AutoClosedBanner({required this.title, required this.onDismiss});

  final String title;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => FadeSlideIn(
    offset: -10,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brand.dangerTint,
          borderRadius: BorderRadius.circular(Insets.radiusField),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.trending_down_rounded,
              size: 16,
              color: Brand.danger,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '다른 중개사가 계약한 매물 1건이 리스트에서 자동으로 내려갔어요. ($title)',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Brand.danger,
                ),
              ),
            ),
            GestureDetector(
              onTap: onDismiss,
              child: const Icon(
                Icons.close_rounded,
                size: 17,
                color: Brand.danger,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final closed = listing.status == ListingStatus.closed;
    return Material(
      color: Brand.surface,
      borderRadius: BorderRadius.circular(Insets.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Insets.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: _Thumbnail(paths: listing.photoPaths),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusChip(
                          closed
                              ? (listing.closedReason?.label ?? '성사됨')
                              : '광고중',
                          color: closed ? Brand.inkMuted : Brand.blue,
                        ),
                        const SizedBox(width: 8),
                        Text(_date(listing.createdAt), style: Type.caption),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      listing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.title.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      listing.priceLine,
                      style: Type.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (listing.channels.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final platform in listing.channels.keys)
                            PlatformChip(platform),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _date(DateTime value) => '${value.month}월 ${value.day}일 등록';
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    for (final path in paths) {
      final file = File(path);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            // A picked photo can be gone by the next launch (cache eviction,
            // the user deleting it); the hatched box is the honest fallback.
            errorBuilder: (_, _, _) => const PhotoPlaceholder(),
          ),
        );
      }
    }
    return const PhotoPlaceholder();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.tab});

  final int tab;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 46),
    alignment: Alignment.center,
    child: Column(
      children: [
        Text(
          tab == 0 ? '아직 올린 광고가 없어요' : '아직 성사된 광고가 없어요',
          style: Type.body.copyWith(
            color: Brand.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tab == 0 ? '위의 광고 등록하기로 첫 매물을 올려보세요.' : '거래가 완료되면 여기로 옮겨드려요.',
          style: Type.caption,
        ),
      ],
    ),
  );
}

class _TestPanel extends StatelessWidget {
  const _TestPanel({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Insets.radiusCard),
      border: Border.all(color: Brand.hairline, style: BorderStyle.solid),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('테스트용', style: Type.caption),
        const SizedBox(height: 10),
        BrandButton(
          '남이 계약했다고 알림 받기',
          kind: BrandButtonKind.outlined,
          onPressed: enabled ? onTap : null,
        ),
      ],
    ),
  );
}
