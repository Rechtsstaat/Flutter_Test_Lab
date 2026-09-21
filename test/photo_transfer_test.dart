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
  late List<XFile> photos;
  // 직방은 JPG·PNG 만 받는다. 형식별로 갈리는 자리를 재려면 두 가지가 다 있어야 한다.
  late XFile jpeg;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('listing_photos_');
    photo = XFile((await _png('${temporary.path}/room.png')).path);
    // 폼은 같은 파일을 두 번 들이지 않고, 진짜 사진인지 바이트를 읽어 본다 — 장수를
    // 재려면 **서로 다른, 실제로 있는** 사진이라야 한다.
    photos = [
      for (var i = 0; i < minListingPhotos; i++)
        XFile((await _png('${temporary.path}/room-$i.png')).path),
    ];
    final shot = File('${temporary.path}/room.jpg');
    await shot.writeAsBytes([0xff, 0xd8, 0xff, 0xe0, 7, 7, 7, 7]);
    jpeg = XFile(shot.path);
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

  /* 직방 쪽 판단도 **돌려 봐야** 안다.
   *
   * 직방은 사진을 창 안에서 받는다. 「창이 열렸는가 / 다 모였는가 / 확인이 풀렸는가 /
   * 카드가 그만큼 앉았는가」는 전부 JavaScript 문자열 안에 있어 글자만으로는 보이지
   * 않는다. 실물을 흉내 낸 가짜 창 위에서 다리를 그대로 돌린다. */
  test('직방 사진 다리를 가짜 창 위에서 실제로 돌려 본다', () {
    final script = File(
      '${Directory.systemTemp.path}/zigbang_photo_bridge_${DateTime.now().microsecondsSinceEpoch}.js',
    );
    try {
      script.writeAsStringSync(listingPhotoBridgeScript(PhotoTarget.zigbang));
      final result = Process.runSync('node', [
        'test/tools/photo_bridge_probe.mjs',
        '--script=${script.path}',
        '--target=zigbang',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final report = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(report['pass'], isTrue, reason: result.stdout as String);
      expect((report['cases'] as List), hasLength(4));
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

  test('each photo bridge looks only at its own form', () {
    final zigbang = listingPhotoBridgeScript(PhotoTarget.zigbang);
    final dabang = listingPhotoBridgeScript(PhotoTarget.dabang);
    final daangn = listingPhotoBridgeScript(PhotoTarget.daangn);
    expect(zigbang, contains('"/ads/oneroom/ad-item/new/"'));
    expect(dabang, contains('"/dabang/form/room/"'));
    expect(dabang, contains("section#visual_info"));
    expect(daangn, contains('"/daangn/form/article/"'));
    expect(daangn, contains("document.getElementById('image-upload')"));
    // 당근 칸은 올라가는 동안 잠기고, 다 올라가면 sortable 과 data-mirror-key 를 받는다.
    expect(daangn, contains("classList.contains('cursor-not-allowed')"));
    expect(daangn, contains("getAttribute('data-mirror-key')"));
    for (final script in [zigbang, dabang, daangn]) {
      // 완료를 만들어 내지 않는다 — 플랫폼이 제 카드를 처리 완료로 표시해야 한다.
      expect(script, contains('const strict = grown && fresh.every(settled)'));
      expect(script, contains("el.dispatchEvent(new Event('change'"));
    }
  });

  /* 직방의 파일 입력은 **창을 열기 전에는 문서에 없다** (2026-09-08 현장조사 §3-6).
   *
   * 폼의 `input[name=images]` 는 readonly 라 값을 받아 적기만 하고, 진짜 입력은
   * 「이미지 넣기」 창 안 Dropzone 에 숨어 있다. 그래서 다리는 창을 열고(open),
   * 고른 것을 한 번에 건네고, 확인 버튼으로 폼에 들여보낸다(seal). */
  test('직방 다리는 창을 열고 한 번에 건넨 뒤 확인으로 들여보낸다', () {
    final zigbang = listingPhotoBridgeScript(PhotoTarget.zigbang);
    expect(zigbang, contains('const MODAL = true;'));
    expect(zigbang, contains(r"/이미지 넣기/.test(box.textContent || '')"));
    expect(zigbang, contains(r'''document.querySelector('input[name="images"]')'''));
    // 확인 버튼은 직방이 사진을 다 받고 나서야 풀린다.
    expect(zigbang, contains(r"(b.textContent || '').trim() === '확인'"));
    expect(zigbang, contains('if (!button || button.disabled) return false;'));
    // 다 모이기 전에는 쥐고만 있는다 — 직방은 5장 미만을 받지 않는다.
    expect(zigbang, contains('if (this.queue.length < this.expected) return'));
    // 다방은 예전 그대로 한 장씩 건넨다.
    expect(
      listingPhotoBridgeScript(PhotoTarget.dabang),
      contains('const MODAL = false;'),
    );
  });

  // 직방이 창에 적어 둔 규칙 그대로다: JPG·PNG 만, 장당 10MB, 최소 5장 최대 20장.
  test('직방의 사진 규칙은 그 창이 적어 둔 것을 그대로 따른다', () {
    expect(PhotoTarget.zigbang.acceptedTypes, {'image/jpeg', 'image/png'});
    expect(PhotoTarget.zigbang.minimum, 5);
    expect(PhotoTarget.zigbang.maximum, 20);
    expect(PhotoTarget.zigbang.maxBytes, 10 * 1024 * 1024);
    expect(PhotoTarget.dabang.minimum, 1);
    expect(PhotoTarget.dabang.modal, isFalse);
  });

  // 실기기의 다방은 **서버 id 까지 받은 카드를** aria-disabled=true 로 둔 채 두기도
  // 한다(2026-09-20). 그것까지 실패로 접으면 이미 올라간 사진을 실패라고 말하게 된다.
  test('플랫폼이 잠금을 안 풀어도 같은 카드가 버티면 붙은 것으로 본다', () {
    final dabang = listingPhotoBridgeScript(PhotoTarget.dabang);
    expect(dabang, contains('const PATIENCE = 4000;'));
    expect(dabang, contains('const patient = !strict && grown && stableFor >= PATIENCE;'));
    // 인정한 카드는 다음 사진을 막지 않는다.
    expect(dabang, contains('this.okIds.push(mark)'));
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

  /* 사진은 **필수 5~20장**이다 — 직방의 「이미지 넣기」 창이 정한 규칙이다.
   *
   * 한 장이라도 모자라면 직방에서는 확인 버튼이 잠긴 채라 사진 없이 끝난다. 그래서
   * 통합 폼이 먼저 막는다: 5장을 채우기 전에는 등록 CTA 가 열리지 않는다. */
  testWidgets('사진 5장을 채워야 등록 CTA 가 열리고, 한 장을 빼면 다시 잠긴다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ListingFormPage(pickImages: () async => photos),
      ),
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
      isNull,
      reason: '사진이 없으면 등록 CTA 가 잠겨 있어야 합니다.',
    );

    // The photo strip opens 사진 및 광고 채널, further down the long form.
    await tester.scrollUntilVisible(
      find.byTooltip('사진 추가'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('0/$maxListingPhotos'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('사진 추가'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('$minListingPhotos/$maxListingPhotos'), findsOneWidget);
    expect(cta().onPressed, isNotNull);

    // 한 장이 빠지면 직방이 받아 주지 않는다. 보내기 전에 여기서 잠긴다.
    await tester.tap(find.byTooltip('$minListingPhotos번 사진 삭제'));
    await tester.pump();
    expect(find.text('${minListingPhotos - 1}/$maxListingPhotos'), findsOneWidget);
    expect(cta().onPressed, isNull);
    expect(find.textContaining('매물 사진'), findsWidgets);
  });

  /* 직방으로 보내는 길 전체.
   *
   * 창을 열고([open]) → 고른 것을 한 장씩 흘려보내고 → 마지막 장에서 한 번에 건네고
   * → 확인을 눌러([seal]) 폼에 들여보내고 → 카드가 그만큼 앉았는지 본다. 순서가
   * 어긋나면 사진은 조용히 사라진다 — 그래서 순서 자체를 잰다. */
  test('직방에는 창을 열고 다섯 장을 한 번에 건넨 뒤 확인으로 들여보낸다', () async {
    final bridge = _ZigbangBridge();
    final progress = <int>[];

    final skipped = await transferListingPhotos(
      target: PhotoTarget.zigbang,
      photos: List.filled(5, jpeg),
      evaluate: bridge.evaluate,
      onProgress: (done, total) {
        expect(total, 5);
        progress.add(done);
      },
    );

    expect(skipped, isEmpty);
    expect(progress, [0, 1, 2, 3, 4, 5]);
    expect(bridge.opened, greaterThan(0), reason: '창을 먼저 열어야 합니다.');
    expect(bridge.received, hasLength(5));
    // 건넨 것은 고른 그 사진이어야 한다.
    final original = await jpeg.readAsBytes();
    for (final received in bridge.received) {
      expect(received, orderedEquals(original));
    }
    // 창을 열고 → 다 건네고 → 확인 → 카드 확인. 이 차례다.
    expect(
      bridge.order.where((step) => step != 'append').toList(),
      containsAllInOrder([
        'open',
        'begin',
        'commit',
        'begin',
        'commit',
        'seal',
        'status',
        'clear',
      ]),
    );
    expect(
      bridge.order.indexOf('seal'),
      greaterThan(bridge.order.lastIndexOf('commit')),
      reason: '확인은 마지막 사진을 건넨 뒤에 눌러야 합니다.',
    );
    expect(
      bridge.order.indexOf('status'),
      greaterThan(bridge.order.lastIndexOf('seal')),
      reason: '카드는 확인을 누른 뒤에 생깁니다.',
    );
  });

  /* 직방은 5장 미만을 받지 않는다 — 창의 [확인] 이 잠긴 채다.
   *
   * 그러면 **손대지 않는다.** 절반만 올려 두고 실패했다고 말하는 것보다, 왜 못 했는지
   * 말하고 사람이 화면에서 이어서 올리게 하는 편이 낫다. */
  test('직방이 받을 수 있는 사진이 다섯 장을 못 채우면 폼을 건드리지 않는다', () async {
    final heic = File('${temporary.path}/room.heic');
    await heic.writeAsBytes([
      ...List.filled(4, 0),
      ...'ftypheic'.codeUnits,
      ...List.filled(24, 0),
    ]);
    var called = false;
    final skipped = await transferListingPhotos(
      target: PhotoTarget.zigbang,
      // 다섯 장이지만 한 장은 직방이 받지 않는 형식이다 → 넷뿐이다.
      photos: [jpeg, jpeg, jpeg, jpeg, XFile(heic.path)],
      evaluate: (_) async {
        called = true;
        return '{}';
      },
      onProgress: (_, _) => fail('한 장도 보내지 않아야 합니다.'),
    );
    expect(called, isFalse);
    expect(skipped, hasLength(2));
    expect(skipped.first, allOf(contains('5번 사진'), contains('JPEG·PNG')));
    expect(skipped.last, allOf(contains('5장 이상'), contains('4장뿐')));
  });

  // 장당 10MB — 직방이 창에 적어 둔 한계다. 그냥 건네면 그쪽 업로더가 조용히 떨어뜨린다.
  test('직방이 정한 장당 크기를 넘는 사진은 건너뛰고 그 이유를 돌려준다', () async {
    final big = File('${temporary.path}/big.jpg');
    final handle = await big.open(mode: FileMode.write);
    await handle.writeFrom([0xff, 0xd8, 0xff, 0xe0]);
    await handle.truncate(PhotoTarget.zigbang.maxBytes + 1);
    await handle.close();

    final bridge = _ZigbangBridge();
    final skipped = await transferListingPhotos(
      target: PhotoTarget.zigbang,
      photos: [jpeg, jpeg, jpeg, jpeg, jpeg, XFile(big.path)],
      evaluate: bridge.evaluate,
      onProgress: (_, _) {},
    );
    expect(bridge.received, hasLength(5), reason: '나머지 다섯 장은 그대로 갑니다.');
    expect(skipped, hasLength(1));
    expect(skipped.single, allOf(contains('6번 사진'), contains('10MB')));
  });

  // 확인 버튼이 끝내 풀리지 않으면 본 것을 그대로 적고 멈춘다 — 직방이 사진을 받지
  // 못했다는 뜻이고, 그 이유는 대개 창 안에 적혀 있다.
  test('직방이 확인 버튼을 열어 주지 않으면 창이 한 말을 그대로 옮긴다', () async {
    await expectLater(
      transferListingPhotos(
        target: PhotoTarget.zigbang,
        photos: List.filled(5, jpeg),
        timeout: Duration.zero,
        evaluate: (script) async {
          if (script.contains('__flrPhotos.open(')) {
            return jsonEncode({'ready': true});
          }
          if (script.contains('__flrPhotos.seal(')) {
            return jsonEncode({
              'sealed': false,
              'count': 0,
              'spoken': '파일 용량이 초과되었습니다',
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
            contains('확인 버튼을 열어 주지 않았습니다'),
            contains('플랫폼 화면: 「파일 용량이 초과되었습니다」'),
          ),
        ),
      ),
    );
  });
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

/// 직방 쪽 전송 차례를 받아 적는다. 창을 열고, 다섯 장을 모아 한 번에 받고, 확인을
/// 누른 뒤에야 카드가 앉는 — 실물이 하는 차례를 그대로 흉내 낸다.
class _ZigbangBridge {
  final order = <String>[];
  final received = <List<int>>[];
  List<int>? staging;
  int opened = 0;
  int staged = 0;
  int seals = 0;
  int statusCalls = 0;

  Future<Object> evaluate(String script) async {
    if (script == listingPhotoBridgeScript(PhotoTarget.zigbang)) {
      return jsonEncode({'ready': true, 'count': 0});
    }
    final command = RegExp(r'window\.__flrPhotos\.(\w+)\(\.\.\.(\[.*\])\)')
        .firstMatch(script);
    expect(command, isNotNull);
    final args = jsonDecode(command!.group(2)!) as List;
    final method = command.group(1)!;
    order.add(method);
    switch (method) {
      case 'open':
        // 창은 곧바로 뜨지 않는다. 한 번 되물어야 열린다.
        opened++;
        return jsonEncode({'ready': opened > 1});
      case 'begin':
        expect(staging, isNull, reason: '앞 장을 마친 뒤에 다음 장을 시작합니다.');
        expect(
          PhotoTarget.zigbang.acceptedTypes,
          contains((args[0] as Map)['type']),
        );
        staging = [];
        return jsonEncode({'count': 0});
      case 'append':
        staging!.addAll(base64Decode(args.single as String));
        return jsonEncode({'bytes': staging!.length});
      case 'commit':
        received.add(staging!);
        staging = null;
        staged++;
        // 마지막 장에서만 실제로 건네진다.
        return jsonEncode(
          staged < received.length + 0 && staged < 5
              ? {'staged': staged}
              : {'dispatched': true, 'files': staged},
        );
      case 'seal':
        // 직방이 사진을 다 받아야 확인이 풀린다 — 한 번은 잠겨 있다.
        seals++;
        return jsonEncode({'sealed': seals > 1, 'count': 0});
      case 'status':
        statusCalls++;
        return jsonEncode({'ready': true, 'count': staged, 'id': 'zb-last'});
      case 'clear':
        return jsonEncode({'cleared': true});
      default:
        fail('Unexpected photo bridge command: $method');
    }
  }
}

/// 1×1 PNG 한 장을 그 자리에 적는다 — 폼이 바이트를 읽어 보므로 진짜 PNG 라야 한다.
Future<File> _png(String path) async => File(path)..writeAsBytesSync(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWZkAAAAASUVORK5CYII=',
  ),
);
