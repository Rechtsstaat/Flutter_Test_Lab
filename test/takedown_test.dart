// 매물을 내리는 쪽 — 번호를 기억하고, 그 번호의 카드만 내리게 한다.
//
// 브라우저 없이 지킬 수 있는 것만 여기서 지킨다: 무엇을 기억하는가, 무엇을 스크립트에
// 실어 보내는가, 누른 것을 어디까지 세는가. 「목록에서 정말 찾아내는가」는 실제 페이지가
// 있어야 답할 수 있는 물음이라 test/mirror_browser_test.dart 로 간다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/data/app_store.dart';
import 'package:jibang_listing_test/fields.dart';
import 'package:jibang_listing_test/mirror_session.dart';
import 'package:jibang_listing_test/models/listing.dart';
import 'package:jibang_listing_test/takedown.dart';

/// 미러의 직방 카드 한 장에서 그대로 옮겨 온 값 (실측 2026-09-21,
/// 「등록번호 : 50144198」). 통합 폼이 이 매물을 올렸다면 이런 값을 들고 있었을 것이다.
const _values = {
  'title': '단기 가능 볕 잘드는 깔끔 원룸',
  'address': '경상북도 포항시 남구 대도동 150-36',
  'unit': '202',
  'trade': '월세',
  'deposit': '200',
  'monthlyRent': '25',
};

