import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jibang_listing_test/fields.dart';
import 'package:jibang_listing_test/mirror_session.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Opens the Zigbang and Dabang mirrors with only an address, and checks that
/// the native frame-script bridge (iOS and Android) picks the Kakao search
/// result without anyone touching the list.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const address = '서울특별시 강남구 테헤란로 123';

  testWidgets('Zigbang: the Kakao result is picked and fills the address', (
    tester,
  ) async {
    final controller = await _open(tester, ListingPlatform.zigbang, address);
    final dom = await _waitForDom(
      tester,
      controller,
      '''
(() => {
  const lat = document.querySelector('[name="lat"]');
  return {
    overlay: !!document.getElementById('flr-postcode-overlay'),
    lat: lat ? String(lat.value || lat.textContent || '') : null,
  };
})()
''',
      (dom) => dom['overlay'] == false && '${dom['lat'] ?? ''}'.isNotEmpty,
    );
    expect(dom['overlay'], isFalse, reason: jsonEncode(dom));
    expect(dom['lat'], contains('테헤란로'), reason: jsonEncode(dom));
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('Dabang: the Kakao result is picked and the search closes', (
    tester,
  ) async {
    final controller = await _open(tester, ListingPlatform.dabang, address);
    final dom = await _waitForDom(
      tester,
      controller,
      '''
(() => {
  const th = [...document.querySelectorAll('#room_info th')]
    .find(el => el.textContent.replace(/\\s+/g, '').includes('매물주소'));
  let cell = th && th.nextElementSibling;
  while (cell && cell.tagName !== 'TD') cell = cell.nextElementSibling;
  const dong = cell && cell.querySelector('input[name="dong"]');
  return {
    overlay: !!document.getElementById('flr-postcode-overlay'),
    picked: cell ? [...cell.querySelectorAll('[class*=AddressList] li')]
      .map(li => li.textContent.trim()).join(' | ') : null,
    dongEnabled: !!dong && !dong.disabled,
  };
})()
''',
      (dom) =>
          dom['overlay'] == false &&
          '${dom['picked'] ?? ''}'.contains('테헤란로'),
    );
    expect(dom['overlay'], isFalse, reason: jsonEncode(dom));
    // 미러는 고른 주소를 도로명·지번으로 적고 동/호 칸을 켠다.
    expect(dom['picked'], contains('테헤란로 123'), reason: jsonEncode(dom));
    expect(dom['dongEnabled'], isTrue, reason: jsonEncode(dom));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Pumps the mirror page and waits for the adapter's first report, which is
/// sent once the Kakao search is up.
Future<WebViewController> _open(
  WidgetTester tester,
  ListingPlatform platform,
  String address,
) async {
  final reported = Completer<WebViewController>();
  await tester.pumpWidget(
    MaterialApp(
      home: RemoteFormPage(
        platform: platform,
        values: {'address': address, 'propertyType': '원룸'},
        onListingResult: (controller, _) {
          if (!reported.isCompleted) reported.complete(controller);
        },
      ),
    ),
  );
  final controller = await reported.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () => throw TimeoutException(
      '${platform.label} 미러의 페이지 로드·자동 입력이 2분 안에 끝나지 않았습니다.',
    ),
  );
  await tester.pump();
  // The status line only says this when the native bridge took the script.
  expect(find.textContaining('주소 자동 선택'), findsOneWidget);
  return controller;
}

Future<Map<String, dynamic>> _waitForDom(
  WidgetTester tester,
  WebViewController controller,
  String probe,
  bool Function(Map<String, dynamic>) done,
) async {
  var dom = <String, dynamic>{};
  final until = DateTime.now().add(const Duration(seconds: 40));
  while (DateTime.now().isBefore(until)) {
    await tester.pump(const Duration(milliseconds: 500));
    final raw = await controller.runJavaScriptReturningResult(
      'JSON.stringify($probe)',
    );
    var text = raw is String ? raw : raw.toString();
    // Android hands back the JSON string still quoted.
    if (text.startsWith('"')) text = jsonDecode(text) as String;
    dom = jsonDecode(text) as Map<String, dynamic>;
    if (done(dom)) break;
  }
  return dom;
}
