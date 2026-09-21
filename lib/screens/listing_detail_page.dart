import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../android_layout.dart';
import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../fields.dart';
import '../models/listing.dart';
import 'home_page.dart' show stateColor;
import 'listing_form_page.dart';
import 'takedown_flow_page.dart';

/// 102 매물상세 — the record, each platform's state, and the way out
/// ("광고를 종료할래요" → 301).
class ListingDetailPage extends StatefulWidget {
  const ListingDetailPage({
    super.key,
    required this.store,
    required this.listingId,
    this.guarded = guardLiveAds,
  });

  final AppStore store;
  final String listingId;

  /// 광고 종료로 가는 길을 닫아 둘 것인가 ([guardLiveAds]).
  final bool guarded;

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

  void _edit(Listing listing) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ListingFormPage(store: widget.store, initial: listing),
    ),
  );

  Future<void> _end(Listing listing) async {
    // 빗장이 걸려 있으면 버튼도 없지만, 여기로 오는 다른 길이 생기더라도 닫혀 있게 둔다.
    if (widget.guarded) return;
    final picked = await showModalBottomSheet<Set<ListingPlatform>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColor.bgSurface,
      barrierColor: AppColor.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.r24)),
      ),
      builder: (_) => TakedownSheet(channels: listing.liveChannels),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TakedownFlowPage(
          store: widget.store,
          listing: listing,
          channels: livePlatforms.where(picked.contains).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.store.byId(widget.listingId);
    if (listing == null) {
      return const Scaffold(
        backgroundColor: AppColor.bgPage,
        appBar: BackTitleBar(title: '매물 상세'),
        body: Center(child: Text('삭제된 매물이에요', style: AppText.bodySmall)),
      );
    }
    final canEnd = listing.liveChannels.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColor.bgPage,
      appBar: BackTitleBar(
        title: '매물 상세',
        actions: [
          if (listing.status == ListingStatus.advertising)
            BarAction('수정', onPressed: () => _edit(listing)),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero + androidBottomInset(context),
        children: [
          SizedBox(height: 260, child: _Gallery(paths: listing.photoPaths)),
          Transform.translate(
            offset: const Offset(0, -Space.s24),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColor.bgSurface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(Radii.r24),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.s24,
                Space.gutter,
                Space.s32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    listing.fullName,
                    style: AppText.title.copyWith(color: AppColor.textBrand),
                  ),
                  const SizedBox(height: Space.s4),
                  Text(listing.priceLine, style: AppText.bodySmall),
                  const SizedBox(height: Space.s24),
                  const Text('광고 상태', style: AppText.title),
                  const SizedBox(height: Space.s12),
                  _AdStateCard(listing: listing),
                  for (final section in _sections(listing.values)) ...[
                    const SectionRule(),
                    Text(section.title, style: AppText.title),
                    const SizedBox(height: Space.s12),
                    _InfoCard(rows: section.rows),
                  ],
                  if (canEnd) ...[
                    const SizedBox(height: Space.s24),
                    if (widget.guarded)
                      // 빗장을 말없이 걸면 「버튼이 사라졌다」가 된다. 왜 없는지 적어 둔다.
                      const Text(
                        '광고 종료는 지금 잠겨 있어요 — 실제 계정으로 폼 입력을 확인하는 중입니다.',
                        style: AppText.caption,
                      )
                    else
                      BrandButton(
                        '광고를 종료할래요',
                        kind: BrandButtonKind.outlined,
                        foreground: AppColor.statusError,
                        onPressed: () => _end(listing),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Gallery extends StatefulWidget {
  const _Gallery({required this.paths});

  final List<String> paths;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final files = widget.paths
        .map(File.new)
        .where((file) => file.existsSync())
        .toList();
    final count = files.isEmpty ? 1 : files.length;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (files.isEmpty)
          const PhotoPlaceholder(radius: 0, cell: 24)
        else
          PageView(
            onPageChanged: (page) => setState(() => _page = page),
            children: [
              for (final file in files)
                Image.file(
                  file,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const PhotoPlaceholder(radius: 0, cell: 24),
                ),
            ],
          ),
        Positioned(
          top: Space.s12,
          right: Space.s12,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColor.bgSurface.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              size: 18,
              color: AppColor.iconBrand,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: Space.s32 + Space.s4,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < count.clamp(1, 8); i++)
                AnimatedContainer(
                  duration: Motion.quick,
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page
                        ? AppColor.textSecondary
                        : AppColor.indicatorInactive.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 광고 상태 — one row per platform with its state colour.
class _AdStateCard extends StatelessWidget {
  const _AdStateCard({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) => _Card(
    children: [
      // 잠시 내려 둔 플랫폼의 광고 상태는 보여 줄 것이 없다
      for (final platform in livePlatforms)
        _AdStateRow(
          platform: platform,
          state: listing.channels[platform] ?? ChannelState.pending,
          date: listing.channelDates[platform],
        ),
    ],
  );
}

class _AdStateRow extends StatelessWidget {
  const _AdStateRow({
    required this.platform,
    required this.state,
    required this.date,
  });

  final ListingPlatform platform;
  final ChannelState state;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final color = stateColor(state);
    final dateLabel = switch (state) {
      ChannelState.published when date != null => '등록일 ${formatDate(date!)}',
      ChannelState.removed when date != null => '종료일 ${formatDate(date!)}',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(platform.label, style: AppText.bodyStrong),
                if (dateLabel != null) Text(dateLabel, style: AppText.caption),
              ],
            ),
          ),
          Text(
            state.statusLabel,
            style: AppText.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: Space.s4),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ],
      ),
    );
  }
}

String formatDate(DateTime date) =>
    '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

/// A bordered card whose children are separated by hairlines.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.s16),
    decoration: BoxDecoration(
      color: AppColor.bgSurface,
      borderRadius: BorderRadius.circular(Radii.r16),
      border: Border.all(color: AppColor.borderSubtle),
    ),
    child: Column(
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0) const Divider(height: 1, color: AppColor.borderFaint),
          child,
        ],
      ],
    ),
  );
}