void main() {
  group('매물 번호를 기억한다', () {
    test('저장하고 다시 읽어도 번호가 남는다', () {
      final listing = Listing(
        id: 'L1',
        createdAt: DateTime(2026, 9, 21),
        values: const {},
        channels: const {ListingPlatform.zigbang: ChannelState.published},
        channelNumbers: const {
          ListingPlatform.zigbang: '50144198',
          ListingPlatform.dabang: '58948955',
        },
      );
      final again = Listing.fromJson(jsonDecode(jsonEncode(listing.toJson())))!;
      expect(again.channelNumbers[ListingPlatform.zigbang], '50144198');
      expect(again.channelNumbers[ListingPlatform.dabang], '58948955');
    });

    test('번호가 없던 시절에 쓰인 기록도 그대로 열린다', () {
      final old = Listing.fromJson({
        'id': 'L0',
        'createdAt': DateTime(2026, 9, 1).toIso8601String(),
        'values': const {},
        'channels': const {'zigbang': 'published'},
      })!;
      expect(old.channelNumbers, isEmpty);
    });

    test('빈 번호는 적어 두지 않는다 — 없는 것과 같다', () {
      final listing = Listing.fromJson({
        'id': 'L2',
        'createdAt': DateTime(2026, 9, 1).toIso8601String(),
        'values': const {},
        'channels': const {'zigbang': 'published'},
        'channelNumbers': const {'zigbang': '  '},
      })!;
      expect(listing.channelNumbers, isEmpty);
    });

    test('광고를 종료해도 번호는 남는다 — 무엇을 내렸는지 나중에 볼 수 있어야 한다', () {
      final listing = Listing(
        id: 'L3',
        createdAt: DateTime(2026, 9, 21),
        values: const {},
        channels: const {ListingPlatform.zigbang: ChannelState.published},
        channelNumbers: const {ListingPlatform.zigbang: '50144198'},
      );
      final closed = listing.copyWith(
        channels: const {ListingPlatform.zigbang: ChannelState.removed},
        status: ListingStatus.closed,
      );
      expect(closed.channelNumbers[ListingPlatform.zigbang], '50144198');
    });
  });

  group('번호를 읽는 스크립트', () {
    test('한방이 아는 것을 모두 싣고 간다 — 제목·주소·호·금액', () {
      final script = listingNumberScript(ListingPlatform.zigbang, _values);
      expect(script, contains('단기 가능 볕 잘드는 깔끔 원룸'));
      expect(script, contains('경상북도 포항시 남구 대도동 150-36'));
      expect(script, contains('"unit":"202"'));
      // 목록의 카드가 적는 방식 그대로. 「1억 8000」처럼 접으면 글자가 안 맞는다.
      expect(script, contains(r'월세 200/25'));
    });

    test('금액은 억으로 접지 않는다 — 목록은 만원 단위로 적는다', () {
      expect(
        listingPriceLine(const {
          'trade': '매매',
          'salePrice': '12500',
        }),
        '매매 12500',
      );
      expect(
        listingPriceLine(const {'trade': '전세', 'deposit': '18,000'}),
        '전세 18000',
      );
      // 거래 유형을 아직 안 고른 매물은 견줄 금액이 없다.
      expect(listingPriceLine(const {}), isEmpty);
    });

    test('플랫폼 자신의 종료 버튼 글자로 카드를 가린다', () {
      final zigbang = listingNumberScript(ListingPlatform.zigbang, _values);
      final dabang = listingNumberScript(ListingPlatform.dabang, _values);
      expect(zigbang, contains('매물 종료하기'));
      expect(dabang, contains('광고 종료'));
      expect(zigbang, isNot(contains('광고 종료')));
    });

    test('한 가지만 맞아서는 번호를 말하지 않는다', () {
      // 통과선 3 — 제목(3) 하나면 되지만, 금액(2)이나 주소(2) 하나로는 모자란다.
      expect(listingNumberScript(ListingPlatform.zigbang, _values),
          contains('best.score >= 3'));
    });
  });

  group('카드에 표를 붙이는 스크립트', () {
    test('번호와 종료 버튼 글자를 싣고, 누를 자리는 건드리지 않는다', () {
      final script = takedownCardScript(ListingPlatform.dabang, '58948955');
      expect(script, contains('58948955'));
      expect(script, contains('광고 종료'));
      // 되돌릴 수 없는 누름은 사람 몫이다. 스크립트에 누르는 코드가 있으면 안 된다.
      expect(script, isNot(contains('.click()')));
      expect(script, isNot(contains('MouseEvent')));
    });

    test('못 찾으면 플랫폼 자신의 검색창에 번호를 넣어 본다', () {
      final script = takedownCardScript(ListingPlatform.zigbang, '50144198');
      expect(script, contains('등록번호'));
      expect(script, contains('매물번호'));
      expect(script, contains('placeholder'));
    });
  });

  group('누른 것을 어디까지 세는가', () {
    test('울타리가 없으면 페이지 전체를 본다 — 등록 폼이 그렇다', () {
      final script = pressWatcherScript(const ['매물 등록 완료']);
      expect(script, contains('const within = null;'));
    });

    test('울타리가 있으면 그 상자 안에서 누른 것만 센다', () {
      final script = pressWatcherScript(
        ListingPlatform.dabang.takedownLabels,
        within: takedownCardSelector,
      );
      expect(script, contains('"[data-flr-takedown-card]"'));
      expect(script, contains('el.closest(watch.within)'));
    });

    test('다시 깔면 울타리도 함께 바뀐다 — 플랫폼이 넘어가면 카드도 바뀐다', () {
      final script = pressWatcherScript(const ['광고 종료'], within: '[x]');
      expect(script, contains('window.__flrPressWatch.within = within;'));
    });

    test('사람이 누른 것만 센다 — 어댑터의 합성 클릭은 세지 않는다', () {
      expect(pressWatcherScript(const ['광고 종료']),
          contains('if (!event.isTrusted) return;'));
    });
  });

  group('뒤늦게 읽어 낸 번호도 적어 둔다', () {
    late Directory directory;
    late AppStore store;
    late Listing listing;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('hanbang_takedown');
      store = AppStore(directory: directory);
      listing = Listing(
        id: 'L1',
        createdAt: DateTime(2026, 9, 21),
        values: _values,
        channels: const {ListingPlatform.zigbang: ChannelState.published},
      );
      await store.save(listing);
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('내릴 때 읽어 낸 번호가 다음 실행에도 남는다', () async {
      await store.rememberNumber(listing, ListingPlatform.zigbang, '50144198');

      final reopened = AppStore(directory: directory);
      await reopened.load();
      expect(
        reopened.byId('L1')!.channelNumbers[ListingPlatform.zigbang],
        '50144198',
      );
    });

    test('다른 플랫폼의 번호를 덮어쓰지 않는다', () async {
      await store.rememberNumber(listing, ListingPlatform.zigbang, '50144198');
      final both = await store.rememberNumber(
        store.byId('L1')!,
        ListingPlatform.dabang,
        '58948955',
      );
      expect(both.channelNumbers, {
        ListingPlatform.zigbang: '50144198',
        ListingPlatform.dabang: '58948955',
      });
    });

    test('종료를 적어도 번호는 지워지지 않는다', () async {
      await store.rememberNumber(listing, ListingPlatform.zigbang, '50144198');
      final closed = await store.close(
        store.byId('L1')!,
        reason: ClosedReason.adEnded,
        channels: {ListingPlatform.zigbang},
      );
      expect(closed.status, ListingStatus.closed);
      expect(closed.channelNumbers[ListingPlatform.zigbang], '50144198');
    });
  });

  group('플랫폼마다 번호를 부르는 이름이 다르다', () {
    test('직방은 등록번호, 다방은 매물번호', () {
      expect(ListingPlatform.zigbang.listingNumberLabel, '등록번호');
      expect(ListingPlatform.dabang.listingNumberLabel, '매물번호');
    });
  });
}
