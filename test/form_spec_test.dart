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

  testWidgets(
    'the register CTA gates on validation and routes the picked channel',
    (tester) async {
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
          (widget) => widget is BrandButton && widget.label == '광고 등록',
        ),
      );

      // With nothing filled in, the one CTA stays off and says why.
      expect(cta().onPressed, isNull);
      expect(find.textContaining('필수 항목'), findsOneWidget);

      // Narrow the run to 다방 in 플랫폼 선택, at the end of the long form.
      await tester.scrollUntilVisible(
        find.text('플랫폼 선택'),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('당근'));
      await tester.tap(find.text('직방'));
      await tester.tap(find.text('당근'));
      await tester.pump();
      expect(cta().onPressed, isNull);

      await tester.tap(find.text('자동 채우기'));
      await tester.pump();
      expect(cta().onPressed, isNotNull);
      expect(find.textContaining('필수 항목'), findsNothing);

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
      expect(receivedPhotos, isEmpty);
      expect(receivedValues, isNot(contains('photoCount')));
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
      expect(script, contains('filled(data.address) && !complexProperty'));
    }
  });

  test(
    'Dabang executes complex selection without a building name and switches majors',
    () {
      for (final scenario in [
        ('아파트', '오피스텔', false),
        ('오피스텔 원룸형', '아파트', false),
        ('아파트', '오피스텔', true),
      ]) {
        final targetLabel = scenario.$1.startsWith('오피스텔') ? '오피스텔' : '아파트';
        final picker = dabangInjectionScript(
          '{"propertyType":"${scenario.$1}","address":"서울특별시 강남구 테헤란로 123",'
          '"roadAddress":"서울특별시 강남구 테헤란로 123",'
          '"jibunAddress":"서울특별시 강남구 역삼동 123","noManagementFee":true}',
        );
        final temp = File(
          '${Directory.systemTemp.path}/complex_picker_${DateTime.now().microsecondsSinceEpoch}.js',
        );
        try {
          temp.writeAsStringSync('''
let selectedMajor = '${scenario.$2}';
let picked = false;
let report = null;
class FakeControl {
  constructor(tagName) { this.tagName = tagName; this._value = ''; this.disabled = false; }
  get value() { return this._value; }
  set value(value) { this._value = String(value); }
  focus() {} blur() {} dispatchEvent() { return true; }
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
global.PointerEvent = global.Event;
global.MouseEvent = global.Event;
global.MutationObserver = class { observe() {} };
const option = (value, label) => ({value, textContent: label});
const selects = [
  Object.assign(new HTMLSelectElement('SELECT'), {options: [option('', '선택'), option('서울', '서울')]}),
  Object.assign(new HTMLSelectElement('SELECT'), {options: [option('', '선택'), option('강남구', '강남구')]}),
  Object.assign(new HTMLSelectElement('SELECT'), {options: [option('', '선택'), option('역삼동', '역삼동')]}),
];
const candidateButton = {dispatchEvent(event) { if (event.type === 'click') picked = true; }};
const candidate = {
  textContent: '건물명 없는 후보',
  attributes: ${scenario.$3 ? '[]' : "[{name: 'data-road-address', value: '서울특별시 강남구 테헤란로 123'}]"},
  getAttribute(name) { return ${scenario.$3 ? 'null' : "name === 'data-road-address' ? '서울특별시 강남구 테헤란로 123' : null"}; },
  querySelector() { return candidateButton; },
};
const otherCandidate = {
  textContent: '다른 건물명 없는 후보', attributes: [],
  getAttribute() { return null; }, querySelector() { return candidateButton; },
};
const summary = {textContent: '도로명 서울특별시 강남구 테헤란로 123 지번 서울특별시 강남구 역삼동 123'};
const cell = {
  tagName: 'TD',
  querySelectorAll(selector) {
    if (selector === 'select') return selects;
    if (selector === 'ul[class*=SearchList] > li') return ${scenario.$3 ? '[candidate, otherCandidate]' : '[candidate]'};
    if (selector === '[class*=AddressList] li') return [];
    if (selector === 'button') return [];
    return [];
  },
  querySelector(selector) {
    if (selector === '[class*=AddressList]') return picked ? summary : null;
    return null;
  },
};
const th = {textContent: '매물 주소', nextElementSibling: cell};
const root = {
  querySelectorAll(selector) {
    if (selector === 'th') return [th];
    if (selector === 'tr') return [];
    return [];
  },
};
const majorButton = label => ({
  textContent: label,
  className: '',
  getAttribute(name) { return name === 'aria-pressed' ? String(selectedMajor === label) : null; },
  querySelector() { return null; },
  dispatchEvent(event) { if (event.type === 'click') selectedMajor = label; },
});
const majorButtons = [majorButton('주택'), majorButton('오피스텔'), majorButton('아파트')];
global.window = global;
global.document = {
  body: {},
  getElementById(id) { return id === 'room_info' ? root : null; },
  querySelector(selector) { return selector === '#room_info input[name="buildingType"]' ? null : null; },
  querySelectorAll(selector) { return selector === 'button' ? majorButtons : []; },
};
global.ListingResult = {postMessage(value) {
  report = JSON.parse(value);
  const addressMissing = report.missing.some(item => item.startsWith('address:'));
  const correct = ${scenario.$3 ? '!picked && addressMissing' : 'picked && !addressMissing'};
  if (selectedMajor !== '$targetLabel' || !correct) {
    console.error(JSON.stringify({selectedMajor, picked, report}));
    process.exit(1);
  }
  process.exit(0);
}};
$picker
setTimeout(() => {
  console.error(JSON.stringify({failure: 'timeout', selectedMajor, picked, report}));
  process.exit(1);
}, 10000);
''');
          final result = Process.runSync('node', [temp.path]);
          expect(
            result.exitCode,
            0,
            reason: '${scenario.$1}: ${result.stdout}\n${result.stderr}',
          );
        } finally {
          if (temp.existsSync()) temp.deleteSync();
        }
      }
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
