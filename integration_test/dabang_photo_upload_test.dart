import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jibang_listing_test/main.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final photoCount in [1, 5]) {
    testWidgets(
      '$photoCount selected image file(s) reach ready Dabang cards in the real WKWebView',
      (tester) async {
        final photos = await _writePngFiles(photoCount);
        final photoDirectory = File(photos.first.path).parent;
        addTearDown(() async {
          if (await photoDirectory.exists()) {
            await photoDirectory.delete(recursive: true);
          }
        });

        final transferFinished = Completer<_TransferResult>();
        await tester.pumpWidget(
          MaterialApp(
            home: ListingFormPage(
              pickImages: () async => photos,
              remotePageBuilder: (values, platform, selectedPhotos) =>
                  RemoteFormPage(
                    values: values,
                    platform: platform,
                    photos: selectedPhotos,
                    onPhotoTransferComplete: (controller, failure) {
                      if (!transferFinished.isCompleted) {
                        transferFinished.complete(
                          _TransferResult(controller, failure),
                        );
                      }
                    },
                  ),
            ),
          ),
        );

        await tester.tap(find.text('자동 채우기'));
        await tester.pump();
        await tester.scrollUntilVisible(
          find.text('5. 입주 및 매물 상세 설명'),
          500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('5. 입주 및 매물 상세 설명'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('사진 선택 (0/20장)'),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('사진 선택 (0/20장)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('사진 선택 (0/20장)'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('사진 선택 ($photoCount/20장)'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('다방에 보내기'),
          500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('다방에 보내기'));
        await tester.pump();

        final result = await transferFinished.future.timeout(
          const Duration(minutes: 4),
          onTimeout: () => throw TimeoutException(
            '다방 미러의 페이지 로드·자동입력·사진 전송이 4분 안에 끝나지 않았습니다. '
            '시뮬레이터 네트워크, Basic 인증, 또는 미러의 사진 업로드 상태를 확인해 주세요.',
          ),
        );
        final dom = await _readDabangPhotoDom(result.controller);
        expect(
          result.failure,
          isNull,
          reason: '다방 사진 전송 실패: ${result.failure}\n원격 DOM 진단: $dom',
        );
        // The mirror consumes each FileList and deliberately clears its hidden
        // input after creating a card. The bridge checks `files.length == 1`
        // immediately before dispatch; final success is represented by cards.
        expect(
          dom['inputFiles'],
          0,
          reason: '다방 미러가 처리 후 일반 사진 input을 정리하지 않았습니다: $dom',
        );
        expect(
          dom['cardCount'],
          photoCount,
          reason: '다방 미러 사진 카드가 정확히 $photoCount개여야 합니다: $dom',
        );
        expect(
          dom['readyCount'],
          photoCount,
          reason: '각 사진 카드는 data-id와 aria-disabled=false로 완료되어야 합니다: $dom',
        );
        expect(
          dom['idsUnique'],
          isTrue,
          reason: '다방 미러가 각 카드에 고유 data-id를 만들지 못했습니다: $dom',
        );
        expect(
          dom['allEnabled'],
          isTrue,
          reason: '다방 미러에 아직 처리 중인 사진 카드가 남아 있습니다: $dom',
        );
        expect(
          dom['formPath'],
          '/dabang/form/room/',
          reason: '검증 대상이 다방 원격 등록 폼이 아닙니다: $dom',
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}

class _TransferResult {
  const _TransferResult(this.controller, this.failure);
  final WebViewController controller;
  final String? failure;
}

Future<List<XFile>> _writePngFiles(int count) async {
  const png =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWZkAAAAASUVORK5CYII=';
  final directory = await Directory.systemTemp.createTemp('dabang_wkwebview_');
  final bytes = base64Decode(png);
  final photos = <XFile>[];
  for (var index = 0; index < count; index++) {
    final file = File('${directory.path}/room-${index + 1}.png');
    await file.writeAsBytes(bytes, flush: true);
    photos.add(XFile(file.path));
  }
  return photos;
}

Future<Map<String, dynamic>> _readDabangPhotoDom(
  WebViewController controller,
) async {
  const script = r'''(() => {
    const section = document.querySelector('section#visual_info');
    const input = [...document.querySelectorAll('input[type="file"]')]
      .find(el => el.multiple && el.accept === 'image/*');
    const cards = section ? [...section.querySelectorAll('[class*="SortableContainer"] [data-index]')] : [];
    const fileInputs = [...document.querySelectorAll('input[type="file"]')].map(el => ({
      id: el.id || null,
      name: el.name || null,
      accept: el.accept || null,
      multiple: el.multiple,
      files: el.files ? el.files.length : -1,
      outerHTML: el.outerHTML.slice(0, 600),
    }));
    const photoSections = [...document.querySelectorAll('section')]
      .filter(el => /사진|이미지|photo|image/i.test(el.innerText || '') || el.querySelector('input[type="file"]'))
      .map(el => ({id: el.id || null, classes: el.className || null, html: el.outerHTML.slice(0, 1500)}));
    const ids = cards.map(card => card.dataset.id || null);
    const enabled = cards.map(card => card.getAttribute('aria-disabled') === 'false');
    return JSON.stringify({
      formPath: location.pathname,
      inputFiles: input ? input.files.length : -1,
      cardCount: cards.length,
      readyCount: cards.filter(card => card.dataset.id && card.getAttribute('aria-disabled') === 'false').length,
      ids,
      idsUnique: ids.length === new Set(ids).size && ids.every(Boolean),
      allEnabled: enabled.every(Boolean),
      html: section ? section.outerHTML.slice(0, 2000) : null,
      fileInputs,
      photoSections,
      pageText: document.body ? document.body.innerText.slice(0, 2500) : null,
    });
  })()''';
  Object? value = await controller.runJavaScriptReturningResult(script);
  for (var index = 0; index < 2 && value is String; index++) {
    value = jsonDecode(value);
  }
  return Map<String, dynamic>.from(value as Map);
}
