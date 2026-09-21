import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jibang_listing_test/main.dart';
import 'package:jibang_listing_test/photo_transfer.dart';

void main() {
  /* 사진은 **필수 5~20장**이다.
   *
   * 직방이 그렇게 요구한다 — 「이미지 넣기」 창은 5장을 채우기 전에는 [확인] 을
   * 열어 주지 않는다(2026-09-08 현장조사 §3-6). 통합 폼이 그보다 느슨하면 그 사진은
   * 등록 흐름 한복판에서 조용히 떨어져 나간다. */
  test('master form keeps the 50 spec rows and photos are required 5~20', () {
    final fields = groups.expand((group) => group.fields).toList();

    expect(groups, hasLength(5));
    // 명세서의 50 줄은 번호를 그대로 달고 남아 있다. 51~ 은 실물 폼이 더 물어본 줄이다
    // (단지명·관리비 상세·의뢰인 연락처 …) — 명세서를 줄인 것이 아니라 덧댄 것이다.
    expect(fields.where((field) => field.number <= 50), hasLength(50));
    expect(fields, hasLength(62));
    expect(fields.map((field) => field.number).toSet(), hasLength(fields.length));
    expect(fields.where((field) => field.required), hasLength(29));
    expect(
      fields.singleWhere((field) => field.key == 'photoCount').required,
      isTrue,
    );
    expect(minListingPhotos, 5);
    expect(maxListingPhotos, 20);
    // 숫자를 손으로 적지 않는다 — 플랫폼이 정한 것을 그대로 따라간다.
    expect(minListingPhotos, PhotoTarget.zigbang.minimum);
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
      // 매물 종류는 **건물의 형태**다. 방이 몇 개인지·오픈형인지는 방 구조가 따로 받는다
      // — 실물 폼이 그렇게 갈라 놓았고(직방은 형태별로 폼 자체가 다르다), 통합 폼도 따른다.
      expect(fields['propertyType']!.options, contains('빌라/연립/다세대'));
      expect(fields['propertyType']!.options, isNot(contains('오픈형 원룸')));
      expect(fields['roomLayout']!.options, contains('오픈형 원룸'));
      expect(fields['buildingUse']!.options, contains('공동주택'));
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
      expect(
        ListingPlatform.zigbang.formUrl,
        'https://ceo.zigbang.com/ads/oneroom/ad-item/new',
      );
      expect(
        ListingPlatform.dabang.formUrl,
        'https://pro.dabangapp.com/form/room',
      );
      expect(ListingPlatform.daangn.formUrl, contains('/daangn/form/article/'));
      // 당근은 자기 주소 검색을 쓰고, 사진은 셋 다 받는다.
      expect(ListingPlatform.daangn.usesKakaoPostcode, isFalse);
      expect(ListingPlatform.zigbang.usesKakaoPostcode, isTrue);
      expect(ListingPlatform.dabang.usesKakaoPostcode, isTrue);
      expect(ListingPlatform.zigbang.photoTarget, PhotoTarget.zigbang);
      expect(ListingPlatform.dabang.photoTarget, PhotoTarget.dabang);
      expect(ListingPlatform.daangn.photoTarget, PhotoTarget.daangn);
      // 직방만 사진을 창 안에서 받는다.
      expect(PhotoTarget.zigbang.modal, isTrue);
      expect(PhotoTarget.dabang.modal, isFalse);
    },
  );

  testWidgets(
    'the register CTA gates on validation and routes the picked channel',
    (tester) async {
      Map<String, dynamic>? receivedValues;
      ListingPlatform? receivedPlatform;
      List<Object>? receivedPhotos;
      // 폼은 고른 사진의 바이트를 읽어 진짜 JPG·PNG 인지 본다 — 이름만 사진인 것은
      // 들이지 않는다. 그래서 여기서도 실제 PNG 를 그 자리에 적어 둔다.
      // 파일 만들기는 **동기로** 한다 — testWidgets 안에서 기다린 진짜 입출력은
      // 가짜 시계 위에서 영영 돌아오지 않는다.
      final album = Directory.systemTemp.createTempSync('listing_cta_');
      addTearDown(() => album.deleteSync(recursive: true));
      final picked = [
        for (var i = 0; i < minListingPhotos; i++)
          XFile(
            (File('${album.path}/room-$i.png')..writeAsBytesSync(
              base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
                '/x8AAwMCAO+aWZkAAAAASUVORK5CYII=',
              ),
            )).path,
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: ListingFormPage(
            pickImages: () async => picked,
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
          (widget) => widget is BrandButton && widget.label == '광고 등록',
        ),
      );

      // With nothing filled in, the one CTA stays off and says why.
      expect(cta().onPressed, isNull);
      expect(find.textContaining('필수 항목'), findsOneWidget);

      // Narrow the run to 다방 in 플랫폼 선택, at the end of the long form.
      // 처음에는 살아 있는 둘(직방·다방)이 잡혀 있다 — 당근은 내려 두어 고를 수 없다.
      await tester.scrollUntilVisible(
        find.text('플랫폼 선택'),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('직방'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('직방'));
      await tester.pump();
      expect(cta().onPressed, isNull);

      await tester.tap(find.text('자동 채우기'));
      await tester.pump();
      // 사진은 자동 채우기가 만들어 낼 수 없다 — 진짜 사진이라야 폼으로 들어간다.
      expect(
        cta().onPressed,
        isNull,
        reason: '사진 $minListingPhotos장을 채우기 전에는 등록 CTA 가 잠겨 있어야 합니다.',
      );

      await tester.scrollUntilVisible(
        find.byTooltip('사진 추가'),
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('사진 추가'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('$minListingPhotos/$maxListingPhotos'), findsOneWidget);
      expect(cta().onPressed, isNotNull);
      expect(find.textContaining('필수 항목'), findsNothing);

      await tester.ensureVisible(find.text('광고 등록'));
      await tester.tap(find.text('광고 등록'));
      // The Process Hub animates for as long as a platform is being worked on,
      // so pump past the route change by hand.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('다방에 입력하는 중이에요'), findsOneWidget);
      expect(find.text('광고 등록 1 / 1'), findsWidgets);
      // The platform page is mounted under the hub from the start.
      expect(find.text('전송 대상 폼'), findsOneWidget);
      expect(receivedPlatform, ListingPlatform.dabang);
      expect(receivedPhotos, hasLength(minListingPhotos));
      expect(receivedValues, containsPair('photoCount', minListingPhotos));
      expect(receivedValues, containsPair('address', isNotEmpty));
      // The hi-fi's 구조 + 복층 여부 still reach the adapters as 방 구조.
      expect(receivedValues, containsPair('roomLayout', '오픈형 원룸'));
    },
  );

  testWidgets('입력 과정 보기 lifts the platform page out of the hub', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PublishFlowPage(
          listing: Listing(
            id: 'L1',
            createdAt: DateTime(2026, 9, 17),
            values: const {},
            channels: const {},
          ),
          values: const {},
          photos: const [],
          // 잠시 내려 둔 플랫폼(당근)은 흐름에서 걸러지므로, 살아 있는 둘로 본다
          channels: const [ListingPlatform.zigbang, ListingPlatform.dabang],
          remotePageBuilder: (_, platform, _) =>
              Center(child: Text('${platform.label} 페이지')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('직방에 입력하는 중이에요'), findsOneWidget);
    expect(find.text('정보를 입력하고 있어요'), findsOneWidget);
    expect(find.text('입력 대기'), findsOneWidget);

    await tester.tap(find.text('입력 과정 보기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('입력이 끝날 때 까지 잠시만 기다려주세요'), findsOneWidget);
    expect(find.text('직방 페이지'), findsOneWidget);

    await tester.tap(find.byTooltip('진행 상황으로'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // Leaving before the form is filled only brings the hub back.
    expect(find.text('정보를 입력하고 있어요'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
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

  /* 실물 확인 2026-09-21(로그인한 계정으로 세 폼을 열어 봄).
   *
   * 직방은 매물 종류마다 폼을 따로 두고, **열어 주지 않을 때가 있다** — 남은 광고 수량이
   * 없으면 「빌라 매물의 광고수량을 모두 이용중입니다」, 상품을 사지 않았으면 「오피스텔
   * (도시형생활주택) 매물 광고상품 구매 후 이용할 수 있습니다」가 뜨고 폼 본문은 비어 있다.
   * 그대로 채우러 들어가면 쉰 줄이 모두 「찾지 못했습니다」로 쏟아져 정작 알아야 할
   * 한 가지가 묻힌다. */
  test('Zigbang adapter stops when 직방 does not open the form at all', () {
    final script = zigbangInjectionScript('{}');
    expect(script, contains("const shut = dialogWith(['광고수량', '광고상품', '상품 구매', '등록이 불가능']);"));
    expect(script, contains("if (shut || !byName('title')) {"));
    expect(script, contains('직방이 이 매물 종류의 등록 폼을 열어 주지 않았습니다'));
    // 먼저 보아야 뜻이 있다 — 건물 종류를 고르기 전에 와야 한다.
    expect(
      script.indexOf('const shut = dialogWith('),
      lessThan(script.indexOf("await pick('propertyType'")),
    );
  });

  /* 통합 폼은 한 곳만 받는 값도 필수로 받는다 — 그래야 한 번 채우면 두 폼이 모두 끝난다.
   * 그 대신 **어디로 갔는지**는 말해 주어야 한다. 실물에서 두 폼의 모든 줄을 훑어
   * 갈 곳이 없는 값을 추렸다(2026-09-21). */
  test('adapters say which values the other side has no room for', () {
    final zigbang = zigbangInjectionScript(
      '{"supplyArea":"40.12","heating":"개별난방","airconType":["벽걸이형"],'
      '"roomFeatures":["신축"],"lh":"가능","complexName":"역삼래미안"}',
    );
    // 직방 원룸 폼에는 이 여섯 줄이 없다.
    for (final (key, what) in [
      ('supplyArea', '공급면적'),
      ('heating', '난방 방식'),
      ('airconType', '에어컨 종류'),
      ('roomFeatures', '방 특징'),
      ('lh', 'LH 전세임대 여부'),
      ('complexName', '단지명'),
    ]) {
      expect(
        zigbang,
        contains("[data.$key, '$what']"),
        reason: '$what 이 직방에 들어가지 않는다는 안내가 없습니다.',
      );
    }
    expect(zigbang, contains('직방 등록 폼에 대응 입력란이 없어 다방에만 들어갑니다.'));

    // 다방 폼의 일곱 섹션 어디에도 위반건축물·중개 의뢰 방법 줄이 없다.
    final dabang = dabangInjectionScript('{}');
    expect(dabang, contains('위반건축물 여부: 다방 등록 폼에 대응 입력란이 없어'));
    expect(dabang, contains('중개 의뢰를 받은 방법: 다방 등록 폼에 대응 입력란이 없어'));
    // 「해당 없음」은 굳이 알릴 것이 없다.
    expect(dabang, contains("data.violation !== '해당 없음'"));
  });

  test('Zigbang adapter fills the address through the Kakao picker', () {
    final script = zigbangInjectionScript('{}');
    expect(script, contains("press(lat)"));
    expect(script, contains('__flrPostcode'));
    // 실물 직방은 주소를 받고 나서 「이 주소는 다른 폼으로」라고 되묻는다(아파트·오피스텔).
    // 어댑터가 대신 답할 수 있는 창이 아니므로, 무슨 말을 들었는지 그대로 적어 올린다.
    expect(script, contains('watchAddressDialogs();'));
    expect(script, contains("'아파트 주소로 확인'"));
    expect(script, contains('직방이 이 주소를 이 폼으로 받지 않는다고 합니다'));
    // 주소는 더 이상 「불가」 항목이 아니다.
    expect(script, isNot(contains('address:')));
  });

  /* 직방의 전화번호 [확인] 은 칸을 보는 것이 아니라 **직방에 그 번호를 묻는** 일이다.
   * 그래서 통합 폼의 「자동 채우기」가 넣어 두는 연습용 번호에는 누르지 않는다 — 폼을 한
   * 번 재 볼 때마다 남의 번호가 계정의 이름으로 조회되기 때문이다. 칸은 채워 두고
   * 「확인할 항목」으로 남겨, 실제 번호로 바꾸면 사람이 직접 누르게 한다. */
  test('Zigbang adapter leaves [확인] unpressed for the auto-fill sample phone', () {
    final script = zigbangInjectionScript(
      jsonEncode({'ownerPhone': sampleOwnerPhone}),
    );
    // 연습용 번호는 통합 폼과 **한 곳**에서 온다 — 예시가 바뀌면 빗장도 같이 움직인다.
    expect(script, contains('const samplePhone = "$sampleOwnerPhone";'));
    expect(script, contains('if (phone === digits(samplePhone)) {'));
    expect(script, contains('연습용 번호'));
    expect(script, contains('실제 의뢰인 번호로 바꾼 뒤 화면에서 [확인] 을 눌러 주세요.'));
    // 누르기 **전에** 와야 뜻이 있다.
    expect(
      script.indexOf('if (phone === digits(samplePhone)) {'),
      lessThan(script.indexOf('\n    press(button);')),
    );
    // 그래도 칸은 채운다 — 사람이 그 자리에서 번호만 고쳐 넣게.
    expect(
      script.indexOf("fillIn('ownerPhone', 'verification.lessorPhone'"),
      lessThan(script.indexOf('if (phone === digits(samplePhone)) {')),
    );
    // 실제 번호는 예전 그대로 눌린다 — 빗장은 이 한 번호에만 걸린다.
    expect(script, contains("mark('ownerPhone.confirm', true)"));
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
      // 안드로이드는 문서 시작 때 넣는다. 카카오가 결과 버튼에 클릭 처리기를 붙인
      // 뒤(DOMContentLoaded 처리기들이 다 돈 뒤)에 눌러야 선택이 먹힌다.
      expect(
        script,
        contains(
          "document.addEventListener('DOMContentLoaded', () => setTimeout(pick)",
        ),
      );
      // 안드로이드가 스크립트를 들여보내는 출처도 같은 두 호스트다.
      expect(kakaoPostcodeOrigins, [
        'https://postcode.map.kakao.com',
        'https://postcode.map.daum.net',
      ]);
      // 다방은 documentEnd 뒤에 검색어와 후보를 늦게 채우므로 둘을 deadline
      // 안에서 기다린다. 완료 표시는 실제 후보를 누르기 직전에만 남긴다.
      expect(script, contains('const deadline = Date.now() + 12000'));
      expect(script, contains('const value = query();'));
      expect(script, contains('window.__flrPickerRunning = true'));
      expect(
        script.indexOf('window.__flrPickerRan = true'),
        greaterThan(script.indexOf('const first = await waitFor')),
      );
      expect(script, contains("sessionStorage.getItem('flrPicked')"));
      // 후보는 카카오가 붙여 둔 한글 주소 속성에서 읽는다.
      expect(script, contains("span.txt_address[data-addr]"));
      // 점수가 같으면 카카오가 준 순서대로 — 맨 위가 이긴다.
      expect(script, contains('weighted > winner.weighted'));
    },
  );

  test('Kakao picker waits for a query and candidates populated later', () {
    final picker = addressPickerFrameScript('"서울특별시 강남구 테헤란로 123"');
    final temp = File(
      '${Directory.systemTemp.path}/delayed_picker_${DateTime.now().microsecondsSinceEpoch}.js',
    );
    try {
      temp.writeAsStringSync('''
let clicks = 0;
const clickedAddresses = [];
let queryReady = false;
let candidateAddress = '';
global.window = global;
global.location = {hostname: 'postcode.map.kakao.com', search: ''};
global.sessionStorage = {
  values: {},
  getItem(key) { return this.values[key] || null; },
  setItem(key, value) { this.values[key] = value; },
};
const button = {scrollIntoView() {}, click() { clicks++; clickedAddresses.push(candidateAddress); }};
const span = {
  querySelector(selector) { return selector === 'button.link_post' ? button : null; },
  getAttribute(name) {
    if (name === 'data-addr') return candidateAddress;
    if (name === 'data-addr_type') return 'R';
    return null;
  },
};
global.document = {
  readyState: 'complete',
  getElementById(id) { return id === 'cQuery' && queryReady ? {value: '서울특별시 강남구 테헤란로 123'} : null; },
  querySelectorAll(selector) { return selector === 'span.txt_address[data-addr]' && candidateAddress ? [span] : []; },
  querySelector() { return null; },
};
setTimeout(() => { queryReady = true; }, 30);
// 이전 검색 결과가 먼저 남아 있어도 절대 누르지 않고 새 결과를 기다린다.
setTimeout(() => { candidateAddress = '서울 강남구 다른로 999'; }, 60);
setTimeout(() => { candidateAddress = '서울 강남구 테헤란로 123'; }, 140);
$picker
setTimeout(() => {
  if (clicks !== 1 || clickedAddresses[0] !== '서울 강남구 테헤란로 123' || window.__flrPickerRan !== true || window.__flrPickerRunning !== false) {
    console.error(JSON.stringify({clicks, clickedAddresses, ran: window.__flrPickerRan, running: window.__flrPickerRunning}));
    process.exit(1);
  }
  process.exit(0);
}, 2800);
''');
      final result = Process.runSync('node', [temp.path]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      if (temp.existsSync()) temp.deleteSync();
    }
  });

  test('Kakao picker accepts the equivalent jibun but rejects a stale road', () {
    final picker = addressPickerFrameScript(
      '["서울특별시 강남구 테헤란로 123","서울특별시 강남구 역삼동 737"]',
    );
    final temp = File(
      '${Directory.systemTemp.path}/variant_picker_${DateTime.now().microsecondsSinceEpoch}.js',
    );
    try {
      temp.writeAsStringSync('''
let clicks = 0;
const clickedAddresses = [];
let candidateAddress = '서울 강남구 다른로 123';
global.window = global;
global.location = {hostname: 'postcode.map.kakao.com', search: ''};
global.sessionStorage = {getItem() { return null; }, setItem() {}};
const button = {scrollIntoView() {}, click() { clicks++; clickedAddresses.push(candidateAddress); }};
const span = {
  querySelector(selector) { return selector === 'button.link_post' ? button : null; },
  getAttribute(name) {
    if (name === 'data-addr') return candidateAddress;
    if (name === 'data-addr_type') return 'J';
    return null;
  },
};
global.document = {
  readyState: 'complete',
  getElementById(id) { return id === 'cQuery' ? {value: '서울특별시 강남구 테헤란로 123'} : null; },
  querySelectorAll(selector) { return selector === 'span.txt_address[data-addr]' ? [span] : []; },
  querySelector() { return null; },
};
setTimeout(() => { candidateAddress = '서울 강남구 역삼동 737'; }, 120);
$picker
setTimeout(() => {
  if (clicks !== 1 || clickedAddresses[0] !== '서울 강남구 역삼동 737') {
    console.error(JSON.stringify({clicks, clickedAddresses}));
    process.exit(1);
  }
  process.exit(0);
}, 2800);
''');
      final result = Process.runSync('node', [temp.path]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      if (temp.existsSync()) temp.deleteSync();
    }
  });

  test('iOS frame bridge targets the owning WebView by unique channel', () {
    final mirror = File('lib/mirror_session.dart').readAsStringSync();
    final bridge = File(
      'ios/Runner/FrameScriptBridge.swift',
    ).readAsStringSync();

    expect(mirror, contains("'targetChannel': _frameTargetChannel"));
    expect(mirror, contains('FrameScriptTarget_'));
    expect(bridge, contains('targets.object(forKey: targetChannel'));
    expect(bridge, isNot(contains('seen.allObjects.last')));
  });

  test('Dabang uses complex search for apartment and officetel addresses', () {
    for (final property in ['아파트', '오피스텔 원룸형', '오피스텔 분리/투룸형']) {
      final script = dabangInjectionScript(
        '{"propertyType":"$property","address":"서울특별시 강남구 역삼동 테헤란로 123","buildingName":"테헤란아파트"}',
      );
      expect(script, contains('await enterComplexAddress'));
      expect(script, contains("ul[class*=SearchList] > li"));
      expect(script, contains('[class*=AddressList]'));
      expect(script, contains('data.buildingName'));
      // 단지를 직접 고르는 쪽은 카카오 화면을 띄우지 않는다 — 그 갈림이 살아 있는가.
      expect(script, contains('if (complexProperty) {\n      await enterComplexAddress'));
      expect(script, contains('} else if (filled(data.address)) {'));
      expect(script, contains('await pickAddress();'));
    }
  });

  // 실물 실측(2026-09-20): 주소를 고르면 다방이 폼을 처음 상태로 되돌린다 — 주소와
  // 섹션이 다른 「제목」에 손으로 친 글자까지 사라졌다. 그래서 주소는 맨 뒤가 아니라
  // 값들보다 **먼저** 앉아야 하고, 그러고도 끝에서 한 번 더 대조해야 한다.
  test('Dabang settles the address before the other fields and reconciles last', () {
    final script = dabangInjectionScript(
      '{"propertyType":"오픈형 원룸","address":"서울특별시 강남구 역삼동 1","title":"제목"}',
    );
    final address = script.indexOf('await pickAddress();');
    final title = script.indexOf("fill('title'");
    final reconcile = script.indexOf('await reconcile();');

    expect(address, greaterThan(0), reason: '주소를 끝까지 받는 단계가 있어야 한다');
    expect(title, greaterThan(address), reason: '주소가 값들보다 먼저 앉아야 한다');
    expect(reconcile, greaterThan(title), reason: '대조는 모든 입력 뒤여야 한다');

    // 되돌림을 되돌리는 그물: 넣은 것마다 「다시 재는 법·다시 넣는 법」을 적어 둔다.
    expect(script, contains('const remember = (key, el, check, redo)'));
    expect(script, contains('const reconcile = async ()'));
    // 값을 받고 닫히는 창(월 관리비 상세입력) 안의 칸은 적어 두지 않는다 — 닫히면
    // 사라지는 것이 정상이라, 적어 두면 「사라졌다」는 오탐이 된다.
    expect(script, contains("el.closest('#modal-container')"));
    // 본 차례가 끝난 뒤 늦게 도착하는 주소도 대조를 한 번 더 부른다.
    expect(script, contains('if (settled && !replaying)'));
  });

  /* 사진은 폼이 다 채워진 **뒤에** 붙는다.
   *
   * [WebViewController.runJavaScript] 는 async 어댑터의 첫 await 에서 돌아오므로,
   * 표식이 없으면 사진 첨부가 폼 입력과 나란히 돈다. 그리고 다방은 주소를 고르는 순간
   * 폼을 처음 상태로 되돌려 방금 올라간 사진 카드까지 쓸어 간다 — 실기기에서 「카드가
   * 한때 1장까지 보였다가 사라졌습니다」로 끝난 것이 이것이다(2026-09-20). */
  test('어댑터 셋 다 사진을 붙여도 되는 때를 표식으로 알린다', () {
    for (final script in [
      zigbangInjectionScript('{}'),
      dabangInjectionScript('{}'),
      daangnInjectionScript('{}'),
    ]) {
      final down = script.indexOf('window.__flrFormDone = false;');
      final up = script.lastIndexOf('window.__flrFormDone = true;');
      expect(down, greaterThan(0), reason: '시작할 때 앞선 시도의 표식을 내려야 한다');
      expect(up, greaterThan(down), reason: '끝난 뒤에 세워야 한다');
      // 오류로 빠져나온 길에도 세운다 — 반쯤 채워진 폼이라도 사진은 붙는 편이 낫다.
      expect(up, greaterThan(script.indexOf('} catch (error)')));
    }
  });

  /* 직방은 **사진을 먼저** 붙이고 주소를 띄운다.
   *
   * 사진은 「이미지 넣기」 창 안에서 받는데, Radix 창이 열려 있는 동안은 body 의
   * 포인터가 막힌다 — 그 위에 주소 검색 겹이 떠 있으면 사람이 주소를 고를 수 없다.
   * 그래서 어댑터는 주소 직전에 표식을 세워 사진을 부르고, 사진이 끝났다는 말을 들은
   * 뒤에 주소로 간다. */
  test('직방 어댑터는 사진이 끝나기를 기다렸다가 주소 검색을 띄운다', () {
    final script = zigbangInjectionScript('{}');
    final handOff = script.indexOf('if (Number(data.photoCount) > 0) {');
    final wait = script.indexOf('window.__flrPhotosDone !== true');
    final address = script.indexOf("if (window.__flrPostcode) window.__flrPostcode.query");

    expect(handOff, greaterThan(0), reason: '사진 차례를 내주는 자리가 있어야 한다');
    expect(wait, greaterThan(handOff), reason: '내준 뒤에 기다려야 한다');
    expect(address, greaterThan(wait), reason: '주소는 사진 뒤여야 한다');
    // 사진이 없으면 기다리지 않고, 끝내 말이 없어도 주소로 넘어간다.
    expect(script, contains('const until = Date.now() + 300000;'));
    expect(script, contains('window.__flrPhotosDone = false;'));
    // 직방도 이제 사진을 받는다 — 「미지원」 안내는 사라져야 한다.
    expect(script, isNot(contains('사진 자동 첨부를 지원하지 않아')));
  });

  // [reconcile] 은 없어진 값을 다시 넣는데, 매물유형을 다시 누르면 7행이 통째로 다시
  // 그려진다. 그 다시 그리기가 방금 올라간 사진 카드를 쓸어 간다. 사진 카드가 생기고
  // 사라지는 것 자체도 body 의 변화라, 막지 않으면 사진이 제가 저를 지우게 된다.
  test('사진을 붙이는 동안 다방 어댑터는 폼을 건드리지 않는다', () {
    final script = dabangInjectionScript('{}');
    expect(
      script,
      contains(
        'const photoBusy = () => !!window.__flrPhotos && '
        'Date.now() < (window.__flrPhotos.until || 0);',
      ),
    );
    expect(script, contains('if (photoBusy()) return;'));
    // 사진 자리 안에서만 일어난 변화는 폼의 되돌림이 아니다.
    expect(
      script,
      contains('records.every(record => spot.contains(record.target))'),
    );
  });

  // 되돌림 감시자가 [reconcile] 을 여러 번 부른다. 부를 때마다 같은 항목을 또 빼면
  // 검증 숫자가 0까지 내려가고 「확인할 항목」에 같은 줄이 쌓인다.
  test('여러 번 대조해도 검증 숫자와 확인할 항목이 부풀지 않는다', () {
    final script = dabangInjectionScript('{}');
    expect(
      script,
      contains(
        'output.verified = Math.max(0, output.verified + deducted - stuck.length);',
      ),
    );
    expect(script, contains('deducted = stuck.length;'));
    expect(script, contains('/: 넣은 값이 폼에서 사라져/.test(output.missing[i])'));
  });

  // 실물 실측(2026-09-20): 사용승인일 칸은 넣은 `20250301` 을 제 형식으로 고쳐
  // 되돌려 준다. 글자 그대로 견주면 넣고도 실패로 읽혔다.
  test('Dabang compares the approval date by digits and says what it read', () {
    final script = dabangInjectionScript(
      '{"propertyType":"빌라/연립/다세대","approvalDate":"2025-03-01"}',
    );
    expect(script, contains('const sameDigits = (got, wanted)'));
    expect(
      script,
      contains('const fill = (key, locate, value, transform = v => v, same = sameText)'),
    );
    // 느슨한 비교는 **그 칸에만** 준다. 전부에 주면 진짜 실패가 묻힌다.
    expect(
      script,
      contains("data.approvalDate, v => String(v).replace(/-/g, ''), sameDigits)"),
    );
    // 입주 가능 일자도 같은 칸이다 — 폼이 제 형식으로 고쳐 되돌려 준다.
    expect(
      script,
      contains("data.moveInDate, v => String(v).replace(/-/g, ''), sameDigits)"),
    );
    // 정의 한 번, 쓰는 곳은 날짜 칸 둘 — 그게 전부여야 한다.
    expect('sameDigits'.allMatches(script).length, 3);
    // 어긋났을 때 폼이 **무엇으로 읽었는지**를 적는다. 이것이 없어 한 번 더 재야 했다.
    expect(script, contains('」인데 폼은 「'));
  });

  /* 오피스텔·아파트는 주소 대신 **단지**를 고른다(실물 2026-09-21).
   *
   * 대분류를 바꾸면 다방이 매물 정보 7행을 통째로 다시 그리므로 어댑터는 그것부터 하고,
   * 시/도→시/군/구→동을 법정동 코드로 고른 뒤 단지명으로 단지를 확정한다. 단지명이
   * 없으면 고를 수 없다 — 목록에는 이름만 있고 주소가 없어 견줄 것이 없기 때문이다.
   * 그때는 **아무것도 누르지 않고** 사람에게 넘긴다. 이 세 갈래를 실제로 돌려 본다. */
  test('Dabang picks the complex by name and switches the major first', () {
    for (final scenario in [
      // (통합 폼의 매물 종류, 폼에 이미 골라져 있는 대분류, 단지명)
      ('아파트', '오피스텔', '역삼래미안'),
      ('오피스텔', '아파트', '역삼아이파크'),
      ('아파트', '오피스텔', ''),
    ]) {
      final (type, opened, complexName) = scenario;
      final picker = dabangInjectionScript(
        '{"propertyType":"$type","complexName":"$complexName",'
        '"address":"서울특별시 강남구 테헤란로 123",'
        '"legalDongCode":"1168010100","sido":"서울","sigungu":"강남구",'
        '"bname":"역삼동","exclusiveArea":"59.94","supplyArea":"79.93"}',
      );
      final temp = File(
        '${Directory.systemTemp.path}/complex_picker_${DateTime.now().microsecondsSinceEpoch}.js',
      );
      try {
        temp.writeAsStringSync('''
let major = '$opened';
let pickedComplex = null;
let report = null;

// ── 다방 폼 흉내 ───────────────────────────────────────────────
// 어댑터가 실제로 짚는 자리만 세운다: #room_info 의 (th, td) 쌍, 매물유형 행의 대분류
// 단추와 소분류 label, 매물 주소 칸의 지역 선택 셋 · 단지검색 · 후보 목록 · 확정된 주소,
// 매물 크기 칸의 평형 선택.
class FakeControl {
  constructor(tagName) { this.tagName = tagName; this._value = ''; this.disabled = false; this.checked = false; }
  get value() { return this._value; }
  set value(value) { this._value = String(value); }
  focus() {} blur() {} closest() { return null; } dispatchEvent() { return true; }
}
global.HTMLSelectElement = class extends FakeControl {
  get value() { return this._value; } set value(value) { this._value = String(value); }
};
global.HTMLInputElement = class extends FakeControl {
  get value() { return this._value; } set value(value) { this._value = String(value); }
};
global.HTMLTextAreaElement = class extends FakeControl {
  get value() { return this._value; } set value(value) { this._value = String(value); }
};
global.Event = class { constructor(type) { this.type = type; } };
global.FocusEvent = global.Event;
global.PointerEvent = global.Event;
global.MouseEvent = global.Event;
global.MutationObserver = class { observe() {} };

const node = (props) => Object.assign(
  {tagName: 'DIV', textContent: '', querySelector: () => null, querySelectorAll: () => [],
   getAttribute: () => null, closest: () => null, dispatchEvent: () => true},
  props,
);
const option = (value, label) => ({value, textContent: label});
const regionSelect = (...options) => Object.assign(
  new HTMLSelectElement('SELECT'), {options: [option('', '선택'), ...options]},
);
const city = regionSelect(option('11', '서울특별시'));
const gu = regionSelect(option('11680', '강남구'));
const dong = regionSelect(option('11680101', '역삼동'));
// 평형은 「공급 / 전용」이다. 전용 59.94 에 맞는 것 하나를 둔다.
const space = regionSelect(
  option('1', '24A (79.93㎡ / 59.94㎡)'), option('2', '32B (105.78㎡ / 84.96㎡)'),
);
const search = new HTMLInputElement('INPUT');
const dongInput = new HTMLInputElement('INPUT');
const hoInput = new HTMLInputElement('INPUT');

// 단지 목록은 칸에 글자가 들어가야 뜬다 — 실물이 그렇다.
const candidates = () => search.value
  ? [node({textContent: '역삼래미안', dispatchEvent: (event) => {
      if (event.type === 'click') pickedComplex = '역삼래미안';
      return true;
    }}),
     node({textContent: '역삼아이파크', dispatchEvent: (event) => {
      if (event.type === 'click') pickedComplex = '역삼아이파크';
      return true;
    }})]
  : [];

const addressTd = node({
  tagName: 'TD',
  querySelector(selector) {
    if (selector === 'select[name="city"]') return city;
    if (selector === 'select[name="gu"]') return gu;
    if (selector === 'select[name="dong"]') return dong;
    if (selector === 'input[placeholder="단지검색"]') return search;
    if (selector === 'input[name="dong"]') return dongInput;
    if (selector === 'input[name="ho"]') return hoInput;
    if (selector === '[class*=AddressList]') {
      return pickedComplex ? node({textContent: '서울특별시 강남구 역삼동 ' + pickedComplex}) : null;
    }
    return null;
  },
  querySelectorAll(selector) {
    if (selector === 'ul[class*=SearchList] > li') return candidates();
    if (selector === '[class*=AddressList] li') {
      return pickedComplex ? [node({textContent: pickedComplex})] : [];
    }
    return [];
  },
});
const sizeTd = node({
  tagName: 'TD',
  querySelector: (selector) => selector === 'select[name="complexSpaceSeq"]' ? space : null,
});
// 소분류 label 이 지금 골라진 대분류를 말해 준다 — 대분류 단추에는 표식이 없다.
const minors = () => major === '주택'
  ? ['빌라/연립/다세대', '단독주택', '다가구주택', '상가주택']
  : [major];
const majorTd = node({
  tagName: 'TD',
  querySelectorAll: (selector) => selector === 'label'
    ? minors().map(name => node({textContent: name,
        querySelector: () => new HTMLInputElement('INPUT')}))
    : [],
});
const majorButtons = ['주택', '오피스텔', '아파트'].map(label => node({
  tagName: 'BUTTON', textContent: label,
  dispatchEvent: (event) => { if (event.type === 'click') major = label; return true; },
}));
const row = (label, cell) => {
  const th = node({tagName: 'TH', textContent: label, nextElementSibling: cell,
                   querySelector: (s) => s === 'th h1' ? null : null});
  const tr = node({
    tagName: 'TR',
    querySelector: (selector) => selector === 'th h1' ? node({textContent: label}) : null,
    querySelectorAll: (selector) => selector === 'button'
      ? (label === '매물유형' ? majorButtons : [])
      : selector === 'label' ? (label === '매물유형' ? majorTd.querySelectorAll('label') : []) : [],
  });
  return {th, tr};
};
const rows = [row('매물유형', majorTd), row('매물 주소', addressTd), row('매물 크기', sizeTd)];
const root = node({
  querySelectorAll: (selector) => selector === 'th' ? rows.map(r => r.th)
    : selector === 'tr' ? rows.map(r => r.tr) : [],
});
global.window = global;
global.document = {
  body: node({}),
  getElementById: (id) => id === 'room_info' ? root : null,
  querySelector: () => null,
  querySelectorAll: () => [],
};
global.ListingResult = {postMessage(value) {
  report = JSON.parse(value);
  console.log(JSON.stringify({major, pickedComplex,
    missing: report.missing, unsupported: report.unsupported}));
  process.exit(0);
}};
$picker
setTimeout(() => {
  console.error(JSON.stringify({failure: 'timeout', major, pickedComplex, report}));
  process.exit(1);
}, 90000);
''');
        final result = Process.runSync('node', [temp.path]);
        final why = '$type: ${result.stdout}\n${result.stderr}';
        expect(result.exitCode, 0, reason: why);
        final seen = jsonDecode(result.stdout.toString().trim()) as Map;
        // 대분류는 통합 폼의 매물 종류대로 바뀌어 있어야 한다.
        expect(seen['major'], type, reason: why);
        final missing = (seen['missing'] as List).cast<String>();
        if (complexName.isEmpty) {
          // 단지명이 없으면 아무 단지도 누르지 않고, 왜 못 골랐는지 적어 올린다.
          expect(seen['pickedComplex'], isNull, reason: why);
          expect(
            missing.where((line) => line.startsWith('address:')),
            contains(contains('단지명이 없어')),
            reason: why,
          );
        } else {
          expect(seen['pickedComplex'], complexName, reason: why);
          expect(
            missing.where((line) => line.startsWith('address:')),
            isEmpty,
            reason: why,
          );
        }
      } finally {
        if (temp.existsSync()) temp.deleteSync();
      }
    }
  });

  test('generated adapters are valid JavaScript', () {
    final scripts = {
      'zigbang': zigbangInjectionScript('{}'),
      'dabang': dabangInjectionScript('{}'),
      'bridge': postcodeBridgeScript('""'),
      'framePicker': addressPickerFrameScript('""'),
      'daangn': daangnInjectionScript('{}'),
      'zigbangPhotoBridge': listingPhotoBridgeScript(PhotoTarget.zigbang),
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
