import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jibang_listing_test/main.dart';

void main() {
  test('master form has all 50 fields and 29 required fields from the specification', () {
    final fields = groups.expand((group) => group.fields).toList();

    expect(groups, hasLength(5));
    expect(fields, hasLength(50));
    expect(fields.where((field) => field.required), hasLength(29));
  });

  test(
    'every field has an editable input definition and an auto-fill example',
    () {
      for (final field in groups.expand((group) => group.fields)) {
        expect(field.key, isNotEmpty);
        expect(field.label, isNotEmpty);
        expect(field.example, isNotEmpty);
      }
    },
  );

  test(
    'recreated-form mappings use structured choices where the target has them',
    () {
      final fields = {
        for (final field in groups.expand((group) => group.fields))
          field.key: field,
      };

      expect(fields['manageBasis']!.options, contains('직전월 관리비 기준'));
      expect(fields['manageIncludes']!.type, InputType.multiSelect);
      expect(fields['appliances']!.type, InputType.multiSelect);
      expect(fields['facilities']!.type, InputType.multiSelect);
      expect(fields['propertyType']!.options, contains('오픈형 원룸'));
      expect(fields['otherFeeReason']!.visibleWhenValue, '기타 부과');
    },
  );

  test('platform configuration exposes separate Zigbang and Dabang forms', () {
    expect(ListingPlatform.values, hasLength(2));
    expect(ListingPlatform.zigbang.label, '직방');
    expect(ListingPlatform.dabang.label, '다방');
    expect(ListingPlatform.zigbang.formUrl, contains('/zigbang/form/'));
    expect(ListingPlatform.dabang.formUrl, contains('/dabang/form/room/'));
  });

  testWidgets('both platform CTAs share validation enablement', (tester) async {
    await tester.pumpWidget(const ListingApp());
    await tester.scrollUntilVisible(
      find.text('직방에 보내기'),
      600,
      scrollable: find.byType(Scrollable).first,
    );

    FilledButton zigbang = tester.widget(
      find.widgetWithText(FilledButton, '직방에 보내기'),
    );
    FilledButton dabang = tester.widget(
      find.widgetWithText(FilledButton, '다방에 보내기'),
    );
    expect(zigbang.onPressed, isNull);
    expect(dabang.onPressed, isNull);

    await tester.tap(find.text('자동 채우기'));
    await tester.pump();
    zigbang = tester.widget(find.widgetWithText(FilledButton, '직방에 보내기'));
    dabang = tester.widget(find.widgetWithText(FilledButton, '다방에 보내기'));
    expect(zigbang.onPressed, isNotNull);
    expect(dabang.onPressed, isNotNull);
  });

  test('Dabang script reports its result and never activates submit', () {
    final script = dabangInjectionScript('{}');
    expect(script, contains('window.ListingResult.postMessage'));
    expect(script, contains('unsupported: []'));
    expect(script, contains('missing: []'));
    expect(script, contains('violations: []'));
    expect(script, contains("querySelectorAll('tr')"));
    expect(script, contains("selectRow('buildingUse', '건축물용도'"));
    expect(script, contains("selectRow('directionBase', '방향 기준/방향'"));
    expect(script, contains("named('room', 1)"));
    expect(script, contains("named('supply', 1)"));
    expect(script, contains('el.value === option.value'));
    expect(script, isNot(contains("getElementById('submit')")));
    expect(script, isNot(contains("querySelector('#submit')")));
    expect(script, isNot(contains("press(document.getElementById('submit'))")));
  });
}
