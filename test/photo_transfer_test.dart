import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jibang_listing_test/main.dart';
import 'package:jibang_listing_test/photo_transfer.dart';

void main() {
  late Directory temporary;
  late XFile photo;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('listing_photos_');
    final file = File('${temporary.path}/room.png');
    await file.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWZkAAAAASUVORK5CYII=',
      ),
    );
    photo = XFile(file.path);
  });
  tearDown(() async => temporary.delete(recursive: true));

  test(
    'photo validation reads actual bytes, not the extension or reported MIME',
    () async {
      expect(await validateListingPhoto(photo), 'image/png');
      final fake = File('${temporary.path}/fake.png');
      await fake.writeAsString('not a photo');
      await expectLater(
        validateListingPhoto(XFile(fake.path, mimeType: 'image/png')),
        throwsFormatException,
      );
      await fake.writeAsBytes([]);
      await expectLater(
        validateListingPhoto(XFile(fake.path)),
        throwsFormatException,
      );
      final oversized = await fake.open(mode: FileMode.write);
      await oversized.truncate(maxListingPhotoBytes + 1);
      await oversized.close();
      await expectLater(
        validateListingPhoto(XFile(fake.path)),
        throwsFormatException,
      );
    },
  );

  test('transfer refuses empty or excessive photo counts before touching the WebView', () async {
    var called = false;
    for (final photos in [<XFile>[], List.filled(21, photo)]) {
      await expectLater(
        transferListingPhotos(
          target: PhotoTarget.dabang,
          photos: photos,
          evaluate: (_) async {
            called = true;
            return '{}';
          },
          onProgress: (_, _) {},
        ),
        throwsFormatException,
      );
    }
    expect(called, isFalse);
  });

  test('one photo finishes successfully', () async {
    final bridge = _RecordingPhotoBridge(doubleEncoded: false);
    final progress = <int>[];

    await transferListingPhotos(
      target: PhotoTarget.dabang,
      photos: [photo],
      evaluate: bridge.evaluate,
      onProgress: (done, total) {
        expect(total, 1);
        progress.add(done);
      },
    );

    expect(progress, [0, 1]);
    expect(bridge.remaining, [1]);
    expect(bridge.received, hasLength(1));
    expect(bridge.received.single, orderedEquals(await photo.readAsBytes()));
    expect(bridge.cleared, isTrue);
  });

  test(
    'a card that never completes is a failure, not upload success',
    () async {
      final progress = <int>[];
      var cleared = false;
      await expectLater(
        transferListingPhotos(
          target: PhotoTarget.dabang,
          photos: List.filled(5, photo),
          timeout: Duration.zero,
          evaluate: (script) async {
            if (script.contains('__flrPhotos.status(')) {
              return jsonEncode({'ready': false, 'count': 1});
            }
            if (script.contains('__flrPhotos.clear(')) cleared = true;
            return '{}';
          },
          onProgress: (done, _) => progress.add(done),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'error',
            contains('1번 사진'),
          ),
        ),
      );
      expect(progress, [0]);
      expect(cleared, isTrue);
    },
  );

  // 실물은 사진을 제 저장소로 진짜 올린 뒤에야 카드를 만든다(미러는 즉시 만든다).
  // 그래서 큰 사진일수록 오래 걸리고, 고정 45초로는 실패와 느림이 구분되지 않는다.
  test('카드를 기다리는 시간은 사진 크기를 따라 늘고, 한계에서 멈춘다', () {
    const base = Duration(seconds: 45);
    expect(settleBudget(base, 0), base);
    expect(settleBudget(base, 2 * 1024 * 1024).inSeconds, 85);
    expect(settleBudget(base, 1024 * 1024 ~/ 2).inSeconds, 55);
    // 사진마다 한없이 붙들면 등록 흐름 전체가 멈춘다.
    expect(settleBudget(base, 999 * 1024 * 1024), const Duration(seconds: 120));
  });

  // 「현재 0장입니다」만으로는 업로드가 실패한 것인지 아직 올라가는 중인지 알 수 없어
  // 실물에서 몇 번을 더 재 봐야 했다. 본 것을 그대로 적는다.
  test('카드를 못 본 채 시간이 다하면 플랫폼이 한 말과 페이지 오류를 함께 적는다', () async {
    await expectLater(
      transferListingPhotos(
        target: PhotoTarget.dabang,
        photos: [photo],
        timeout: Duration.zero,
        evaluate: (script) async {
          if (script.contains('__flrPhotos.status(')) {
            return jsonEncode({
              'ready': false,
              'count': 0,
              'spoken': '사진 업로드에 실패했습니다',
              'errors': ['오류: Network request failed'],
            });
          }
          return '{}';
        },
        onProgress: (_, _) {},
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'error',
          allOf(
            contains('현재 0장입니다'),
            contains('플랫폼 화면: 「사진 업로드에 실패했습니다」'),
            contains('페이지 오류: 오류: Network request failed'),
            contains('MB'),
          ),
        ),
      ),
    );
  });

  test('할 말이 없으면 군더더기를 붙이지 않는다', () async {
    await expectLater(
      transferListingPhotos(
        target: PhotoTarget.dabang,
        photos: [photo],
        timeout: Duration.zero,
        evaluate: (script) async => script.contains('__flrPhotos.status(')
            ? jsonEncode({'ready': false, 'count': 0})
            : '{}',
        onProgress: (_, _) {},
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'error',
          allOf(
            contains('현재 0장입니다'),
            isNot(contains('플랫폼 화면')),
            isNot(contains('페이지 오류')),
          ),
        ),
      ),
    );
  });

  // 실기기에서 108초 동안 아무 말 없이 실패했다. WebView 의 콘솔을 볼 방법이 없으므로
  // 브리지가 증거를 모아 오고, 그것을 사람이 읽을 말로 바꾼다. 미러에서 성공했을 때의
  // 지문은 「읽힘 / mutations > 0 / held 0」이다.
  group('침묵의 정체를 말로 옮긴다', () {
    test('파일이 껍데기면 그것부터 말한다', () {
      final said = describePhotoSilence({
        'readBack': {'state': '읽기 실패', 'why': 'The operation was aborted'},
        'mutations': 0,
        'held': 1,
      });
      expect(said, contains('되읽지 못했습니다(읽기 실패: The operation was aborted)'));
      expect(said, contains('한 번도 움직이지 않았습니다'));
      expect(said, contains('파일 1개를 쥐고 있습니다'));
    });

    test('파일은 멀쩡한데 페이지가 못 봤으면 그렇게 말한다', () {
      final said = describePhotoSilence({
        'readBack': {'state': '읽힘', 'bytes': 3},
        'mutations': 0,
        'held': 1,
      });
      expect(said, contains('정상으로 읽힙니다'));
      expect(said, contains('한 번도 움직이지 않았습니다'));
    });

    test('페이지가 움직였고 파일도 가져갔으면 군더더기를 빼고 말한다', () {
      final said = describePhotoSilence({
        'readBack': {'state': '읽힘', 'bytes': 3},
        'mutations': 13,
        'held': 0,
      });
      expect(said, contains('정상으로 읽힙니다'));
      expect(said, contains('13번 움직였습니다'));
      expect(said, isNot(contains('쥐고 있습니다')));
    });

    test('브리지가 아무것도 못 모아 왔어도 무너지지 않는다', () {
      expect(describePhotoSilence(const {}), contains('파일 확인 결과 없음'));
    });
  });

  /* 폼이 사진을 쓸어 갔을 때.
   *
   * 다방은 주소를 고르는 순간 폼을 처음 상태로 되돌린다. 그때 방금 올라간 사진 카드도
   * 함께 지워진다 — 실기기에서 「카드가 한때 1장까지 보였다가 사라졌습니다」로 끝난 것이
   * 이것이다. 값은 어댑터의 reconcile 이 다시 넣지만 사진은 아무도 다시 붙여 주지 않는다. */
  group('폼이 사진 카드를 쓸어 가면', () {
    test('남은 예산을 흘려보내지 않고 그 자리에서 다시 붙인다', () async {
      var begins = 0;
      var statuses = 0;
      final progress = <int>[];
      await transferListingPhotos(
        target: PhotoTarget.dabang,
        photos: [photo],
        // 예산이 넉넉해도 기다리지 않는다 — 기다림이 아니라 다시 붙이기가 답이다.
        timeout: const Duration(minutes: 2),
        evaluate: (script) async {
          if (script.contains('__flrPhotos.begin(')) begins++;
          if (!script.contains('__flrPhotos.status(')) return '{}';
          statuses++;
          return begins == 1
              ? jsonEncode({
                  'ready': false,
                  'count': 0,
                  'peak': 1,
                  'gone': true,
                  'remade': true,
                  'wiped': true,
                })
              : jsonEncode({'ready': true, 'count': 1});
        },
        onProgress: (done, _) => progress.add(done),
      );
      expect(begins, 2, reason: '지워진 사진은 한 번 더 붙여야 합니다.');
      expect(statuses, 2, reason: '지워진 것을 본 뒤로는 기다리지 않아야 합니다.');
      expect(progress, [0, 1]);
    });

    test('두 번째에도 지워지면 본 것을 그대로 적고 멈춘다', () async {
      var begins = 0;
      await expectLater(
        transferListingPhotos(
          target: PhotoTarget.dabang,
          photos: [photo],
          timeout: const Duration(minutes: 2),
          evaluate: (script) async {
            if (script.contains('__flrPhotos.begin(')) begins++;
            return script.contains('__flrPhotos.status(')
                ? jsonEncode({
                    'ready': false,
                    'count': 0,
                    'peak': 1,
                    'gone': true,
                    'remade': true,
                    'wiped': true,
                    'readBack': {'state': '읽힘', 'bytes': 3},
                    'mutations': 6,
                  })
                : '{}';
          },
          onProgress: (_, _) {},
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'error',
            allOf(
              // 기다린 시간은 실제로 기다린 만큼만 적는다 — 예산을 적어 버리면
              // 3초 만에 접은 것을 47초 기다렸다고 말하게 된다.
              contains('초를 기다렸고'),
              isNot(contains('120초를 기다렸고')),
              contains('카드가 한때 1장까지 보였다가 사라졌습니다'),
              contains('사진 자리가 통째로 다시 그려졌습니다'),
            ),
          ),
        ),
      );
      expect(begins, 2, reason: '끝없이 다시 붙이지는 않습니다.');
    });
  });

  /* 다리의 **판단**은 글자가 아니라 돌려 봐야 안다.
   *
   * 「카드가 앉았는가 / 폼이 다시 그려졌는가 / 카드가 떴다 사라졌는가」는 전부
   * JavaScript 문자열 안에 있어 여기서는 보이지 않는다. 그리고 실기기에서 47초를
   * 헛기다리게 만든 것이 바로 그 판단이었다 — 가짜 DOM 위에서 다리를 그대로 돌린다. */
  test('사진 다리의 판단 규칙을 실제로 돌려 본다', () {
    final script = File(
      '${Directory.systemTemp.path}/photo_bridge_${DateTime.now().microsecondsSinceEpoch}.js',
    );
    try {
      script.writeAsStringSync(listingPhotoBridgeScript(PhotoTarget.dabang));
      final result = Process.runSync('node', [
        'test/tools/photo_bridge_probe.mjs',
        '--script=${script.path}',
      ]);
      expect(
        result.exitCode,
        0,
        reason: '${result.stdout}\n${result.stderr}',
      );
      final report = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(report['pass'], isTrue, reason: result.stdout as String);
      expect((report['cases'] as List), hasLength(7));
    } finally {
      if (script.existsSync()) script.deleteSync();
    }
  });

  // image_picker 의 60자짜리 임시 이름을 그대로 올리지 않는다. 남의 광고에 붙을 이름으로
  // 마땅치 않고, 실기기에서만 조용히 실패하는 동안 한 번도 확인해 보지 않은 변수였다.
  test('플랫폼에는 짧고 단순한 파일 이름으로 보낸다', () async {
    final names = <String>[];
    await transferListingPhotos(
      target: PhotoTarget.dabang,
      photos: List.filled(2, photo),
      evaluate: (script) async {
        final match = RegExp(r'"name":"([^"]+)"').firstMatch(script);
        if (match != null) names.add(match.group(1)!);
        return script.contains('__flrPhotos.status(')
            ? jsonEncode({'ready': true, 'count': 1})
            : '{}';
      },
      onProgress: (_, _) {},
    );
    expect(names, ['photo-1.png', 'photo-2.png']);
    expect(names.every((n) => !n.contains('image_picker')), isTrue);
  });

  test('확장자는 실제로 읽어 낸 형식을 따른다', () {
    expect(uploadFileName(1, 'image/jpeg'), 'photo-1.jpg');
    expect(uploadFileName(7, 'image/webp'), 'photo-7.webp');
    expect(uploadFileName(2, 'image/heic'), 'photo-2.heic');
    // 모르는 형식이라고 이름을 비우지는 않는다.
    expect(uploadFileName(3, 'image/unknown'), 'photo-3.jpg');
  });

  // 업로드가 왜 실패했는지 들으려고 페이지를 **바꾸지는** 않는다. 남의 계정으로 도는
  // 실물 폼이라, 우리 래퍼가 잘못되는 순간 그 사람의 업로드가 깨진다.
  test('오류는 엿듣기만 한다 — fetch·XHR 을 바꿔 끼우지 않는다', () {
    final bridge = listingPhotoBridgeScript(PhotoTarget.dabang);
    expect(bridge, contains("window.addEventListener('error'"));
    expect(bridge, contains("window.addEventListener('unhandledrejection'"));
    expect(bridge, isNot(contains('window.fetch =')));
    expect(bridge, isNot(contains('XMLHttpRequest.prototype.open =')));
  });

  for (final doubleEncoded in [false, true]) {
    test(
      'five photos finish sequentially with ${doubleEncoded ? 'double' : 'single'} JSON encoded WebView results',
      () async {
        final bridge = _RecordingPhotoBridge(doubleEncoded: doubleEncoded);
        final progress = <int>[];
        await transferListingPhotos(
          target: PhotoTarget.dabang,
          photos: List.filled(5, photo),
          evaluate: bridge.evaluate,
          onProgress: (done, total) {
            expect(total, 5);
            expect(done, bridge.completed);
            progress.add(done);
          },
        );
        expect(progress, [0, 1, 2, 3, 4, 5]);
        expect(bridge.remaining, [5, 4, 3, 2, 1]);
        expect(bridge.received, hasLength(5));
        final original = await photo.readAsBytes();
        for (final received in bridge.received) {
          expect(received, orderedEquals(original));
        }
        expect(bridge.statusCalls, 10);
        expect(bridge.cleared, isTrue);
      },
    );
  }

  test('a stream chunk larger than 96 KiB is split without byte loss or reordering', () async {
    final header = await photo.readAsBytes();
    final bytes = Uint8List.fromList([
      ...header,
      ...List.generate(220 * 1024, (i) => (i * 31 + 7) % 256),
    ]);
    // XFile.fromData yields one large stream chunk. File.openRead generally
    // yields smaller chunks and alone would not exercise the splitting branch.
    final largePhoto = XFile.fromData(
      bytes,
      path: 'room "large".png',
      lastModified: DateTime(2026, 9, 16),
    );
    final bridge = _RecordingPhotoBridge(doubleEncoded: true);
    await transferListingPhotos(
      target: PhotoTarget.dabang,
      photos: List.filled(5, largePhoto),
      evaluate: bridge.evaluate,
      onProgress: (_, _) {},
    );
    expect(bridge.completed, 5);
    expect(bridge.chunkLengths, hasLength(15));
    expect(bridge.chunkLengths.every((length) => length <= 96 * 1024), isTrue);
    expect(
      bridge.chunkLengths.where((length) => length == 96 * 1024),
      hasLength(10),
    );
    for (final received in bridge.received) {
      expect(received, orderedEquals(bytes));
    }
    expect(bridge.cleared, isTrue);
  });

  test('Daangn skips photo formats its mirror drops and sends the rest', () async {
    final bmp = File('${temporary.path}/plan.bmp');
    await bmp.writeAsBytes([66, 77, ...List.filled(40, 0)]);
    final bridge = _RecordingPhotoBridge(
      doubleEncoded: false,
      target: PhotoTarget.daangn,
    );
    final progress = <int>[];

    final skipped = await transferListingPhotos(
      target: PhotoTarget.daangn,
      photos: [photo, XFile(bmp.path)],
      evaluate: bridge.evaluate,
      onProgress: (done, total) {
        expect(total, 1);
        progress.add(done);
      },
    );

    expect(progress, [0, 1]);
    expect(bridge.types, ['image/png']);
    // Only the photo that will really arrive counts toward the 20-photo check.
    expect(bridge.remaining, [1]);
    expect(skipped, hasLength(1));
    expect(skipped.single, allOf(contains('2번 사진'), contains('BMP')));

    // The same BMP is a valid Dabang photo.
    expect(PhotoTarget.dabang.acceptedTypes, contains('image/bmp'));
  });

  test('a batch with nothing Daangn takes never touches the WebView', () async {
    final bmp = File('${temporary.path}/plan.bmp');
    await bmp.writeAsBytes([66, 77, ...List.filled(40, 0)]);
    var called = false;
    final skipped = await transferListingPhotos(
      target: PhotoTarget.daangn,
      photos: [XFile(bmp.path)],
      evaluate: (_) async {
        called = true;
        return '{}';
      },
      onProgress: (_, _) => fail('No photo should be reported as sent.'),
    );
    expect(called, isFalse);
    expect(skipped, hasLength(1));
  });

  test('each photo bridge looks only at its own mirror form', () {
    final dabang = listingPhotoBridgeScript(PhotoTarget.dabang);
    final daangn = listingPhotoBridgeScript(PhotoTarget.daangn);
    expect(dabang, contains('"/dabang/form/room/"'));
    expect(dabang, contains("section#visual_info"));
    expect(daangn, contains('"/daangn/form/article/"'));
    expect(daangn, contains("document.getElementById('image-upload')"));
    // 당근 칸은 올라가는 동안 잠기고, 다 올라가면 sortable 과 data-mirror-key 를 받는다.
    expect(daangn, contains("classList.contains('cursor-not-allowed')"));
    expect(daangn, contains("getAttribute('data-mirror-key')"));
    for (final script in [dabang, daangn]) {
      // 완료를 만들어 내지 않는다 — 플랫폼이 제 카드를 처리 완료로 표시해야 한다.
      expect(script, contains('const strict = grown && settled(fresh[0])'));
      expect(script, contains("el.dispatchEvent(new Event('change'"));
    }
  });

  // 실기기의 다방은 **서버 id 까지 받은 카드를** aria-disabled=true 로 둔 채 두기도
  // 한다(2026-09-20). 그것까지 실패로 접으면 이미 올라간 사진을 실패라고 말하게 된다.
  test('플랫폼이 잠금을 안 풀어도 같은 카드가 버티면 붙은 것으로 본다', () {
    final dabang = listingPhotoBridgeScript(PhotoTarget.dabang);
    expect(dabang, contains('const PATIENCE = 4000;'));
    expect(dabang, contains('const patient = !strict && grown && stableFor >= PATIENCE;'));
    // 인정한 카드는 다음 사진을 막지 않는다.
    expect(dabang, contains('this.okIds.push(id)'));
    expect(dabang, contains('!this.okIds.includes(cardId(c))'));
  });

  // 폼이 다시 그려졌는지는 **사진 자리 노드가 그대로인지**로 안다. 관찰자는 옛 노드에
  // 붙은 채 남아 mutations 가 그 자리에서 멈추므로, 그것만으로는 「페이지가 조용하다」와
  // 구분되지 않아 실기기에서 47초를 헛기다렸다.
  test('브리지는 사진 자리가 통째로 갈렸는지를 따로 본다', () {
    final dabang = listingPhotoBridgeScript(PhotoTarget.dabang);
    expect(dabang, contains('this.spotNode = region();'));
    expect(dabang, contains('const remade = !!this.spotNode && this.spotNode !== region();'));
    // 어댑터가 「사진 붙이는 중」을 알아볼 수 있어야 폼을 건드리지 않는다.
    expect(dabang, contains('touch() { this.until = Date.now() + 60000; }'));
  });

  testWidgets(
    'photos are optional and one selected photo can be sent or deleted',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ListingFormPage(pickImages: () async => [photo])),
      );

      BrandButton cta() => tester.widget<BrandButton>(
        find.byWidgetPredicate(
          (widget) => widget is BrandButton && widget.label == '광고 등록',
        ),
      );

      await tester.tap(find.text('자동 채우기'));
      await tester.pump();
      expect(
        cta().onPressed,
        isNotNull,
        reason: '사진이 없어도 등록 CTA 가 활성화되어야 합니다.',
      );

      // The photo strip opens 사진 및 광고 채널, further down the long form.
      await tester.scrollUntilVisible(
        find.byTooltip('사진 추가'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('0/20'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('사진 추가'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('1/20'), findsOneWidget);
      expect(cta().onPressed, isNotNull);

      await tester.tap(find.byTooltip('1번 사진 삭제'));
      await tester.pump();
      expect(find.text('0/20'), findsOneWidget);

      await tester.tap(find.text('자동 채우기'));
      await tester.pump();
      expect(cta().onPressed, isNotNull);
    },
  );
}

