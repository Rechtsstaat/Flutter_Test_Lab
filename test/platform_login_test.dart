// 플랫폼 로그인 — 「로그인 화면으로 튕겼나」와 「세션이 있나」를 확인하는 부분.
//
// 웹뷰 없이 확인할 수 있는 만큼만 본다. 값의 근거는 미러 실측이다(2026-09-18):
// 다방 `auth_key` 는 HttpOnly 라 JS 로 못 보고, 직방 `ceo_zauth` 는 페이지가 심어 보인다.
import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/fields.dart';
import 'package:jibang_listing_test/mirror_session.dart';

void main() {
  group('로그인 화면으로 튕겼는지', () {
    test('직방은 랜딩과 로그인 화면 둘 다 「로그인 안 됨」이다', () {
      const zigbang = ListingPlatform.zigbang;
      expect(zigbang.isSignedOut(Uri.parse('https://m.test/zigbang/intro/')), isTrue);
      expect(
        zigbang.isSignedOut(Uri.parse('https://m.test/zigbang/account/login/email/')),
        isTrue,
      );
      expect(zigbang.isSignedOut(Uri.parse('https://m.test/zigbang/')), isFalse);
      expect(
        zigbang.isSignedOut(Uri.parse('https://m.test/zigbang/form/oneroom/')),
        isFalse,
      );
    });

    test('다방은 로그인 화면이 그 자리다', () {
      const dabang = ListingPlatform.dabang;
      expect(dabang.isSignedOut(Uri.parse('https://m.test/dabang/login/')), isTrue);
      expect(dabang.isSignedOut(Uri.parse('https://m.test/dabang/')), isFalse);
      expect(
        dabang.isSignedOut(Uri.parse('https://m.test/dabang/form/room/')),
        isFalse,
      );
    });

    test('다른 플랫폼의 로그인 주소에는 반응하지 않는다', () {
      expect(
        ListingPlatform.dabang.isSignedOut(Uri.parse('https://m.test/zigbang/intro/')),
        isFalse,
      );
    });

    test('당근은 로그인이 없다 (수집 없음)', () {
      expect(ListingPlatform.daangn.hasLogin, isFalse);
      expect(ListingPlatform.daangn.isSignedOut(Uri.parse('https://m.test/daangn/')), isFalse);
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
      expect(script, contains('/dabang/api/v2/user/login/check'));
      expect(script, contains('body.isLogin'), reason: '코드가 아니라 본문으로 가른다');
      expect(script, isNot(contains('document.cookie')));
    });

    test('물어보지 못하면 「모르겠다」고 답한다 — 화면으로 판단하는 갈래', () {
      expect(sessionProbeScript(ListingPlatform.dabang), contains("'unknown'"));
      expect(sessionProbeScript(ListingPlatform.daangn), contains("'unknown'"));
    });

    test('모든 갈래가 SessionProbe 로 답한다', () {
      for (final platform in ListingPlatform.values) {
        expect(sessionProbeScript(platform), contains('window.SessionProbe.postMessage'));
      }
    });
  });
}
