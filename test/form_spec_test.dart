import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/main.dart';
import 'package:jibang_listing_test/photo_transfer.dart';

void main() {
  test('master form has all 50 fields and photos are optional', () {
    final fields = groups.expand((group) => group.fields).toList();

    expect(groups, hasLength(5));
    expect(fields, hasLength(50));
    expect(fields.where((field) => field.required), hasLength(28));
    expect(
      fields.singleWhere((field) => field.key == 'photoCount').required,
      isFalse,
    );
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

  test(
    'platform configuration exposes separate Zigbang, Dabang and Daangn forms',
    () {
      expect(ListingPlatform.values, hasLength(3));
      expect(ListingPlatform.zigbang.label, '직방');
      expect(ListingPlatform.dabang.label, '다방');
      expect(ListingPlatform.daangn.label, '당근');
      expect(ListingPlatform.zigbang.formUrl, contains('/zigbang/form/'));
      expect(ListingPlatform.dabang.formUrl, contains('/dabang/form/room/'));
      expect(ListingPlatform.daangn.formUrl, contains('/daangn/form/article/'));
      // 당근은 자기 주소 검색을 쓰고, 사진은 다방·당근만 받는다.
      expect(ListingPlatform.daangn.usesKakaoPostcode, isFalse);
      expect(ListingPlatform.zigbang.usesKakaoPostcode, isTrue);
      expect(ListingPlatform.dabang.usesKakaoPostcode, isTrue);
      expect(ListingPlatform.zigbang.photoTarget, isNull);
      expect(ListingPlatform.dabang.photoTarget, PhotoTarget.dabang);
      expect(ListingPlatform.daangn.photoTarget, PhotoTarget.daangn);
    },
  );

  testWidgets('the register CTA gates on validation and routes the picked channel', (
    tester,
  ) async {
    Map<String, dynamic>? receivedValues;
    ListingPlatform? receivedPlatform;
    List<Object>? receivedPhotos;
    await tester.pumpWidget(
      MaterialApp(
        home: ListingFormPage(
          remotePageBuilder: (values, platform, photos) {
            receivedValues = values;
            receivedPlatform = platform;
            receivedPhotos = photos;
            return const Scaffold(body: Text('전송 대상 폼'));
          },
        ),
      ),
    );

    BrandButton cta() => tester.widget<BrandButton>(
      find.byWidgetPredicate(
        (widget) => widget is BrandButton && widget.label.endsWith('채널에 등록하기'),
      ),
    );

    // With nothing filled in, the one CTA gates every selected channel at once.
    expect(find.text('선택한 3개 채널에 등록하기'), findsOneWidget);
    expect(cta().onPressed, isNull);

    // Narrowing the channel set has to narrow what the CTA promises.
    await tester.tap(find.text('직방'));
    await tester.tap(find.text('당근'));
    await tester.pump();
    expect(find.text('선택한 1개 채널에 등록하기'), findsOneWidget);
    expect(cta().onPressed, isNull);

    await tester.tap(find.text('자동 채우기'));
    await tester.pump();
    expect(cta().onPressed, isNotNull);

    await tester.tap(find.text('선택한 1개 채널에 등록하기'));
    // The publish flow holds a beat on its progress screen before opening the
    // mirror, and that screen animates forever — pump past it by hand rather
    // than waiting for the tree to settle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('전송 대상 폼'), findsOneWidget);
    expect(receivedPlatform, ListingPlatform.dabang);
    expect(receivedPhotos, isEmpty);
    expect(receivedValues, isNot(contains('photoCount')));
    expect(receivedValues, containsPair('address', isNotEmpty));
  });

  test('adapters report their result and never activate submit', () {
    for (final script in [
      zigbangInjectionScript('{}'),
      dabangInjectionScript('{}'),
      daangnInjectionScript('{}'),
    ]) {
      expect(script, contains('window.ListingResult.postMessage'));
      expect(script, contains('missing: []'));
      expect(script, contains('unsupported: []'));
      expect(script, contains('violations: []'));
      expect(script, isNot(contains("getElementById('submit')")));
      expect(script, isNot(contains("querySelector('#submit')")));
      expect(script, isNot(contains("'등록 완료'")));
      expect(script, isNot(contains("'임시저장'")));
      expect(script, isNot(contains("'매물 등록하기'")));
    }
  });

  test('Daangn adapter follows the SEED form and its shared radio name', () {
    final script = daangnInjectionScript('{}');
    // 줄은 굵은 글씨 이름으로 찾고, 반응마다 다시 찾는다.
    expect(script, contains("querySelectorAll('span.t4-bold')"));
    expect(script, contains("closest('div.flex.items-start.gap-x3')"));
    expect(script, contains('const at = target =>'));
    // 확인은 input.checked 가 아니라 라벨의 data-checked — 대출·반려동물·주차는 name 이 같다.
    expect(script, contains("hasAttribute('data-checked')"));
    expect(
      script,
      contains("'input[type=\"radio\"][value=\"' + value + '\"]'"),
    );
    expect(script, contains("radio('loanAvailable', '대출'"));
    expect(script, contains("radio('petAllowed', '반려동물'"));
    expect(script, contains("radio('parking', '주차'"));
    // 깐깐이를 통과하는 입력·클릭 방식
    expect(script, contains('valueSetter(el).call(el, String(value))'));
    expect(script, contains("new PointerEvent('pointerdown', init)"));
    // 선택 상자는 표시된 값으로 확인한다.
    expect(script, contains('.seed-input-button__value'));
    for (final name in ['salesType', 'buildingUsage', 'buildingOrientation']) {
      expect(script, contains("'$name'"));
    }
  });

  test('Daangn adapter enters the address first and keeps the form values', () {
    final script = daangnInjectionScript('{}');
    // 카카오가 아니라 미러 안의 주소 창 — 고르고, 상세 주소를 넣고, 「입력하기」.
    expect(script, isNot(contains('__flrPostcode')));
    expect(script, contains("selectButton('address')"));
    expect(script, contains("dialogButton('입력하기')"));
    expect(script, contains("suffix(data.building, '동')"));
    expect(script, contains("suffix(data.unit, '호')"));
    // 예시 주소(중계 실패)는 고르지 않는다.
    expect(script, contains("querySelector('[data-mirror-note]')"));
    // 주소가 다른 칸보다 먼저, 그리고 건축물대장이 덮어쓴 값은 끝에서 다시 맞춘다.
    expect(
      script.indexOf('await enterAddress()'),
      lessThan(script.indexOf("await choose('propertyType'")),
    );
    expect(script, contains('[data-mirror-note="ledger"]'));
    expect(script, contains('if (addressEntered) await reconcileLedger();'));
    // 단기 매물은 단기도 함께 고르고 금액을 복사한다.
    expect(script, contains("trades.push('단기')"));
    expect(script, contains("fill('shortTerm.deposit'"));
    // 관리비 10만원 미만은 체크 하나로 묶음이 바뀐다.
    expect(script, contains('10만원 미만 혹은 의뢰인이 세부 내역 미제공'));
  });

  test(
    'Dabang adapter addresses one th/td pair at a time and re-resolves rows',
    () {
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
    },
  );

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

  test(
    'address picker runs only in the Kakao frame and only for our search',
    () {
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
    },
  );

  test('generated adapters are valid JavaScript', () {
    final scripts = {
      'zigbang': zigbangInjectionScript('{}'),
      'dabang': dabangInjectionScript('{}'),
      'bridge': postcodeBridgeScript('""'),
      'framePicker': addressPickerFrameScript('""'),
      'daangn': daangnInjectionScript('{}'),
      'dabangPhotoBridge': listingPhotoBridgeScript(PhotoTarget.dabang),
      'daangnPhotoBridge': listingPhotoBridgeScript(PhotoTarget.daangn),
      'photoCommand': listingPhotoCommand('append', ['aGVsbG8=']),
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
