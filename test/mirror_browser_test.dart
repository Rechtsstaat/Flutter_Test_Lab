@Tags(['render'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/fields.dart';
import 'package:jibang_listing_test/mobile_layout.dart';

/// What only a browser can answer: will the mirror serve the page the app
/// asks for, and does the 등록 button land where a thumb can reach it.
///
/// Both questions had already been answered wrong in shipped code while every
/// offline assertion passed. 다방's 등록 완료 sat 499px past the right edge of
/// a 390px viewport, clipped by the page's own `overflow-x: hidden`. And the
/// 0011 login was a stand-in of 한방's own that set no platform session, so
/// 직방 and 다방 turned every later request away and 매물 등록 spent its whole
/// timeout on the mirror's landing page. Neither is visible from the CSS or
/// the Dart; both are obvious the moment a browser loads the thing.
///
/// Needs Chrome and the mirror. Without either the probe says so and these
/// skip, so an offline machine is not a failing one.
void main() {
  const viewport = 390;
  final probe = File('test/tools/mirror_layout_probe.mjs');

  /// Runs the harness and returns its report, or null when it could not run
  /// (already marked skipped).
  Future<Map<String, dynamic>?> run(List<String> extra) async {
    final ProcessResult result;
    try {
      result = await Process.run('node', [probe.path, ...extra]);
    } on ProcessException catch (error) {
      markTestSkipped('node is not available: ${error.message}');
      return null;
    }
    if (result.exitCode != 0) {
      markTestSkipped('probe exited ${result.exitCode}: ${result.stderr}');
      return null;
    }
    final report =
        jsonDecode('${result.stdout}'.trim()) as Map<String, dynamic>;
    if (report['skip'] != null) {
      markTestSkipped('${report['skip']}');
      return null;
    }
    return report;
  }

  List<String> urlsOf(ListingPlatform platform) => [
    '--login=${platform.loginUrl}',
    '--dashboard=${platform.dashboardUrl}',
    '--form=${platform.formUrl}',
    '--listings=${platform.listingsUrl}',
  ];

  group('the mirror serves what the app asks for', () {
    for (final platform in ListingPlatform.values) {
      test('${platform.label} signs in and then opens every page', () async {
        final report = await run(['--job=routes', ...urlsOf(platform)]);
        if (report == null) return;

        // 0011 has to be able to reach the sign-in page without a session —
        // it is the one page a fresh install can open.
        final signedOut = report['signedOut'] as Map<String, dynamic>;
        final login = signedOut['login'] as Map<String, dynamic>;
        expect(
          login['landed'],
          login['wanted'],
          reason:
              'loginUrl itself bounced to ${login['landed']} '
              '(${login['title']})',
        );

        // MirrorLogin.linked keys on arriving at the dashboard, so signing in
        // has to actually put the WebView there.
        final afterLogin = report['afterLogin'] as Map<String, dynamic>;
        expect(
          afterLogin['landed'],
          afterLogin['wanted'],
          reason:
              'signing in left the WebView on ${afterLogin['landed']} '
              '(${afterLogin['title']}) instead of the dashboard — '
              'MirrorLogin would never report 연동 완료',
        );

        // And the session that sign-in leaves behind has to carry: this is
        // precisely what the old stand-in login never did. The dashboard row
        // doubles as the re-linking case — MirrorLogin opens the dashboard
        // first, and a session still good means the agent types nothing.
        final signedIn = report['signedIn'] as Map<String, dynamic>;
        expect(
          signedIn['dashboard'],
          isNotNull,
          reason: 'the dashboard is what MirrorLogin opens and waits for',
        );
        for (final entry in signedIn.entries) {
          final page = entry.value as Map<String, dynamic>;
          expect(
            page['landed'],
            page['wanted'],
            reason:
                '${entry.key} bounced to ${page['landed']} (${page['title']}) '
                'even after signing in',
          );
        }
      }, timeout: const Timeout(Duration(minutes: 3)));
    }

    test('a gated platform really does turn a signed-out form away', () async {
      // The premise behind failing fast in MirrorSession.onPage. If the mirror
      // ever stops gating, that failure would be dead code and this says so.
      final report = await run([
        '--job=routes',
        ...urlsOf(ListingPlatform.dabang),
      ]);
      if (report == null) return;

      final signedOut = report['signedOut'] as Map<String, dynamic>;
      final form = signedOut['form'] as Map<String, dynamic>;
      expect(
        form['landed'],
        isNot(form['wanted']),
        reason:
            '다방 served its form without a session — MirrorSession no longer '
            'needs to fail fast on a bounce',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('the mobile layout makes the sign-in page usable', () {
    for (final platform in ListingPlatform.values) {
      test('${platform.label} 로그인 controls are reachable', () async {
        final script = File(
          '${Directory.systemTemp.path}/flr_signin_${platform.name}_'
          '${DateTime.now().microsecondsSinceEpoch}.js',
        );
        Map<String, dynamic>? report;
        try {
          script.writeAsStringSync(
            mirrorMobileLayoutScript(platform, Uri.parse(platform.loginUrl))!,
          );
          report = await run([
            '--job=signin',
            ...urlsOf(platform),
            '--script=${script.path}',
            '--width=$viewport',
            '--height=844',
          ]);
        } finally {
          if (script.existsSync()) script.deleteSync();
        }
        if (report == null) return;

        // 당근 has no sign-in page; its dashboard just has to fit.
        final controls = (report['controls'] as List)
            .cast<Map<String, dynamic>>();
        for (final control in controls) {
          expect(
            control['onScreen'],
            isTrue,
            reason:
                '${control['what']} sits at ${control['rect']} on a '
                '$viewport px screen — 0011 cannot be finished',
          );
          expect(
            control['hittable'],
            isTrue,
            reason:
                'something covers ${control['what']} at '
                '${control['rect']}',
          );
        }
        // A gated platform has to actually show its form here; 당근 has none,
        // and whatever its dashboard does show just has to be reachable.
        if (platform.loginUrl != platform.dashboardUrl) {
          expect(
            controls,
            hasLength(3),
            reason:
                'expected 아이디 · 비밀번호 · 로그인 on ${report['url']} '
                '(${report['title']}), found ${controls.length}',
          );
        }
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  });

  group('the mobile layout puts the CTA on the screen', () {
    for (final platform in ListingPlatform.values) {
      test('${platform.label} 등록 CTA is visible and hittable', () async {
        final script = File(
          '${Directory.systemTemp.path}/flr_layout_${platform.name}_'
          '${DateTime.now().microsecondsSinceEpoch}.js',
        );
        Map<String, dynamic>? report;
        try {
          script.writeAsStringSync(
            mirrorMobileLayoutScript(platform, Uri.parse(platform.formUrl))!,
          );
          report = await run([
            '--job=layout',
            ...urlsOf(platform),
            '--script=${script.path}',
            // NUL, not a space: 「매물 등록 완료」 is one label with spaces in it.
            '--labels=${platform.submitLabels.join('\u0000')}',
            '--width=$viewport',
            '--height=844',
          ]);
        } finally {
          if (script.existsSync()) script.deleteSync();
        }
        if (report == null) return;

        expect(report['installed'], isTrue, reason: 'the script declined');
        final ctas = (report['ctas'] as List).cast<Map<String, dynamic>>();
        expect(
          ctas,
          isNotEmpty,
          reason:
              '${platform.submitLabels} is nowhere on ${report['url']} '
              '(${report['title']})',
        );
        for (final cta in ctas) {
          expect(
            cta['insideX'],
            isTrue,
            reason: '${cta['label']} is off the side at ${cta['rect']}',
          );
          expect(
            cta['insideY'],
            isTrue,
            reason:
                '${cta['label']} is off the top or bottom at '
                '${cta['rect']}',
          );
          expect(
            cta['hitsSelf'],
            isTrue,
            reason: 'something covers ${cta['label']} at ${cta['rect']}',
          );
        }

        // The page clips at the root, so whatever is left outside is gone
        // rather than merely off to the side — no scrolling reaches it.
        expect(
          report['wide'],
          isEmpty,
          reason:
              'out of reach on a $viewport px screen: ${report['wide']} '
              '(body measures ${report['bodyScrollWidth']}px)',
        );
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  });
}
