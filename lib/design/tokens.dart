import 'package:flutter/material.dart';

import '../fields.dart';

/// The palette sampled directly from the "최종 로우파이" section of the
/// 한,방 디자인 Figma file. Every colour here appears in those screens; nothing
/// is invented, so re-sampling the lo-fi should keep producing these values.
abstract final class Brand {
  static const blue = Color(0xff4880ee);
  static const blueDim = Color(0xff719cf2);
  static const blueTint = Color(0xffe9effd);
  static const blueFaint = Color(0xfff8fbff);

  static const ink = Color(0xff1a1f27);
  static const inkMuted = Color(0xff8a9099);
  static const inkFaint = Color(0xffa1a4a8);

  static const canvas = Color(0xfff3f4f6);
  static const surface = Color(0xffffffff);
  static const placeholder = Color(0xffeceef2);
  static const hairline = Color(0xffe6e8ec);

  static const danger = Color(0xffe2483d);
  static const dangerTint = Color(0xfffdf0ef);
  static const success = Color(0xff2f9e63);
}

extension PlatformPalette on ListingPlatform {
  /// The badge colour each platform carries throughout the lo-fi.
  Color get color => switch (this) {
    ListingPlatform.zigbang => const Color(0xffed7446),
    ListingPlatform.dabang => const Color(0xff5638df),
    ListingPlatform.daangn => const Color(0xffef8549),
  };

  /// The tint the platform chips use on the 나의 광고 cards.
  Color get tint => switch (this) {
    ListingPlatform.zigbang => const Color(0xfffef7f4),
    ListingPlatform.dabang => const Color(0xfff5f3fc),
    ListingPlatform.daangn => const Color(0xfffef8f4),
  };

  /// The single glyph the lo-fi prints inside the rounded platform badge.
  String get glyph => switch (this) {
    ListingPlatform.zigbang => '직',
    ListingPlatform.dabang => '다',
    ListingPlatform.daangn => '당',
  };
}

/// Type ramp read off the lo-fi: one display size for the "…해 주세요" screen
/// openers, one card title, one body, one caption.
abstract final class Type {
  static const display = TextStyle(
    fontSize: 24,
    height: 1.35,
    fontWeight: FontWeight.w800,
    color: Brand.ink,
    letterSpacing: -0.4,
  );
  static const title = TextStyle(
    fontSize: 18,
    height: 1.35,
    fontWeight: FontWeight.w700,
    color: Brand.ink,
    letterSpacing: -0.2,
  );
  static const price = TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w800,
    color: Brand.blue,
    letterSpacing: -0.2,
  );
  static const body = TextStyle(fontSize: 15, height: 1.5, color: Brand.ink);
  static const bodyMuted = TextStyle(
    fontSize: 15,
    height: 1.5,
    color: Brand.inkMuted,
  );
  static const label = TextStyle(
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w700,
    color: Brand.ink,
  );
  static const caption = TextStyle(
    fontSize: 12.5,
    height: 1.4,
    color: Brand.inkMuted,
  );
}

abstract final class Insets {
  static const gutter = 20.0;
  static const card = 16.0;
  static const radiusCard = 16.0;
  static const radiusField = 12.0;
  static const radiusPill = 999.0;
}

/// Motion is deliberately narrow: the lo-fi only ever needs an entrance, a
/// "work is happening" loop, and a settle on completion. Reusing three curves
/// keeps unrelated screens from drifting apart.
abstract final class Motion {
  static const quick = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 520);
  static const breath = Duration(milliseconds: 1500);

  static const enter = Curves.easeOutCubic;
  static const settle = Curves.easeOutBack;
  static const exit = Curves.easeInCubic;
}
