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
      expect(script, contains('current.every(settled)'));
      expect(script, contains("el.dispatchEvent(new Event('change'"));
    }
  });

  testWidgets(
    'photos are optional and one selected photo can be sent or deleted',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ListingFormPage(pickImages: () async => [photo])),
      );

      BrandButton cta() => tester.widget<BrandButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is BrandButton && widget.label.endsWith('채널에 등록하기'),
        ),
      );

      await tester.tap(find.text('자동 채우기'));
      await tester.pump();
      expect(
        cta().onPressed,
        isNotNull,
        reason: '사진이 없어도 등록 CTA 가 활성화되어야 합니다.',
      );

      // The photo picker lives in the last group, which starts collapsed.
      await tester.scrollUntilVisible(
        find.text('5. 입주 및 매물 상세 설명'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('5. 입주 및 매물 상세 설명'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('사진 선택 (0/20장)'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('사진 선택 (0/20장)'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('사진 선택 (0/20장)'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('사진 선택 (1/20장)'), findsOneWidget);
      expect(cta().onPressed, isNotNull);

      await tester.ensureVisible(find.byTooltip('1번 사진 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('1번 사진 삭제'));
      await tester.pump();
      expect(find.text('사진 선택 (0/20장)'), findsOneWidget);

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
