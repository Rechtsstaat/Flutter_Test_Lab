import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/fields.dart';
import 'package:jibang_listing_test/mirror_session.dart';

/// The rules 한방 uses to tell "the platform served the page" from "the
/// platform sent me back to sign in".
///
/// Getting this wrong is expensive in a way nothing here can see on its own —
/// see mirror_browser_test.dart — but the pieces are plain functions, and the
/// URL table is the thing that has to be right before any of it matters.
void main() {
  group('mirrorDirectory', () {
    test('reads the 308 and the bare form as one page', () {
      // The mirror serves .../oneroom/index.html as a 308 to .../oneroom/, so
      // the URL that finishes loading never equals the one that was asked for.
      expect(
        mirrorDirectory(Uri.parse('https://m.test/zigbang/form/oneroom/')),
        '/zigbang/form/oneroom/',
      );
      expect(
        mirrorDirectory(
          Uri.parse('https://m.test/zigbang/form/oneroom/index.html'),
        ),
        '/zigbang/form/oneroom/',
      );
      expect(
        mirrorDirectory(Uri.parse('https://m.test/zigbang/form/oneroom')),
        '/zigbang/form/oneroom/',
      );
    });

    test('ignores the query, which 직방 carries on its ad list', () {
      expect(
        mirrorDirectory(
          Uri.parse('https://m.test/zigbang/ads/oneroom/?status=open'),
        ),
        mirrorDirectory(Uri.parse('https://m.test/zigbang/ads/oneroom/')),
      );
    });

    test('separates a gate from the page it guards', () {
      // This difference is the whole signal: 직방 answers a signed-out form
      // with its landing page, 다방 with its login.
      for (final platform in ListingPlatform.values) {
        final form = mirrorDirectory(Uri.parse(platform.formUrl));
        final login = mirrorDirectory(Uri.parse(platform.loginUrl));
        expect(form, isNot(login));
      }
    });
  });

  group('platform URLs', () {
    test("every page 0011 and 2022 open lives on the form's host", () {
      for (final site in PlatformSite.values) {
        for (final platform in ListingPlatform.values) {
          final urls = platform.urlsOn(site);
          for (final url in [urls.login, urls.dashboard, urls.listings]) {
            expect(Uri.parse(url).host, urls.host, reason: url);
            expect(platform.siteOf(Uri.parse(url)), isNotNull, reason: url);
          }
        }
      }
    });

    test('the app talks to the live 직방 CEO and 다방프로 by default', () {
      expect(PlatformSite.active, PlatformSite.live);
      expect(
        Uri.parse(ListingPlatform.zigbang.formUrl).host,
        'ceo.zigbang.com',
      );
      expect(
        Uri.parse(ListingPlatform.dabang.formUrl).host,
        'pro.dabangapp.com',
      );
      for (final platform in livePlatforms) {
        for (final url in [
          platform.formUrl,
          platform.loginUrl,
          platform.dashboardUrl,
          platform.listingsUrl,
        ]) {
          expect(url, isNot(contains(mirrorHost)), reason: url);
        }
      }
    });

    test('a gated platform signs in somewhere other than its dashboard', () {
      // 직방 and 다방 gate everything, so 0011 has to open their own sign-in
      // page. Pointing it at the dashboard is what made the app report
      // 연동 완료 while the WebView sat on the landing page.
      for (final platform in [
        ListingPlatform.zigbang,
        ListingPlatform.dabang,
      ]) {
        expect(
          platform.loginUrl,
          isNot(platform.dashboardUrl),
          reason: '${platform.label} needs its own sign-in page',
        );
        expect(platform.loginUrl, contains('login'));
      }
      // 당근's mirror has no gate; its dashboard is where onboarding starts
      // and ends, and pretending otherwise would hang on a page that is not
      // there.
      expect(
        ListingPlatform.daangn.loginUrl,
        ListingPlatform.daangn.dashboardUrl,
      );
    });
  });

  group('signInLost', () {
    test('names the platform and points at where to fix it', () {
      for (final platform in ListingPlatform.values) {
        final message = signInLost(platform);
        expect(message, contains(platform.label));
        expect(message, contains('연동'));
      }
    });
  });
}
