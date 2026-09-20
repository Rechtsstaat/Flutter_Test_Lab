// 남의 계정으로 어댑터를 재 보는 동안 거는 빗장 (`--dart-define=GUARD_LIVE_ADS=1`).
//
// 지키려는 것은 하나다 — **운영 중인 실제 매물이 걸린 자리에는 실수로도 못 들어간다.**
// 「광고 종료」는 한 번 누르면 되돌릴 수 없으므로, 빗장이 걸리면 버튼이 사라지고 왜
// 없는지가 대신 적혀야 한다. 빗장을 풀면 예전 그대로 눌려야 한다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/data/app_store.dart';
import 'package:jibang_listing_test/fields.dart';
import 'package:jibang_listing_test/models/listing.dart';
import 'package:jibang_listing_test/screens/listing_detail_page.dart';

const _guardNote = '광고 종료는 지금 잠겨 있어요 — 실제 계정으로 폼 입력을 확인하는 중입니다.';

/// `AppStore.save` 는 파일에 쓴다. `testWidgets` 안의 가짜 시간에서는 진짜 I/O 가
/// 영영 끝나지 않으므로 [WidgetTester.runAsync] 로 진짜 시간에 내보낸다.
Future<AppStore> _storeWithLiveListing(
  WidgetTester tester,
  Directory directory,
) async {
  final store = AppStore(directory: directory);
  await tester.runAsync(
    () => store.save(
      Listing(
        id: 'L1',
        createdAt: DateTime(2026, 9, 20),
        values: const {},
        channels: const {ListingPlatform.dabang: ChannelState.published},
      ),
    ),
  );
  return store;
}

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('hanbang_guard');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  // `--dart-define` 없이 도는 평소에는 「빗장은 풀려 있다」를 지키고, 빗장을 걸고
  // 돌리면(`flutter test --dart-define=GUARD_LIVE_ADS=1`) **열쇠 이름과 철자**를
  // 지킨다 — `fields.dart` 가 다른 키를 읽게 되면 그쪽에서 어긋난다.
  test('빗장은 GUARD_LIVE_ADS=1 을 줄 때만, 그때는 반드시 걸린다', () {
    expect(guardLiveAds, const String.fromEnvironment('GUARD_LIVE_ADS') == '1');
  });

  // 102 에는 쉬지 않고 도는 애니메이션(PulseDot 등)이 살 수 있어 pumpAndSettle 은
  // 영영 돌아오지 않는다. 프레임을 세어 가며 민다.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // 위의 두 가지는 `guarded:` 를 손으로 넣어 재는 것이라, 화면이 **스위치를 따르는지**는
  // 따로 지켜야 한다. 아무것도 주지 않았을 때 [guardLiveAds] 와 같은 얼굴이어야 한다.
  testWidgets('아무것도 주지 않으면 102 는 스위치를 그대로 따른다', (tester) async {
    final store = await _storeWithLiveListing(tester, directory);
    await tester.pumpWidget(
      MaterialApp(home: ListingDetailPage(store: store, listingId: 'L1')),
    );
    await settle(tester);

    expect(
      find.text('광고를 종료할래요'),
      guardLiveAds ? findsNothing : findsOneWidget,
    );
    expect(find.text(_guardNote), guardLiveAds ? findsOneWidget : findsNothing);
  });

  testWidgets('빗장이 걸리면 102 에 「광고를 종료할래요」가 없고 이유가 적힌다', (tester) async {
    final store = await _storeWithLiveListing(tester, directory);
    await tester.pumpWidget(
      MaterialApp(
        home: ListingDetailPage(store: store, listingId: 'L1', guarded: true),
      ),
    );
    await settle(tester);

    expect(find.text('광고를 종료할래요'), findsNothing);
    expect(find.text(_guardNote), findsOneWidget);
  });

  testWidgets('빗장을 풀면 그대로 눌리고 종료 바텀시트가 뜬다', (tester) async {
    final store = await _storeWithLiveListing(tester, directory);
    await tester.pumpWidget(
      MaterialApp(
        home: ListingDetailPage(store: store, listingId: 'L1', guarded: false),
      ),
    );
    await settle(tester);

    expect(find.text(_guardNote), findsNothing);
    final button = find.text('광고를 종료할래요');
    expect(button, findsOneWidget);

    // 버튼은 102 의 맨 아래라 화면 밖에 있다. 눈에 들이지 않고 tap 하면 그 자리에 있는
    // 다른 것이 눌리고, 테스트는 조용히 아무 일도 없었다고 말한다.
    await tester.ensureVisible(button);
    await settle(tester);
    await tester.tap(button);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('어느 플랫폼에서 내릴까요?'), findsOneWidget);
    expect(find.text('다방'), findsWidgets);
  });
}