/// Records the native transport contract. DOM/card behavior is exercised by
/// the separate real-mirror WebKit verification, rather than simulated here.
class _RecordingPhotoBridge {
  _RecordingPhotoBridge({
    required this.doubleEncoded,
    this.target = PhotoTarget.dabang,
  });

  final bool doubleEncoded;
  final PhotoTarget target;
  final types = <String>[];
  final received = <List<int>>[];
  final chunkLengths = <int>[];
  final remaining = <int>[];
  Map<String, dynamic>? metadata;
  List<int>? staging;
  bool committed = false;
  bool cleared = false;
  int completed = 0;
  int statusCalls = 0;
  int _currentPolls = 0;

  Future<Object> evaluate(String script) async {
    if (script == listingPhotoBridgeScript(target)) {
      return _encode({'ready': true, 'count': 0});
    }
    final command = RegExp(r'window\.__flrPhotos\.(\w+)\(\.\.\.(\[.*\])\)')
        .firstMatch(script);
    expect(
      command,
      isNotNull,
      reason: 'Every transport command must contain parseable JSON arguments.',
    );
    final args = jsonDecode(command!.group(2)!) as List;
    switch (command.group(1)) {
      case 'begin':
        expect(
          staging,
          isNull,
          reason: 'The previous file must finish before beginning another.',
        );
        metadata = Map<String, dynamic>.from(args[0] as Map);
        types.add(metadata!['type'] as String);
        expect(target.acceptedTypes, contains(metadata!['type']));
        expect(metadata!['name'], isNotEmpty);
        remaining.add(args[1] as int);
        staging = [];
        committed = false;
        _currentPolls = 0;
        return _encode({'count': completed});
      case 'append':
        expect(committed, isFalse);
        final bytes = base64Decode(args.single as String);
        chunkLengths.add(bytes.length);
        staging!.addAll(bytes);
        return _encode({'bytes': staging!.length});
      case 'commit':
        expect(staging!.length, metadata!['size']);
        expect(committed, isFalse);
        committed = true;
        return _encode({'dispatched': true});
      case 'status':
        expect(committed, isTrue);
        statusCalls++;
        _currentPolls++;
        if (_currentPolls == 1) {
          return _encode({'ready': false, 'count': completed + 1});
        }
        received.add(staging!);
        staging = null;
        completed++;
        return _encode({
          'ready': true,
          'count': completed,
          'id': 'photo-$completed',
        });
      case 'clear':
        cleared = true;
        staging = null;
        return _encode({'cleared': true});
      default:
        fail('Unexpected photo bridge command: ${command.group(1)}');
    }
  }

  String _encode(Map<String, dynamic> value) {
    final encoded = jsonEncode(value);
    return doubleEncoded ? jsonEncode(encoded) : encoded;
  }
}
