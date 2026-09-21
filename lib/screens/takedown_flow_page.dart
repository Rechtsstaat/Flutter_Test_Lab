import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../fields.dart';
import '../mirror_session.dart';
import '../models/listing.dart';
import 'home_page.dart';
import 'listing_detail_page.dart' show formatDate;

/// 3021 광고 종료-웹뷰 → 303 광고 종료 완료.
///
/// Each picked platform's listing management page opens in turn inside 한방's
/// chrome. The agent presses the platform's own 종료 button there; hearing
/// that press moves on to the next platform. Leaving a page without pressing
/// keeps that platform live.
///
/// ## 어느 카드가 그 매물인가
///
/// 광고 목록에는 이 중개사의 매물이 통째로 걸려 있고(미러 실측 2026-09-21: 직방
/// 광고 중 45건, 다방 광고 진행 119건), 같은 글자의 종료 버튼이 그 수만큼 있다.
/// 그래서 이 화면은 목록을 열어 두기만 하지 않는다:
///
/// 1. 등록할 때 적어 둔 매물 번호([Listing.channelNumbers])로 그 카드를 찾아
///    화면 가운데로 올리고 테를 두른다.
/// 2. 번호가 없으면(예전 매물이거나 등록 직후에 못 읽었으면) 제목·주소·호·금액으로
///    목록에서 찾아내고, 찾아낸 번호는 저장소에 적어 둔다.
/// 3. **테가 둘린 카드 안에서 누른 종료만** 이 매물을 내린 것으로 센다. 옆 매물을
///    내린 누름을 이 매물의 종료로 적지 않기 위해서다.
///
/// 누르는 것은 끝까지 사람이다. 되돌릴 수 없는 누름을 한방이 대신하지 않는다.
class TakedownFlowPage extends StatefulWidget {
  const TakedownFlowPage({
    super.key,
    required this.store,
    required this.listing,
    required this.channels,
  });

  final AppStore store;
  final Listing listing;
  final List<ListingPlatform> channels;

  @override
  State<TakedownFlowPage> createState() => _TakedownFlowPageState();
}

class _TakedownFlowPageState extends State<TakedownFlowPage> {
  /// 잠시 내려 둔 플랫폼은 종료 흐름에도 들어오지 못한다 (publish 와 같은 이유).
  late final List<ListingPlatform> _channels = widget.channels
      .where((platform) => platform.isLive)
      .toList(growable: false);

  final _removed = <ListingPlatform>{};
  final _skipped = <ListingPlatform>{};
  final _pages = <ListingPlatform, MirrorListings>{};

  /// 플랫폼이 이 매물에 붙인 번호. 저장소에서 들고 오고, 목록에서 뒤늦게 읽어 내면
  /// 여기와 저장소 양쪽에 적는다.
  late final Map<ListingPlatform, String> _numbers = {
    ...widget.listing.channelNumbers,
  };

  int _index = 0;
  bool _done = false;

  /// Set while 303's 바로보기 has a page in front.
  ListingPlatform? _viewing;

  @override
  void initState() {
    super.initState();
    // 내릴 곳이 하나도 안 남았으면(전부 잠시 내려 둔 플랫폼이었으면) 곧바로 결과로 간다
    if (_channels.isEmpty) {
      _done = true;
      return;
    }
    _open(0);
  }

  @override
  void dispose() {
    for (final page in _pages.values) {
      page.dispose();
    }
    super.dispose();
  }

  void _open(int index) {
    final platform = _channels[index];
    final page = _pages[platform] = MirrorListings(
      platform: platform,
      values: widget.listing.values,
      number: _numbers[platform],
      mark: true,
    )..addListener(() => _onPage(platform));
    // 「광고 종료」를 누르면 플랫폼이 한 번 더 묻는다. 그 물음은 사람이 답한다.
    attachPlatformDialogs(page, () => context);
    _index = index;
  }

  void _onPage(ListingPlatform platform) {
    if (!mounted) return;
    final page = _pages[platform];
    if (page == null) return;
    // 목록에서 뒤늦게 번호를 읽어 냈다면 그대로 흘려보내지 않는다 — 다음 번에 이
    // 매물을 내릴 때는 처음부터 그 카드로 갈 수 있어야 한다.
    final number = page.number;
    if (number != null && _numbers[platform] != number) {
      _numbers[platform] = number;
      unawaited(widget.store.rememberNumber(widget.listing, platform, number));
    }
    if (page.pressedLabel != null && _removed.add(platform)) {
      _advance();
    } else {
      setState(() {});
    }
  }

