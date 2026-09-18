import 'dart:io';

import 'package:flutter/material.dart';

import '../android_layout.dart';
import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../fields.dart';
import '../mirror_session.dart';
import '../models/listing.dart';
import 'listing_detail_page.dart';
import 'listing_form_page.dart';
import 'onboarding_flow.dart';

/// 101 홈 — manage every listing's state and start a new one.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});

  final AppStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// null is 전체.
  ListingPlatform? _filter;

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

  void _register() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ListingFormPage(store: widget.store),
    ),
  );

  /// 로그아웃 — 연동 상태(앱)와 플랫폼 로그인(웹뷰) 둘 다 지워야 다음 연동이
  /// 진짜 처음부터 돈다. 하나만 지우면 0011 을 지나면서도 플랫폼은 이미
  /// 로그인된 화면을 띄워, 로그인 갈래를 시험할 수가 없다.
  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColor.bgSurface,
        title: const Text('로그아웃할까요?', style: AppText.title),
        content: const Text(
          '연결한 플랫폼이 모두 해제되고, 웹뷰에 남은 로그인도 지워져요.\n'
          '등록한 매물 기록은 그대로 남아요.',
          style: AppText.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColor.statusError),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 쿠키를 못 지워도 연동 해제는 한다 — 로그아웃이 반쯤 되다 마는 것이 제일
    // 나쁘다. 대신 다음 로그인이 건너뛰어질 수 있다고 말해 준다.
    String? failure;
    try {
      await clearPlatformSessions();
    } catch (error) {
      failure = '$error';
    }
    await widget.store.signOut();
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('웹뷰에 남은 로그인을 지우지 못했어요 ($failure)')),
      );
    }
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder<void>(
        transitionDuration: Motion.base,
        pageBuilder: (_, _, _) => OnboardingFlow(store: widget.store),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
      (route) => false,
    );
  }

  void _open(Listing listing) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          ListingDetailPage(store: widget.store, listingId: listing.id),
    ),
  );

  bool _matches(Listing listing) =>
      _filter == null || listing.channels.containsKey(_filter);

  @override
  Widget build(BuildContext context) {
    final live = widget.store.advertising.where(_matches).toList();
    final ended = widget.store.closed.where(_matches).toList();

    return Scaffold(
      backgroundColor: AppColor.bgPage,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding:
              const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.s16,
                Space.gutter,
                Space.s32,
              ) +
              androidBottomInset(context),
          children: [
            Row(
              children: [
                const HanbangLogo(size: 24),
                const SizedBox(width: Space.s8),
                const Text('한방', style: AppText.bodyStrong),
                const Spacer(),
                BarAction('로그아웃', onPressed: _signOut),
              ],
            ),
            const SizedBox(height: Space.s24),
            const Text('매물 광고를 한 번에', style: AppText.title),
            const SizedBox(height: Space.s16),
            _LinkedBanner(linked: widget.store.linked, onRegister: _register),
            const SizedBox(height: Space.s24),
            const Text('진행 중', style: AppText.title),
            const SizedBox(height: Space.s4),
            const Text('매물 광고 등록 상태를 한곳에서 확인하세요.', style: AppText.caption),
            const SizedBox(height: Space.s16),
            _FilterChips(
              selected: _filter,
              onChanged: (platform) => setState(() => _filter = platform),
            ),
            const SizedBox(height: Space.s16),
            if (live.isEmpty)
              _EmptyState(filtered: _filter != null)
            else
              for (final (index, listing) in live.indexed)
                FadeSlideIn(
                  key: ValueKey('live-${listing.id}'),
                  delay: Duration(milliseconds: 30 * index),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Space.s12),
                    child: ListingCard(
                      listing: listing,
                      onTap: () => _open(listing),
                    ),
                  ),
                ),
            if (ended.isNotEmpty) ...[
              const SizedBox(height: Space.s16),
              Text('종료된 광고 ${ended.length}', style: AppText.label),
              const SizedBox(height: Space.s12),
              for (final listing in ended)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s12),
                  child: ListingCard(
                    listing: listing,
                    onTap: () => _open(listing),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinkedBanner extends StatelessWidget {
  const _LinkedBanner({required this.linked, required this.onRegister});

  final Set<ListingPlatform> linked;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final names = livePlatforms
        .where(linked.contains)
        .map((platform) => platform.label)
        .join('·');
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.s16,
        Space.s16,
        Space.s12,
        Space.s16,
      ),
      decoration: BoxDecoration(
        color: AppColor.actionPrimary,
        borderRadius: BorderRadius.circular(Radii.r16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              names.isEmpty ? '연결된 플랫폼이 없어요' : '$names에\n연결되어있어요',
              style: AppText.bodySmall.copyWith(
                color: AppColor.textOnColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Material(
            color: AppColor.bgSurface,
            borderRadius: BorderRadius.circular(Radii.r8),
            child: InkWell(
              onTap: onRegister,
              borderRadius: BorderRadius.circular(Radii.r8),
              child: const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: Space.s12,
                  vertical: Space.s8,
                ),
                child: Text(
                  '+ 새 광고',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColor.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onChanged});

  final ListingPlatform? selected;
  final ValueChanged<ListingPlatform?> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.s8,
    children: [
      for (final platform in <ListingPlatform?>[null, ...livePlatforms])
        _FilterChip(
          label: platform?.label ?? '전체',
          selected: selected == platform,
          onTap: () => onChanged(platform),
        ),
    ],
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.quick,
        height: 36,
        constraints: const BoxConstraints(minWidth: 52),
        padding: const EdgeInsets.symmetric(horizontal: Space.s12),
        decoration: BoxDecoration(
          color: selected ? AppColor.bgBrandSubtle : AppColor.bgSurface,
          borderRadius: BorderRadius.circular(Radii.r24),
          border: Border.all(
            color: selected ? AppColor.borderFocus : AppColor.borderSubtle,
          ),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: AppText.bodySmall.copyWith(
              color: selected ? AppColor.textPrimary : AppColor.textTertiary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    ),
  );
}

/// A listing on 101: thumbnail, address, price and facts, then one status per
/// platform.
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColor.bgSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.r16),
      side: const BorderSide(color: AppColor.borderSubtle),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Space.s16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: _Thumbnail(paths: listing.photoPaths),
                ),
                const SizedBox(width: Space.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listing.headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong,
                      ),
                      Text(
                        listing.priceLine,
                        style: AppText.bodySmall.copyWith(
                          color: AppColor.textBrand,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(listing.factLine, style: AppText.caption),
                    ],
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.s12),
              child: Divider(height: 1, color: AppColor.borderSubtle),
            ),
            PlatformStatusLine(channels: listing.channels),
          ],
        ),
      ),
    ),
  );
}

