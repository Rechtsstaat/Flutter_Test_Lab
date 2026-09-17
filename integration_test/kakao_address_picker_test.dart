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
    final dom = await _waitForDom(tester, controller, '''
(() => {
  const lat = document.querySelector('[name="lat"]');
  return {
    overlay: !!document.getElementById('flr-postcode-overlay'),
    lat: lat ? String(lat.value || lat.textContent || '') : null,
  };
})()
''', (dom) => dom['overlay'] == false && '${dom['lat'] ?? ''}'.isNotEmpty);
    await _expectFramePickerStatus(tester, ListingPlatform.zigbang, controller);
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
          dom['overlay'] == false && '${dom['picked'] ?? ''}'.contains('테헤란로'),
    );
    await _expectFramePickerStatus(tester, ListingPlatform.dabang, controller);
    expect(dom['overlay'], isFalse, reason: jsonEncode(dom));
    // 미러는 고른 주소를 도로명·지번으로 적고 동/호 칸을 켠다.
    expect(dom['picked'], contains('테헤란로 123'), reason: jsonEncode(dom));
    expect(dom['dongEnabled'], isTrue, reason: jsonEncode(dom));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Pumps the mirror page and returns its controller as soon as the WebView is
/// mounted. Waiting for ListingResult here would hide a picker failure: the
/// adapter only publishes that result after the address flow has finished.
Future<WebViewController> _open(
  WidgetTester tester,
  ListingPlatform platform,
  String address,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RemoteFormPage(
        platform: platform,
        values: {'address': address, 'propertyType': '오픈형 원룸'},
      ),
    ),
  );
  final until = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(until)) {
    await tester.pump(const Duration(milliseconds: 100));
    final mirrorWebView = find.byType(MirrorWebView);
    if (mirrorWebView.evaluate().isNotEmpty) {
      return tester.widget<MirrorWebView>(mirrorWebView).page.controller;
    }
  }
  throw TimeoutException(
    '${platform.label} WebView가 10초 안에 생성되지 않았습니다. '
    'visibleText=${_visibleText(tester)}',
  );
}

Future<void> _expectFramePickerStatus(
  WidgetTester tester,
  ListingPlatform platform,
  WebViewController controller,
) async {
  final until = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(until)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (find.textContaining('주소 자동 선택').evaluate().isNotEmpty) return;
  }
  throw TimeoutException(
    '${platform.label} 프레임 스크립트 상태가 20초 안에 표시되지 않았습니다. '
    'url=${await controller.currentUrl()}, visibleText=${_visibleText(tester)}',
  );
}

Future<Map<String, dynamic>> _waitForDom(
  WidgetTester tester,
  WebViewController controller,
  String probe,
  bool Function(Map<String, dynamic>) done,
) async {
  var dom = <String, dynamic>{};
  Object? lastError;
  final until = DateTime.now().add(const Duration(seconds: 40));
  while (DateTime.now().isBefore(until)) {
    await tester.pump(const Duration(milliseconds: 500));
    try {
      final raw = await controller.runJavaScriptReturningResult(
        'JSON.stringify($probe)',
      );
      var text = raw is String ? raw : raw.toString();
      // Android hands back the JSON string still quoted.
      if (text.startsWith('"')) text = jsonDecode(text) as String;
      dom = jsonDecode(text) as Map<String, dynamic>;
      if (done(dom)) return dom;
    } catch (error) {
      // Navigation can replace the document while this diagnostic probe runs.
      lastError = error;
    }
  }
  throw TimeoutException(
    'DOM 조건이 40초 안에 충족되지 않았습니다. '
    'url=${await controller.currentUrl()}, dom=${jsonEncode(dom)}, '
    'lastError=$lastError, visibleText=${_visibleText(tester)}',
  );
}

List<String> _visibleText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((widget) => widget.data)
    .whereType<String>()
    .where((text) => text.isNotEmpty)
    .toList();
