import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/main.dart';

void main() {
  test('master form has all 50 fields and 29 required fields from the specification', () {
    final fields = groups.expand((group) => group.fields).toList();

    expect(groups, hasLength(5));
    expect(fields, hasLength(50));
    expect(fields.where((field) => field.required), hasLength(29));
  });

  test(
    'every field has an editable input definition and an auto-fill example',
    () {
      for (final field in groups.expand((group) => group.fields)) {
        expect(field.key, isNotEmpty);
        expect(field.label, isNotEmpty);
        expect(field.example, isNotEmpty);
      }
    },
  );

  test(
    'recreated-form mappings use structured choices where the target has them',
    () {
      final fields = {
        for (final field in groups.expand((group) => group.fields))
          field.key: field,
      };

      expect(fields['manageBasis']!.options, contains('직전월 관리비 기준'));
      expect(fields['manageIncludes']!.type, InputType.multiSelect);
      expect(fields['appliances']!.type, InputType.multiSelect);
      expect(fields['facilities']!.type, InputType.multiSelect);
      expect(fields['propertyType']!.options, contains('오픈형 원룸'));
      expect(fields['otherFeeReason']!.visibleWhenValue, '기타 부과');
    },
  );

  test('platform configuration exposes separate Zigbang and Dabang forms', () {
    expect(ListingPlatform.values, hasLength(2));
    expect(ListingPlatform.zigbang.label, '직방');
    expect(ListingPlatform.dabang.label, '다방');
    expect(ListingPlatform.zigbang.formUrl, contains('/zigbang/form/'));
    expect(ListingPlatform.dabang.formUrl, contains('/dabang/form/room/'));
  });

  testWidgets('both platform CTAs share validation enablement', (tester) async {
    await tester.pumpWidget(const ListingApp());
    await tester.scrollUntilVisible(
      find.text('직방에 보내기'),
      600,
      scrollable: find.byType(Scrollable).first,
    );

    FilledButton zigbang = tester.widget(
      find.widgetWithText(FilledButton, '직방에 보내기'),
    );
    FilledButton dabang = tester.widget(
      find.widgetWithText(FilledButton, '다방에 보내기'),
    );
    expect(zigbang.onPressed, isNull);
    expect(dabang.onPressed, isNull);

    await tester.tap(find.text('자동 채우기'));
    await tester.pump();
    zigbang = tester.widget(find.widgetWithText(FilledButton, '직방에 보내기'));
    dabang = tester.widget(find.widgetWithText(FilledButton, '다방에 보내기'));
    expect(zigbang.onPressed, isNotNull);
    expect(dabang.onPressed, isNotNull);
  });

  test('adapters report their result and never activate submit', () {
    for (final script in [
      zigbangInjectionScript('{}'),
      dabangInjectionScript('{}'),
    ]) {
      expect(script, contains('window.ListingResult.postMessage'));
      expect(script, contains('missing: []'));
      expect(script, contains('unsupported: []'));
      expect(script, contains('violations: []'));
      expect(script, isNot(contains("getElementById('submit')")));
      expect(script, isNot(contains("querySelector('#submit')")));
      expect(script, isNot(contains("'등록 완료'")));
      expect(script, isNot(contains("'임시저장'")));
    }
  });

  test('Dabang adapter addresses one th/td pair at a time and re-resolves rows', () {
    final script = dabangInjectionScript('{}');
    // 다방은 한 <tr> 에 (th, td) 쌍을 여럿 넣는다 — 줄 전체를 훑으면 옆 항목을 건드린다.
    expect(script, contains('const cellOf = (section, label)'));
    expect(script, contains("while (node && node.tagName !== 'TD')"));
    expect(script, contains("cellOf('additional_info', '엘리베이터')"));
    // 미러가 행을 통째로 갈아 끼우므로 자리는 늘 함수로 다시 찾아야 한다.
    expect(script, contains('const at = target =>'));
    expect(script, contains('const ready = (locate, timeout)'));
    // 깐깐이를 통과하는 입력·클릭 방식
    expect(script, contains('valueSetter(el).call(el, String(value))'));
    expect(script, contains("new PointerEvent('pointerdown', init)"));
    // 주소·관리비 흐름
    expect(script, contains("modal('월 관리비 상세입력')"));
    expect(script, contains("modal('건축물대장')"));
    expect(script, contains('new MutationObserver'));
    expect(script, contains('afterAddressPicked'));
    expect(script, contains("input[name=\"keyword\"]"));
  });

  test('Zigbang adapter fills the address through the Kakao picker', () {
    final script = zigbangInjectionScript('{}');
    expect(script, contains("press(lat)"));
    expect(script, contains('__flrPostcode'));
    expect(script, contains('소재지 공개 확인'));
    // 주소는 더 이상 「불가」 항목이 아니다.
    expect(script, isNot(contains('address:')));
  });

  test('Kakao postcode bridge renders in-page instead of opening a window', () {
    final script = postcodeBridgeScript('"서울특별시 강남구 테헤란로 123"');
    expect(script, contains('inner.embed(host, params)'));
    expect(script, contains("id = 'flr-postcode-overlay'"));
    expect(script, contains("history.pushState({flrPostcode: true}"));
    expect(script, contains('window.__flrClosePostcode'));
    // 미러가 넘긴 oncomplete 는 그대로 살려야 원래 폼 흐름이 돈다.
    expect(script, contains('source.oncomplete(value)'));
    // 직방 미러가 늦게 실어 오는 원본 스크립트도 래퍼를 덮지 못한다.
    expect(script, contains("Object.defineProperty(window.daum, 'Postcode'"));
    // open() 은 창을 열지 않고 이 페이지 안의 겹을 세운다.
    expect(script, contains('self.open = extra => {'));
    expect(script, contains('const host = buildOverlay();'));
  });

  test('address picker runs only in the Kakao frame and only for our search', () {
    final script = addressPickerFrameScript('"서울특별시 강남구 테헤란로 123"');
    // 이 스크립트는 모든 프레임에서 돈다 — 미러 페이지는 건드리면 안 된다.
    expect(script, contains(r"/^postcode\.map\.(kakao\.com|daum\.net)$/"));
    // 사용자가 검색어를 바꿔 다시 찾으면 자동 선택하지 않는다.
    expect(script, contains('if (squash(query) !== squash(target)) return;'));
    expect(script, contains("sessionStorage.getItem('flrPicked')"));
    // 후보는 카카오가 붙여 둔 한글 주소 속성에서 읽는다.
    expect(script, contains("span.txt_address[data-addr]"));
    // 점수가 같으면 카카오가 준 순서대로 — 맨 위가 이긴다.
    expect(script, contains('weighted > winner.weighted'));
  });

  test('generated adapters are valid JavaScript', () {
    final scripts = {
      'zigbang': zigbangInjectionScript('{}'),
      'dabang': dabangInjectionScript('{}'),
      'bridge': postcodeBridgeScript('""'),
      'framePicker': addressPickerFrameScript('""'),
    };
    scripts.forEach((name, source) {
      final temp = File(
        '${Directory.systemTemp.path}/${name}_adapter_${DateTime.now().microsecondsSinceEpoch}.js',
      );
      try {
        temp.writeAsStringSync(source);
        final result = Process.runSync('node', ['--check', temp.path]);
        expect(
          result.exitCode,
          0,
          reason: '$name: ${result.stdout}\n${result.stderr}',
        );
      } finally {
        if (temp.existsSync()) temp.deleteSync();
      }
    });
  });
}