/// One info row: one or two label/value cells.
typedef _Cell = ({String label, String value, bool copy, bool plain});

_Cell _cell(
  String label,
  String value, {
  bool copy = false,
  bool plain = false,
}) => (label: label, value: value, copy: copy, plain: plain);

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<List<_Cell>> rows;

  @override
  Widget build(BuildContext context) => _Card(
    children: [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, cell) in row.indexed) ...[
                if (index > 0) const SizedBox(width: Space.s12),
                Expanded(child: _InfoCell(cell)),
              ],
            ],
          ),
        ),
    ],
  );
}

class _InfoCell extends StatelessWidget {
  const _InfoCell(this.cell);

  final _Cell cell;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(cell.label, style: AppText.caption),
      const SizedBox(height: 2),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cell.copy)
            // A phone number reads wrong once it wraps; shrink it instead.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(cell.value, style: AppText.bodyStrong),
              ),
            )
          else
            Expanded(
              child: Text(
                cell.value,
                style: cell.plain ? AppText.body : AppText.bodyStrong,
              ),
            ),
          if (cell.copy && cell.value != '-')
            IconButton(
              tooltip: '연락처 복사',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: cell.value));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('연락처를 복사했어요')));
              },
              icon: const Icon(
                Icons.copy_rounded,
                size: 16,
                color: AppColor.iconSecondary,
              ),
            ),
        ],
      ),
    ],
  );
}

typedef _Section = ({String title, List<List<_Cell>> rows});

