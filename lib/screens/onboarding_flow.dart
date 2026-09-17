import 'package:flutter/material.dart';

import '../android_layout.dart';
import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../fields.dart';
import 'home_page.dart';

enum _Stage { select, login, linked, done }

/// 0. 로그인 — platform pick, then one login screen per platform, each followed
/// by a short "연동 완료" beat, then the shared finish screen.
///
/// The 개선 notes settle the ownership question this way: 한방 owns the process
/// chrome (the step bar, the back affordance, the copy), and the authenticating
/// party is named unmistakably inside it. The credential exchange itself is a
/// placeholder here — pressing the CTA always advances — so the flow can be
/// reviewed before any real provider session exists.
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

  List<ListingPlatform> get _queue =>
      ListingPlatform.values.where(_picked.contains).toList(growable: false);

  ListingPlatform get _current => _queue[_index];

  void _beginLinking() {
    if (_picked.isEmpty) return;
    setState(() {
      _index = 0;
      _stage = _Stage.login;
    });
  }

  void _confirmCurrent({required bool linked}) {
    if (linked) _connected.add(_current);
    setState(() => _stage = linked ? _Stage.linked : _Stage.select);
    if (!linked) {
      _advance();
      return;
    }
    // The interstitial is a beat, not a screen to read: it hands off on its
    // own so the agent never has to tap through an empty confirmation.
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && _stage == _Stage.linked) _advance();
    });
  }

  void _advance() {
    if (_index + 1 < _queue.length) {
      setState(() {
        _index += 1;
        _stage = _Stage.login;
      });
    } else {
      setState(() => _stage = _Stage.done);
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
    final body = switch (_stage) {
      _Stage.select => _SelectStep(
        key: const ValueKey('select'),
        picked: _picked,
        onToggle: (platform) => setState(() {
          if (!_picked.remove(platform)) _picked.add(platform);
        }),
        onNext: _beginLinking,
      ),
      _Stage.login => _LoginStep(
        key: ValueKey('login-${_current.name}'),
        platform: _current,
        step: _index + 1,
        total: _queue.length,
        onLink: () => _confirmCurrent(linked: true),
        onSkip: () => _confirmCurrent(linked: false),
      ),
      _Stage.linked => _LinkedStep(
        key: ValueKey('linked-${_current.name}'),
        platform: _current,
        step: _index + 1,
        total: _queue.length,
        next: _index + 1 < _queue.length ? _queue[_index + 1] : null,
      ),
      _Stage.done => _DoneStep(
        key: const ValueKey('done'),
        connected: _connected.toList(),
        onStart: _finish,
      ),
    };

    return Scaffold(
      backgroundColor: Brand.surface,
      body: SafeArea(
        child: AnimatedSwitcher(
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
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        const FadeSlideIn(child: Text('사용하는 플랫폼을\n선택하세요', style: Type.display)),
        const SizedBox(height: 10),
        const FadeSlideIn(
          delay: Duration(milliseconds: 60),
          child: Text(
            '한 번만 연동하면, 다음부터는 한방에서\n바로 광고를 올릴 수 있어요.',
            style: Type.bodyMuted,
          ),
        ),
        const SizedBox(height: 26),
        for (final (index, platform) in ListingPlatform.values.indexed)
          FadeSlideIn(
            delay: Duration(milliseconds: 110 + index * 60),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PlatformRow(
                platform: platform,
                selected: picked.contains(platform),
                onTap: () => onToggle(platform),
              ),
            ),
          ),
        const Spacer(),
        FadeSlideIn(
          delay: const Duration(milliseconds: 300),
          child: BrandButton(
            picked.isEmpty ? '플랫폼을 선택해 주세요' : '${picked.length}개 플랫폼 연동하기',
            onPressed: picked.isEmpty ? null : onNext,
          ),
        ),
        SizedBox(height: 20 + androidBottomInset(context).bottom),
      ],
    ),
  );
}

class _PlatformRow extends StatelessWidget {
  const _PlatformRow({
    required this.platform,
    required this.selected,
    required this.onTap,
  });

