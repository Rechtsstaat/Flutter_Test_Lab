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
}
