@Tags(['render'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/fields.dart';
import 'package:jibang_listing_test/mobile_layout.dart';
import 'package:jibang_listing_test/takedown.dart';

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
/// This harness measures the mirror: the live sites need an account.
PlatformUrls mirrorOf(ListingPlatform platform) =>
    platform.urlsOn(PlatformSite.mirror);

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
    '--login=${mirrorOf(platform).login}',
    '--dashboard=${mirrorOf(platform).dashboard}',
    '--form=${mirrorOf(platform).form}',
    '--listings=${mirrorOf(platform).listings}',
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

  // 광고 목록 위에서 도는 내리기 스크립트 (lib/takedown.dart).
  //
  // 이 둘은 offline 으로 흉내 낼 수 없다. 목록에는 이 중개사의 매물이 통째로 걸려
  // 있고(직방 광고 중 45건, 다방 광고 진행 119건) 같은 글자의 종료 버튼이 그 수만큼
  // 있는데, 「그중 어느 것이 그 매물인가」와 「그 카드의 버튼이 390px 화면 어디에
  // 앉는가」는 실제 페이지만이 답할 수 있다.
  group('내리기 — 목록에서 그 매물을 짚는다', () {
    /// 각 미러의 광고 목록에 실제로 걸려 있는 매물 한 건 (실측 2026-09-21).
    /// 통합 폼이 그 매물을 올렸다면 들고 있었을 값을 그대로 옮겨 적었다. 미러의
    /// 수집본이 바뀌면 여기가 먼저 깨지는데, 그것이 맞다 — 바뀐 것을 알아야 한다.
    const fixtures = {
      ListingPlatform.zigbang: (
        number: '50144198',
        values: {
          'title': '단기 가능 볕 잘드는 깔끔 원룸',
          'address': '경상북도 포항시 남구 대도동 150-36',
          'unit': '202',
          'trade': '월세',
          'deposit': '200',
          'monthlyRent': '25',
        },
      ),
      ListingPlatform.dabang: (
        number: '58948955',
        values: {
          'title': '수가성근교 깔끔한 분리형 원룸',
          'address': '경상북도 포항시 북구 죽도동 667-17',
          'unit': '302',
          'trade': '월세',
          'deposit': '200',
          'monthlyRent': '20',
        },
      ),
    };

    /// 목록을 열고 [scripts] 를 차례로 돌린 뒤의 보고. 모바일 레이아웃은 앱이 모든
    /// 플랫폼 페이지에 까는 것이라 여기서도 맨 앞에 깐다.
    Future<Map<String, dynamic>?> onListings(
      ListingPlatform platform,
      List<String> scripts,
    ) async {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final files = [
        mirrorMobileLayoutScript(
          platform,
          Uri.parse(mirrorOf(platform).listings),
        )!,
        ...scripts,
      ].indexed.map((entry) {
        final file = File(
          '${Directory.systemTemp.path}/flr_takedown_${platform.name}_'
          '$stamp${entry.$1}.js',
        );
        return file..writeAsStringSync(entry.$2);
      }).toList();
      try {
        return await run([
          '--job=listings',
          ...urlsOf(platform),
          // US(\u001f), not a space: 파일 경로에도 「광고 종료」에도 빈칸이 들어
          // 있다. NUL 도 못 쓴다 — 인자는 첫 NUL 에서 끝나 버린다.
          '--scripts=${files.map((file) => file.path).join('\u001f')}',
          '--labels=${platform.takedownLabels.join('\u001f')}',
          '--width=$viewport',
          '--height=844',
        ]);
      } finally {
        for (final file in files) {
          if (file.existsSync()) file.deleteSync();
        }
      }
    }

    for (final platform in livePlatforms) {
      final fixture = fixtures[platform]!;

      test('${platform.label} 목록에서 매물 번호를 읽어 낸다', () async {
        final report = await onListings(platform, [
          listingNumberScript(platform, fixture.values),
        ]);
        if (report == null) return;

        expect(
          report['number'],
          isNotNull,
          reason:
              '번호를 읽는 스크립트가 아무 답도 하지 않았다 '
              '(${report['landed']})',
        );
        final answer =
            jsonDecode('${report['number']}') as Map<String, dynamic>;
        expect(
          answer['cards'],
          greaterThan(1),
          reason: '목록에서 카드를 한 장도 세지 못했다면 읽은 번호도 우연이다',
        );
        expect(
          answer['number'],
          fixture.number,
          reason:
              '「${fixture.values['title']}」을 ${answer['score']}점으로 '
              '${answer['why']} 에서 찾았다 (2등 ${answer['runnerUp']}점)',
        );
        // 미러의 깐깐이가 잡는 짓은 하지 않는다 — 검색창에 값을 꽂는 쪽도 마찬가지다.
        expect(jsonDecode('${report['violations']}'), isEmpty);
      }, timeout: const Timeout(Duration(minutes: 3)));

      test('${platform.label} 그 번호의 카드에만 표를 붙이고 종료 버튼을 화면에 올린다', () async {
        final report = await onListings(platform, [
          takedownCardScript(platform, fixture.number),
        ]);
        if (report == null) return;

        final card = report['card'] as Map<String, dynamic>?;
        expect(
          card,
          isNotNull,
          reason:
              '${fixture.number} 카드를 찾지 못했다 — 목록에는 있는데 '
              '(${report['landed']}) 스크립트가 못 짚었다면 카드를 알아보는 법이 '
              '틀린 것이다',
        );
        expect(
          card!['marked'],
          1,
          reason: '표가 둘 이상이면 어느 것이 그 매물인지 말해 주지 못한다',
        );
        expect(
          card['text'],
          contains(fixture.number),
          reason: '표가 엉뚱한 카드에 붙었다: ${card['text']}',
        );
        expect(
          card['onScreen'],
          isTrue,
          reason: '카드가 ${card['rect']} 에 있다 — 스크롤이 그 자리로 가지 않았다',
        );

        final button = card['button'] as Map<String, dynamic>?;
        expect(
          button,
          isNotNull,
          reason: '표가 붙은 카드 안에 ${platform.takedownLabels} 가 없다',
        );
        expect(
          button!['insideX'],
          isTrue,
          reason: '${button['label']} 가 ${button['rect']} — 화면 옆으로 나갔다',
        );
        expect(
          button['inside'],
          isTrue,
          reason: '${button['label']} 가 ${button['rect']} — 위아래로 나갔다',
        );
        expect(
          button['hitsSelf'],
          isTrue,
          reason: '${button['rect']} 에서 ${button['label']} 를 무언가가 덮고 있다',
        );

        // 카드를 찾았다고 앱에 알려야 눌림 울타리가 쳐진다.
        final told = jsonDecode('${report['told']}') as Map<String, dynamic>;
        expect(told['found'], isTrue);
        expect(told['number'], fixture.number);
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
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
            mirrorMobileLayoutScript(
              platform,
              Uri.parse(mirrorOf(platform).login),
            )!,
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
        if (mirrorOf(platform).login != mirrorOf(platform).dashboard) {
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
            mirrorMobileLayoutScript(
              platform,
              Uri.parse(mirrorOf(platform).form),
            )!,
          );
          report = await run([
            '--job=layout',
            ...urlsOf(platform),
            '--script=${script.path}',
            // US(\u001f), not a space: 「매물 등록 완료」 is one label with
            // spaces in it. Not NUL either — an argument ends at its first NUL,
            // so a NUL-joined list arrives at the probe with only its head.
            '--labels=${platform.submitLabels.join('\u001f')}',
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