  /// 지금 이 플랫폼에서 사람에게 할 말. 「무엇을 누를지」보다 「어느 것이 그 매물인지」를
  /// 먼저 말한다 — 목록에는 같은 글자의 종료 버튼이 매물 수만큼 있기 때문이다.
  (String, String?) _toastFor(ListingPlatform platform) {
    final page = _pages[platform];
    final number = page?.number ?? _numbers[platform];
    // 번호를 모르면 이름으로 부른다 — 사람이 목록에서 눈으로 찾을 때 쥘 것이 그것뿐이다.
    final what = number == null
        ? '「${widget.listing.headline}」'
        : '${platform.listingNumberLabel} $number';
    if (page == null || !page.loaded) {
      return ('${platform.label} 광고 목록을 여는 중이에요', null);
    }
    if (page.cardFound) {
      return (
        '$what 매물을 찾았어요',
        _press(platform),
      );
    }
    if (page.gaveUp) {
      // 목록에서 못 짚었다. 여기서는 울타리도 풀려 있으므로([MirrorListings.pressScope])
      // 사람이 제 손으로 찾아 누르면 그대로 들린다 — 무엇을 찾아야 하는지 말해 준다.
      return ('목록에서 이 매물을 찾지 못했어요', '$what 매물을 직접 찾아 종료해주세요');
    }
    return ('$what 매물을 찾는 중이에요', '잠시만 기다려주세요');
  }

  /// 무엇을 눌러야 정말 내려가는가.
  ///
  /// 직방은 카드의 「매물 종료하기」가 모달을 열 뿐이고, 광고를 내리는 것은 그 모달의
  /// 「네, 종료합니다」다([ListingPlatform.takedownConfirmLabels]). 첫 누름에서 손을
  /// 떼면 광고는 그대로 남는다 — 그러니 두 걸음을 **처음부터 함께** 말해 준다.
  String _press(ListingPlatform platform) {
    final first = '파란 테두리 카드의 「${platform.takedownLabels.first}」';
    final confirm = platform.takedownConfirmLabels.firstOrNull;
    return confirm == null
        ? '$first를 눌러주세요'
        : '$first를 누른 뒤, 창의 「$confirm」까지 눌러주세요';
  }

  Future<void> _advance() async {
    if (_index + 1 < _channels.length) {
      setState(() => _open(_index + 1));
      return;
    }
    if (_removed.isNotEmpty) {
      // 저장소에 있는 쪽을 닫는다. 흐름 도중에 읽어 낸 번호가 거기 적혀 있으므로,
      // 들고 들어온 옛 기록으로 닫으면 그 번호를 도로 지우게 된다.
      await widget.store.close(
        widget.store.byId(widget.listing.id) ?? widget.listing,
        reason: ClosedReason.adEnded,
        channels: _removed,
      );
    }
    if (mounted) setState(() => _done = true);
  }

