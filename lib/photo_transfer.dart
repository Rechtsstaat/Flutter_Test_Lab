import 'dart:convert';

import 'package:image_picker/image_picker.dart';

const maxListingPhotoBytes = 30 * 1024 * 1024;

/// Read only the header here. The full image is streamed when transferring it.
Future<String> validateListingPhoto(XFile photo) async {
  final length = await photo.length();
  if (length == 0) throw FormatException('${photo.name}: 빈 사진 파일입니다.');
  if (length > maxListingPhotoBytes) {
    throw FormatException('${photo.name}: 사진 한 장은 최대 30MB입니다.');
  }
  final header = <int>[];
  await for (final chunk in photo.openRead(0, length < 32 ? length : 32)) {
    header.addAll(chunk);
  }
  bool starts(List<int> bytes) =>
      header.length >= bytes.length &&
      List.generate(bytes.length, (i) => header[i] == bytes[i]).every((v) => v);
  if (starts([0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
  if (starts([71, 73, 70, 56])) return 'image/gif';
  if (starts([66, 77])) return 'image/bmp';
  final ascii = String.fromCharCodes(header);
  if (ascii.length >= 12 &&
      ascii.startsWith('RIFF') &&
      ascii.substring(8).startsWith('WEBP')) {
    return 'image/webp';
  }
  if (ascii.length >= 12 && ascii.substring(4, 8) == 'ftyp') {
    final brand = ascii.substring(8, 12);
    if (['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].contains(brand)) {
      return 'image/heic';
    }
    if (['avif', 'avis'].contains(brand)) return 'image/avif';
  }
  throw FormatException(
    '${photo.name}: 지원하는 사진 파일(JPEG, PNG, GIF, WebP, BMP, HEIC, AVIF)이 아닙니다.',
  );
}

/// The mirror owns the upload handler and its cards. Never synthesize cards or
/// success: a file is complete only once that handler creates a ready data-id.
String dabangPhotoBridgeScript() => r'''
(() => {
  try {
  if (location.hostname !== 'mirror-dimension-lab.pages.dev' ||
      !location.pathname.startsWith('/dabang/form/room/')) throw new Error('다방 미러 등록 폼이 아닙니다.');
  // The mirror can render this input outside the expected section and gives it
  // generated class names. Locate it by native properties rather than CSS
  // structure or generated class names.
  const input = () => {
    const candidates = document.querySelectorAll('input[type="file"]');
    for (let index = 0; index < candidates.length; index++) {
      const candidate = candidates[index];
      if (candidate.multiple && candidate.accept === 'image/*') return candidate;
    }
    return null;
  };
  const cards = () => [...document.querySelectorAll('section#visual_info [class*="SortableContainer"] [data-index]')];
  if (!input() || !input().multiple || input().accept !== 'image/*') {
    throw new Error('다방 일반 사진 선택란을 찾지 못했습니다.');
  }
  if (typeof File !== 'function' || typeof DataTransfer !== 'function') throw new Error('이 WebView는 사진 파일 전달을 지원하지 않습니다. 운영체제와 앱을 업데이트해 주세요.');
  const bridge = window.__flrPhotos = {
    chunks: [], before: [], beforeCount: 0, size: 0, metadata: null,
    begin(metadata, remaining) {
      const existing = cards();
      if (existing.length + remaining > 20) throw new Error('다방에 이미 있는 사진과 선택한 사진의 합계가 20장을 넘습니다.');
      if (existing.some(c => !c.dataset.id || c.getAttribute('aria-disabled') !== 'false')) throw new Error('다방에서 다른 사진을 처리 중입니다. 완료 후 다시 시도해 주세요.');
      this.before = existing.map(c => c.dataset.id);
      this.beforeCount = existing.length;
      this.chunks = []; this.size = 0; this.metadata = metadata;
      return {count: existing.length};
    },
    append(encoded) {
      const raw = atob(encoded);
      const bytes = new Uint8Array(raw.length);
      for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
      this.size += bytes.length;
      if (!this.metadata || this.size > this.metadata.size || this.size > 30 * 1024 * 1024) throw new Error('사진 전송 크기가 일치하지 않습니다.');
      this.chunks.push(bytes);
      return {bytes: this.size};
    },
    commit() {
      const el = input();
      if (!el || !this.metadata || this.size !== this.metadata.size) throw new Error('사진 전송이 끊겼습니다.');
      const file = new File(this.chunks, this.metadata.name, {type: this.metadata.type, lastModified: this.metadata.lastModified});
      this.chunks = [];
      const transfer = new DataTransfer();
      transfer.items.add(file);
      el.files = transfer.files;
      if (el.files.length !== 1 || el.files[0].size !== file.size) throw new Error('WebView가 사진 선택란에 파일을 전달하지 못했습니다.');
      el.dispatchEvent(new Event('input', {bubbles: true}));
      el.dispatchEvent(new Event('change', {bubbles: true}));
      return {dispatched: true};
    },
    status() {
      const current = cards();
      const fresh = current.filter(c => c.dataset.id && !this.before.includes(c.dataset.id));
      const ready = current.length === this.beforeCount + 1 && fresh.length === 1 &&
        fresh[0].getAttribute('aria-disabled') === 'false' &&
        current.every(c => c.dataset.id && c.getAttribute('aria-disabled') === 'false');
      return {ready, count: current.length, id: ready ? fresh[0].dataset.id : null};
    },
    clear() { this.chunks = []; this.metadata = null; return {cleared: true}; }
  };
  return JSON.stringify({ready: true, count: cards().length});
  } catch (e) {
    return JSON.stringify({error: String(e && (e.message || e))});
  }
})()
''';

String dabangPhotoCommand(
  String method, [
  List<Object?> arguments = const [],
]) =>
    '''(() => { try {
      if (!window.__flrPhotos) throw new Error('사진 전송 중 페이지가 변경되었습니다.');
      return JSON.stringify(window.__flrPhotos.$method(...${jsonEncode(arguments)}));
    } catch (e) { return JSON.stringify({error: String(e.message || e)}); } })()''';

typedef PhotoJavaScriptRunner = Future<Object> Function(String script);

/// Each bridge call is bounded and awaited. The browser's staging buffer holds
/// only the current file (at most 96 KiB per call from the native stream).
/// The mirror retains already uploaded files for its photo cards separately.
Future<void> transferDabangPhotos({
  required List<XFile> photos,
  required PhotoJavaScriptRunner evaluate,
  required void Function(int completed, int total) onProgress,
  bool Function()? isCancelled,
  Duration timeout = const Duration(seconds: 45),
}) async {
  if (photos.isEmpty || photos.length > 20) {
    throw const FormatException('다방에 첨부할 실제 사진 1~20장을 선택해 주세요.');
  }
  Future<Map<String, dynamic>> run(String operation, String script) async {
    if (isCancelled?.call() == true) throw StateError('사진 전송이 취소되었습니다.');
    Object? result;
    try {
      result = await evaluate(script);
    } catch (error) {
      throw StateError('다방 WebView $operation JavaScript 실행 실패: $error');
    }
    // Android and WKWebView differ in whether returned strings are JSON quoted.
    Map<String, dynamic> data;
    try {
      for (var i = 0; i < 2 && result is String; i++) {
        result = jsonDecode(result);
      }
      data = Map<String, dynamic>.from(result as Map);
    } catch (error) {
      throw StateError('다방 WebView $operation 응답 해석 실패: $error');
    }
    if (data['error'] != null) {
      throw StateError('다방 WebView $operation 오류: ${data['error']}');
    }
    return data;
  }

  final bridgeStart = Stopwatch()..start();
  while (true) {
    try {
      await run('사진 첨부 초기화', dabangPhotoBridgeScript());
      break;
    } catch (error) {
      if (bridgeStart.elapsed >= const Duration(seconds: 20)) {
        throw StateError('다방 사진 선택란이 준비되지 않았습니다: $error');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
  onProgress(0, photos.length);
  try {
    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      try {
        final mime = await validateListingPhoto(photo);
        await run(
          '${index + 1}번 사진 전송 시작',
          dabangPhotoCommand('begin', [
            {
              'name': photo.name,
              'type': mime,
              'size': await photo.length(),
              'lastModified':
                  (await photo.lastModified()).millisecondsSinceEpoch,
            },
            photos.length - index,
          ]),
        );
        await for (final chunk in photo.openRead()) {
          const chunkSize = 96 * 1024;
          for (var offset = 0; offset < chunk.length; offset += chunkSize) {
            final end = offset + chunkSize < chunk.length
                ? offset + chunkSize
                : chunk.length;
            await run(
              '${index + 1}번 사진 데이터 추가',
              dabangPhotoCommand('append', [
                base64Encode(chunk.sublist(offset, end)),
              ]),
            );
          }
        }
        await run('${index + 1}번 사진 선택 이벤트 전달', dabangPhotoCommand('commit'));
        final watch = Stopwatch()..start();
        while (true) {
          final state = await run(
            '${index + 1}번 사진 카드 완료 상태 확인',
            dabangPhotoCommand('status'),
          );
          if (state['ready'] == true) break;
          if (watch.elapsed >= timeout) {
            throw StateError(
              '다방 사진 카드의 처리 완료를 확인하지 못했습니다. 현재 ${state['count']}장입니다. 사진 형식 또는 미러 오류를 확인해 주세요.',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        onProgress(index + 1, photos.length);
      } catch (error) {
        throw StateError('${index + 1}번 사진 (${photo.name}) 전송 실패: $error');
      }
    }
  } finally {
    // Preserve uploaded cards on a partial failure, but release staging bytes.
    try {
      await run('사진 전송 임시 데이터 정리', dabangPhotoCommand('clear'));
    } catch (_) {}
  }
}