  final ListingPlatform platform;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: Motion.quick,
      curve: Motion.enter,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: selected ? Brand.blueFaint : Brand.surface,
        borderRadius: BorderRadius.circular(Insets.radiusCard),
        border: Border.all(
          color: selected ? Brand.blue : Brand.hairline,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          PlatformBadge(platform, size: 38),
          const SizedBox(width: 14),
          Text(platform.label, style: Type.title),
          const Spacer(),
          // The tick scales in so a tap registers even when the colour shift
          // is easy to miss at a glance.
          AnimatedScale(
            duration: Motion.quick,
            curve: Motion.settle,
            scale: selected ? 1 : 0.86,
            child: AnimatedContainer(
              duration: Motion.quick,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? Brand.blue : const Color(0xfff0f1f3),
              ),
              child: Icon(
                Icons.check_rounded,
                size: 16,
                color: selected ? Colors.white : const Color(0xffd3d6da),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _LoginStep extends StatelessWidget {
  const _LoginStep({
    super.key,
    required this.platform,
    required this.step,
    required this.total,
    required this.onLink,
    required this.onSkip,
  });

  final ListingPlatform platform;
  final int step;
  final int total;
  final VoidCallback onLink;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        StepBar(total: total, current: step),
        const SizedBox(height: 10),
        Text('플랫폼 연동 $step / $total', style: Type.caption),
        const SizedBox(height: 24),
        FadeSlideIn(child: PlatformBadge(platform, size: 52)),
        const SizedBox(height: 18),
        FadeSlideIn(
          delay: const Duration(milliseconds: 60),
          child: Text('${platform.label} 계정으로\n로그인해 주세요', style: Type.display),
        ),
        const SizedBox(height: 10),
        FadeSlideIn(
          delay: const Duration(milliseconds: 100),
          child: Text(
            '중개사님이 쓰시던 ${platform.label} 아이디를\n그대로 입력하시면 됩니다.',
            style: Type.bodyMuted,
          ),
        ),
        const SizedBox(height: 26),
        FadeSlideIn(
          delay: const Duration(milliseconds: 140),
          child: _Field(hint: '${platform.label} 아이디'),
        ),
        const SizedBox(height: 10),
        FadeSlideIn(
          delay: const Duration(milliseconds: 180),
          child: const _Field(hint: '비밀번호', obscure: true),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          delay: const Duration(milliseconds: 220),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Brand.canvas,
              borderRadius: BorderRadius.circular(Insets.radiusField),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 15,
                  color: Brand.inkMuted,
                ),
                SizedBox(width: 9),
                Expanded(
                  // Wording fixed per the 확정 note: the account is not kept,
                  // it is only used at the moment a listing is posted.
                  child: Text(
                    '로그인 정보는 저장되지 않고, 광고 등록 시에만 사용됩니다.',
                    style: Type.caption,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        BrandButton(
          '${platform.label} 연동하기',
          color: platform.color,
          onPressed: onLink,
        ),
        const SizedBox(height: 4),
        BrandButton('나중에 할게요', kind: BrandButtonKind.quiet, onPressed: onSkip),
        SizedBox(height: 12 + androidBottomInset(context).bottom),
      ],
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.hint, this.obscure = false});

  final String hint;
  final bool obscure;

  @override
  Widget build(BuildContext context) => TextField(
    obscureText: obscure,
    style: Type.body,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: Type.bodyMuted,
      filled: true,
      fillColor: Brand.canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Insets.radiusField),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Insets.radiusField),
        borderSide: const BorderSide(color: Brand.blue, width: 1.4),
      ),
    ),
  );
}

class _LinkedStep extends StatelessWidget {
  const _LinkedStep({
    super.key,
    required this.platform,
    required this.step,
    required this.total,
    required this.next,
  });

  final ListingPlatform platform;
  final int step;
  final int total;
  final ListingPlatform? next;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        StepBar(total: total, current: step),
        const SizedBox(height: 10),
        Text('플랫폼 연동 $step / $total', style: Type.caption),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PulseHalo(
                  color: platform.color,
                  child: PlatformBadge(platform, size: 88),
                ),
                const SizedBox(height: 22),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 120),
                  child: Text('${platform.label} 연동 완료', style: Type.title),
                ),
                const SizedBox(height: 6),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 180),
                  child: Text(
                    next == null
                        ? '모든 플랫폼 연동이 끝났어요'
                        : '${next!.label} 로그인으로 넘어갈게요',
                    style: Type.bodyMuted,
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

class _DoneStep extends StatelessWidget {
  const _DoneStep({super.key, required this.connected, required this.onStart});

  final List<ListingPlatform> connected;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
    child: Column(
      children: [
        const Spacer(flex: 3),
        // The linked badges fan into a row: the point of the screen is that
        // several channels now sit behind one app.
        SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final (index, platform) in connected.indexed)
                FadeSlideIn(
                  delay: Duration(milliseconds: 80 * index),
                  offset: 0,
                  child: Transform.translate(
                    offset: Offset(
                      (index - (connected.length - 1) / 2) * 42,
                      0,
                    ),
                    child: PlatformBadge(platform, size: 54),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        const SuccessTick(size: 64),
        const SizedBox(height: 22),
        const FadeSlideIn(
          delay: Duration(milliseconds: 220),
          child: Text(
            '중개사님, 이제 매물을\n한방에 올릴 수 있어요',
            textAlign: TextAlign.center,
            style: Type.display,
          ),
        ),
        const SizedBox(height: 10),
        FadeSlideIn(
          delay: const Duration(milliseconds: 280),
          child: Text(
            connected.isEmpty
                ? '연동된 플랫폼이 없어요. 언제든 설정에서 연동할 수 있어요.'
                : '${connected.map((p) => p.label).join(' · ')} 연동됨',
            style: Type.caption,
          ),
        ),
        const Spacer(flex: 2),
        FadeSlideIn(
          delay: const Duration(milliseconds: 340),
          child: BrandButton('시작하기', onPressed: onStart),
        ),
        SizedBox(height: 24 + androidBottomInset(context).bottom),
      ],
    ),
  );
}