  Future<void> _back() async {
    if (_done) {
      if (_viewing != null) {
        setState(() => _viewing = null);
      } else {
        _home();
      }
      return;
    }
    final page = _pages[_channels[_index]];
    if (await page?.closeOverlay() ?? false) return;
    if (!mounted) return;
    final skip = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColor.bgSurface,
        title: Text(
          '${_channels[_index].label} 광고를 그대로 둘까요?',
          style: AppText.title,
        ),
        content: const Text(
          '종료하기 버튼을 누르지 않으면 이 플랫폼의 광고는 계속 노출돼요.',
          style: AppText.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 종료하기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('그대로 두기'),
          ),
        ],
      ),
    );
    if (skip == true && mounted) {
      _skipped.add(_channels[_index]);
      await _advance();
    }
  }

  void _home() => Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => HomePage(store: widget.store)),
    (route) => false,
  );

  @override
  Widget build(BuildContext context) {
    final current = _channels[_index];
    final front = _done ? _viewing : current;
    final (toastTitle, toastDetail) = _toastFor(current);
    // All pages stay mounted; the one in front is painted last.
    final order = [
      ..._pages.keys.where((platform) => platform != front),
      if (front != null && _pages.containsKey(front)) front,
    ];
    final frontPage = front == null ? null : _pages[front];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColor.bgPage,
        body: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 60,
                    child: _done
                        ? BackTitleBar(
                            title: _viewing?.label ?? '',
                            onBack: _back,
                          )
                        : StepProgress(
                            total: _channels.length,
                            current: _index + 1,
                            label: '광고 종료 ${_index + 1} / ${_channels.length}',
                            onBack: _back,
                          ),
                  ),
                  Expanded(
                    child: WebSheet(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          for (final platform in order)
                            KeyedSubtree(
                              key: ObjectKey(_pages[platform]),
                              child: MirrorWebView(_pages[platform]!),
                            ),
                          if (frontPage?.failure != null)
                            ColoredBox(
                              color: AppColor.bgSurface,
                              child: Center(
                                child: Text(
                                  frontPage!.failure!,
                                  style: AppText.bodySmall,
                                ),
                              ),
                            ),
                          if (!_done)
                            Positioned(
                              left: Space.s16,
                              right: Space.s16,
                              bottom: Space.s16,
                              child: SafeArea(
                                top: false,
                                child: TimedToast(
                                  // 찾는 중 → 찾았다로 바뀔 때 토스트를 다시 띄운다.
                                  // 사람이 기다려야 하는 말과 눌러야 하는 말은
                                  // 다른 말이다.
                                  toastKey: (
                                    current,
                                    _pages[current]?.cardFound,
                                    _pages[current]?.gaveUp,
                                  ),
                                  title: toastTitle,
                                  detail: toastDetail,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_done)
              IgnorePointer(
                ignoring: _viewing != null,
                child: AnimatedSlide(
                  duration: Motion.base,
                  curve: Motion.enter,
                  offset: _viewing == null ? Offset.zero : const Offset(0, 1),
                  child: ColoredBox(
                    color: AppColor.bgPage,
                    child: _Result(
                      listing:
                          widget.store.byId(widget.listing.id) ??
                          widget.listing,
                      removed: _removed,
                      skipped: _skipped,
                      channels: _channels,
                      numbers: _numbers,
                      onView: (platform) => setState(() => _viewing = platform),
                      onHome: _home,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.listing,
    required this.removed,
    required this.skipped,
    required this.channels,
    required this.numbers,
    required this.onView,
    required this.onHome,
  });

  final Listing listing;
  final Set<ListingPlatform> removed;
  final Set<ListingPlatform> skipped;
  final List<ListingPlatform> channels;
  final Map<ListingPlatform, String> numbers;
  final ValueChanged<ListingPlatform> onView;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final title = removed.isEmpty
        ? '광고를 종료하지 않았어요'
        : '${removed.length}개 플랫폼에서 광고 종료';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          60,
          Space.gutter,
          Space.s16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Text(title, textAlign: TextAlign.center, style: AppText.title),
            const SizedBox(height: Space.s16),
            Center(
              child: OutcomeMark(
                removed.isEmpty ? OutcomeKind.warning : OutcomeKind.success,
              ),
            ),
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: Space.s16),
              Text(
                '${skipped.map((p) => p.label).join('·')} 광고는 계속 노출돼요',
                textAlign: TextAlign.center,
                style: AppText.bodySmall,
              ),
            ],
            const Spacer(flex: 2),
            for (final platform in channels)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s8),
                child: removed.contains(platform)
                    ? ChannelRow(
                        mark: RowMark.done,
                        name: platform.label,
                        status: '광고 종료',
                        action: '바로보기',
                        actionIcon: Icons.north_east_rounded,
                        onAction: () => onView(platform),
                        // 종료일 옆에 번호를 남긴다. 사람이 플랫폼에 직접 들어가
                        // 「정말 내려갔나」를 확인할 때 들고 갈 수 있는 한 가지다.
                        subline: [
                          if (listing.channelDates[platform] != null)
                            '종료일: ${formatDate(listing.channelDates[platform]!)}',
                          if (numbers[platform] != null)
                            '${platform.listingNumberLabel} ${numbers[platform]}',
                        ].join(' · ').ifEmpty(null),
                      )
                    : ChannelRow(
                        mark: RowMark.waiting,
                        name: platform.label,
                        status: '광고 유지',
                      ),
              ),
            const SizedBox(height: Space.s24),
            BrandButton('홈으로', onPressed: onHome),
          ],
        ),
      ),
    );
  }
}

extension on String {
  /// 빈 줄은 줄이 아니다 — [ChannelRow] 의 부제는 없으면 아예 없어야 한다.
  String? ifEmpty(String? fallback) => isEmpty ? fallback : this;
}
