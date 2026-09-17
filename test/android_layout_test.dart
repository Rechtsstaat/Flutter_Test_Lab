import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/android_layout.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('bottom inset is applied only on Android ($platform)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      late EdgeInsets inset;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: 48)),
          child: Builder(
            builder: (context) {
              inset = androidBottomInset(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        inset,
        platform == TargetPlatform.android
            ? const EdgeInsets.only(bottom: 48)
            : EdgeInsets.zero,
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
