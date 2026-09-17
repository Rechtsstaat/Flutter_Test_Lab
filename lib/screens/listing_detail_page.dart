import 'dart:io';

import 'package:flutter/material.dart';

import '../android_layout.dart';
import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../fields.dart';
import '../models/listing.dart';
import 'listing_form_page.dart';
import 'takedown_flow_page.dart';

/// 102 매물 상세.
///
/// Two 확정 notes shape the bottom of this screen. 삭제 is split into 거래 완료 and
/// 광고 종료 so the two stop sharing a word, and the pair is no longer pinned to
/// the viewport — ending an ad is not the errand the agent opened this screen
/// for, so it sits at the end of the record rather than over it.
class ListingDetailPage extends StatefulWidget {
  const ListingDetailPage({
    super.key,
    required this.store,
    required this.listingId,
  });

  final AppStore store;
  final String listingId;

  @override
  State<ListingDetailPage> createState() => _ListingDetailPageState();
}

class _ListingDetailPageState extends State<ListingDetailPage> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _edit(Listing listing) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListingFormPage(store: widget.store, initial: listing),
      ),
    );
  }

  Future<void> _end(Listing listing, ClosedReason reason) async {
    final channels = await showModalBottomSheet<Set<ListingPlatform>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ChannelPickSheet(
        reason: reason,
        channels: listing.channels.keys.toList(),
      ),
    );
    if (channels == null || channels.isEmpty || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TakedownFlowPage(
          store: widget.store,
          listing: listing,
          reason: reason,
          channels: ListingPlatform.values.where(channels.contains).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.store.byId(widget.listingId);
    if (listing == null) {
      return const Scaffold(
        backgroundColor: Brand.canvas,
        body: Center(child: Text('삭제된 매물이에요', style: Type.bodyMuted)),
      );
    }
    final closed = listing.status == ListingStatus.closed;

    return Scaffold(
      backgroundColor: Brand.canvas,
      appBar: AppBar(
        backgroundColor: Brand.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.chevron_left_rounded,
            size: 30,
            color: Brand.ink,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('매물 상세', style: Type.title),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: ListView(
        padding: EdgeInsets.zero + androidBottomInset(context),
        children: [
          SizedBox(height: 240, child: _Gallery(paths: listing.photoPaths)),
          Transform.translate(
            offset: const Offset(0, -18),
            child: Container(
              decoration: const BoxDecoration(
                color: Brand.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(
                Insets.gutter,
                22,
                Insets.gutter,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusChip(
                    closed ? (listing.closedReason?.label ?? '성사됨') : '광고중',
                    color: closed ? Brand.inkMuted : Brand.blue,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    listing.title,
                    style: Type.display.copyWith(fontSize: 21),
                  ),
                  const SizedBox(height: 6),
                  Text(listing.priceLine, style: Type.price),
                  const SizedBox(height: 8),
                  Text(
                    [
                      listing.address,
                      if ('${listing.values['unit'] ?? ''}'.isNotEmpty)
                        '${listing.values['unit']}',
                    ].where((part) => part.isNotEmpty).join(', '),
                    style: Type.bodyMuted,
                  ),
                  const SizedBox(height: 22),
                  _SpecGrid(values: listing.values),
                  if ('${listing.values['description'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text(
                      '${listing.values['description']}',
                      style: Type.body.copyWith(color: Brand.inkMuted),
                    ),
                  ],
                  const SizedBox(height: 26),
                  const SectionLabel('광고 중인 채널'),
                  for (final entry in listing.channels.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ChannelStatusRow(
                        platform: entry.key,
                        state: entry.value,
                      ),
                    ),
                  const SizedBox(height: 28),
                  if (!closed) ...[
                    BrandButton(
                      '수정',
                      kind: BrandButtonKind.outlined,
                      onPressed: () => _edit(listing),
                    ),
                    const SizedBox(height: 10),
                    BrandButton(
                      '거래 완료',
                      onPressed: () => _end(listing, ClosedReason.dealDone),
                    ),
                    const SizedBox(height: 4),
                    // 광고 종료 is deliberately the quietest control here: the
                    // note asks for it not to read as a positive outcome.
                    BrandButton(
                      '광고 종료',
                      kind: BrandButtonKind.quiet,
                      onPressed: () => _end(listing, ClosedReason.adEnded),
                    ),
                  ] else
                    Center(
                      child: Text(
                        '${listing.closedReason?.label ?? '성사'}로 내려간 광고예요.',
                        style: Type.caption,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final files = paths
        .map(File.new)
        .where((file) => file.existsSync())
        .toList();
    if (files.isEmpty) {
      return PhotoPlaceholder(label: '매물 사진 (${paths.length}장)', radius: 0);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView(
          children: [
            for (final file in files)
              Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const PhotoPlaceholder(radius: 0),
              ),
          ],
        ),
        Positioned(
          right: 14,
          bottom: 30,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Brand.ink.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(Insets.radiusPill),
            ),
            child: Text(
              '사진 ${files.length}장',
              style: const TextStyle(color: Colors.white, fontSize: 11.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// The six-cell table the lo-fi puts under the price.
class _SpecGrid extends StatelessWidget {
  const _SpecGrid({required this.values});

  final Map<String, dynamic> values;

  @override
  Widget build(BuildContext context) {
    String at(String key, {String suffix = ''}) {
      final raw = '${values[key] ?? ''}'.trim();
      return raw.isEmpty ? '-' : '$raw$suffix';
    }

    final cells = <(String, String)>[
      ('전용면적', at('exclusiveArea', suffix: 'm²')),
      (
        '층수',
        values['floor'] == null && values['floorAll'] == null
            ? '-'
            : '${at('floor', suffix: '층')} / ${at('floorAll', suffix: '층')}',
      ),
      ('방/욕실', '${at('rooms', suffix: '개')} / ${at('bathrooms', suffix: '개')}'),
      (
        '관리비',
        values['noManagementFee'] == true
            ? '없음'
            : at('managementFee', suffix: '만원'),
      ),
      (
        '입주가능',
        values['moveInType'] == '날짜 지정' ? at('moveInDate') : at('moveInType'),
      ),
      ('주차', at('parking')),
    ];

    return Column(
      children: [
        for (var row = 0; row < cells.length; row += 2)
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: row + 2 < cells.length
                    ? const BorderSide(color: Brand.hairline)
                    : BorderSide.none,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var column = 0; column < 2; column++)
                  if (row + column < cells.length)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cells[row + column].$1, style: Type.caption),
                          const SizedBox(height: 4),
                          Text(
                            cells[row + column].$2,
                            style: Type.body.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChannelStatusRow extends StatelessWidget {
  const _ChannelStatusRow({required this.platform, required this.state});

  final ListingPlatform platform;
  final ChannelState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      ChannelState.published => ('노출중', Brand.blue),
      ChannelState.removed => ('내려감', Brand.inkFaint),
      ChannelState.failed => ('확인 필요', Brand.danger),
      _ => ('대기 중', Brand.inkFaint),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(Insets.radiusField),
        border: Border.all(color: Brand.hairline),
      ),
      child: Row(
        children: [
          PlatformBadge(
            platform,
            size: 30,
            dimmed: state == ChannelState.removed,
          ),
          const SizedBox(width: 12),
          Text(
            platform.label,
            style: Type.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 301's opening question — "어느 채널에서 내릴까요?"
class _ChannelPickSheet extends StatefulWidget {
  const _ChannelPickSheet({required this.reason, required this.channels});

  final ClosedReason reason;
  final List<ListingPlatform> channels;

  @override
  State<_ChannelPickSheet> createState() => _ChannelPickSheetState();
}

class _ChannelPickSheetState extends State<_ChannelPickSheet> {
  final _picked = <ListingPlatform>{};

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Brand.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    padding: const EdgeInsets.fromLTRB(Insets.gutter, 24, Insets.gutter, 16),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('어느 채널에서 내릴까요?', style: Type.display),
          const SizedBox(height: 8),
          Text(
            widget.reason == ClosedReason.dealDone
                ? '거래가 끝난 채널을 선택해 주세요.'
                : '선택한 채널에서만 광고가 내려갑니다.',
            style: Type.bodyMuted,
          ),
          const SizedBox(height: 20),
          for (final platform in widget.channels)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => setState(() {
                  if (!_picked.remove(platform)) _picked.add(platform);
                }),
                child: AnimatedContainer(
                  duration: Motion.quick,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: _picked.contains(platform)
                        ? Brand.blueFaint
                        : Brand.surface,
                    borderRadius: BorderRadius.circular(Insets.radiusCard),
                    border: Border.all(
                      color: _picked.contains(platform)
                          ? Brand.blue
                          : Brand.hairline,
                      width: _picked.contains(platform) ? 1.4 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      PlatformBadge(platform, size: 36),
                      const SizedBox(width: 14),
                      Text(platform.label, style: Type.title),
                      const Spacer(),
                      AnimatedScale(
                        duration: Motion.quick,
                        curve: Motion.settle,
                        scale: _picked.contains(platform) ? 1 : 0.86,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _picked.contains(platform)
                                ? Brand.blue
                                : const Color(0xfff0f1f3),
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: _picked.contains(platform)
                                ? Colors.white
                                : const Color(0xffd3d6da),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          BrandButton(
            _picked.isEmpty ? '채널을 선택해 주세요' : '${_picked.length}개 채널에서 내리기',
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.pop(context, _picked),
          ),
          BrandButton(
            '취소',
            kind: BrandButtonKind.quiet,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    ),
  );
}
