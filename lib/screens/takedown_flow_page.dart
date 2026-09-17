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
  final _removed = <ListingPlatform>{};
  final _skipped = <ListingPlatform>{};
  final _pages = <ListingPlatform, MirrorPage>{};

  int _index = 0;
  bool _done = false;

  /// Set while 303's 바로보기 has a page in front.
  ListingPlatform? _viewing;

  @override
  void initState() {
    super.initState();
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
    final platform = widget.channels[index];
    _pages[platform] = MirrorPage(
      platform: platform,
      url: Uri.parse(platform.listingsUrl),
      watchLabels: platform.takedownLabels,
    )..addListener(() => _onPage(platform));
    _index = index;
  }

  void _onPage(ListingPlatform platform) {
    if (!mounted) return;
    final page = _pages[platform];
    if (page?.pressedLabel != null && _removed.add(platform)) {
      _advance();
    } else {
      setState(() {});
    }
  }

  Future<void> _advance() async {
    if (_index + 1 < widget.channels.length) {
      setState(() => _open(_index + 1));
      return;
    }
    if (_removed.isNotEmpty) {
      await widget.store.close(
        widget.listing,
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
    final page = _pages[widget.channels[_index]];
    if (await page?.closeOverlay() ?? false) return;
    if (!mounted) return;
    final skip = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColor.bgSurface,
        title: Text(
          '${widget.channels[_index].label} 광고를 그대로 둘까요?',
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
      _skipped.add(widget.channels[_index]);
      await _advance();
    }
  }

  void _home() => Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => HomePage(store: widget.store)),
    (route) => false,
  );

  @override
  Widget build(BuildContext context) {
    final current = widget.channels[_index];
    final front = _done ? _viewing : current;
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
                            total: widget.channels.length,
                            current: _index + 1,
                            label:
                                '광고 종료 ${_index + 1} / ${widget.channels.length}',
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
                                  toastKey: current,
                                  title: '종료하기 버튼을 눌러주세요',
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
                      channels: widget.channels,
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
    required this.onView,
    required this.onHome,
  });

  final Listing listing;
  final Set<ListingPlatform> removed;
  final Set<ListingPlatform> skipped;
  final List<ListingPlatform> channels;
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
                        subline: listing.channelDates[platform] == null
                            ? null
                            : '종료일: ${formatDate(listing.channelDates[platform]!)}',
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
