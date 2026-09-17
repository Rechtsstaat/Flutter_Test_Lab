import 'package:flutter/material.dart';

import '../fields.dart';

/// Seed Palette v0.2 — the raw values from the 한,방 디자인 file's "System"
/// frame (02_하이파이). The file's own rule is that screens never name these:
/// they go through [AppColor], so a seed can move without a screen noticing.
abstract final class _Seed {
  static const brand50 = Color(0xfff7f3fc);
  static const brand400 = Color(0xffa27cd1);
  static const brand600 = Color(0xff6842a8);
  static const brand700 = Color(0xff55338d);
  static const brand800 = Color(0xff462c72);

  static const neutral0 = Color(0xffffffff);
  static const neutral50 = Color(0xfff8f9fb);
  static const neutral100 = Color(0xfff2f4f7);
  static const neutral200 = Color(0xffe5e8ed);
  static const neutral300 = Color(0xffd2d6de);
  static const neutral500 = Color(0xff848c9a);
  static const neutral600 = Color(0xff626a78);
  static const neutral700 = Color(0xff4d5360);
  static const neutral900 = Color(0xff20232b);

  static const success = Color(0xff2563eb);
  static const warning = Color(0xffa85d00);
  static const error = Color(0xffc9363e);
  static const info = Color(0xff0e7490);
}

/// Semantic Color v0.2. Names follow the file one-to-one
/// (`text/primary` → [textPrimary]) so a token read off a Dev Spec card can be
/// found here without translation.
abstract final class AppColor {
  static const textPrimary = _Seed.neutral900;
  static const textSecondary = _Seed.neutral700;
  static const textTertiary = _Seed.neutral600;
  static const textDisabled = _Seed.neutral500;
  static const textOnColor = _Seed.neutral0;
  static const textBrand = _Seed.brand600;
  static const textBrandStrong = _Seed.brand800;

  static const bgPage = _Seed.neutral50;
  static const bgSurface = _Seed.neutral0;
  static const bgSubtle = _Seed.neutral100;
  static const bgBrandSubtle = _Seed.brand50;
  static const bgInverse = _Seed.neutral700;
  static const bgOverlay = _Seed.neutral900;

  static const borderDefault = _Seed.neutral300;
  static const borderSubtle = _Seed.neutral200;
  static const borderFocus = _Seed.brand400;
  static const borderSelected = _Seed.brand600;
  static const borderFaint = _Seed.neutral100;

  static const actionPrimary = _Seed.brand600;
  static const actionPrimaryHover = _Seed.brand700;
  static const actionPrimaryPressed = _Seed.brand800;
  static const actionPrimaryContent = _Seed.neutral0;
  static const actionLink = _Seed.brand800;
  static const actionLinkSubtle = _Seed.brand400;

  static const iconBrand = _Seed.brand700;
  static const iconSecondary = _Seed.neutral500;
  static const iconTertiary = _Seed.neutral600;
  static const indicatorInactive = _Seed.neutral500;

  /// The overview frame assigns these to states, not to feelings: success is
  /// 등록 완료 / 광고 중, warning is 확인 필요, error is 연결 오류.
  static const statusSuccess = _Seed.success;
  static const statusWarning = _Seed.warning;
  static const statusError = _Seed.error;
  static const statusInfo = _Seed.info;

  /// The dimmed backdrop behind the 301 bottom sheet.
  static Color get scrim => bgOverlay.withValues(alpha: 0.48);
}

extension PlatformPalette on ListingPlatform {
  /// The swatches the hi-fi keeps next to its overview frame.
  Color get color => switch (this) {
    ListingPlatform.zigbang => const Color(0xffff641e),
    ListingPlatform.dabang => const Color(0xff326cf9),
    ListingPlatform.daangn => const Color(0xffff6f0f),
  };

  /// Platform icons sit on their own colour at 10%.
  Color get tint => color.withValues(alpha: 0.1);

  /// The single glyph printed inside the small platform icon.
  String get glyph => switch (this) {
    ListingPlatform.zigbang => '직',
    ListingPlatform.dabang => '다',
    ListingPlatform.daangn => '당',
  };
}

/// Foundation v0.2 typography: "크기·행간·정보 위계가 먼저 보이도록". Eight roles,
/// each with the size / line height / weight the System frame lists.
abstract final class AppText {
  static const display = TextStyle(
    fontSize: 28,
    height: 38 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppColor.textPrimary,
  );
  static const heading = TextStyle(
    fontSize: 24,
    height: 34 / 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColor.textPrimary,
  );
  static const title = TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColor.textPrimary,
  );
  static const body = TextStyle(
    fontSize: 16,
    height: 26 / 16,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
    color: AppColor.textPrimary,
  );
  static const bodyStrong = TextStyle(
    fontSize: 16,
    height: 26 / 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColor.textPrimary,
  );
  static const label = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: AppColor.textSecondary,
  );
  static const bodySmall = TextStyle(
    fontSize: 14,
    height: 22 / 14,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    color: AppColor.textSecondary,
  );
  static const caption = TextStyle(
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w400,
    color: AppColor.textTertiary,
  );
}

/// Spacing & Radius from the same frame. Screens use these steps only.
abstract final class Space {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
  static const s40 = 40.0;
  static const s48 = 48.0;

  /// Every hi-fi screen keeps 16 on each side.
  static const gutter = s16;
}

abstract final class Radii {
  static const r8 = 8.0;
  static const r12 = 12.0;
  static const r16 = 16.0;
  static const r24 = 24.0;
}

/// Motion stays narrow. The splash dissolve and the toast hold are the two
/// timings the Dev Spec cards state outright.
abstract final class Motion {
  static const quick = Duration(milliseconds: 180);
  static const dissolve = Duration(milliseconds: 220);
  static const base = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 520);

  /// 000: "약 2.5s 후 001 플랫폼 연동 선택 으로 이동".
  static const splashHold = Duration(milliseconds: 2500);

  /// 2021: "약 50000 ms 유지후 토스트 내려옴 (모든 토스트 동일)". Read as 5 s —
  /// a guidance toast that sits for fifty seconds would outlast the input it
  /// describes.
  static const toastHold = Duration(seconds: 5);

  static const enter = Curves.easeOutCubic;
  static const settle = Curves.easeOutBack;
  static const exit = Curves.easeInCubic;
  static const dissolveCurve = Curves.easeInOut;
}
