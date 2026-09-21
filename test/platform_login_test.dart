// 플랫폼 로그인 — 「로그인 화면으로 튕겼나」와 「세션이 있나」를 확인하는 부분.
//
// 웹뷰 없이 확인할 수 있는 만큼만 본다. 값의 근거는 미러 실측이다(2026-09-18):
// 다방 `auth_key` 는 HttpOnly 라 JS 로 못 보고, 직방 `ceo_zauth` 는 페이지가 심어 보인다.
import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/fields.dart';
import 'package:jibang_listing_test/mirror_session.dart';

void main() {
  group('로그인 화면으로 튕겼는지 — 실물', () {
    bool signedOut(ListingPlatform platform, String url) =>
        platform.isSignedOut(Uri.parse(url));

    test('직방은 랜딩(/intro)과 account.zigbang.com 로그인이 「로그인 안 됨」이다', () {
      const zigbang = ListingPlatform.zigbang;
      expect(signedOut(zigbang, 'https://ceo.zigbang.com/intro'), isTrue);
      expect(
        signedOut(zigbang, 'https://ceo.zigbang.com/account/login/email'),
        isTrue,
      );
      // 로그인은 도메인을 건너간다 — OAuth 화면도 로그인 화면이다.
      expect(
        signedOut(zigbang, 'https://account.zigbang.com/login/email'),
        isTrue,
      );
      expect(signedOut(zigbang, 'https://ceo.zigbang.com/dashboard'), isFalse);
      expect(
        signedOut(zigbang, 'https://ceo.zigbang.com/ads/oneroom/ad-item/new'),
        isFalse,
      );
    });

    test('다방프로는 랜딩 `/` 과 /login 이 그 자리다', () {
      const dabang = ListingPlatform.dabang;
      // 로그인 안 된 /dashboard · /form/room 은 랜딩 `/` 으로 주소만 바뀐다 (실측).
      expect(signedOut(dabang, 'https://pro.dabangapp.com/'), isTrue);
      expect(signedOut(dabang, 'https://pro.dabangapp.com'), isTrue);
      expect(signedOut(dabang, 'https://pro.dabangapp.com/login'), isTrue);
      expect(signedOut(dabang, 'https://pro.dabangapp.com/dashboard'), isFalse);
      expect(signedOut(dabang, 'https://pro.dabangapp.com/form/room'), isFalse);
    });

    test('다른 플랫폼·다른 호스트의 로그인 주소에는 반응하지 않는다', () {
      const dabang = ListingPlatform.dabang;
      expect(signedOut(dabang, 'https://ceo.zigbang.com/intro'), isFalse);
      expect(signedOut(dabang, 'https://example.com/login'), isFalse);
    });

    test('당근은 로그인이 없다 (수집 없음)', () {
      const daangn = ListingPlatform.daangn;
      expect(daangn.hasLogin, isFalse);
      expect(signedOut(daangn, daangn.dashboardUrl), isFalse);
    });
  });

  group('랜딩과 로그인 화면을 가른다', () {
    bool loginScreen(ListingPlatform platform, String url) =>
        platform.urls.isLoginScreen(Uri.parse(url));

    test('직방 랜딩은 로그인 화면이 아니고, account.zigbang.com 은 그렇다', () {
      const zigbang = ListingPlatform.zigbang;
      expect(loginScreen(zigbang, 'https://ceo.zigbang.com/intro'), isFalse);
      expect(
        loginScreen(zigbang, 'https://account.zigbang.com/login/email'),
        isTrue,
      );
    });

    test('다방프로 랜딩 `/` 은 로그인 화면이 아니고, /login 은 그렇다', () {
      const dabang = ListingPlatform.dabang;
      expect(loginScreen(dabang, 'https://pro.dabangapp.com/'), isFalse);
      expect(loginScreen(dabang, 'https://pro.dabangapp.com/login'), isTrue);
    });
  });

  group('로그인 화면으로 튕겼는지 — 미러', () {
    bool signedOut(ListingPlatform platform, String path) => platform
        .urlsOn(PlatformSite.mirror)
        .isSignedOut(Uri.parse('https://$mirrorHost$path'));

    test('직방은 랜딩과 로그인 화면 둘 다 「로그인 안 됨」이다', () {
      const zigbang = ListingPlatform.zigbang;
      expect(signedOut(zigbang, '/zigbang/intro/'), isTrue);
      expect(signedOut(zigbang, '/zigbang/account/login/email/'), isTrue);
      expect(signedOut(zigbang, '/zigbang/'), isFalse);
      expect(signedOut(zigbang, '/zigbang/form/oneroom/'), isFalse);
    });

    test('다방은 로그인 화면이 그 자리다', () {
      const dabang = ListingPlatform.dabang;
      expect(signedOut(dabang, '/dabang/login/'), isTrue);
      expect(signedOut(dabang, '/dabang/'), isFalse);
      expect(signedOut(dabang, '/dabang/form/room/'), isFalse);
      expect(signedOut(dabang, '/zigbang/intro/'), isFalse);
    });
  });

  group('세션 확인 방법이 플랫폼마다 다르다', () {
    test('직방은 쿠키를 눈으로 본다 — document.cookie 에 보이기 때문', () {
      expect(ListingPlatform.zigbang.sessionCheck, SessionCheck.cookieVisible);
      final script = sessionProbeScript(ListingPlatform.zigbang);
      expect(script, contains('document.cookie'));
      expect(script, contains('ceo_zauth='));
      expect(script, isNot(contains('fetch(')));
    });

    test('다방은 플랫폼에 묻는다 — auth_key 가 HttpOnly 라 볼 수 없다', () {
      expect(ListingPlatform.dabang.sessionCheck, SessionCheck.platformAsks);
      final script = sessionProbeScript(ListingPlatform.dabang);
      expect(script, contains('"/api/v2/user/login/check"'));
      // 코드가 아니라 본문으로 가른다. 실물은 `result`, 미러는 `isLogin` 에 싣는다.
      expect(script, contains('body.result === true'));
      expect(script, contains('body.isLogin'));
      expect(script, isNot(contains('document.cookie')));
    });

    test('물어보지 못하면 「모르겠다」고 답한다 — 화면으로 판단하는 갈래', () {
      expect(sessionProbeScript(ListingPlatform.dabang), contains("'unknown'"));
      expect(sessionProbeScript(ListingPlatform.daangn), contains("'unknown'"));
    });

    test('모든 갈래가 SessionProbe 로 답한다', () {
      for (final platform in ListingPlatform.values) {
        expect(
          sessionProbeScript(platform),
          contains('window.SessionProbe.postMessage'),
        );
      }
    });
  });
}