/// "직방 광고 중 ● | 다방 광고 중 ● | 당근 미등록 ●"
class PlatformStatusLine extends StatelessWidget {
  const PlatformStatusLine({super.key, required this.channels});

  final Map<ListingPlatform, ChannelState> channels;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (index, platform) in livePlatforms.indexed) ...[
        if (index > 0)
          Container(
            width: 1,
            height: 10,
            margin: const EdgeInsets.symmetric(horizontal: Space.s8),
            color: AppColor.borderDefault,
          ),
        Flexible(
          child: _PlatformStatus(
            platform: platform,
            state: channels[platform] ?? ChannelState.pending,
          ),
        ),
      ],
    ],
  );
}

class _PlatformStatus extends StatelessWidget {
  const _PlatformStatus({required this.platform, required this.state});

  final ListingPlatform platform;
  final ChannelState state;

  @override
  Widget build(BuildContext context) {
    final color = stateColor(state);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          platform.label,
          style: AppText.caption.copyWith(color: AppColor.textSecondary),
        ),
        const SizedBox(width: Space.s4),
        Flexible(
          child: Text(
            state.statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 3),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ],
    );
  }
}

/// The overview frame's state colours.
Color stateColor(ChannelState state) => switch (state) {
  ChannelState.published => AppColor.statusSuccess,
  ChannelState.working => AppColor.actionPrimary,
  ChannelState.needsCheck => AppColor.statusWarning,
  ChannelState.failed => AppColor.statusError,
  ChannelState.pending || ChannelState.removed => AppColor.textDisabled,
};

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    for (final path in paths) {
      final file = File(path);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(Radii.r8),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            cacheWidth: 192,
            // A picked photo can be gone by the next launch; the checkerboard
            // is the honest fallback.
            errorBuilder: (_, _, _) => const PhotoPlaceholder(cell: 8),
          ),
        );
      }
    }
    return const PhotoPlaceholder(cell: 8);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: Space.s40),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColor.bgSurface,
      borderRadius: BorderRadius.circular(Radii.r16),
      border: Border.all(color: AppColor.borderSubtle),
    ),
    child: Column(
      children: [
        Text(
          filtered ? '이 플랫폼에 올린 광고가 없어요' : '아직 올린 광고가 없어요',
          style: AppText.bodyStrong.copyWith(color: AppColor.textTertiary),
        ),
        const SizedBox(height: Space.s4),
        const Text('+ 새 광고로 첫 매물을 올려보세요.', style: AppText.caption),
      ],
    ),
  );
}
