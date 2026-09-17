import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import 'home_page.dart';
import 'onboarding_flow.dart';

/// 000 스플래시 — shown on a cold start only. The three dots merge into the
/// 한방 mark, and after about 2.5 s the app dissolves into 001 (or 101 once the
/// agent has linked their platforms).
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.store});

  final AppStore store;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    final loading = widget.store.loaded
        ? Future<void>.value()
        : widget.store.load();
    Future.wait([loading, Future<void>.delayed(Motion.splashHold)]).then((_) {
      if (mounted) _next();
    });
  }

  void _next() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: Motion.dissolve,
        pageBuilder: (_, _, _) => widget.store.onboarded
            ? HomePage(store: widget.store)
            : OnboardingFlow(store: widget.store),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Motion.dissolveCurve,
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColor.bgPage,
    body: Center(child: SplashMerge()),
  );
}
