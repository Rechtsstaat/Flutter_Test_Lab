import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/fields.dart';
import 'package:jibang_listing_test/mobile_layout.dart';

/// What the script is allowed to be: scoped to the known forms, reversible,
/// and never a substitute for the agent's own press.
///
/// Nothing here can tell whether a button ends up on the screen — reading CSS
/// cannot do that, and believing otherwise is how 다방's 등록 완료 spent a
/// release 499px past the right edge with this suite green. Geometry belongs
/// to mirror_browser_test.dart, which asks a real browser.
void main() {
  group('mirrorMobileLayoutScript', () {
    test('covers this platform on the mirror, and nothing else', () {
      for (final platform in ListingPlatform.values) {
        final form = Uri.parse(platform.formUrl);

        // Every page 0011 and the publish flow put in front of the agent.
        for (final url in [
          platform.formUrl,
          platform.loginUrl,
          platform.dashboardUrl,
          platform.listingsUrl,
        ]) {
          expect(
            mirrorMobileLayoutScript(platform, Uri.parse(url)),
            isNotNull,
            reason: url,
          );
        }
        // The mirror serves the form's index.html as a 308 to the directory.
        expect(
          mirrorMobileLayoutScript(
            platform,
            form.replace(path: '${form.path}index.html'),
          ),
          isNotNull,
        );

        expect(
          mirrorMobileLayoutScript(platform, form.replace(host: 'example.com')),
          isNull,
        );
        expect(
          mirrorMobileLayoutScript(platform, form.replace(path: '/dashboard/')),
          isNull,
        );
        // One platform's profile must never dress another's page: the Kakao
        // postcode frame and the other two mirrors are none of its business.
        for (final other in ListingPlatform.values) {
          if (other == platform) continue;
          expect(
            mirrorMobileLayoutScript(platform, Uri.parse(other.formUrl)),
            isNull,
            reason: '${platform.label} styled ${other.label}',
          );
        }
      }
    });

    test('leaves the platform controls and their handlers alone', () {
      for (final platform in ListingPlatform.values) {
        final script = mirrorMobileLayoutScript(
          platform,
          Uri.parse(platform.formUrl),
        )!;

        // Restyling only. Anything that rebuilt a node would drop the React
        // listener on it, and anything that pressed one would forge the
        // agent's 등록.
        expect(script, isNot(contains('cloneNode')));
        expect(script, isNot(contains('replaceWith')));
        expect(script, isNot(contains('.click()')));
        expect(script, isNot(contains('innerHTML')));
        expect(script, isNot(contains('dispatchEvent')));
        // The only node it ever takes out is the stylesheet it put in.
        expect(
          RegExp(r'\.remove\(\)').allMatches(script).length,
          1,
          reason: 'it removes something other than its own <style>',
        );
        expect(script, contains('document.getElementById(styleId)?.remove()'));
      }
    });

    test('installs once, re-runs on change, and takes itself back out', () {
      final script = mirrorMobileLayoutScript(
        ListingPlatform.zigbang,
        Uri.parse(ListingPlatform.zigbang.formUrl),
      )!;

      expect(script, contains('window.__flrMobileFormLayout'));
      expect(script, contains('MutationObserver'));
      expect(script, contains('if (!inScope())'));
      expect(script, contains('cleanup();'));
      expect(script, contains("removeEventListener('popstate'"));
      expect(script, contains('location.host === config.host'));
      expect(script, contains('meta[name="viewport"]'));
      // A second install must not leave the first one's observer or its
      // pending pass running.
      expect(script, contains('previous.observer?.disconnect()'));
      expect(script, contains('clearTimeout(previous.state.timer)'));
      // The pass reads computed styles across the whole form; a frame-rate
      // trigger would run it against every keystroke of the adapter.
      expect(
        script,
        contains('setTimeout(() => { state.timer = 0; apply(); }'),
      );
      expect(script, isNot(contains('requestAnimationFrame')));
      expect(script, contains(r"replace(/\s+/g, ' ')"));
      expect(script, isNot(contains(r"replace(/\\s+/g, ' ')")));
    });

    test('decides what is too wide by measuring, not by class name', () {
      for (final platform in ListingPlatform.values) {
        final script = mirrorMobileLayoutScript(
          platform,
          Uri.parse(platform.formUrl),
        )!;

        // The desktop width is pinned above the content, so the sweep has to
        // cover the whole page rather than one subtree.
        expect(script, contains('document.body.querySelectorAll'));
        expect(script, contains('data-flr-mobile-pinned'));
        // Three ways a box misses the screen, all measured.
        expect(script, contains('minWidth > width'));
        expect(script, contains('rect.right > width + 1'));
        expect(script, contains('element.scrollWidth > element.clientWidth'));
        // A percentage clamp is dropped inside an indefinite grid track, so
        // the release has to name a length the viewport always defines.
        expect(script, contains('max-width: 100vw !important'));
        // Tailwind's own phone layout is not ours to override: an unprefixed
        // grid-cols-3 IS the phone layout, md:* is already dormant at 390px.
        expect(script, isNot(contains('[class*="grid-cols-"]')));
        expect(script, isNot(contains('[class*="md:grid-cols-"]')));
        expect(script, isNot(contains('[class*="md:flex-row"]')));
      }
    });

    test('gives the 등록 bar the height the form has to clear', () {
      final script = mirrorMobileLayoutScript(
        ListingPlatform.dabang,
        Uri.parse(ListingPlatform.dabang.formUrl),
      )!;

      expect(script, contains("const barProperty = '--flr-mobile-bar';"));
      expect(script, contains('findSubmitBar'));
      expect(script, contains('data-flr-mobile-submit-bar'));
      expect(script, contains('var(--flr-mobile-bar'));
      // 다방's bar is the desktop sidebar. Sticky keeps it inside the 1200px
      // content row it belongs to; only fixed answers to the viewport.
      expect(
        script,
        contains(
          '[class*="styled__StickyContainer-sc-h5ond6-"] {\n'
          '        position: fixed !important;',
        ),
      );
      // 해당 항목으로 이동 survives as one scrolling row of chips.
      expect(script, contains('overflow-x: auto !important;'));
      expect(script, contains('flex-wrap: nowrap !important;'));
      expect(script, contains('[class*="styled__ItemBtn-sc-33x7dx-"]'));
    });

    test('keeps a modal above the bar and lets a tall one scroll', () {
      final script = mirrorMobileLayoutScript(
        ListingPlatform.daangn,
        Uri.parse(ListingPlatform.daangn.formUrl),
      )!;

      expect(script, contains('data-flr-mobile-dialog-open'));
      expect(script, contains('dialog.hidden'));
      expect(script, contains("getAttribute('aria-hidden') === 'true'"));
      expect(script, contains("computed.display !== 'none'"));
      expect(script, contains('dialog.getClientRects().length > 0'));
      expect(script, contains('pointer-events: none !important'));
      // A capped height with no scroller hides the sheet's own confirm.
      expect(
        script,
        contains(
          'max-height: calc(100dvh - 24px) !important;\n'
          '      overflow-x: hidden !important;',
        ),
      );
      expect(script, contains('overflow-y: auto !important;'));
      expect(script, contains('z-index: 40 !important'));
      expect(script, isNot(contains('z-index: 2147483000')));
    });

    test('embeds platform-specific profiles and original submit labels', () {
      for (final platform in ListingPlatform.values) {
        final script = mirrorMobileLayoutScript(
          platform,
          Uri.parse(platform.formUrl),
        )!;

        expect(script, contains(platform.name));
        for (final label in platform.submitLabels) {
          expect(script, contains(label));
        }
      }
    });

    test('generates syntactically valid JavaScript for every platform', () {
      for (final platform in ListingPlatform.values) {
        final script = mirrorMobileLayoutScript(
          platform,
          Uri.parse(platform.formUrl),
        )!;
        final temp = File(
          '${Directory.systemTemp.path}/mobile_layout_${platform.name}_'
          '${DateTime.now().microsecondsSinceEpoch}.js',
        );
        try {
          temp.writeAsStringSync(script);
          final result = Process.runSync('node', ['--check', temp.path]);
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
        } finally {
          if (temp.existsSync()) temp.deleteSync();
        }
      }
    });
  });
}
