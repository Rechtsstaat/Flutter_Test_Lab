// 플랫폼을 잠시 내려 두는 스위치 — 회색으로 남기고, 흐름에는 들이지 않는다.
//
// 켜고 끄는 곳은 `ListingPlatform.status` 하나뿐이다. 이 테스트는 그 한 곳을 바꾸면
// 화면과 흐름이 **저절로** 따라오는지를 지킨다. 새 플랫폼이 들어와도 같은 규칙이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/design/components.dart';
import 'package:jibang_listing_test/fields.dart';
import 'package:jibang_listing_test/models/listing.dart';
import 'package:jibang_listing_test/screens/publish_flow_page.dart';

void main() {
  group('스위치 한 곳', () {
    test('지금은 당근만 내려 둔 상태다', () {
      expect(ListingPlatform.daangn.status, PlatformStatus.paused);
      expect(ListingPlatform.daangn.isLive, isFalse);
      expect(ListingPlatform.zigbang.isLive, isTrue);
      expect(ListingPlatform.dabang.isLive, isTrue);
    });

    test('livePlatforms 는 내려 둔 플랫폼을 담지 않는다', () {
      expect(livePlatforms, isNot(contains(ListingPlatform.daangn)));
      expect(livePlatforms, [ListingPlatform.zigbang, ListingPlatform.dabang]);
      // 화면에 회색으로 남기려면 전체 목록은 그대로여야 한다
      expect(ListingPlatform.values.length, livePlatforms.length + 1);
    });

    test('내려 둔 플랫폼에는 회색 칩에 적을 말이 있고, 살아 있는 쪽에는 없다', () {
      expect(ListingPlatform.daangn.pausedNote, isNotNull);
      for (final platform in livePlatforms) {
        expect(platform.pausedNote, isNull);
      }
    });

    test('다시 켤 재료는 그대로 남아 있다 — 주소·어댑터 설정을 지우지 않았다', () {
      expect(ListingPlatform.daangn.formUrl, contains('/daangn/'));
      expect(ListingPlatform.daangn.photoTarget, isNotNull);
    });
  });

  group('내려 둔 플랫폼은 고를 수 없다', () {
    testWidgets('SelectCard 를 눌러도 아무 일도 없다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectCard(
              platform: ListingPlatform.daangn,
              selected: false,
              enabled: ListingPlatform.daangn.isLive,
              note: ListingPlatform.daangn.pausedNote,
              onTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('당근'));
      await tester.pump();
      expect(taps, 0, reason: '눌리는 척하지 않는다');
      expect(find.text('준비 중'), findsOneWidget);
    });

    testWidgets('살아 있는 플랫폼은 그대로 눌린다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectCard(
              platform: ListingPlatform.zigbang,
              selected: false,
              enabled: ListingPlatform.zigbang.isLive,
              note: ListingPlatform.zigbang.pausedNote,
              onTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('직방'));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('내려 둔 플랫폼은 흐름에도 못 들어온다', () {
    testWidgets('등록 흐름은 문 앞에서 거른다 (둘을 넣어도 하나만 돈다)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PublishFlowPage(
            listing: Listing(
              id: 'L1',
              createdAt: DateTime(2026, 9, 19),
              values: const {},
              channels: const {},
            ),
            values: const {},
            photos: const [],
            channels: const [ListingPlatform.zigbang, ListingPlatform.daangn],
            remotePageBuilder: (_, platform, _) =>
                Center(child: Text('${platform.label} 페이지')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('광고 등록 1 / 1'), findsWidgets);
      expect(find.text('당근 페이지'), findsNothing);
      expect(find.text('직방에 입력하는 중이에요'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });

    test('올린 기록에 남아 있어도 종료 대상에서 빠진다', () {
      final listing = Listing(
        id: 'L2',
        createdAt: DateTime(2026, 9, 19),
        values: const {},
        channels: const {
          ListingPlatform.zigbang: ChannelState.published,
          ListingPlatform.daangn: ChannelState.published,
        },
      );
      expect(listing.liveChannels, [ListingPlatform.zigbang]);
    });
  });
}
