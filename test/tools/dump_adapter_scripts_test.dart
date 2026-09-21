// 어댑터 스크립트를 파일로 떨어뜨리는 도구 — 실물 폼에 손으로 돌려 볼 때 쓴다.
//
// ```sh
// DUMP_SCRIPTS_DIR=/tmp/flr flutter test test/tools/dump_adapter_scripts_test.dart
// ```
//
// `$DUMP_SCRIPTS_DIR/<이름>.payload.json` 마다 `<이름>.zigbang.js` ·
// `<이름>.dabang.js` 를, 그리고 `postcode.js` · `photo.zigbang.js` ·
// `photo.dabang.js` 를 적는다. 스크립트는 로그인한 브라우저의 등록 폼에서 돌린다 —
// 어댑터는 채우기만 하고 등록 단추는 누르지 않는다. 환경 변수가 없으면 아무것도
// 하지 않는다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/fields.dart';
import 'package:jibang_listing_test/listing_rules.dart';
import 'package:jibang_listing_test/photo_transfer.dart';
import 'package:jibang_listing_test/remote_form.dart';

void main() {
  final dir = Platform.environment['DUMP_SCRIPTS_DIR'];
  test('dump adapter scripts', () {
    if (dir == null || dir.isEmpty) return;
    final out = Directory(dir)..createSync(recursive: true);
    for (final file in out.listSync().whereType<File>()) {
      if (!file.path.endsWith('.payload.json')) continue;
      final name = file.uri.pathSegments.last.replaceAll('.payload.json', '');
      final values = Map<String, dynamic>.from(
        jsonDecode(file.readAsStringSync()) as Map,
      );
      final payload = jsonEncode(values);
      // 통합 폼이 이 값을 통과시키는가 — 통과시키지 않는 값으로 재 봐야 소용없다.
      final problems = listingViolations(
        values,
        channels: {ListingPlatform.zigbang, ListingPlatform.dabang},
      );
      // ignore: avoid_print
      print('$name: ${problems.isEmpty ? '통합 폼 통과' : problems.join(' / ')}');
      File('${out.path}/$name.zigbang.js')
          .writeAsStringSync(zigbangInjectionScript(payload));
      File('${out.path}/$name.dabang.js')
          .writeAsStringSync(dabangInjectionScript(payload));
    }
    File('${out.path}/postcode.js')
        .writeAsStringSync(postcodeBridgeScript('""'));
    File('${out.path}/photo.zigbang.js')
        .writeAsStringSync(listingPhotoBridgeScript(PhotoTarget.zigbang));
    File('${out.path}/photo.dabang.js')
        .writeAsStringSync(listingPhotoBridgeScript(PhotoTarget.dabang));
  });
}
