import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../fields.dart';
import '../mirror_session.dart';
import '../models/listing.dart';
import 'home_page.dart';
import 'listing_detail_page.dart' show formatDate;

typedef RemotePageBuilder =
    Widget Function(
      Map<String, dynamic> values,
      ListingPlatform platform,
      List<XFile> photos,
    );

/// Which surface is in front.
enum _Front {
  /// 202/203 while working, 204/205/206/2062 once every platform has had its
  /// turn.
  hub,

  /// 2021/2023 (the platform being worked on) or 2051 (one waiting on a
  /// check): the platform's own form, lifted out from under the hub.
  form,

  /// 2022 등록된 광고 보기.
  listings,
}

/// 202~206 광고 등록 — the Process Hub.
///
/// 한방 keeps the screen the whole time. Each platform's page is loaded into a
/// WebView that stays mounted underneath the hub, so the agent can lift it
/// into view at any moment ("입력 과정 보기") and 한방 lifts it by itself when
/// the adapter is done — the last step, pressing the platform's own 등록
/// button, is the agent's. That press is what moves the hub on to the next
/// platform.
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
  late final Map<ListingPlatform, DateTime> _dates = {
    ...widget.listing.channelDates,
  };

  final _sessions = <ListingPlatform, MirrorSession>{};
  final _builtPages = <ListingPlatform, Widget>{};
  final _listingPages = <ListingPlatform, MirrorPage>{};

  /// Platforms whose session already lifted itself once.
  final _autoLifted = <MirrorSession>{};

  /// Platforms that have used their one retry (2061); a second failure is
  /// final (2062).
  final _retried = <ListingPlatform>{};

  ListingPlatform? _active;
  ListingPlatform? _shown;
  _Front _front = _Front.hub;
  int _toastKey = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _next());
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    for (final page in _listingPages.values) {
      page.dispose();
    }
    super.dispose();
  }

  // ---- flow ----------------------------------------------------------------

  void _next() {
    if (!mounted) return;
    final waiting = widget.channels.where(
      (platform) => _states[platform] == ChannelState.pending,
    );
    if (waiting.isEmpty) {
      setState(() => _active = null);
      _persist();
      return;
    }
    _start(waiting.first);
  }

  void _start(ListingPlatform platform) {
    _sessions.remove(platform)?.dispose();
    setState(() {
      _active = platform;
      _states[platform] = ChannelState.working;
    });
    final builder = widget.remotePageBuilder;
    if (builder != null) {
      _builtPages[platform] = builder(widget.values, platform, widget.photos);
      setState(() {});
      return;
    }
    _sessions[platform] = MirrorSession(
      platform: platform,
      values: widget.values,
      photos: widget.photos,
    )..addListener(() => _onSession(platform));
    _persist();
  }

  void _onSession(ListingPlatform platform) {
    final session = _sessions[platform];
    if (session == null || !mounted) return;
    if (session.pressedLabel != null) {
      _complete(platform);
    } else if (session.failure != null) {
      _failed(platform);
    } else if (session.filled && _autoLifted.add(session)) {
      // AUTO: 입력 완료 후 → 2023. The rest is the agent's to press.
      if (platform == _active) _lift(platform);
    } else {
      setState(() {});
    }
  }

  void _complete(ListingPlatform platform) {
    if (_states[platform] == ChannelState.published) return;
    setState(() {
      _states[platform] = ChannelState.published;
      _dates[platform] = DateTime.now();
      if (_shown == platform) _front = _Front.hub;
    });
    _persist();
    if (platform == _active) _next();
  }

  void _failed(ListingPlatform platform) {
    if (_states[platform] == ChannelState.failed) return;
    setState(() {
      _states[platform] = ChannelState.failed;
      if (_shown == platform && _front == _Front.form) _front = _Front.hub;
    });
    _persist();
    if (platform == _active) _next();
  }

  void _lift(ListingPlatform platform) => setState(() {
    _shown = platform;
    _front = _Front.form;
    _toastKey++;
  });

  void _showListings(ListingPlatform platform) {
    _listingPages.putIfAbsent(
      platform,
      () =>
          MirrorPage(platform: platform, url: Uri.parse(platform.listingsUrl))
            ..addListener(() {
              if (mounted) setState(() {});
            }),
    );
    setState(() {
      _shown = platform;
      _front = _Front.listings;
    });
  }

  void _retry(ListingPlatform platform) {
    _retried.add(platform);
    setState(() => _states[platform] = ChannelState.pending);
    if (_active == null) _next();
  }

  /// Back from a lifted page. Leaving the form unsent is 205's "확인이 필요해요".
  Future<void> _backToHub() async {
    final platform = _shown;
    if (platform == null) return;
    final page = _front == _Front.form
        ? _sessions[platform]
        : _listingPages[platform];
    if (await page?.closeOverlay() ?? false) return;
    if (!mounted) return;
    final session = _sessions[platform];
    final unsent =
        _front == _Front.form &&
        session != null &&
        session.filled &&
        session.pressedLabel == null;
    setState(() {
      _front = _Front.hub;
      if (unsent) _states[platform] = ChannelState.needsCheck;
    });
    if (unsent) {
      _persist();
      if (platform == _active) _next();
    }
  }

  Future<void> _persist() async {
    final store = widget.store;
    if (store == null) return;
    await store.save(
      widget.listing.copyWith(
        channels: {
          for (final entry in _states.entries)
            // An interrupted run must not read as still working next launch.
            entry.key: entry.value == ChannelState.working
                ? ChannelState.pending
                : entry.value,
        },
        channelDates: Map.of(_dates),
      ),
    );
  }

  void _home() {
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

  // ---- view ----------------------------------------------------------------

  ChannelRow _row(ListingPlatform platform) {
    final state = _states[platform] ?? ChannelState.pending;
    final name = platform.label;
    final date = _dates[platform];
    return switch (state) {
      ChannelState.published => ChannelRow(
        mark: RowMark.done,
        name: name,
        status: '등록 완료',
        action: '등록된 광고 보기',
        actionIcon: Icons.north_east_rounded,
        onAction: () => _showListings(platform),
        subline: date == null ? null : '등록일: ${formatDate(date)}',
      ),
      ChannelState.working => ChannelRow(
        mark: RowMark.working,
        name: name,
        status: '정보를 입력하고 있어요',
        action: '입력 과정 보기',
        onAction: () => _lift(platform),
      ),
      ChannelState.needsCheck => ChannelRow(
        mark: RowMark.warning,
        name: name,
        status: '확인이 필요해요',
        action: '확인하기',
        onAction: () => _lift(platform),
      ),
      ChannelState.failed when _retried.contains(platform) => ChannelRow(
        mark: RowMark.error,
        name: name,
        status: '나중에 다시 시도해주세요',
      ),
      ChannelState.failed => ChannelRow(
        mark: RowMark.error,
        name: name,
        status: '연결이 어려워요',
        action: '다시시도',
        onAction: () => _retry(platform),
      ),
      ChannelState.pending || ChannelState.removed => ChannelRow(
        mark: RowMark.waiting,
        name: name,
        status: '입력 대기',
      ),
    };
  }

  Widget _hub() {
    final active = _active;
    final rows = [
      for (final platform in widget.channels)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s8),
          child: _row(platform),
        ),
    ];
    if (active != null) {
      final step = widget.channels.indexOf(active) + 1;
      final retrying = _retried.contains(active);
      return _HubLayout(
        key: const ValueKey('working'),
        progress: StepProgress(
          total: widget.channels.length,
          current: step,
          label: '광고 등록 $step / ${widget.channels.length}',
        ),
        title: retrying
            ? '${active.label} 등록을 다시 시도하고 있어요'
            : '${active.label}에 입력하는 중이에요',
        hero: PlatformTile(active, key: ValueKey(active)),
        message: retrying
            ? null
            : const Text.rich(
                TextSpan(
                  text: '조금만 기다려주세요.\n최대 2분 소요될 수 있어요.\n',
                  children: [
                    TextSpan(
                      text: '앱을 종료하지 말고 기다려주세요!',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColor.textPrimary,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: AppText.bodySmall,
              ),
        rows: rows,
      );
    }

    final published = widget.channels
        .where((p) => _states[p] == ChannelState.published)
        .toList();
    final retryable = widget.channels.where(
      (p) => _states[p] == ChannelState.failed && !_retried.contains(p),
    );
    final checks = widget.channels.where(
      (p) => _states[p] == ChannelState.needsCheck,
    );
    final given = widget.channels.where(
      (p) => _states[p] == ChannelState.failed && _retried.contains(p),
    );
    final OutcomeKind kind;
    final String title;
    String? message;
    if (retryable.isNotEmpty) {
      kind = OutcomeKind.error;
      title = '${retryable.first.label} 등록을 완료하지 못했어요';
    } else if (checks.isNotEmpty) {
      kind = OutcomeKind.warning;
      title = '${checks.first.label}에서 확인이 필요해요';
      message = '입력된 내용을 확인한 뒤\n등록하기 버튼을 직접 눌러주세요';
    } else if (published.isEmpty) {
      kind = OutcomeKind.error;
      title = '광고를 등록하지 못했어요';
      message = '연결이 원활해지면 다시 등록할 수 있어요';
    } else if (given.isNotEmpty) {
      kind = OutcomeKind.success;
      title = '${published.length}곳에 광고를 등록 했어요';
      message =
          '${given.map((p) => p.label).join('·')}은 연결이 원활해지면\n다시 등록할 수 있어요';
    } else {
      kind = OutcomeKind.success;
      title = widget.channels.length == 1
          ? '${published.first.label}에 광고를 등록 했어요'
          : '모든 플랫폼에 등록 했어요';
    }
    return _HubLayout(
      key: ValueKey('summary-$title'),
      title: title,
      hero: OutcomeMark(kind),
      message: message == null
          ? null
          : Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.bodySmall,
            ),
      rows: rows,
      action: BrandButton('홈으로', onPressed: _home),
    );
  }

  Widget _formChrome(ListingPlatform platform) {
    if (platform == _active) {
      final step = widget.channels.indexOf(platform) + 1;
      return StepProgress(
        total: widget.channels.length,
        current: step,
        label: '광고 등록 $step / ${widget.channels.length}',
        onBack: _backToHub,
      );
    }
    return BackTitleBar(title: platform.label, onBack: _backToHub);
  }

  (String, String?) _toastFor(ListingPlatform platform) {
    final session = _sessions[platform];
    if (session == null || !session.filled) {
      return ('입력이 끝날 때 까지 잠시만 기다려주세요', null);
    }
    if (platform != _active || session.blockers.isNotEmpty) {
      return ('입력된 내용을 확인한 뒤', '등록하기 버튼을 직접 눌러주세요');
    }
    return ('입력이 끝났어요', '내용을 확인하고 등록하기 버튼을 직접 눌러주세요');
  }

  Widget _webLayer() {
    final shown = _shown;
    // Every page stays mounted — a WebView taken out of the window is
    // throttled — and the one in front is painted last.
    final pages = <(Object, Widget)>[
      for (final entry in _builtPages.entries)
        (('built', entry.key), entry.value),
      for (final entry in _sessions.entries)
        (entry.value, MirrorWebView(entry.value)),
      for (final entry in _listingPages.entries)
        (entry.value, MirrorWebView(entry.value)),
    ];
    final Object? frontKey = shown == null
        ? null
        : switch (_front) {
            _Front.form => _sessions[shown] ?? ('built', shown),
            _Front.listings => _listingPages[shown],
            _Front.hub => null,
          };
    final front = pages.where((page) => page.$1 == frontKey).toList();
    pages
      ..removeWhere((page) => page.$1 == frontKey)
      ..addAll(front);

    final session = shown == null ? null : _sessions[shown];
    final (toastTitle, toastDetail) = shown == null
        ? ('', null)
        : _toastFor(shown);
    final chrome = shown == null
        ? const SizedBox(height: 52)
        : _front == _Front.listings
        ? BackTitleBar(title: shown.label, onBack: _backToHub)
        : _formChrome(shown);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 60, child: chrome),
          Expanded(
            child: WebSheet(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final (key, page) in pages)
                    KeyedSubtree(key: ObjectKey(key), child: page),
                  if (_front == _Front.form) ...[
                    if (session != null && session.reasons.isNotEmpty)
                      Positioned(
                        top: Space.s12,
                        right: Space.s12,
                        child: _ReasonsChip(session: session),
                      ),
                    Positioned(
                      left: Space.s16,
                      right: Space.s16,
                      bottom: Space.s16,
                      child: SafeArea(
                        top: false,
                        child: TimedToast(
                          toastKey: (_toastKey, session?.filled, shown),
                          title: toastTitle,
                          detail: toastDetail,
                        ),
                      ),
                    ),
                  ],
                  if (_front == _Front.listings &&
                      _listingPages[shown]?.failure != null)
                    _PageFailure(message: _listingPages[shown]!.failure!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onHub = _front == _Front.hub;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!onHub) {
          _backToHub();
        } else if (_active == null) {
          _home();
        }
      },
      child: Scaffold(
        backgroundColor: AppColor.bgPage,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _webLayer(),
            IgnorePointer(
              ignoring: !onHub,
              child: AnimatedSlide(
                duration: Motion.base,
                curve: onHub ? Motion.enter : Motion.exit,
                offset: onHub ? Offset.zero : const Offset(0, 1),
                child: ColoredBox(
                  color: AppColor.bgPage,
                  child: AnimatedSwitcher(duration: Motion.base, child: _hub()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubLayout extends StatelessWidget {
  const _HubLayout({
    super.key,
    required this.title,
    required this.hero,
    required this.rows,
    this.progress,
    this.message,
    this.action,
  });

  final Widget? progress;
  final String title;
  final Widget hero;
  final Widget? message;
  final List<Widget> rows;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 60, child: progress),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    SizedBox(height: constraints.maxHeight * 0.08),
                    FadeSlideIn(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: AppText.title,
                      ),
                    ),
                    const SizedBox(height: Space.s16),
                    hero,
                    if (message != null) ...[
                      const SizedBox(height: Space.s16),
                      message!,
                    ],
                    const SizedBox(height: Space.s40),
                    ...rows,
                    const SizedBox(height: Space.s24),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (action != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.s16,
            ),
            child: action,
          ),
      ],
    ),
  );
}

