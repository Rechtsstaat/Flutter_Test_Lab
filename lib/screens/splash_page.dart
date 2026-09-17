import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../design/tokens.dart';
import 'home_page.dart';
import 'onboarding_flow.dart';

/// 0. 스플래시 — the blue opener. It waits for the store so the tap can go
/// straight to the right place instead of flashing an empty home list.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.store});

  final AppStore store;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.slow,
  )..forward();

  @override
  void initState() {
    super.initState();
    if (!widget.store.loaded) widget.store.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: Motion.base,
        pageBuilder: (_, _, _) => widget.store.onboarded
            ? HomePage(store: widget.store)
            : OnboardingFlow(store: widget.store),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Brand.blue,
    body: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _start,
      // Scaffold hands its body loose constraints, so a Column of centred
      // content would otherwise shrink to its widest child and hug the left
      // edge — taking the tap target with it.
      child: SizedBox.expand(
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 4),
              ScaleTransition(
                scale: Tween<double>(begin: 0.76, end: 1).animate(
                  CurvedAnimation(parent: _controller, curve: Motion.settle),
                ),
                child: FadeTransition(
                  opacity: _controller,
                  child: Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: const Text(
                      '한방',
                      style: TextStyle(
                        color: Brand.blue,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              FadeTransition(
                opacity: CurvedAnimation(
                  parent: _controller,
                  curve: const Interval(0.45, 1, curve: Curves.easeOut),
                ),
                child: const Text(
                  '매물 관리를 한방에',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(flex: 5),
              // The hint breathes rather than sitting still: the splash has no
              // other affordance, so it has to read as waiting for a tap.
              _BreathingHint(controller: _controller),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BreathingHint extends StatefulWidget {
  const _BreathingHint({required this.controller});

  final AnimationController controller;

  @override
  State<_BreathingHint> createState() => _BreathingHintState();
}

class _BreathingHintState extends State<_BreathingHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: Motion.breath,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_breath, widget.controller]),
    builder: (context, _) => Opacity(
      opacity:
          widget.controller.value *
          (0.45 + 0.35 * Curves.easeInOut.transform(_breath.value)),
      child: const Text(
        '화면을 눌러 시작하기',
        style: TextStyle(color: Colors.white, fontSize: 14),
      ),
    ),
  );
}