List<_Section> _sections(Map<String, dynamic> v) {
  String at(String key, {String suffix = ''}) {
    final raw = v[key];
    if (raw == null) return '-';
    if (raw is List) {
      return raw.isEmpty ? '-' : raw.map((e) => optionLabel('$e')).join(', ');
    }
    final text = '$raw'.trim();
    return text.isEmpty ? '-' : '$text$suffix';
  }

  final floor = at('floor');
  final floorAll = at('floorAll');
  final appliances = List<String>.from(v['appliances'] as List? ?? const []);
  final trade = '${v['trade'] ?? ''}';
  final fee = v['noManagementFee'] == true;
  final parking = v['parking'] == '주차 불가능';

  return [
    (
      title: '기본 정보',
      rows: [
        [_cell('주소', at('address'))],
        [
          _cell(
            '동, 호수',
            [
              v['singleBuilding'] == true ? '단일동' : at('building', suffix: '동'),
              at('unit', suffix: '호'),
            ].where((p) => p != '-').join(' ').ifEmpty('-'),
          ),
          _cell('건축물 법정 용도', at('buildingUse')),
        ],
        [
          _cell('매물 종류', at('propertyType')),
          _cell('사용승인일', at('approvalDate')),
        ],
        [
          _cell('총 세대수', at(HifiField.householdCount)),
          _cell('위반건축물 해당 여부', at('violation')),
        ],
      ],
    ),
    (
      title: '거래 및 가격 정보',
      rows: [
        if (trade == '매매')
          [_cell('거래 유형', '매매'), _cell('매매 금액', at('salePrice', suffix: '만원'))]
        else
          [
            _cell('보증금', at('deposit', suffix: '만원')),
            trade == '월세'
                ? _cell('월세', at('monthlyRent', suffix: '만원'))
                : _cell('거래 유형', trade.ifEmpty('-')),
          ],
        [
          _cell(
            '융자금',
            v['loan'] == '없음' ? '없음' : at('loanAmount', suffix: '만원'),
          ),
          _cell(
            '입주가능일',
            v['moveInType'] == '날짜 지정' ? at('moveInDate') : at('moveInType'),
          ),
        ],
        [_cell('입주가능일 추가 설명', at(HifiField.moveInNote), plain: true)],
        [
          _cell('전자계약 가능 여부', at(HifiField.eContract)),
          _cell('LH 전세임대 여부', at('lh')),
        ],
        if (v['shortTerm'] == true) [_cell('단기 매물', '가능')],
      ],
    ),
    (
      title: '공간 및 건물 구조',
      rows: [
        [
          _cell('전용면적', at('exclusiveArea', suffix: ' m²')),
          _cell('공급면적', at('supplyArea', suffix: ' m²')),
        ],
        [
          _cell(
            '층 수',
            floor == '-' && floorAll == '-'
                ? '-'
                : '$floor/${floorAll == '-' ? '-' : '$floorAll층'}'
                      '${v['floorPrivate'] == true ? ' (비공개)' : ''}',
          ),
          _cell('층군 구분', at(HifiField.floorBand)),
        ],
        [
          _cell(
            '방 수 및 원룸 구조',
            [
              at('rooms', suffix: '개'),
              at(HifiField.structure),
            ].where((p) => p != '-').join(', ').ifEmpty('-'),
          ),
          _cell('복층 여부', at(HifiField.duplex)),
        ],
        [
          _cell('욕실 수', at('bathrooms', suffix: '개')),
          _cell('주실 방향', at('direction')),
        ],
        [_cell('현관 구조 유형', at(HifiField.entranceType))],
      ],
    ),
    (
      title: '관리비',
      rows: fee
          ? [
              [_cell('부과 방식', '관리비 없음')],
            ]
          : [
              [
                _cell('부과 방식', at('manageMethod')),
                _cell('기본 금액', at('managementFee', suffix: ' 만원')),
              ],
              [_cell('부과 기준', at('manageBasis'))],
              [_cell('포함 목록', at('manageIncludes'))],
            ],
    ),
    (
      title: '시설 및 옵션',
      rows: [
        [
          _cell(
            '주차 가능 및 대 수',
            parking ? '불가' : at('parkingCount', suffix: ' 대'),
          ),
          _cell(
            '월 주차비',
            parking ? '-' : at(HifiField.monthlyParkingFee, suffix: ' 만원'),
          ),
        ],
        [_cell('엘리베이터 유무', at('elevator')), _cell('반려동물 허용', at('petAllowed'))],
        [_cell('전세자금대출 가능 여부', at('loanAvailable'))],
        [
          _cell(
            '기본 가전 옵션',
            appliances
                .where(homeApplianceOptions.contains)
                .join(', ')
                .ifEmpty('-'),
          ),
        ],
        [
          _cell(
            '가구 및 수납 옵션',
            appliances.where(furnitureOptions.contains).join(', ').ifEmpty('-'),
          ),
        ],
        [
          _cell(
            '보안 및 부대시설',
            List<String>.from(v['facilities'] as List? ?? const [])
                .where((item) => item != evChargerFacility)
                .map(optionLabel)
                .join(', ')
                .ifEmpty('-'),
          ),
        ],
        [
          _cell('난방 방식', at('heating')),
          _cell('전기차 충전 설비', at(HifiField.evCharger)),
        ],
      ],
    ),
    (
      title: '의뢰인 정보',
      rows: [
        [
          _cell('임대인 성함', at(HifiField.ownerName)),
          _cell('연락처', at('ownerPhone'), copy: true),
        ],
        [_cell('중개 수임 경로', at(HifiField.brokerageRoute))],
        [_cell('내부 비밀 메모', at('privateMemo'), plain: true)],
      ],
    ),
    if ('${v['title'] ?? ''}'.isNotEmpty ||
        '${v['description'] ?? ''}'.isNotEmpty)
      (
        title: '광고 문구',
        rows: [
          [_cell('매물 제목', at('title'))],
          [_cell('매물 상세 설명', at('description'), plain: true)],
          if ((v[HifiField.tags] as List?)?.isNotEmpty ?? false)
            [_cell('관심 태그', at(HifiField.tags))],
        ],
      ),
  ];
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// 301/302 "어느 플랫폼에서 내릴까요?"
class TakedownSheet extends StatefulWidget {
  const TakedownSheet({super.key, required this.channels});

  final List<ListingPlatform> channels;

  @override
  State<TakedownSheet> createState() => _TakedownSheetState();
}

class _TakedownSheetState extends State<TakedownSheet> {
  final _picked = <ListingPlatform>{};

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.s12,
        Space.gutter,
        Space.s8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColor.borderDefault,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: Space.s24),
          const Text('어느 플랫폼에서 내릴까요?', style: AppText.title),
          const SizedBox(height: Space.s4),
          const Text('선택한 플랫폼에서만 광고가 내려갑니다.', style: AppText.bodySmall),
          const SizedBox(height: Space.s16),
          for (final platform in widget.channels)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s8),
              child: SelectCard(
                platform: platform,
                selected: _picked.contains(platform),
                onTap: () => setState(() {
                  if (!_picked.remove(platform)) _picked.add(platform);
                }),
              ),
            ),
          const SizedBox(height: Space.s12),
          BrandButton(
            _picked.isEmpty ? '플랫폼을 선택해주세요' : '광고 종료하기',
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.pop(context, Set.of(_picked)),
          ),
          BrandButton(
            '취소',
            kind: BrandButtonKind.text,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    ),
  );
}