/// "확인할 항목 N개" — what the adapter could not settle, on demand.
class _ReasonsChip extends StatelessWidget {
  const _ReasonsChip({required this.session});

  final MirrorSession session;

  void _open(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColor.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.r24)),
    ),
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(Space.s24),
          children: [
            Text('${session.platform.label}에서 확인할 항목', style: AppText.title),
            const SizedBox(height: Space.s4),
            Text(session.status, style: AppText.caption),
            const SizedBox(height: Space.s16),
            for (final reason in session.blockers)
              _ReasonLine(reason, color: AppColor.statusWarning),
            for (final reason in [
              ...session.unsupported,
              ...session.photoNotes,
            ])
              _ReasonLine(reason, color: AppColor.iconSecondary),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final blocking = session.blockers.isNotEmpty;
    final color = blocking ? AppColor.statusWarning : AppColor.textSecondary;
    return Material(
      color: AppColor.bgSurface,
      shape: StadiumBorder(
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      elevation: 2,
      shadowColor: AppColor.bgOverlay.withValues(alpha: 0.2),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s12,
            vertical: 6,
          ),
          child: Text(
            blocking
                ? '확인할 항목 ${session.blockers.length}개'
                : '참고 사항 ${session.reasons.length}개',
            style: AppText.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReasonLine extends StatelessWidget {
  const _ReasonLine(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7, right: Space.s8),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ),
        Expanded(child: SelectableText(text, style: AppText.bodySmall)),
      ],
    ),
  );
}

class _PageFailure extends StatelessWidget {
  const _PageFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColor.bgSurface,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OutcomeMark(OutcomeKind.error),
            const SizedBox(height: Space.s16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
