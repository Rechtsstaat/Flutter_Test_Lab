import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../fields.dart';
import '../mirror_session.dart';
import 'home_page.dart';

enum _Stage { select, login, done }

/// 001 플랫폼 연동 선택 → 0011 플랫폼 연동-웹뷰 (one per platform) → 002 완료.
///
/// 한방 keeps the chrome — the step bar and the order of platforms — while each
/// platform's own login page runs in the sheet underneath. The app never sees
/// what is typed there; it only hears that the platform let the agent in.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.store});

  final AppStore store;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _picked = <ListingPlatform>{
    ListingPlatform.zigbang,
    ListingPlatform.dabang,
  };
  final _connected = <ListingPlatform>{};

  _Stage _stage = _Stage.select;
  int _index = 0;
  MirrorLogin? _login;

  List<ListingPlatform> get _queue =>
      ListingPlatform.values.where(_picked.contains).toList(growable: false);

  @override
  void dispose() {
    _disposeLogin();
    super.dispose();
  }

  void _disposeLogin() {
    _login
      ?..removeListener(_onLogin)
      ..dispose();
    _login = null;
  }

  void _openLogin(int index) {
    _disposeLogin();
    setState(() {
      _index = index;
      _stage = _Stage.login;
      _login = MirrorLogin(platform: _queue[index])..addListener(_onLogin);
    });
  }

  void _onLogin() {
    final login = _login;
    if (login == null || !mounted) return;
    if (login.linked) {
      _connected.add(login.platform);
      // Let the signed-in page register before moving on.
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted && identical(_login, login)) _advance();
      });
    }
    setState(() {});
  }

  void _advance() {
    if (_index + 1 < _queue.length) {
      _openLogin(_index + 1);
    } else {
      _disposeLogin();
      setState(() => _stage = _Stage.done);
    }
  }

  void _back() {
    if (_stage == _Stage.login && _index > 0) {
      _openLogin(_index - 1);
    } else {
      _disposeLogin();
      setState(() => _stage = _Stage.select);
    }
  }

  Future<void> _finish() async {
    await widget.store.completeOnboarding(_connected);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: Motion.base,
        pageBuilder: (_, _, _) => HomePage(store: widget.store),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final login = _login;
    final body = switch (_stage) {
      _Stage.select => _SelectStep(
        key: const ValueKey('select'),
        picked: _picked,
        onToggle: (platform) => setState(() {
          if (!_picked.remove(platform)) _picked.add(platform);
        }),
        onNext: _picked.isEmpty ? null : () => _openLogin(0),
      ),
      _Stage.login when login != null => _LoginStep(
        key: ValueKey(login),
        login: login,
        step: _index + 1,
        total: _queue.length,
        onRetry: () => _openLogin(_index),
        onSkip: _advance,
      ),
      _ => _DoneStep(
        key: const ValueKey('done'),
        connected: _connected.length,
        onHome: _finish,
      ),
    };

    return PopScope(
      canPop: _stage == _Stage.select,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _login?.closeOverlay() ?? false) return;
        if (mounted) _back();
      },
      child: Scaffold(
        backgroundColor: AppColor.bgPage,
        body: AnimatedSwitcher(
          duration: Motion.base,
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          child: body,
        ),
      ),
    );
  }
}

class _SelectStep extends StatelessWidget {
  const _SelectStep({
    super.key,
    required this.picked,
    required this.onToggle,
    required this.onNext,
  });

  final Set<ListingPlatform> picked;
  final ValueChanged<ListingPlatform> onToggle;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.s48,
        Space.gutter,
        Space.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FadeSlideIn(
            child: Text('사용하는 플랫폼을\n선택하세요', style: AppText.heading),
          ),
          const SizedBox(height: Space.s8),
          const FadeSlideIn(
            delay: Duration(milliseconds: 60),
            child: Text(
              '한 번만 연결하면, 다음부터는 한방에서\n바로 광고를 올릴 수 있어요.',
              style: AppText.bodySmall,
            ),
          ),
          const SizedBox(height: Space.s24),
          for (final (index, platform) in ListingPlatform.values.indexed)
            FadeSlideIn(
              delay: Duration(milliseconds: 100 + index * 50),
              child: Padding(
                padding: const EdgeInsets.only(bottom: Space.s8),
                child: SelectCard(
                  platform: platform,
                  selected: picked.contains(platform),
                  onTap: () => onToggle(platform),
                ),
              ),
            ),
          const SizedBox(height: Space.s4),
          const Text('선택한 플랫폼은 다음 단계에서 하나씩 연결해요.', style: AppText.caption),
          const Spacer(),
          BrandButton(
            picked.isEmpty ? '플랫폼을 선택해주세요' : '플랫폼 연결하기',
            onPressed: onNext,
          ),
        ],
      ),
    ),
  );
}

class _LoginStep extends StatelessWidget {
  const _LoginStep({
    super.key,
    required this.login,
    required this.step,
    required this.total,
    required this.onRetry,
    required this.onSkip,
  });

  final MirrorLogin login;
  final int step;
  final int total;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepProgress(
          total: total,
          current: step,
          label: '플랫폼 연동 $step / $total',
        ),
        Expanded(
          child: WebSheet(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MirrorWebView(login),
                if (login.failure != null)
                  _LoginFailure(
                    platform: login.platform,
                    reason: login.failure!,
                    onRetry: onRetry,
                    onSkip: onSkip,
                  )
                else if (login.linked)
                  _LinkedBadge(platform: login.platform),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The beat between a platform letting the agent in and the next login.
class _LinkedBadge extends StatelessWidget {
  const _LinkedBadge({required this.platform});

  final ListingPlatform platform;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Padding(
      padding: const EdgeInsets.all(Space.s16),
      child: SafeArea(
        top: false,
        child: FadeSlideIn(
          child: GuideToast(title: '${platform.label} 연결을 확인했어요'),
        ),
      ),
    ),
  );
}

class _LoginFailure extends StatelessWidget {
  const _LoginFailure({
    required this.platform,
    required this.reason,
    required this.onRetry,
    required this.onSkip,
  });

  final ListingPlatform platform;
  final String reason;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColor.bgSurface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(Space.s24),
        child: Column(
          children: [
            const Spacer(),
            const OutcomeMark(OutcomeKind.error),
            const SizedBox(height: Space.s16),
            Text('${platform.label} 로그인 화면을 열지 못했어요', style: AppText.title),
            const SizedBox(height: Space.s8),
            Text(reason, textAlign: TextAlign.center, style: AppText.bodySmall),
            const Spacer(),
            BrandButton('다시 시도', onPressed: onRetry),
            const SizedBox(height: Space.s8),
            BrandButton(
              '나중에 연결할게요',
              kind: BrandButtonKind.text,
              onPressed: onSkip,
            ),
          ],
        ),
      ),
    ),
  );
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({super.key, required this.connected, required this.onHome});

  final int connected;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        0,
        Space.gutter,
        Space.s16,
      ),
      child: Column(
        children: [
          const Spacer(),
          Text(
            connected == 0 ? '연결된 플랫폼이 없어요' : '플랫폼 연동을 완료했어요',
            style: AppText.title,
          ),
          const SizedBox(height: Space.s16),
          OutcomeMark(
            connected == 0 ? OutcomeKind.warning : OutcomeKind.success,
          ),
          if (connected == 0) ...[
            const SizedBox(height: Space.s16),
            const Text('광고를 올릴 때 다시 연결할 수 있어요.', style: AppText.bodySmall),
          ],
          const Spacer(),
          BrandButton('홈으로', onPressed: onHome),
        ],
      ),
    ),
  );
}
