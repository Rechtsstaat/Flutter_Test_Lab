import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jibang_listing_test/main.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Drives the real form → 「당근에 보내기」 → WKWebView flow against the
/// Daangn mirror, then reads the mirror's own DOM to check what landed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('auto-filled listing and one photo land in the Daangn mirror', (
    tester,
  ) async {
    final photos = await _writePngFiles(1);
    addTearDown(() => File(photos.first.path).parent.delete(recursive: true));
    final run = await _sendToDaangn(tester, photos: photos);
    final dom = run.dom;
    final reason = run.describe();

    expect(run.photoFailure, isNull, reason: reason);
    expect(run.missing, isEmpty, reason: reason);
    expect(run.violations, isEmpty, reason: reason);
    expect(dom['path'], '/daangn/form/article/', reason: reason);
    expect(dom['dialogOpen'], isFalse, reason: reason);

    expect(dom['address'], contains('테헤란로 123'), reason: reason);
    expect(dom['address'], contains('101동 202호'), reason: reason);
    expect(dom['salesType'], '오픈형 원룸', reason: reason);
    // 건축물대장은 이 주소를 업무시설 · 1985-06-13 · 15층 · 엘리베이터로 채운다.
    // 어댑터는 통합 폼 값으로 되돌려야 한다.
    expect(dom['usage'], '공동주택', reason: reason);
    expect(dom['approval'], '2018-03-01', reason: reason);
    expect(dom['topFloor'], '10', reason: reason);
    expect(dom['area'], '33.05', reason: reason);
    expect(dom['supply'], '40.12', reason: reason);
    expect(dom['trades'], ['월세'], reason: reason);
    expect(dom['tradeInputs'], {
      'trades.0.price@월세': '1000',
      'trades.0.monthlyPay@월세': '65',
      'trades.0.adjustable@월세': false,
    }, reason: reason);
    expect(dom['rooms'], '1', reason: reason);
    expect(dom['baths'], '1', reason: reason);
    expect(dom['floor'], '5', reason: reason);
    expect(dom['orientation'], '남향', reason: reason);
    expect(dom['loan'], ['가능'], reason: reason);
    expect(dom['pet'], ['가능'], reason: reason);
    expect(dom['parking'], ['가능'], reason: reason);
    expect(dom['parkingTotal'], '10', reason: reason);
    expect(dom['parkingPer'], '0.7', reason: reason);
    expect(dom['violation'], isEmpty, reason: reason);
    expect(dom['features'], ['엘리베이터'], reason: reason);
    expect(
      dom['appliances'],
      unorderedEquals(['에어컨', '세탁기', '냉장고']),
      reason: reason,
    );
    expect(
      dom['feeMode'],
      unorderedEquals(['정액 관리비', '10만원 미만 혹은 의뢰인이 세부 내역 미제공']),
      reason: reason,
    );
    expect(dom['period'], ['직전 월'], reason: reason);
    expect(dom['total'], '8', reason: reason);
    expect(dom['includes'], unorderedEquals(['인터넷비', '수도료']), reason: reason);
    expect(dom['moveIn'], ['즉시 입주 가능'], reason: reason);
    expect(dom['content'], '역세권에 위치한 깨끗한 원룸입니다.', reason: reason);
    expect(dom['oneLine'], '채광 좋은 강남 원룸', reason: reason);
    expect(dom['memo'], '임대인 연락은 오후에', reason: reason);
    expect(dom['phone'], '010-1234-5678', reason: reason);
    expect(dom['photos'], 1, reason: reason);
    expect(dom['photoKeys'], 1, reason: reason);
    expect(dom['strictViolations'], 0, reason: reason);

    for (final expected in [
      '매물 기본 주소',
      '건축물대장',
      '방향 기준',
      '보안 및 시설 옵션 CCTV',
      '보안 및 시설 옵션 테라스',
      '난방 방식',
      'LH 전세임대 여부',
      '융자금',
    ]) {
      expect(
        run.unsupported.any((line) => line.startsWith(expected)),
        isTrue,
        reason: '$expected 안내가 없습니다.\n$reason',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('apartment, short-term, fixed fee over 100k and dated move-in', (
    tester,
  ) async {
    final run = await _sendToDaangn(
      tester,
      overrides: {
        'propertyType': '아파트',
        'floorAll': '15',
        'floor': '7',
        'floorPrivate': true,
        'singleBuilding': true,
        'shortTerm': true,
        'managementFee': '15',
        'moveInType': '날짜 지정',
        'moveInDate': '2026-10-01',
        'moveInNegotiable': true,
        'elevator': '없음',
        'parking': '주차 불가능',
        'violation': '위반건축물 해당',
        'loanAvailable': '확인 필요',
        'petAllowed': '불가능',
        'appliances': ['전자레인지', '가스레인지', '건조기'],
      },
    );
    final dom = run.dom;
    final reason = run.describe();

    expect(run.missing, isEmpty, reason: reason);
    expect(run.violations, isEmpty, reason: reason);
    expect(dom['address'], contains('202호'), reason: reason);
    expect(dom['address'], isNot(contains('101동')), reason: reason);
    expect(dom['salesType'], '아파트', reason: reason);
    expect(dom['topFloor'], '15', reason: reason);
    expect(dom['floor'], '7', reason: reason);
    // 7/15 층 → 중층
    expect(
      dom['floorChecks'],
      unorderedEquals(['저/중/고로 표시', '중층']),
      reason: reason,
    );
    expect(dom['trades'], ['월세', '단기'], reason: reason);
    expect(dom['tradeInputs'], {
      'trades.0.price@월세': '1000',
      'trades.0.monthlyPay@월세': '65',
      'trades.0.adjustable@월세': false,
      'trades.1.price@단기': '1000',
      'trades.1.monthlyPay@단기': '65',
      'trades.1.description@조건': '',
    }, reason: reason);
    // 건축물대장이 켠 엘리베이터를 다시 끈다.
    expect(dom['features'], isEmpty, reason: reason);
    expect(dom['loan'], ['확인 필요'], reason: reason);
    expect(dom['pet'], ['불가능'], reason: reason);
    expect(dom['parking'], ['불가능'], reason: reason);
    expect(dom['parkingTotal'], isNull, reason: reason);
    expect(dom['violation'], ['해당'], reason: reason);
    expect(
      dom['appliances'],
      unorderedEquals(['전자렌지', '가스렌지']),
      reason: reason,
    );
    expect(dom['feeMode'], ['정액 관리비'], reason: reason);
    expect(dom['period'], ['직전 월'], reason: reason);
    expect(dom['items'], {
      '전기료': ['쓴 만큼'],
      '수도료': ['정액'],
      '가스비': ['쓴 만큼'],
      '난방비': ['쓴 만큼'],
      '인터넷비': ['정액'],
      'TV': ['쓴 만큼'],
      '기타': ['쓴 만큼'],
    }, reason: reason);
    expect(dom['moveInDate'], '2026-10-01', reason: reason);
    expect(dom['moveIn'], ['입주일 협의 가능'], reason: reason);

    for (final expected in [
      '단기 매물',
      '단기 조건',
      '층수 비공개',
      '공용 관리비 금액',
      '정액 항목 금액(수도료·인터넷비)',
      '관리비 기타 항목',
      '가전·가구 옵션 건조기',
    ]) {
      expect(
        run.unsupported.any((line) => line.startsWith(expected)),
        isTrue,
        reason: '$expected 안내가 없습니다.\n$reason',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets(
    'jeonse villa with other-basis fee, semi-basement and negotiable move-in',
    (tester) async {
      final run = await _sendToDaangn(
        tester,
        overrides: {
          'propertyType': '투룸 빌라',
          'buildingUse': '교정 및 군사시설',
          'trade': '전세',
          'monthlyRent': null,
          'floor': '반지하',
          'manageMethod': '기타 부과',
          'moveInType': '협의 가능',
        },
      );
      final dom = run.dom;
      final reason = run.describe();

      expect(run.missing, isEmpty, reason: reason);
      expect(run.violations, isEmpty, reason: reason);
      expect(dom['salesType'], '빌라(투룸 이상)', reason: reason);
      expect(dom['usage'], '교정시설', reason: reason);
      expect(dom['trades'], ['전세'], reason: reason);
      expect(dom['tradeInputs'], {'trades.0.price@전세': '1000'}, reason: reason);
      expect(dom['floorChecks'], ['반지하'], reason: reason);
      expect(dom['floorDisabled'], isTrue, reason: reason);
      expect(dom['feeMode'], ['기타 부과'], reason: reason);
      expect(dom['period'], ['직전 월'], reason: reason);
      expect(dom['total'], '8', reason: reason);
      expect(dom['includes'], unorderedEquals(['인터넷비', '수도료']), reason: reason);
      expect(dom['etcBasis'], ['관리규약에 따라 부과'], reason: reason);
      expect(dom['moveIn'], isEmpty, reason: reason);
      expect(
        run.unsupported.any((line) => line.startsWith('입주 방식 협의 가능')),
        isTrue,
        reason: reason,
      );
      expect(
        run.unsupported.any((line) => line.startsWith('건축물 용도 교정 및 군사시설')),
        isTrue,
        reason: reason,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'duplex sale with no management fee on the first basement floor',
    (tester) async {
      final run = await _sendToDaangn(
        tester,
        overrides: {
          'propertyType': '복층형 원룸',
          'roomLayout': '복층형 원룸',
          'trade': '매매',
          'salePrice': '45000',
          'deposit': null,
          'monthlyRent': null,
          'noManagementFee': true,
          'floor': '지하 1층',
        },
      );
      final dom = run.dom;
      final reason = run.describe();

      expect(run.missing, isEmpty, reason: reason);
      expect(run.violations, isEmpty, reason: reason);
      expect(dom['salesType'], '오픈형 원룸', reason: reason);
      expect(dom['trades'], ['매매'], reason: reason);
      expect(dom['tradeInputs'], {
        'trades.0.price@매매': '45000',
      }, reason: reason);
      expect(dom['floorChecks'], ['지하'], reason: reason);
      expect(dom['floor'], '1', reason: reason);
      expect(
        dom['feeMode'],
        unorderedEquals(['정액 관리비', '10만원 미만 혹은 의뢰인이 세부 내역 미제공']),
        reason: reason,
      );
      expect(dom['total'], '0', reason: reason);
      expect(dom['features'], unorderedEquals(['복층', '엘리베이터']), reason: reason);
      expect(
        run.unsupported.any((line) => line.startsWith('관리비 없음')),
        isTrue,
        reason: reason,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets('short-term rooftop listing with unverifiable management fee', (
    tester,
  ) async {
    final run = await _sendToDaangn(
      tester,
      overrides: {
        'trade': '단기',
        'deposit': null,
        'monthlyRent': null,
        'floor': '옥탑',
        'manageMethod': '확인 불가',
      },
    );
    final dom = run.dom;
    final reason = run.describe();

    expect(run.missing, isEmpty, reason: reason);
    expect(run.violations, isEmpty, reason: reason);
    expect(dom['trades'], ['단기'], reason: reason);
    expect(dom['floor'], '', reason: reason);
    expect(dom['features'], unorderedEquals(['옥탑', '엘리베이터']), reason: reason);
    expect(dom['feeMode'], ['확인 불가'], reason: reason);
    expect(dom['unavailable'], [
      '미등기건물, 신축건물 등 관리비 내역이 확인불가한 경우',
    ], reason: reason);
    for (final expected in ['단기 보증금·월세', '해당 층 옥탑']) {
      expect(
        run.unsupported.any((line) => line.startsWith(expected)),
        isTrue,
        reason: '$expected 안내가 없습니다.\n$reason',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class _Run {
  _Run(this.result, this.dom, this.photoFailure);
  final Map<String, dynamic> result;
  final Map<String, dynamic> dom;
  final String? photoFailure;

  List<String> _list(String key) =>
      List<String>.from(result[key] as List? ?? const []);
  List<String> get missing => _list('missing');
  List<String> get violations => _list('violations');
  List<String> get unsupported => _list('unsupported');

  String describe() => const JsonEncoder.withIndent('  ')
      .convert({'result': result, 'dom': dom, 'photoFailure': photoFailure});
}

Future<_Run> _sendToDaangn(
  WidgetTester tester, {
  Map<String, Object?> overrides = const {},
  List<XFile> photos = const [],
}) async {
  final published = Completer<(WebViewController, Map<String, dynamic>)>();
  final photosDone = Completer<String?>();
  await tester.pumpWidget(
    MaterialApp(
      home: ListingFormPage(
        pickImages: () async => photos,
        remotePageBuilder: (values, platform, selected) {
          final target = {...values, ...overrides}
            ..removeWhere((_, value) => value == null);
          return RemoteFormPage(
            values: target,
            platform: platform,
            photos: selected,
            onListingResult: (controller, result) {
              if (!published.isCompleted) {
                published.complete((controller, result));
              }
            },
            onPhotoTransferComplete: (_, failure) {
              if (!photosDone.isCompleted) photosDone.complete(failure);
            },
          );
        },
      ),
    ),
  );

  await tester.tap(find.text('자동 채우기'));
  await tester.pump();
  final scrollable = find.byType(Scrollable).first;
  if (photos.isNotEmpty) {
    await tester.scrollUntilVisible(
      find.byTooltip('사진 추가'),
      400,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('사진 추가'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('${photos.length}/20'), findsOneWidget);
  }

  // One CTA posts to every selected platform, so narrow the run to 당근 in
  // 플랫폼 선택 at the end of the form.
  await tester.scrollUntilVisible(
    find.text('플랫폼 선택'),
    600,
    scrollable: scrollable,
  );
  await tester.ensureVisible(find.text('당근'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('직방'));
  await tester.tap(find.text('다방'));
  await tester.pump();

  await tester.tap(find.text('광고 등록'));
  // The Process Hub animates for as long as the platform is being worked on
  // — pump past the route change by hand.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();

  final (controller, result) = await published.future.timeout(
    const Duration(minutes: 3),
    onTimeout: () => throw TimeoutException(
      '당근 미러의 페이지 로드·자동 입력이 3분 안에 끝나지 않았습니다. '
      '시뮬레이터 네트워크나 Basic 인증을 확인해 주세요.',
    ),
  );
  final photoFailure = photos.isEmpty
      ? null
      : await photosDone.future.timeout(const Duration(minutes: 2));
  return _Run(result, await _readDaangnDom(controller), photoFailure);
}

Future<List<XFile>> _writePngFiles(int count) async {
  const png =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWZkAAAAASUVORK5CYII=';
  final directory = await Directory.systemTemp.createTemp('daangn_wkwebview_');
  final photos = <XFile>[];
  for (var index = 0; index < count; index++) {
    final file = File('${directory.path}/room-${index + 1}.png');
    await file.writeAsBytes(base64Decode(png), flush: true);
    photos.add(XFile(file.path));
  }
  return photos;
}

Future<Map<String, dynamic>> _readDaangnDom(
  WebViewController controller,
) async {
  const script = r'''(() => {
    const text = el => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
    const rowOf = label => {
      const span = [...document.querySelectorAll('span.t4-bold')].find(s => text(s) === label);
      return span ? span.closest('div.flex.items-start.gap-x3') : null;
    };
    const on = label => {
      const row = rowOf(label);
      return row ? [...row.querySelectorAll('label')].filter(l => l.hasAttribute('data-checked')).map(text) : null;
    };
    const value = selector => {
      const el = document.querySelector(selector);
      return el ? el.value : null;
    };
    const shown = name => {
      const button = document.querySelector('button[name="' + name + '"]');
      const shown = button && button.parentElement.querySelector('.seed-input-button__value');
      return shown ? text(shown) : null;
    };
    const upload = document.getElementById('image-upload');
    const box = upload && upload.parentElement.querySelector('.transition-all');
    const cells = box ? [...box.querySelectorAll('div.grid [aria-roledescription="sortable"]')] : [];
    const tradeInputs = {};
    for (const el of document.querySelectorAll('[name^="trades."]')) {
      const row = el.closest('div.flex.items-start.gap-x3');
      const title = row ? text(row.querySelector('span.t4-bold')) : '';
      tradeInputs[el.name + '@' + title] = el.type === 'checkbox' ? el.checked : el.value;
    }
    const floor = document.querySelector('input[name="floor"]');
    return JSON.stringify({
      path: location.pathname,
      dialogOpen: !!document.querySelector('[role="dialog"][aria-modal="true"]'),
      address: text(rowOf('주소')),
      salesType: shown('salesType'),
      usage: shown('buildingUsage'),
      orientation: shown('buildingOrientation'),
      area: value('input[name="area"]'),
      supply: value('input[name="supplyArea"]'),
      trades: on('거래 유형'),
      tradeInputs,
      approval: value('input[name="buildingApprovalDate"]'),
      rooms: value('input[name="roomCnt"]'),
      baths: value('input[name="bathroomCnt"]'),
      topFloor: value('input[name="topFloor"]'),
      floor: floor ? floor.value : null,
      floorDisabled: floor ? floor.disabled : null,
      floorChecks: on('층 정보'),
      loan: on('대출'),
      pet: on('반려동물'),
      parking: on('주차'),
      parkingTotal: value('input[name="availableTotalParkingSpots"]'),
      parkingPer: value('input[name="availableParkingSpotsV2"]'),
      violation: on('위반건축물'),
      features: on('매물 특징'),
      appliances: on('가전/가구'),
      feeMode: on('부과 방식'),
      period: on('부과 기준'),
      total: value('input[name="totalManageCost"]'),
      includes: on('관리비에 포함'),
      items: Object.fromEntries(['전기료', '수도료', '가스비', '난방비', '인터넷비', 'TV', '기타'].map(k => [k, on(k)])),
      etcBasis: on('관리비 세부 타입(실비 근거)'),
      unavailable: on('확인 불가 사유'),
      moveIn: on('입주가능일'),
      moveInDate: value('input[name="moveInDate"]'),
      content: value('textarea[name="content"]'),
      oneLine: value('input[name="addressInfo"]'),
      memo: value('textarea[name="memoContent"]'),
      phone: value('input[name="lessorPhoneNumber"]'),
      photos: cells.length,
      photoKeys: cells.filter(c => c.getAttribute('data-mirror-key')).length,
      strictViolations: (window.__FLR_VIOLATIONS__ || []).length,
    });
  })()''';
  Object? value = await controller.runJavaScriptReturningResult(script);
  for (var index = 0; index < 2 && value is String; index++) {
    value = jsonDecode(value);
  }
  return Map<String, dynamic>.from(value as Map);
}
