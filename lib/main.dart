import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum ListingPlatform { zigbang, dabang }

extension ListingPlatformConfig on ListingPlatform {
  String get label => this == ListingPlatform.zigbang ? '직방' : '다방';

  String get formUrl => this == ListingPlatform.zigbang
      ? 'https://mirror-dimension-lab.pages.dev/zigbang/form/oneroom/'
      : 'https://mirror-dimension-lab.pages.dev/dabang/form/room/';
}

enum InputType {
  text,
  number,
  date,
  choice,
  toggle,
  multiSelect,
  addressSearch,
  loan,
  manageDetails,
  photoPicker,
}

class MasterField {
  const MasterField({
    required this.number,
    required this.key,
    required this.label,
    required this.type,
    required this.example,
    this.required = false,
    this.options = const [],
    this.visibleWhenKey,
    this.visibleWhenValue,
    this.maxLength,
    this.targetAvailable = true,
    this.unavailableReason,
  });

  final int number;
  final String key;
  final String label;
  final InputType type;
  final String example;
  final bool required;
  final List<String> options;
  final String? visibleWhenKey;
  final String? visibleWhenValue;
  final int? maxLength;
  final bool targetAvailable;
  final String? unavailableReason;
}

class FieldGroup {
  const FieldGroup(this.title, this.fields);
  final String title;
  final List<MasterField> fields;
}

const _types = [
  '오픈형 원룸',
  '분리형 원룸',
  '복층형 원룸',
  '투룸 빌라',
  '쓰리룸 이상 빌라',
  '오피스텔 원룸형',
  '오피스텔 분리/투룸형',
  '아파트',
  '단독주택',
  '다가구주택',
  '상가주택',
  '상가 점포',
  '사무실',
  '일반 건물',
  '공장/창고',
  '토지',
];

/// The 29 statutory building-use categories in Building Act Enforcement
/// Decree, Appendix 1.  These are deliberately not a shortened product list:
/// the unified form must retain values required by the other two targets.
const _uses = [
  '단독주택',
  '공동주택',
  '제1종근린생활시설',
  '제2종근린생활시설',
  '문화 및 집회시설',
  '종교시설',
  '판매시설',
  '운수시설',
  '의료시설',
  '교육연구시설',
  '노유자시설',
  '수련시설',
  '운동시설',
  '업무시설',
  '숙박시설',
  '위락시설',
  '공장',
  '창고시설',
  '위험물저장 및 처리시설',
  '자동차관련시설',
  '동물 및 식물관련시설',
  '자원순환관련시설',
  '교정 및 군사시설',
  '방송통신시설',
  '발전시설',
  '묘지관련시설',
  '관광휴게시설',
  '장례시설',
  '야영장시설',
];
const _fees = [
  '인터넷',
  '유선TV',
  '청소비',
  '수도료',
  '가스사용료',
  '전기료',
  '난방비',
  '승강기유지비',
  '주차비',
  '경비비',
  '기타',
];
const _appliances = [
  '에어컨',
  '세탁기',
  '건조기',
  '냉장고',
  '가스레인지',
  '인덕션',
  '전자레인지',
  '침대',
  '책상',
  '옷장',
  '신발장',
  '식탁',
  '쇼파',
  '싱크대',
];
const _facilities = [
  'CCTV',
  '인터폰',
  '비디오폰',
  '공동현관보안',
  '사설경비',
  '무인택배함',
  '테라스',
  '베란다/발코니',
  '전기차 충전시설',
];

/// The specification's 50 input rows, preserved individually in five sections.
final List<FieldGroup> groups = [
  FieldGroup('1. 매물 기본 정보', [
    MasterField(
      number: 1,
      key: 'propertyType',
      label: '매물 대분류',
      type: InputType.choice,
      required: true,
      example: '오픈형 원룸',
      options: _types,
    ),
    MasterField(
      number: 2,
      key: 'address',
      label: '매물 기본 주소',
      type: InputType.addressSearch,
      required: true,
      example: '서울특별시 강남구 테헤란로 123',
      unavailableReason: '여기서 저장한 주소는 미러의 카카오 주소 검색 창에 검색어로 그대로 넘어갑니다. 좌표와 우편번호는 그 창에서 결과를 골라야 확정되므로, 전송 화면에서 한 번 눌러 주세요.',
    ),
    MasterField(
      number: 3,
      key: 'building',
      label: '동 정보',
      type: InputType.text,
      example: '101',
      required: false,
    ),
    MasterField(
      number: 4,
      key: 'singleBuilding',
      label: '단일동 여부',
      type: InputType.toggle,
      example: 'false',
    ),
    MasterField(
      number: 5,
      key: 'unit',
      label: '호수 정보',
      type: InputType.text,
      required: true,
      example: '202',
    ),
    MasterField(
      number: 6,
      key: 'exclusiveArea',
      label: '전용면적 (㎡)',
      type: InputType.number,
      required: true,
      example: '33.05',
    ),
    MasterField(
      number: 7,
      key: 'supplyArea',
      label: '공급면적 (㎡)',
      type: InputType.number,
      required: true,
      example: '40.12',
    ),
    MasterField(
      number: 8,
      key: 'floorAll',
      label: '전체 층',
      type: InputType.choice,
      required: true,
      example: '10',
      options: List.generate(80, (i) => '${i + 1}'),
    ),
    MasterField(
      number: 9,
      key: 'floor',
      label: '해당 층',
      type: InputType.choice,
      required: true,
      example: '5',
      options: ['지하 1층', '반지하', ...List.generate(80, (i) => '${i + 1}'), '옥탑'],
    ),
    MasterField(
      number: 10,
      key: 'floorPrivate',
      label: '층수 비공개 여부',
      type: InputType.toggle,
      example: 'false',
    ),
    MasterField(
      number: 11,
      key: 'buildingUse',
      label: '건축물 용도',
      type: InputType.choice,
      required: true,
      example: '공동주택',
      options: _uses,
    ),
    MasterField(
      number: 12,
      key: 'approvalDate',
      label: '사용승인일',
      type: InputType.date,
      required: true,
      example: '2018-03-01',
    ),
  ]),
  FieldGroup('2. 가격 및 관리비 정보', [
    MasterField(
      number: 13,
      key: 'trade',
      label: '거래 유형',
      type: InputType.choice,
      required: true,
      example: '월세',
      options: ['월세', '전세', '매매', '단기'],
    ),
    MasterField(
      number: 14,
      key: 'deposit',
      label: '보증금 (만원)',
      type: InputType.number,
      required: true,
      example: '1000',
    ),
    MasterField(
      number: 15,
      key: 'monthlyRent',
      label: '월세 금액 (만원)',
      type: InputType.number,
      required: true,
      example: '65',
      visibleWhenKey: 'trade',
      visibleWhenValue: '월세',
    ),
    MasterField(
      number: 16,
      key: 'salePrice',
      label: '매매 금액 (만원)',
      type: InputType.number,
      example: '45000',
      visibleWhenKey: 'trade',
      visibleWhenValue: '매매',
      targetAvailable: false,
      unavailableReason: '원룸 직방 등록 폼은 매매 거래 유형과 매매가 입력을 제공하지 않습니다.',
    ),
    MasterField(
      number: 17,
      key: 'shortTerm',
      label: '단기 매물 여부',
      type: InputType.toggle,
      example: 'false',
    ),
    MasterField(
      number: 18,
      key: 'loan',
      label: '융자금 유무 및 금액',
      type: InputType.loan,
      example: '없음',
    ),
    MasterField(
      number: 19,
      key: 'noManagementFee',
      label: '관리비 없음',
      type: InputType.toggle,
      example: 'false',
    ),
    MasterField(
      number: 20,
      key: 'manageMethod',
      label: '관리비 부과 방식',
      type: InputType.choice,
      required: true,
      example: '정액 관리비',
      options: ['정액 관리비', '기타 부과', '확인 불가'],
    ),
    MasterField(
      number: 21,
      key: 'manageBasis',
      label: '관리비 부과 기준',
      type: InputType.choice,
      required: true,
      example: '직전월 관리비 기준',
      options: ['직전월 관리비 기준', '3개월 평균 관리비', '1년 평균 관리비', '기타 직접 입력'],
      visibleWhenKey: 'manageMethod',
      visibleWhenValue: '정액 관리비',
    ),
    MasterField(
      number: 22,
      key: 'managementFee',
      label: '총 관리비 금액 (만원)',
      type: InputType.number,
      required: true,
      example: '8',
      visibleWhenKey: 'manageMethod',
      visibleWhenValue: '정액 관리비',
    ),
    MasterField(
      number: 23,
      key: 'manageIncludes',
      label: '관리비 포함 항목',
      type: InputType.multiSelect,
      example: '인터넷,수도료',
      options: _fees,
      visibleWhenKey: 'manageMethod',
      visibleWhenValue: '정액 관리비',
    ),
    MasterField(
      number: 24,
      key: 'manageDetail',
      label: '비목별 실비·정액 내역',
      type: InputType.manageDetails,
      example: '인터넷:정액 부과, 수도료:실비 부과',
    ),
    MasterField(
      number: 25,
      key: 'otherFeeReason',
      label: '기타 부과 법정 사유',
      type: InputType.choice,
      example: '관리규약에 따라 부과',
      options: [
        '관리규약에 따라 부과',
        '면적 및 세대별 부과',
        '전체 세대 균등 부과',
        '계량기별 실비 부과',
        '의뢰인 미고지',
        '기타',
      ],
      visibleWhenKey: 'manageMethod',
      visibleWhenValue: '기타 부과',
    ),
    MasterField(
      number: 26,
      key: 'unknownFeeReason',
      label: '확인 불가 법정 사유',
      type: InputType.choice,
      example: '미등기 건물 사유',
      options: ['단독주택 사유', '상가 및 상가주택 사유', '미등기 건물 사유'],
      visibleWhenKey: 'manageMethod',
      visibleWhenValue: '확인 불가',
    ),
  ]),
  FieldGroup('3. 방 구조 및 건물 조건', [
    MasterField(
      number: 27,
      key: 'roomLayout',
      label: '방 구조',
      type: InputType.choice,
      required: true,
      example: '오픈형 원룸',
      options: ['오픈형 원룸', '분리형 원룸', '복층형 원룸'],
    ),
    MasterField(
      number: 28,
      key: 'rooms',
      label: '방 개수',
      type: InputType.choice,
      required: true,
      example: '1',
      options: ['1', '2', '3', '4', '5 이상'],
    ),
    MasterField(
      number: 29,
      key: 'bathrooms',
      label: '욕실 수',
      type: InputType.choice,
      required: true,
      example: '1',
      options: ['1', '2', '3 이상'],
    ),
    MasterField(
      number: 30,
      key: 'directionBase',
      label: '방향 기준',
      type: InputType.choice,
      required: true,
      example: '주실 기준',
      options: ['거실 기준', '안방 기준', '주실 기준'],
    ),
    MasterField(
      number: 31,
      key: 'direction',
      label: '주실 방향',
      type: InputType.choice,
      required: true,
      example: '남향',
      options: ['동향', '서향', '남향', '북향', '북동향', '남동향', '북서향', '남서향'],
    ),
    MasterField(
      number: 32,
      key: 'parking',
      label: '주차 가능 여부',
      type: InputType.choice,
      required: true,
      example: '주차 가능',
      options: ['주차 가능', '주차 불가능'],
    ),
    MasterField(
      number: 33,
      key: 'parkingCount',
      label: '총 주차 대수',
      type: InputType.number,
      example: '10',
      visibleWhenKey: 'parking',
      visibleWhenValue: '주차 가능',
    ),
    MasterField(
      number: 34,
      key: 'parkingPerHousehold',
      label: '세대당 주차 대수',
      type: InputType.number,
      example: '0.7',
      targetAvailable: false,
      unavailableReason: '직방 원룸 폼은 총 주차대수만 지원하고 세대당 주차대수 필드가 없습니다.',
    ),
    MasterField(
      number: 35,
      key: 'elevator',
      label: '엘리베이터 유무',
      type: InputType.choice,
      required: true,
      example: '있음',
      options: ['있음', '없음'],
    ),
    MasterField(
      number: 36,
      key: 'violation',
      label: '위반건축물 여부',
      type: InputType.choice,
      required: true,
      example: '해당 없음',
      options: ['해당 없음', '위반건축물 해당'],
    ),
    MasterField(
      number: 37,
      key: 'loanAvailable',
      label: '대출 가능 여부',
      type: InputType.choice,
      required: true,
      example: '가능',
      options: ['가능', '불가능', '확인 필요'],
    ),
    MasterField(
      number: 38,
      key: 'petAllowed',
      label: '반려동물 가능 여부',
      type: InputType.choice,
      required: true,
      example: '가능',
      options: ['가능', '불가능', '확인 필요'],
    ),
    MasterField(
      number: 39,
      key: 'heating',
      label: '난방 방식',
      type: InputType.choice,
      example: '개별난방',
      options: ['개별난방', '중앙난방', '지역난방'],
      targetAvailable: false,
      unavailableReason: '직방 원룸 폼에는 난방 방식 입력 항목이 없습니다.',
    ),
  ]),
  FieldGroup('4. 시설 및 옵션', [
    MasterField(
      number: 40,
      key: 'appliances',
      label: '가전·가구 옵션',
      type: InputType.multiSelect,
      example: '에어컨,세탁기,냉장고',
      options: _appliances,
    ),
    MasterField(
      number: 41,
      key: 'facilities',
      label: '보안 및 시설 옵션',
      type: InputType.multiSelect,
      example: 'CCTV,테라스',
      options: _facilities,
    ),
  ]),
  FieldGroup('5. 입주 및 매물 상세 설명', [
    MasterField(
      number: 42,
      key: 'moveInType',
      label: '입주 방식',
      type: InputType.choice,
      required: true,
      example: '즉시 입주',
      options: ['즉시 입주', '날짜 지정', '협의 가능'],
    ),
    MasterField(
      number: 43,
      key: 'moveInDate',
      label: '입주 희망일',
      type: InputType.date,
      example: '2026-10-01',
      visibleWhenKey: 'moveInType',
      visibleWhenValue: '날짜 지정',
    ),
    MasterField(
      number: 44,
      key: 'moveInNegotiable',
      label: '입주 협의 가능 여부',
      type: InputType.toggle,
      example: 'false',
    ),
    MasterField(
      number: 45,
      key: 'photoCount',
      label: '매물 사진 첨부',
      type: InputType.photoPicker,
      required: true,
      example: '5',
      targetAvailable: false,
      unavailableReason: '현재 앱에는 기기 사진 파일을 선택·보관하는 네이티브 피커가 구성되어 있지 않습니다. WebView JavaScript도 파일 input에 파일을 할당할 수 없으므로 사진 수를 임의로 입력하거나 전송 성공으로 표시하지 않습니다.',
    ),
    MasterField(
      number: 46,
      key: 'title',
      label: '매물 제목 (한줄 요약)',
      type: InputType.text,
      required: true,
      example: '채광 좋은 강남 원룸',
      maxLength: 30,
    ),
    MasterField(
      number: 47,
      key: 'description',
      label: '매물 상세 설명',
      type: InputType.text,
      required: true,
      example: '역세권에 위치한 깨끗한 원룸입니다.',
      maxLength: 1000,
    ),
    MasterField(
      number: 48,
      key: 'lh',
      label: 'LH 전세임대 여부',
      type: InputType.choice,
      example: '불가능',
      options: ['가능', '불가능'],
      targetAvailable: false,
      unavailableReason: '직방 원룸 폼은 LH 전세임대 여부를 입력받지 않습니다.',
    ),
    MasterField(
      number: 49,
      key: 'privateMemo',
      label: '비공개 메모 (내부용)',
      type: InputType.text,
      example: '임대인 연락은 오후에',
    ),
    MasterField(
      number: 50,
      key: 'ownerPhone',
      label: '집주인 연락처',
      type: InputType.text,
      example: '010-1234-5678',
    ),
  ]),
];

void main() => runApp(const ListingApp());

class ListingApp extends StatelessWidget {
  const ListingApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff1565c0),
      useMaterial3: true,
    ),
    home: const ListingFormPage(),
  );
}

class ListingFormPage extends StatefulWidget {
  const ListingFormPage({super.key});
  @override
  State<ListingFormPage> createState() => _ListingFormPageState();
}

class _ListingFormPageState extends State<ListingFormPage> {
  final values = <String, dynamic>{};
  final textControllers = <String, TextEditingController>{};
  String? error;

  @override
  void dispose() {
    for (final controller in textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _visible(MasterField field) {
    // These conditions use booleans, thresholds, or two trade types. Keeping
    // them here preserves the specification's exactly 50 master rows.
    switch (field.key) {
      case 'building':
        return values['singleBuilding'] != true;
      case 'deposit':
        return values['trade'] == '월세' || values['trade'] == '전세';
      case 'manageMethod':
        return values['noManagementFee'] != true;
      case 'manageBasis':
      case 'managementFee':
      case 'manageIncludes':
        return values['noManagementFee'] != true &&
            values['manageMethod'] == '정액 관리비';
      case 'manageDetail':
        return values['noManagementFee'] != true &&
            values['manageMethod'] == '정액 관리비' &&
            (num.tryParse('${values['managementFee'] ?? ''}') ?? 0) >= 10;
      case 'otherFeeReason':
        return values['noManagementFee'] != true &&
            values['manageMethod'] == '기타 부과';
      case 'unknownFeeReason':
        return values['noManagementFee'] != true &&
            values['manageMethod'] == '확인 불가';
      case 'lh':
        return values['trade'] == '월세' || values['trade'] == '전세';
      default:
        return field.visibleWhenKey == null ||
            values[field.visibleWhenKey] == field.visibleWhenValue;
    }
  }

  void _autoFill() {
    for (final field in groups.expand((g) => g.fields)) {
      switch (field.type) {
        case InputType.multiSelect:
          values[field.key] = field.example.split(',');
        case InputType.toggle:
          values[field.key] = field.example == 'true';
        case InputType.loan:
          values[field.key] = '없음';
          values.remove('loanAmount');
        case InputType.manageDetails:
          values[field.key] = {
            for (final fee in _fees)
              fee: (values['manageIncludes'] as List? ?? const []).contains(fee)
                  ? '정액 부과'
                  : '실비 부과',
          };
        case InputType.addressSearch:
          values[field.key] = field.example;
          values['postalCode'] = '06236';
          values['legalDongCode'] = '1168010100';
        case InputType.photoPicker:
          // A test count lets the rest of the target adapter be exercised.
          // The result page still reports that browser security prevents
          // automatic File transfer to the remote input.
          values[field.key] = field.example;
        default:
          values[field.key] = field.example;
      }
      if (field.type != InputType.photoPicker) {
        textControllers[field.key]?.text = values[field.key]?.toString() ?? '';
      }
    }
    setState(() => error = null);
  }

  List<String> _violations() {
    final violations = <String>[];
    for (final field in groups.expand((g) => g.fields)) {
      if (!_visible(field)) continue;
      final value = values[field.key];
      // These asterisks represent conditionally required master rows. Their
      // conditions are evaluated explicitly below instead of globally.
      if (const {
        'deposit',
        'manageBasis',
        'managementFee',
        'manageIncludes',
        'manageDetail',
        'otherFeeReason',
        'unknownFeeReason',
        'photoCount',
      }.contains(field.key)) {
        continue;
      }
      if (field.required &&
          (value == null || value == '' || (value is List && value.isEmpty))) {
        violations.add('${field.number}. ${field.label}');
      }
    }
    if ((values['trade'] == '월세' || values['trade'] == '전세') &&
        _blank('deposit')) {
      violations.add('14. 보증금 (월세/전세)');
    }
    if (values['trade'] == '매매' && _blank('salePrice')) {
      violations.add('16. 매매 금액 (매매)');
    }
    if (values['parking'] == '주차 가능' && _blank('parkingCount')) {
      violations.add('33. 총 주차 대수');
    }
    if (values['singleBuilding'] != true && _blank('building')) {
      violations.add('3. 동 정보 (단일동 아님)');
    }
    if (values['loan'] == '있음' && _blank('loanAmount')) {
      violations.add('18. 융자금 금액 (융자금 있음)');
    }
    if (values['noManagementFee'] != true) {
      if (_blank('manageMethod')) violations.add('20. 관리비 부과 방식');
      if (values['manageMethod'] == '정액 관리비') {
        if (_blank('manageBasis')) violations.add('21. 관리비 부과 기준');
        if (_blank('managementFee')) violations.add('22. 총 관리비 금액');
        final includes = values['manageIncludes'];
        if (includes is! List || includes.isEmpty) {
          violations.add('23. 관리비 포함 항목');
        }
        if ((num.tryParse('${values['managementFee'] ?? ''}') ?? 0) >= 10) {
          final details = values['manageDetail'];
          if (details is! Map ||
              _fees.any((fee) => '${details[fee] ?? ''}'.isEmpty)) {
            violations.add('24. 비목별 실비·정액 내역');
          }
        }
      } else if (values['manageMethod'] == '기타 부과' &&
          _blank('otherFeeReason')) {
        violations.add('25. 기타 부과 법정 사유');
      } else if (values['manageMethod'] == '확인 불가' &&
          _blank('unknownFeeReason')) {
        violations.add('26. 확인 불가 법정 사유');
      }
    }
    if (values['moveInType'] == '날짜 지정' && _blank('moveInDate')) {
      violations.add('43. 입주 희망일');
    }
    if ((values['trade'] == '월세' || values['trade'] == '전세') && _blank('lh')) {
      violations.add('48. LH 전세임대 여부');
    }
    final photos = int.tryParse('${values['photoCount'] ?? 0}') ?? 0;
    if (photos < 5 || photos > 20) {
      violations.add('45. 실제로 선택된 매물 사진 5~20장');
    }
    if ('${values['title'] ?? ''}'.length > 30) {
      violations.add('46. 제목은 최대 30자');
    }
    if ('${values['description'] ?? ''}'.length > 1000) {
      violations.add('47. 상세 설명은 최대 1000자');
    }
    return violations;
  }

  bool _blank(String key) =>
      values[key] == null || values[key].toString().trim().isEmpty;

  void _send(ListingPlatform platform) {
    final violations = _violations();
    if (violations.isNotEmpty) {
      setState(() => error = '필수/제한 확인: ${violations.join(', ')}');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteFormPage(
          values: Map<String, dynamic>.from(values),
          platform: platform,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('통합 매물 등록'),
      actions: [TextButton(onPressed: _autoFill, child: const Text('자동 채우기'))],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '직방·다방·당근 통합 명세 50개 항목',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('직방 전송에서는 지원하지 않는 항목을 결과에서 명확히 안내합니다.'),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 10),
        ...groups.map(
          (group) => Card(
            child: ExpansionTile(
              title: Text(group.title),
              initiallyExpanded: group == groups.first,
              children: group.fields.where(_visible).map(_field).toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _violations().isEmpty
              ? () => _send(ListingPlatform.zigbang)
              : null,
          icon: const Icon(Icons.send),
          label: const Text('직방에 보내기'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _violations().isEmpty
              ? () => _send(ListingPlatform.dabang)
              : null,
          icon: const Icon(Icons.send),
          label: const Text('다방에 보내기'),
        ),
      ],
    ),
  );

  Widget _field(MasterField field) {
    final title =
        '${field.number.toString().padLeft(2, '0')}. ${field.label}${_isRequiredNow(field) ? ' *' : ''}';
    if (field.type == InputType.addressSearch) {
      return _addressSearchField(field, title);
    }
    if (field.type == InputType.loan) return _loanField(field, title);
    if (field.type == InputType.manageDetails) {
      return _manageDetailsField(field, title);
    }
    if (field.type == InputType.photoPicker) return _photoField(title);
    if (field.type == InputType.toggle) {
      return SwitchListTile(
        title: Text(title),
        value: values[field.key] == true,
        onChanged: (v) => setState(() => values[field.key] = v),
      );
    }
    if (field.type == InputType.choice) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: DropdownButtonFormField<String>(
          initialValue: values[field.key] as String?,
          decoration: InputDecoration(
            labelText: title,
            border: const OutlineInputBorder(),
          ),
          items: field.options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) => setState(() => values[field.key] = v),
        ),
      );
    }
    if (field.type == InputType.multiSelect) {
      final selected = List<String>.from(
        values[field.key] as List? ?? const [],
      );
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            Wrap(
              spacing: 6,
              children: field.options
                  .map(
                    (option) => FilterChip(
                      label: Text(option),
                      selected: selected.contains(option),
                      onSelected: (on) => setState(() {
                        if (on) {
                          selected.add(option);
                        } else {
                          selected.remove(option);
                        }
                        values[field.key] = selected;
                      }),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      );
    }
    final controller = textControllers.putIfAbsent(
      field.key,
      () => TextEditingController(text: values[field.key]?.toString() ?? ''),
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: controller,
        keyboardType: field.type == InputType.number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        maxLength: field.maxLength,
        maxLines: field.key == 'description' ? 5 : 1,
        decoration: InputDecoration(
          labelText: title,
          hintText: field.example,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) => setState(() => values[field.key] = v),
      ),
    );
  }

  bool _isRequiredNow(MasterField field) {
    if (field.key == 'building') return values['singleBuilding'] != true;
    if (field.key == 'deposit' || field.key == 'lh') {
      return values['trade'] == '월세' || values['trade'] == '전세';
    }
    if (const {
      'manageBasis',
      'managementFee',
      'manageIncludes',
    }.contains(field.key)) {
      return values['noManagementFee'] != true &&
          values['manageMethod'] == '정액 관리비';
    }
    if (field.key == 'manageDetail') {
      return values['noManagementFee'] != true &&
          values['manageMethod'] == '정액 관리비' &&
          (num.tryParse('${values['managementFee'] ?? ''}') ?? 0) >= 10;
    }
    if (field.key == 'otherFeeReason') {
      return values['noManagementFee'] != true &&
          values['manageMethod'] == '기타 부과';
    }
    if (field.key == 'unknownFeeReason') {
      return values['noManagementFee'] != true &&
          values['manageMethod'] == '확인 불가';
    }
    return field.required;
  }

  Widget _addressSearchField(MasterField field, String title) {
    final address = values[field.key] as String? ?? '';
    return ListTile(
      title: Text(title),
      subtitle: Text(
        address.isEmpty
            ? '검색 후 도로명·우편번호·법정동 코드를 함께 저장합니다.'
            : '$address\n우편번호 ${values['postalCode'] ?? '-'} · 법정동 ${values['legalDongCode'] ?? '-'}',
      ),
      trailing: OutlinedButton(
        child: const Text('주소 검색'),
        onPressed: () async {
          final result = await showDialog<Map<String, String>>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('주소 검색'),
              content: const Text('테스트용 검색 결과'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, {
                    'address': '서울특별시 강남구 테헤란로 123',
                    'postalCode': '06236',
                    'legalDongCode': '1168010100',
                  }),
                  child: const Text('테헤란로 123'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, {
                    'address': '서울특별시 강남구 역삼로 100',
                    'postalCode': '06242',
                    'legalDongCode': '1168010100',
                  }),
                  child: const Text('역삼로 100'),
                ),
              ],
            ),
          );
          if (result != null && mounted) {
            setState(() {
              values[field.key] = result['address'];
              values['postalCode'] = result['postalCode'];
              values['legalDongCode'] = result['legalDongCode'];
            });
          }
        },
      ),
    );
  }

  Widget _loanField(MasterField field, String title) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: values[field.key] as String?,
          decoration: InputDecoration(
            labelText: title,
            border: const OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: '없음', child: Text('융자금 없음')),
            DropdownMenuItem(value: '있음', child: Text('융자금 있음')),
          ],
          onChanged: (value) => setState(() {
            values[field.key] = value;
            if (value != '있음') values.remove('loanAmount');
          }),
        ),
        if (values[field.key] == '있음')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '융자금 금액 (만원)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => values['loanAmount'] = value,
            ),
          ),
      ],
    ),
  );

  Widget _manageDetailsField(MasterField field, String title) {
    final details = Map<String, String>.from(
      values[field.key] as Map? ?? const <String, String>{},
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          ..._fees.map(
            (fee) => DropdownButtonFormField<String>(
              key: ValueKey('$fee-${details[fee]}'),
              initialValue: details[fee],
              decoration: InputDecoration(labelText: fee),
              items: const ['정액 부과', '실비 부과', '해당 없음']
                  .map(
                    (choice) =>
                        DropdownMenuItem(value: choice, child: Text(choice)),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                details[fee] = value ?? '';
                values[field.key] = details;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoField(String title) => Padding(
    padding: const EdgeInsets.all(12),
    child: TextField(
      controller: textControllers.putIfAbsent(
        'photoCount',
        () =>
            TextEditingController(text: values['photoCount']?.toString() ?? ''),
      ),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: '$title (5~20장)',
        helperText: '테스트 장수입니다. 원격 미러의 파일 input에는 WebView JavaScript로 파일을 넣을 수 없어 결과에서 제한 사유를 표시합니다.',
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) => setState(() => values['photoCount'] = value),
    ),
  );
}

class RemoteFormPage extends StatefulWidget {
  const RemoteFormPage({
    super.key,
    required this.values,
    required this.platform,
  });
  final Map<String, dynamic> values;
  final ListingPlatform platform;
  @override
  State<RemoteFormPage> createState() => _RemoteFormPageState();
}

class _RemoteFormPageState extends State<RemoteFormPage> {
  late final WebViewController controller;
  late String status;
  List<String> limitations = const [];
  String? _lastInjectedUrl;

  /// The mirror serves `.../oneroom/index.html` as a 308 to `.../oneroom/`, so
  /// the URL that reaches [onPageFinished] never equals the configured one.
  /// Comparing the directory form keeps both spellings pointing at one page.
  static String _directory(Uri uri) {
    var path = uri.path;
    if (path.endsWith('index.html')) {
      path = path.substring(0, path.length - 'index.html'.length);
    }
    return path.endsWith('/') ? path : '$path/';
  }

  @override
  void initState() {
    super.initState();
    status = '${widget.platform.label} 미러를 여는 중…';
    final targetUri = Uri.parse(widget.platform.formUrl);
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('ListingResult', onMessageReceived: _receive)
      ..setNavigationDelegate(
        NavigationDelegate(
          onHttpAuthRequest: (request) {
            if (request.host == targetUri.host) {
              request.onProceed(
                const WebViewCredential(user: 'mirror', password: 'money'),
              );
            } else {
              request.onCancel();
            }
          },
          onWebResourceError: (error) {
            // Sub-resource failures (a CDN image, a public-data call) must not
            // replace the injection status: only report the main frame.
            if (error.isForMainFrame == false) return;
            setState(() => status = '웹 뷰 오류: ${error.description}');
          },
          onPageFinished: _inject,
        ),
      )
      ..loadRequest(targetUri);
  }

  void _receive(JavaScriptMessage message) {
    try {
      final result = jsonDecode(message.message) as Map<String, dynamic>;
      final unsupported = List<String>.from(
        result['unsupported'] as List? ?? const [],
      );
      final missing = List<String>.from(result['missing'] as List? ?? const []);
      final violations = List<String>.from(
        result['violations'] as List? ?? const [],
      );
      setState(() {
        status =
            '입력 ${result['applied'] ?? 0}건 · 검증 ${result['verified'] ?? 0}건';
        limitations = [...missing, ...violations, ...unsupported];
      });
    } catch (_) {
      setState(() => status = '입력 결과를 해석하지 못했습니다.');
    }
  }

  Future<void> _inject(String url) async {
    final current = Uri.tryParse(url);
    final target = Uri.parse(widget.platform.formUrl);
    if (current == null ||
        current.host != target.host ||
        _directory(current) != _directory(target) ||
        _lastInjectedUrl == current.toString()) {
      return;
    }
    _lastInjectedUrl = current.toString();
    setState(() => status = '${widget.platform.label} 미러에 입력하는 중…');
    final payload = jsonEncode(widget.values);
    try {
      // The bridge has to be in place before the adapter presses anything that
      // can open the address search.
      await controller.runJavaScript(
        postcodeBridgeScript(jsonEncode(widget.values['address'] ?? '')),
      );
      await controller.runJavaScript(
        widget.platform == ListingPlatform.zigbang
            ? zigbangInjectionScript(payload)
            : dabangInjectionScript(payload),
      );
    } catch (error) {
      if (mounted) setState(() => status = '자동 입력 JavaScript 오류: $error');
    }
  }

  Future<void> _handleBack(bool didPop, Object? result) async {
    if (didPop) return;
    try {
      // Back closes the Kakao address overlay first, exactly as it would close
      // a native picker, before it leaves the mirror.
      final closed = await controller.runJavaScriptReturningResult(
        "typeof window.__flrClosePostcode === 'function' && "
        "window.__flrClosePostcode()",
      );
      if (closed == true || closed.toString() == 'true') return;
    } catch (_) {
      // The page may be navigating; fall through to the Flutter route.
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: false,
    onPopInvokedWithResult: _handleBack,
    child: Scaffold(
      appBar: AppBar(title: Text('${widget.platform.label} 미러 입력')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(12),
            child: Text(status),
          ),
          if (limitations.isNotEmpty)
            ExpansionTile(
              initiallyExpanded: false,
              title: Text('직접 확인할 항목 ${limitations.length}개'),
              subtitle: const Text('사유 전체 보기'),
              children: limitations
                  .map(
                    (reason) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.info_outline),
                      title: SelectableText(reason),
                    ),
                  )
                  .toList(),
            ),
          Expanded(child: WebViewWidget(controller: controller)),
        ],
      ),
    ),
  );
}

String postcodeBridgeScript(String query) =>
    '''
(() => {
  const query = $query;
  // WKWebView 에는 팝업 창이 없다. 카카오 우편번호의 open() 은 window.open() 을 쓰는데,
  // webview_flutter 는 그 요청을 같은 웹뷰에 실어 버려서 미러 폼이 빈 화면으로 덮인다.
  // 그래서 daum.Postcode 를 감싸 두고, open() 이 오면 같은 인스턴스를 embed() 로
  // 이 페이지 안의 전체 화면 겹에 그린다. 미러가 넘긴 oncomplete 는 그대로 살아 있으므로
  // 주소를 고르면 미러의 원래 흐름(동/호 활성화 · 건축물대장 창 · lat 채움)이 그대로 돈다.
  if (window.__flrPostcode) { window.__flrPostcode.query = query || window.__flrPostcode.query; return; }
  const SRC = 'https://t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js';
  const bridge = window.__flrPostcode = {query: query || '', notes: [], open: false};
  window.daum = window.daum || {};
  let Real = Object.prototype.hasOwnProperty.call(window.daum, 'Postcode') ? window.daum.Postcode : null;
  let loading = null;

  const ensureReal = () => {
    if (Real) return Promise.resolve(Real);
    if (loading) return loading;
    loading = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = SRC;
      script.onload = () => Real ? resolve(Real) : reject(new Error('카카오 우편번호 스크립트가 Postcode 를 등록하지 않았습니다.'));
      script.onerror = () => reject(new Error('카카오 우편번호 스크립트를 내려받지 못했습니다.'));
      setTimeout(() => { if (!Real) reject(new Error('카카오 우편번호 스크립트 응답이 없습니다.')); }, 10000);
      document.head.appendChild(script);
    });
    return loading;
  };

  const closeOverlay = fromHistory => {
    const overlay = document.getElementById('flr-postcode-overlay');
    if (!overlay) return false;
    overlay.remove();
    document.documentElement.style.overflow = overlay.dataset.prevOverflow || '';
    bridge.open = false;
    if (!fromHistory && history.state && history.state.flrPostcode) history.back();
    return true;
  };
  bridge.close = () => closeOverlay(false);
  // Flutter 의 뒤로가기(PopScope)가 먼저 이 겹을 닫는다.
  window.__flrClosePostcode = () => closeOverlay(false);
  window.addEventListener('popstate', () => closeOverlay(true));

  const buildOverlay = () => {
    closeOverlay(true);
    const overlay = document.createElement('div');
    overlay.id = 'flr-postcode-overlay';
    overlay.dataset.prevOverflow = document.documentElement.style.overflow || '';
    overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#fff;display:flex;flex-direction:column;';
    const bar = document.createElement('div');
    bar.style.cssText = 'flex:none;display:flex;align-items:center;justify-content:space-between;' +
      'padding:calc(env(safe-area-inset-top) + 10px) 14px 10px;border-bottom:1px solid #e5e5e5;' +
      'background:#fff;font:600 16px/1.4 -apple-system,BlinkMacSystemFont,sans-serif;color:#222;';
    const title = document.createElement('span');
    title.textContent = '주소 검색';
    const close = document.createElement('button');
    close.type = 'button';
    close.textContent = '닫기';
    close.setAttribute('aria-label', '주소 검색 닫기');
    close.style.cssText = 'border:0;background:transparent;color:#326cf9;font:600 16px -apple-system,sans-serif;padding:8px 4px;';
    close.addEventListener('click', () => closeOverlay(false));
    const host = document.createElement('div');
    host.style.cssText = 'flex:1;min-height:0;width:100%;background:#fff;';
    bar.append(title, close);
    overlay.append(bar, host);
    document.body.appendChild(overlay);
    document.documentElement.style.overflow = 'hidden';
    history.pushState({flrPostcode: true}, '', location.href);
    bridge.open = true;
    return host;
  };

  const showFailure = (host, error) => {
    const reason = error && error.message ? error.message : String(error);
    host.innerHTML = '';
    const note = document.createElement('p');
    note.style.cssText = 'padding:24px;font:14px/1.7 -apple-system,sans-serif;color:#444;';
    note.textContent = '카카오 주소 검색 화면을 열지 못했습니다. ' + reason + ' 네트워크 상태를 확인한 뒤 「검색」을 다시 눌러 주세요.';
    host.appendChild(note);
    bridge.notes.push('주소 검색: ' + reason);
  };

  function Postcode(options) {
    const source = options || {};
    // 미러가 넘긴 oncomplete/onclose 는 그대로 부르고, 그 앞뒤로 겹만 정리한다.
    const wrapped = Object.assign({}, source, {
      width: '100%',
      height: '100%',
      oncomplete: value => {
        closeOverlay(false);
        if (typeof source.oncomplete === 'function') source.oncomplete(value);
      },
      onclose: state => {
        closeOverlay(true);
        if (typeof source.onclose === 'function') source.onclose(state);
      },
    });
    const self = this instanceof Postcode ? this : Object.create(Postcode.prototype);
    let inner = Real ? new Real(wrapped) : null;
    const draw = (host, extra) => {
      if (!inner) inner = new Real(wrapped);
      const params = Object.assign({autoClose: false}, extra || {});
      if (!params.q && bridge.query) params.q = bridge.query;
      inner.embed(host, params);
    };
    self.open = extra => {
      const host = buildOverlay();
      ensureReal().then(() => draw(host, extra)).catch(error => showFailure(host, error));
      return self;
    };
    self.embed = (element, extra) => {
      ensureReal().then(() => draw(element, extra))
        .catch(error => bridge.notes.push('주소 검색: ' + (error.message || String(error))));
      return self;
    };
    return self;
  }

  // 직방 미러는 페이지가 뜰 때 카카오 스크립트를 스스로 불러온다. 그 스크립트가 늦게
  // 도착해 daum.Postcode 에 대입해도 setter 가 받아서 원본만 갈아 끼우고, 미러가 보는
  // 값은 계속 이 래퍼다.
  Object.defineProperty(window.daum, 'Postcode', {
    configurable: true,
    enumerable: true,
    get: () => Postcode,
    set: value => { if (value !== Postcode) Real = value; },
  });
  ensureReal().catch(error => bridge.notes.push('주소 검색: ' + (error.message || String(error))));
})();
''';

String zigbangInjectionScript(String payload) =>
    '''

(async () => {
  const data = $payload;
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const output = {applied: 0, missing: [], unsupported: [], verified: 0, violations: []};
  // These names were read from the published mirror form. Never rely on its
  // generated Radix ids: they change on every page render.
  const names = {
    building: 'dongDetail.dong', unit: 'ho', exclusiveArea: 'sizeM2',
    residenceDescription: 'residence.residenceTypeDescription',
    floorAll: 'floorAll', floor: 'floor', approvalDate: 'approveDate',
    trade: 'sales.salesType', deposit: 'sales.deposit', monthlyRent: 'sales.rent',
    roomLayout: 'roomType', bathrooms: 'bathroomCnt',
    directionBase: 'directionCriterionType', direction: 'roomDirection',
    parkingCount: 'parkingAndHousehold.totalParkingCnt', elevator: 'isElevator',
    violation: 'nonCompliantBuilding', manageBasis: 'manageCostDetail.manageCostCriteria.manageCostCriteria',
    managementFee: 'manageCostDetail.basisDetail.avgManageCost',
    otherFeeReason: 'manageCostDetail.basisDetail.basis', title: 'title',
    description: 'description', privateMemo: 'secretMemo', moveInDate: 'moveInDate',
    moveInNegotiable: 'moveInDateExtra', ownerPhone: 'verification.lessorPhone'
  };
  const unavailable = {
    supplyArea: '공급면적: 직방 원룸 폼에 입력란이 없습니다.',
    salePrice: '매매 금액: 직방 원룸 폼은 매매를 지원하지 않습니다.',
    floorPrivate: '층수 비공개: 직방 원룸 폼은 실제 층수만 지원합니다.',
    buildingUse: '건축물 용도: 직방 원룸 폼은 건축물대장 연동으로만 처리하며 법정 용도 선택란이 없습니다.',
    parkingPerHousehold: '세대당 주차 대수: 직방은 총 주차대수만 지원합니다.',
    heating: '난방 방식: 직방 원룸 폼에 입력란이 없습니다.',
    lh: 'LH 전세임대 여부: 직방 원룸 폼에 입력란이 없습니다.',
    rooms: '방 개수: 직방 원룸 폼은 방 구조로 방 수를 정하며 별도 방 개수 입력란이 없습니다.',
    unknownFeeReason: '확인 불가 법정 사유: 직방 원룸 미러의 관리비 방식에는 확인 불가 분기가 없습니다.',
    photoCount: '사진: WebView JavaScript는 기기 파일을 file input에 할당할 수 없습니다. 사용자가 직방 미러의 파일 선택기로 5~20장을 직접 선택해야 합니다.'
  };
  const esc = s => (window.CSS && CSS.escape) ? CSS.escape(String(s)) : String(s).replace(/[^a-zA-Z0-9_-]/g, '\\\\\$&');
  const find = name => document.querySelector('[name="' + esc(name) + '"], #' + esc(name) + ', [data-flr-key="' + esc(name) + '"]');
  const strict = window.FLR && window.FLR.strict;
  const strictSet = strict && typeof strict.setValue === 'function' ? strict.setValue.bind(strict) : null;
  const strictClick = strict && typeof strict.click === 'function' ? strict.click.bind(strict) : null;
  const press = el => {
    if (!el) return false;
    if (strictClick) { strictClick(el); return true; }
    el.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true}));
    el.dispatchEvent(new MouseEvent('mousedown', {bubbles: true}));
    el.dispatchEvent(new PointerEvent('pointerup', {bubbles: true}));
    el.dispatchEvent(new MouseEvent('mouseup', {bubbles: true}));
    el.dispatchEvent(new MouseEvent('click', {bubbles: true}));
    el.click();
    return true;
  };
  const setValue = (el, value) => {
    if (!el) return false;
    if (strictSet) strictSet(el, String(value));
    const setter = Object.getOwnPropertyDescriptor(el.tagName === 'SELECT' ? HTMLSelectElement.prototype : el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype, 'value')?.set;
    if (!strictSet) { if (setter) setter.call(el, String(value)); else el.value = String(value); }
    ['input', 'change', 'blur'].forEach(type => el.dispatchEvent(new Event(type, {bubbles: true})));
    return true;
  };
  const normalize = value => String(value ?? '').replace(/[ \\t\\r\\n]+/g, '').replace(/향\$/, '').replace(/층\$/, '').replace(/개\$/, '');
  const exactly = (actual, wanted) => normalize(actual) === normalize(wanted);
  const matches = (actual, wanted) => {
    const a = normalize(actual), b = normalize(wanted);
    return exactly(actual, wanted) || a.includes(b) || b.includes(a);
  };
  const waitFor = async (predicate, timeout = 1800) => {
    const until = Date.now() + timeout;
    while (Date.now() < until) {
      const result = predicate();
      if (result) return result;
      await sleep(50);
    }
    return null;
  };
  const selectedButton = el => el?.getAttribute('aria-checked') === 'true' || el?.getAttribute('aria-pressed') === 'true' || (el?.classList?.contains('text-orange-500') && el?.classList?.contains('border-orange-500'));
  const clickCandidate = async el => {
    if (el) {
      press(el);
      ['input','change'].forEach(type => el.dispatchEvent(new Event(type, {bubbles:true})));
      return !!await waitFor(() => selectedButton(el));
    }
    return false;
  };
  const clickText = async (name, value) => {
    // Most radio-like groups repeat the same name on every button.  Prefer
    // that exact target over a nearby label: the latter can accidentally be a
    // hidden select belonging to the next field.
    const named = [...document.querySelectorAll('button[name], [role="radio"][name]')]
        .find(n => n.getAttribute('name') === name && matches(n.textContent.trim(), value));
    if (named) return clickCandidate(named);
    const anchor = find(name);
    const scope = anchor?.parentElement?.parentElement || anchor?.parentElement || document;
    return clickCandidate([...scope.querySelectorAll('label,button,[role="radio"],[role="option"]')]
        .find(n => matches(n.textContent.trim(), value)));
  };
  const clickLabel = async (labelText, value) => {
    const label = [...document.querySelectorAll('label')]
        .find(n => matches(n.textContent.trim().replace('*', ''), labelText));
    let scope = label?.parentElement;
    while (scope && scope !== document.body) {
      const candidate = [...scope.querySelectorAll('button')]
          .find(n => matches(n.textContent.trim(), value));
      if (candidate) return clickCandidate(candidate);
      scope = scope.parentElement;
    }
    return false;
  };
  // A Radix Select is a visible trigger plus a hidden native select.  Setting
  // that native select alone does not call React/Radix's onValueChange.  Open
  // the trigger, then click the rendered option, and read both representations
  // back before reporting success.  This also honours the mirror's strict
  // pointerdown/click ordering and delayed reactions.
  const choose = async (name, value) => {
    const el = find(name);
    if (!el) return false;
    if (el.tagName === 'SELECT') {
      const options = [...el.options];
      const option = options.find(o => exactly(o.textContent.trim(), value) || exactly(o.value, value)) ||
          options.find(o => matches(o.textContent.trim(), value) || matches(o.value, value));
      if (!option) return false;
      const trigger = el.previousElementSibling?.getAttribute('role') === 'combobox'
          ? el.previousElementSibling
          : el.parentElement?.querySelector('[role="combobox"]');
      if (!trigger || trigger.disabled) return false;
      press(trigger);
      const list = await waitFor(() => document.querySelector('[data-mirror="listbox"], [role="listbox"]'));
      if (!list) return false;
      const renderedOptions = [...list.querySelectorAll('[role="option"]')];
      const rendered = renderedOptions.find(item => exactly(item.textContent.trim(), option.textContent.trim())) ||
          renderedOptions.find(item => matches(item.textContent.trim(), option.textContent.trim()));
      if (!rendered) return false;
      press(rendered);
      return !!await waitFor(() =>
        el.value === option.value &&
        matches(trigger.textContent.trim(), option.textContent.trim()) &&
        trigger.getAttribute('aria-expanded') !== 'true',
      );
    }
    return clickText(name, value);
  };
  const check = async (id, wanted) => {
    const el = document.getElementById(id);
    if (!el) return false;
    const checked = el.getAttribute('aria-checked') === 'true';
    if (checked !== wanted) press(el);
    return !!await waitFor(() => (el.getAttribute('aria-checked') === 'true') === wanted);
  };
  // 이 어댑터의 clickText·choose·check 는 미러가 선택 상태를 돌려줄 때까지 기다린 뒤에만
  // true 를 준다. 그래서 「입력됨」은 곧 「확인됨」이다.
  const mark = (key, ok) => {
    if (ok) { output.applied++; output.verified++; }
    else output.missing.push(key + ': 미러의 대상 DOM을 찾거나 선택하지 못했습니다.');
  };
  const note = message => { if (!output.unsupported.includes(message)) output.unsupported.push(message); };
  const publish = () => window.ListingResult.postMessage(JSON.stringify(output));
  const labelled = word => [...document.querySelectorAll('main label')]
      .find(label => label.textContent.trim().replace('*', '') === word);
  try {
    if (typeof strict === 'function') {
      const strictResult = await strict(data);
      Object.assign(output, strictResult || {});
      window.ListingResult.postMessage(JSON.stringify(output)); return;
    }
    if (strict && typeof strict !== 'function' && !strictSet && !strictClick) output.violations.push('FLR.strict에 호출 가능한 helper가 없어 DOM 대체 입력을 사용했습니다.');
    for (const [key, reason] of Object.entries(unavailable)) if (data[key] !== undefined && data[key] !== '') output.unsupported.push(reason);
    const input = (key, value, transform = v => v) => {
      if (value === undefined || value === null || value === '') return;
      const el = find(names[key]);
      if (!el) return mark(key, false);
      const wanted = String(transform(value));
      setValue(el, wanted);
      if (String(el.value) === wanted) return mark(key, true);
      output.applied++;
      output.missing.push(key + ': 값을 넣었지만 폼에서 같은 값을 다시 읽지 못했습니다.');
    };
    const choice = (key, value, transform = v => v) => { if (value === undefined || value === null || value === '') return; mark(key, choose(names[key], transform(value))); };
    // The mirror exposes only 단독주택 and an explicit free-text escape hatch.
    // Keep the source classification by choosing that documented escape hatch
    // instead of pretending that a one-room/villa category was selected.
    const residenceChoice = data.propertyType === '단독주택'
        ? '단독주택' : '그 외(직접 입력)';
    mark('propertyType', await clickText('residence.residenceType', residenceChoice));
    if (residenceChoice === '그 외(직접 입력)') {
      await sleep(350);
      input('residenceDescription', data.propertyType);
    }
    input('building', data.building); mark('singleBuilding', await check('haveNoDong', data.singleBuilding === true)); input('unit', data.unit);
    const targetFloor = data.floor === '옥탑' ? '옥탑방' : /^\\d+\$/.test(String(data.floor)) ? data.floor + '층' : data.floor;
    input('exclusiveArea', data.exclusiveArea); mark('floorAll', await choose(names.floorAll, data.floorAll));
    // The mirror rebuilds the floor options after the delayed whole-floor
    // selection.  Retry only after the rebuilt native select is observable.
    await sleep(650);
    let floorOk = await choose(names.floor, targetFloor);
    if (!floorOk) { await sleep(450); floorOk = await choose(names.floor, targetFloor); }
    mark('floor', floorOk);
    input('approvalDate', data.approvalDate); mark('trade', await clickText('sales.salesType', data.trade)); await sleep(400); if (data.trade === '월세' || data.trade === '전세') input('deposit', data.deposit); if (data.trade === '월세') input('monthlyRent', data.monthlyRent);
    mark('shortTerm', await check('isShortTerm', data.shortTerm === true));
    if (data.loan === '없음') mark('loan', await clickText('noLoan', '융자금 없음'));
    else if (data.loan === '30%이하' || data.loan === '융자금 30%이하') mark('loan', await clickText('loanUnder30', '융자금 30%이하'));
    else if (data.loan !== undefined && data.loan !== null && data.loan !== '') output.unsupported.push('융자금 ' + data.loan + ': 직방 원룸 미러는 융자금 없음 또는 30% 이하만 선택할 수 있어 임의 금액을 자동 변환하지 않았습니다.');
    mark('noManagementFee', await check('no-manage-cost', data.noManagementFee === true));
    if (data.noManagementFee !== true) { mark('manageMethod', await clickLabel('관리비 부과 방식', data.manageMethod === '기타 부과' ? '기타' : data.manageMethod)); await sleep(400); }
    if (data.manageMethod === '정액 관리비' && data.noManagementFee !== true) { mark('manageBasis', await choose(names.manageBasis, ({'3개월 평균 관리비':'최근 3개월 관리비 평균','1년 평균 관리비':'최근 1년 관리비 평균','기타 직접 입력':'직접 입력'})[data.manageBasis] || data.manageBasis)); input('managementFee', data.managementFee, v => String(Number(v) * 10000)); }
    const feeNames = {'인터넷':'인터넷 사용료','유선TV':'TV 사용료','청소비':'일반(공용) 관리비','수도료':'수도료','가스사용료':'가스 사용료','전기료':'전기료','난방비':'난방비'};
    for (const fee of (data.manageIncludes || [])) { if (feeNames[fee]) mark('manageIncludes.' + fee, await clickText('manageCostDetail.detailIncludes', feeNames[fee])); else output.unsupported.push('관리비 포함 항목 ' + fee + ': 직방 원룸 폼에 대응 항목이 없습니다.'); }
    if (data.manageMethod === '기타 부과') mark('otherFeeReason', await choose(names.otherFeeReason, ({
      '면적 및 세대별 부과':'공용관리비는 면적/세대별로 부과하고, 사용료는 사용량에 따른 부과',
      '전체 세대 균등 부과':'전체 사용량을 세대수로 나누어 부과',
      '계량기별 실비 부과':'세대별 사용량(별도 계량기)에 따라 부과',
      '의뢰인 미고지':'중개 의뢰인이 관리비 세부내역 미제시로 관리비 추정 금액 입력',
      '기타':'직접 입력',
    })[data.otherFeeReason] || data.otherFeeReason));
    // 「관리비 실비 부과 세부 내역」은 정액 관리비에서도 필수(*)다. 총액이 10만원 미만인
    // 것은 입력한 금액에서 그대로 따라오므로 그때만 자동으로 고른다.
    if (data.manageMethod === '정액 관리비' && data.noManagementFee !== true) {
      const total = Number(data.managementFee);
      if (!Number.isNaN(total) && total < 10) mark('basisDetail', await choose(names.otherFeeReason, '관리비 월 10만원 미만'));
      else note('관리비 실비 부과 세부 내역: 정액 관리비 10만원 이상은 직방이 부과 근거를 따로 고르게 하는데 통합 폼에 대응하는 값이 없어 화면에서 직접 골라 주셔야 합니다.');
    }
    if (data.manageMethod === '정액 관리비' && data.manageDetail) {
      const detailKeys = {
        electricity: '전기료', water: '수도료', gas: '가스사용료',
        heating: '난방비', internet: '인터넷', tv: '유선TV',
        normalManageCost: '청소비', etcManageCost: '기타'
      };
      for (const el of document.querySelectorAll('select[name\$=".type"]')) {
        const source = Object.keys(detailKeys).find(key => el.name.includes(key));
        if (!source) continue;
        const masterValue = data.manageDetail[detailKeys[source]];
        if (!masterValue) {
          output.unsupported.push('관리비 세부 ' + detailKeys[source] + ': 통합 폼 값이 없어 미러에 입력하지 않았습니다.');
          continue;
        }
        mark('manageDetail.' + detailKeys[source], await choose(el.name, masterValue));
      }
      // 「정액」으로 고른 비목은 금액 칸이 켜지고 필수가 된다 — 통합 폼에는 비목별 금액이 없다.
      const pending = [...document.querySelectorAll('main input[placeholder*="금액"]')]
          .filter(el => !el.disabled && !el.value).length;
      if (pending) note('비목별 정액 금액 ' + pending + '칸: 직방은 「정액」으로 고른 비목마다 금액을 따로 요구하지만 통합 폼은 총액만 받아 비워 두었습니다.');
    }
    mark('roomLayout', await choose(names.roomLayout, ({'오픈형 원룸':'오픈형 원룸 (방1)','분리형 원룸':'분리형 원룸 (방1,거실1)','복층형 원룸':'복층형 원룸'})[data.roomLayout] || data.roomLayout));
    mark('bathrooms', await choose(names.bathrooms, String(data.bathrooms).replace(' 이상', '개'))); mark('directionBase', await clickText('directionCriterionType', data.directionBase === '주실 기준' ? '거실 기준' : data.directionBase)); mark('direction', await choose(names.direction, data.direction));
    mark('parking', await check('no-parking', data.parking === '주차 불가능')); if (data.parking === '주차 가능') input('parkingCount', data.parkingCount);
    mark('elevator', await clickText('isElevator', data.elevator)); mark('violation', await clickText('nonCompliantBuilding', data.violation === '해당 없음' ? '해당없음' : '해당'));
    mark('loanAvailable', await check('itemConditions.loanLease', data.loanAvailable === '가능')); mark('petAllowed', await check('itemConditions.pet', data.petAllowed === '가능'));
    const optionLabel = [...document.querySelectorAll('label')].find(label => label.textContent.trim() === '옵션');
    const optionScope = optionLabel?.parentElement?.parentElement || document;
    for (const option of (data.appliances || [])) { const button = [...optionScope.querySelectorAll('button')].find(b => b.textContent.trim() === option); if (button) { press(button); if (await waitFor(() => selectedButton(button))) { output.applied++; output.verified++; } else output.missing.push('appliances.' + option + ': 미러에서 선택 상태를 확인하지 못했습니다.'); } else output.unsupported.push('가전·가구 옵션 ' + option + ': 직방 원룸 미러에 대응 옵션이 없습니다.'); }
    const conditionIds = {'CCTV':'itemConditions.cctv','테라스':'itemConditions.terrace','전기차 충전시설':'itemConditions.evStation'}; for (const item of (data.facilities || [])) { if (conditionIds[item]) { if (await check(conditionIds[item], true)) { output.applied++; output.verified++; } else output.missing.push('facilities.' + item + ': 미러에서 선택 상태를 확인하지 못했습니다.'); } else output.unsupported.push('보안 및 시설 옵션 ' + item + ': 직방 원룸 미러에 대응 옵션이 없습니다.'); }
    if (data.moveInType === '즉시 입주') mark('moveInType', await check('moveInImmediately', true)); else if (data.moveInType === '날짜 지정') { mark('moveInType', await check('moveInImmediately', false)); input('moveInDate', data.moveInDate); } else output.unsupported.push('입주 방식 협의 가능: 직방 원룸 미러는 즉시 입주 또는 날짜 선택만 지원합니다.');
    if (data.moveInNegotiable === true) input('moveInNegotiable', '협의 가능');
    input('title', data.title); input('description', data.description); input('privateMemo', data.privateMemo); input('ownerPhone', data.ownerPhone);
    for (const message of (window.__flrPostcode ? window.__flrPostcode.notes : [])) note(message);

    // 주소 — 직방 미러는 주소 칸을 누르면 카카오 우편번호 창을 띄운다. 브리지가 그 창을
    // 웹뷰 안 전체 화면 겹으로 바꿔 놓았으므로, 여기서 눌러 주면 사용자가 결과만 고르면 된다.
    // 고르고 나면 미러가 「소재지 공개 확인」 창을 띄운다 — 매물 대분류로 답이 정해진다.
    if (data.address) {
      if (window.__flrPostcode) window.__flrPostcode.query = data.address;
      const lat = find('lat');
      if (!lat) mark('address', false);
      else {
        if (!window.__flrZigbangAddressWatch) {
          const multiUnit = data.propertyType === '다가구주택' ? '예' : '아니요';
          window.__flrZigbangAddressWatch = new MutationObserver(() => {
            const dialog = [...document.querySelectorAll('[data-mirror="modal"] [role="dialog"]')]
                .find(box => box.textContent.includes('소재지 공개 확인'));
            if (!dialog) return;
            const answer = [...dialog.querySelectorAll('button')]
                .find(button => button.textContent.trim() === multiUnit);
            if (!answer) return;
            press(answer);
            const index = output.unsupported.findIndex(message => message.startsWith('매물 기본 주소:'));
            if (index >= 0) output.unsupported.splice(index, 1);
            note('소재지 공개 확인: 매물 대분류가 ' + data.propertyType + '이므로 「' + multiUnit + '」로 답했습니다.');
            if (String(lat.value) !== '') { output.applied++; output.verified++; }
            publish();
          });
          window.__flrZigbangAddressWatch.observe(document.body, {subtree: true, childList: true});
        }
        note('매물 기본 주소: 검색어를 넣고 카카오 주소 검색 화면을 띄웠습니다. 결과를 고르면 직방 주소 칸이 채워집니다.');
        press(lat);
      }
    }
    for (const violation of (window.__FLR_VIOLATIONS__ || [])) {
      const detail = typeof violation === 'string' ? violation : [violation.kind, violation.target, violation.detail].filter(Boolean).join(': ');
      output.violations.push('깐깐이 위반: ' + detail);
    }
  } catch (error) { output.violations.push('자동 입력 오류: ' + String(error)); }
  window.ListingResult.postMessage(JSON.stringify(output));
})();
''';

String dabangInjectionScript(String payload) =>
    '''
(async () => {
  const data = $payload;
  const output = {applied: 0, missing: [], unsupported: [], verified: 0, violations: []};
  const publish = () => window.ListingResult.postMessage(JSON.stringify(output));
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  // 깐깐이(mirror 의 엄격 층)는 click/input/change 를 삼켰다가 0.3초 뒤에 다시 쏜다.
  // 그래서 조작 하나하나의 반응을 기다려야 한다.
  const REACT = 420;
  const text = el => el ? (el.textContent || '').replace(/\\s+/g, ' ').trim() : '';
  const norm = value => String(value === undefined || value === null ? '' : value).replace(/\\s+/g, '');
  const filled = value => value !== undefined && value !== null && value !== '' &&
    !(Array.isArray(value) && value.length === 0);
  const note = message => { if (!output.unsupported.includes(message)) output.unsupported.push(message); };
  const miss = (key, why) => output.missing.push(key + ': ' + why);
  const ok = () => { output.applied++; output.verified++; };
  const waitUntil = async (predicate, timeout = 2600) => {
    const until = Date.now() + timeout;
    for (;;) {
      const value = predicate();
      if (value) return value;
      if (Date.now() >= until) return null;
      await sleep(60);
    }
  };

  /* ── 자리 찾기 ──────────────────────────────────────────────
   * 다방 표는 한 <tr> 안에 (th, td) 쌍이 여럿 들어간다 — 「욕실 수」 옆에 「엘리베이터」,
   * 「복층 여부」 옆에 「현관 유형」이 같은 줄에 있다. 줄 전체를 훑으면 옆 항목의 컨트롤을
   * 잘못 건드리므로, th 바로 뒤의 td 만 본다. td 안의 하위 묶음은 <header><h1>로 갈린다. */
  const cellOf = (section, label) => {
    const root = document.getElementById(section);
    if (!root) return null;
    for (const th of root.querySelectorAll('th')) {
      if (!norm(text(th)).includes(norm(label))) continue;
      let node = th.nextElementSibling;
      while (node && node.tagName !== 'TD') node = node.nextElementSibling;
      return node;
    }
    return null;
  };
  const rowOf = (section, label) => {
    const root = document.getElementById(section);
    if (!root) return null;
    for (const tr of root.querySelectorAll('tr')) {
      const head = tr.querySelector('th h1');
      if (head && norm(text(head)).replace('*', '') === norm(label)) return tr;
    }
    return null;
  };
  const groupOf = (cell, heading) => {
    if (!cell) return null;
    for (const header of cell.querySelectorAll('header')) {
      if (norm(text(header)) === norm(heading)) return header.parentElement;
    }
    return null;
  };
  const labelInput = (scope, wanted) => {
    if (!scope) return null;
    for (const label of scope.querySelectorAll('label')) {
      if (norm(text(label)) === norm(wanted)) return label.querySelector('input');
    }
    for (const label of scope.querySelectorAll('label')) {
      if (norm(text(label)).includes(norm(wanted))) return label.querySelector('input');
    }
    return null;
  };

  /* ── 조작 ───────────────────────────────────────────────────
   * 깐깐이는 ① el.value = v 로 넣은 값을 「폼이 모르는 대입」으로 되돌리고
   * ② 앞에 pointerdown 이 없는 로봇 click 을 버린다. 둘 다 피해서 넣는다. */
  const valueSetter = el => Object.getOwnPropertyDescriptor(
    el.tagName === 'SELECT' ? HTMLSelectElement.prototype :
    el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype,
    'value').set;
  const setNative = (el, value) => {
    if (!el) return false;
    el.focus && el.focus();
    valueSetter(el).call(el, String(value));
    ['input', 'change'].forEach(type => el.dispatchEvent(new Event(type, {bubbles: true})));
    el.blur && el.blur();
    return true;
  };
  const press = el => {
    if (!el) return false;
    const init = {bubbles: true, cancelable: true, composed: true, view: window};
    el.dispatchEvent(new PointerEvent('pointerdown', init));
    el.dispatchEvent(new MouseEvent('mousedown', init));
    el.dispatchEvent(new MouseEvent('mouseup', init));
    el.dispatchEvent(new MouseEvent('click', init));
    return true;
  };

  // 미러는 반응할 때마다 <tr> 을 틀에서 새로 만들어 통째로 갈아 끼운다(setRow).
  // 그래서 붙잡아 둔 노드는 곧 화면 밖의 유령이 된다 — 자리는 늘 함수로 다시 찾는다.
  const at = target => { try { return typeof target === 'function' ? target() : target; } catch (_) { return null; } };
  const ready = (locate, timeout) => waitUntil(() => {
    const el = at(locate);
    return el && !el.disabled ? el : null;
  }, timeout);

  const fill = (key, locate, value, transform = v => v) => {
    if (!filled(value)) return false;
    const el = at(locate);
    if (!el) { miss(key, '다방 폼에서 입력란을 찾지 못했습니다.'); return false; }
    if (el.disabled) { miss(key, '입력란이 잠겨 있어 값을 넣지 못했습니다.'); return false; }
    const wanted = String(transform(value));
    setNative(el, wanted);
    const again = at(locate) || el;
    if (String(again.value) === wanted) { ok(); return true; }
    output.applied++;
    miss(key, '값을 넣었지만 폼에서 같은 값을 다시 읽지 못했습니다.');
    return false;
  };

  const pickOption = (el, wanted) => {
    const target = norm(wanted);
    if (!target) return null;
    const options = [...el.options].filter(option => option.value !== '');
    return options.find(option => norm(text(option)) === target)
      || options.find(option => norm(option.value) === target)
      || options.find(option => norm(text(option)).includes(target))
      || options.find(option => target.includes(norm(text(option))));
  };
  const select = async (key, locate, wanted, timeout = 2600) => {
    if (!filled(wanted)) return false;
    if (!at(locate)) { miss(key, '다방 폼에서 선택란을 찾지 못했습니다.'); return false; }
    const el = await ready(locate, timeout);
    if (!el) { miss(key, '선택란이 아직 잠겨 있어 고르지 못했습니다.'); return false; }
    const option = pickOption(el, wanted);
    if (!option) { note(key + ' ' + wanted + ': 다방 폼의 선택지에 대응하는 항목이 없습니다.'); return false; }
    const value = option.value;
    setNative(el, value);
    if (await waitUntil(() => { const now = at(locate); return now && now.value === value; }, 1200)) {
      ok(); await sleep(REACT); return true;
    }
    output.applied++;
    miss(key, '고른 뒤 폼에서 같은 값을 다시 읽지 못했습니다.');
    return false;
  };

  // 라디오·체크박스는 label 이 아니라 그 안의 input 을 눌러야 미러의 그룹 처리가
  // 어느 것을 눌렀는지 알아본다(미러는 window 캡처에서 e.target 을 본다).
  const toggle = async (key, locate, wanted, label) => {
    const el = await ready(locate, 3000);
    if (!el) {
      miss(key, at(locate) ? (label || '선택지') + '이(가) 아직 잠겨 있어 고르지 못했습니다.'
        : '다방 폼에서 ' + (label || '선택지') + '을(를) 찾지 못했습니다.');
      return false;
    }
    if (el.checked === wanted) { ok(); return true; }
    press(el);
    if (await waitUntil(() => { const now = at(locate); return now && now.checked === wanted; }, 2000)) {
      ok(); await sleep(REACT); return true;
    }
    output.applied++;
    miss(key, (label || '선택지') + '을(를) 눌렀지만 선택 상태가 바뀌지 않았습니다.');
    return false;
  };
  const choose = async (key, scope, wanted, mapped) => {
    if (!filled(wanted)) return false;
    const target = mapped === undefined ? wanted : mapped;
    if (target === null) return false;
    return toggle(key, () => labelInput(at(scope), target), true, target);
  };

  const modal = title => {
    const box = document.getElementById('modal-container');
    return box && norm(text(box)).includes(norm(title)) ? box : null;
  };
  const modalButton = (box, wanted) =>
    [...box.querySelectorAll('button')].find(button => norm(text(button)) === norm(wanted));

  /* ── 주소 ───────────────────────────────────────────────────
   * 「검색」은 카카오 우편번호 화면을 띄운다(브리지가 웹뷰 안 전체 화면 겹으로 그린다).
   * 결과를 고르면 미러가 도로명·지번을 채우고 동/호 칸을 켜고 건축물대장 창을 띄운다.
   * 그 순간을 관찰해 동/호를 자동으로 넣고, 대장 창은 「직접 입력」으로 닫는다 —
   * 대장 조회는 이미 넣은 면적·용도·승인일을 공공데이터 값으로 덮어쓰기 때문이다. */
  const addressCell = () => cellOf('room_info', '매물 주소');
  const afterAddressPicked = () => {
    const cell = addressCell();
    if (!cell) return;
    const ledger = modal('건축물대장');
    if (ledger) {
      const keep = modalButton(ledger, '아니요, 직접 입력할게요') || modalButton(ledger, '닫기');
      if (keep) {
        press(keep);
        note('건축물대장 자동 조회: 이미 입력한 면적·용도·승인일이 공공데이터 값으로 덮어써지지 않도록 「직접 입력」으로 닫았습니다.');
      }
    }
    const dong = cell.querySelector('input[name="dong"]');
    const ho = cell.querySelector('input[name="ho"]');
    if (!dong || !ho || dong.disabled || ho.disabled) return;
    const picked = [...cell.querySelectorAll('[class*=AddressList] li')].map(li => norm(text(li))).join('|');
    if (!picked) return;
    if (window.__flrDabangAddress === picked) return;
    window.__flrDabangAddress = picked;
    for (const bucket of [output.missing, output.unsupported]) {
      for (let i = bucket.length - 1; i >= 0; i--) {
        if (/^(매물 기본 주소|동 정보|호수 정보):/.test(bucket[i])) bucket.splice(i, 1);
      }
    }
    fill('building', dong, data.building);
    fill('unit', ho, data.unit);
    output.applied++;
    output.verified++;
    publish();
  };
  const watchAddress = () => {
    if (window.__flrDabangAddressWatch) return;
    window.__flrDabangAddressWatch = new MutationObserver(() => afterAddressPicked());
    window.__flrDabangAddressWatch.observe(document.body, {
      subtree: true, childList: true, attributes: true, attributeFilter: ['disabled'],
    });
  };

  /* ── 월 관리비 상세입력 창 ─────────────────────────────────── */
  const FEE_INCLUDES = {
    '청소비': '공용 관리비', '승강기유지비': '공용 관리비', '주차비': '공용 관리비', '경비비': '공용 관리비',
    '전기료': '전기', '수도료': '수도', '가스사용료': '가스', '난방비': '난방',
    '인터넷': '인터넷', '유선TV': 'TV', '기타': '기타 관리비',
  };
  const completeFeeModal = async () => {
    const box = await waitUntil(() => modal('월 관리비 상세입력'));
    if (!box) { miss('managementFee', '「관리비 있음」 뒤에 상세입력 창이 열리지 않았습니다.'); return; }
    const method = data.manageMethod === '기타 부과' ? '기타부과'
      : data.manageMethod === '확인 불가' ? '확인불가' : '정액관리비';
    const tab = modalButton(box, method);
    if (tab) { press(tab); await sleep(REACT + 200); } else miss('manageMethod', '상세입력 창에서 「' + method + '」 탭을 찾지 못했습니다.');

    if (method !== '확인불가') {
      const total = Number(data.managementFee);
      if (!filled(data.managementFee) || Number.isNaN(total)) {
        // 다방은 정액·기타 어느 쪽이든 총액이 있어야 「확인」이 켜진다.
        note('관리비 총액: 다방 상세입력 창은 부과 방식과 상관없이 총액을 요구하지만 통합 폼에 금액이 없어 창을 저장하지 않았습니다.');
        const close = modalButton(box, '닫기');
        if (close) press(close);
        return;
      }
      fill('managementFee', () => box.querySelector('input[name="detailCost"]'), data.managementFee, v => String(Number(v) * 10000));
      await sleep(REACT);
      if (method === '정액관리비') {
        // 10만원 미만/이상은 입력한 총액에서 그대로 따라온다.
        await choose('managementFee.threshold', () => box, total >= 10 ? '10만원 이상' : '10만원 미만');
        const basis = {
          '직전월 관리비 기준': '직전 월 관리비',
          '3개월 평균 관리비': '최근 3개월 관리비 평균',
          '1년 평균 관리비': '최근 1년 관리비 평균',
          '기타 직접 입력': '기타',
        }[data.manageBasis];
        if (basis) await choose('manageBasis', () => box, basis);
        else if (filled(data.manageBasis)) note('관리비 부과 기준 ' + data.manageBasis + ': 다방 상세입력 창에 대응하는 기준이 없습니다.');
      }
      if (method === '기타부과' && filled(data.otherFeeReason)) {
        await select('otherFeeReason', () => box.querySelector('[data-mirror-group="feeKind"] select'), {
          '관리규약에 따라 부과': '관리규약 등에 따라 부과',
          '면적 및 세대별 부과': '공용 관리비는 면적/세대별로 부과하고 사용료는 사용량에 따른 부과',
          '전체 세대 균등 부과': '전체 사용량을 세대수로 나누어 부과',
          '계량기별 실비 부과': '세대별 사용량(별도 계량기)에 따라 부과',
          '의뢰인 미고지': '정액관리비이지만 중개의뢰인이 세부내역 미고지한 경우',
          '기타': '기타',
        }[data.otherFeeReason] || data.otherFeeReason);
      }
      const seen = new Set();
      for (const item of (data.manageIncludes || [])) {
        const target = FEE_INCLUDES[item];
        if (!target) { note('관리비 포함 항목 ' + item + ': 다방 상세입력 창에 대응 항목이 없습니다.'); continue; }
        if (seen.has(target)) continue;
        seen.add(target);
        await choose('manageIncludes.' + item, () => box, target);
      }
    }

    const confirm = await waitUntil(() => {
      const button = modalButton(box, '확인');
      return button && !button.disabled ? button : null;
    });
    if (!confirm) {
      miss('managementFee', '상세입력 값을 넣었지만 「확인」이 켜지지 않았습니다. 창을 열어 둔 채 두었으니 직접 확인해 주세요.');
      return;
    }
    press(confirm);
    if (await waitUntil(() => !modal('월 관리비 상세입력'))) ok();
    else miss('managementFee', '「확인」을 눌렀지만 상세입력 창이 닫히지 않았습니다.');
  };

  /* ── 매물유형 ──────────────────────────────────────────────── */
  const PROPERTY = {
    '오픈형 원룸': ['주택', '빌라/연립/다세대'], '분리형 원룸': ['주택', '빌라/연립/다세대'],
    '복층형 원룸': ['주택', '빌라/연립/다세대'], '투룸 빌라': ['주택', '빌라/연립/다세대'],
    '쓰리룸 이상 빌라': ['주택', '빌라/연립/다세대'], '단독주택': ['주택', '단독주택'],
    '다가구주택': ['주택', '다가구주택'], '상가주택': ['주택', '상가주택'],
    '오피스텔 원룸형': ['오피스텔', null], '오피스텔 분리/투룸형': ['오피스텔', null],
    '아파트': ['아파트', null],
  };
  const applyPropertyType = async () => {
    const mapping = PROPERTY[data.propertyType];
    if (!mapping) {
      note('매물 대분류 ' + data.propertyType + ': 다방 주거용 매물 등록 폼에 대응하는 유형이 없습니다.');
      return false;
    }
    const [major, minor] = mapping;
    // 대분류는 소분류 라디오(주택/빌라)나 단지 검색 칸(오피스텔·아파트)의 유무로 알아본다.
    const isHouse = () => !!document.querySelector('#room_info input[name="buildingType"]');
    if (major === '주택' ? !isHouse() : isHouse()) {
      const button = [...(rowOf('room_info', '매물유형') || document).querySelectorAll('button')]
        .find(item => norm(text(item)).startsWith(norm(major)));
      if (!button) { miss('propertyType', '대분류 「' + major + '」 버튼을 찾지 못했습니다.'); return false; }
      press(button);
      // 대분류를 바꾸면 매물 정보·추가 정보의 7개 행이 통째로 다시 그려진다.
      await waitUntil(() => (major === '주택') === isHouse(), 3000);
      await sleep(REACT);
    }
    if (!minor) {
      ok();
      note('매물 주소(' + major + '): 다방은 이 대분류에서 시/도 → 시/군/구 → 동 → 단지 순으로 고르는 단지 검색만 지원해 자동으로 확정할 수 없습니다. 화면에서 직접 골라 주세요.');
      return true;
    }
    // 소분류 라디오는 매물유형 행의 두 번째 칸에 있다.
    return choose('propertyType', () => rowOf('room_info', '매물유형'), minor);
  };

  try {
    if (window.__flrPostcode) window.__flrPostcode.query = data.address || '';
    watchAddress();

    // ① 매물유형 — 대분류를 바꾸면 매물 정보 7행이 통째로 다시 그려지므로 가장 먼저.
    await applyPropertyType();

    // ② 주소 — 검색어만 미리 넣고, 결과 선택은 마지막에 띄우는 카카오 화면에서 받는다.
    const keyword = addressCell() && addressCell().querySelector('input[name="keyword"]');
    if (filled(data.address) && keyword) {
      setNative(keyword, data.address);
      if (keyword.value === String(data.address)) output.applied++;
    }
    afterAddressPicked();

    // ③ 면적 — 평/㎡ 두 칸이 짝이다. ㎡ 칸에 넣으면 미러가 평을 계산한다.
    const sizeCell = () => cellOf('room_info', '매물 크기');
    const areaInput = (heading, name) => () => {
      const group = groupOf(sizeCell(), heading);
      return group ? group.querySelectorAll('input[name="' + name + '"]')[1] : null;
    };
    fill('exclusiveArea', areaInput('전용면적', 'room'), data.exclusiveArea);
    fill('supplyArea', areaInput('공급면적(선택)', 'supply'), data.supplyArea);

    // ④ 건축물 용도·승인
    const pick = (section, label, selector, index = 0) => () => {
      const cell = cellOf(section, label);
      return cell ? cell.querySelectorAll(selector)[index] : null;
    };
    await select('buildingUse', pick('room_info', '건축물용도', 'select'), data.buildingUse);
    await select('approvalDateType', pick('room_info', '건축물승인', 'select'), '사용승인일');
    fill('approvalDate', pick('room_info', '건축물승인', 'input[type="text"]'), data.approvalDate, v => String(v).replace(/-/g, ''));

    // ⑤ 방 정보 — 방 수를 넣어야 방 거실 형태·방 특징이 켜진다.
    // 방 수를 넣으면 미러가 이 행을 통째로 다시 그린다 — 뒤의 자리는 반드시 새로 찾는다.
    const roomGroup = heading => () => groupOf(cellOf('room_info', '방 정보'), heading);
    fill('rooms', () => {
      const group = roomGroup('방 수')();
      return group ? group.querySelector('input') : null;
    }, data.rooms, v => String(v).replace(' 이상', ''));
    await sleep(REACT);
    const layout = {'오픈형 원룸': '오픈형', '분리형 원룸': '분리형', '복층형 원룸': null}[data.roomLayout];
    if (layout) await choose('roomLayout', roomGroup('방 거실 형태'), layout);
    else if (data.roomLayout !== '복층형 원룸' && filled(data.roomLayout)) {
      note('방 구조 ' + data.roomLayout + ': 다방의 오픈형/분리형에 정확히 대응하지 않습니다.');
    }
    if (data.petAllowed === '가능') await choose('petAllowed', roomGroup('방 특징(선택)'), '반려동물');
    else if (filled(data.petAllowed)) {
      note('반려동물 ' + data.petAllowed + ': 다방은 「허용」 체크만 제공해 불가능·확인 필요를 구분해 저장할 수 없습니다.');
    }

    // ⑥ 거래 종류 — 고르면 가격 정보 행과 LH 행이 다시 그려진다. 다 그려진 뒤에 넣는다.
    const tradeCell = () => cellOf('trade_info', '거래 종류');
    await choose('trade', tradeCell, data.trade);
    // 거래 종류를 고르면 가격 정보 행이 그 종류의 틀로 새로 그려진다. 다 그려진 뒤에 넣는다.
    const price = name => () => {
      const cell = cellOf('trade_info', '가격 정보');
      return cell ? cell.querySelector('input[name="' + name + '"]') : null;
    };
    await waitUntil(() => data.trade === '월세' ? price('price')() : price('deposit')(), 3000);
    if (data.trade === '매매') fill('salePrice', price('deposit'), data.salePrice);
    else {
      fill('deposit', price('deposit'), data.deposit);
      if (data.trade === '월세') fill('monthlyRent', price('price'), data.monthlyRent);
    }
    if (data.shortTerm === true) {
      await choose('shortTerm', tradeCell, '단기임대');
      note('단기 매물 계약기간: 다방은 개월 수와 협의 여부를 함께 요구하지만 통합 폼에 기간 정보가 없어 화면에서 직접 골라 주셔야 합니다.');
    }

    // ⑦ 융자금 — 다방은 시세 대비 비율만 받는다.
    if (data.loan === '없음') await select('loan', pick('trade_info', '융자금 여부', 'select'), '없음');
    else if (filled(data.loan)) {
      note('융자금 ' + data.loan + (filled(data.loanAmount) ? ' (' + data.loanAmount + '만원)' : '') +
        ': 다방은 시세 대비 30% 이상/미만 구간만 받아 통합 폼의 금액만으로는 구간을 정할 수 없습니다.');
    }

    // ⑧ LH — 전세·월세에서만 나온다.
    if (filled(data.lh)) {
      if (cellOf('trade_info', 'LH')) await choose('lh', () => cellOf('trade_info', 'LH'), data.lh);
      else note('LH 전세임대 여부: 이 거래 종류에서는 다방 폼에 LH 항목이 나타나지 않습니다.');
    }

    // ⑨ 관리비
    await select('noManagementFee', pick('trade_info', '관리비', 'select'), data.noManagementFee === true ? '없음' : '있음');
    if (data.noManagementFee !== true) await completeFeeModal();
    if (filled(data.unknownFeeReason) && data.manageMethod === '확인 불가') {
      note('확인 불가 법정 사유: 다방 상세입력 창의 「확인불가」에는 사유를 고르는 칸이 없습니다.');
    }
    if (filled(data.manageDetail) && data.manageMethod === '정액 관리비') {
      note('비목별 실비·정액 내역: 다방은 포함 항목 체크만 받고 비목별 부과 방식은 저장하지 않습니다.');
    }

    // ⑩ 입주
    const moveIn = () => cellOf('trade_info', '입주 가능 일자');
    if (data.moveInType === '즉시 입주') await choose('moveInType', moveIn, '즉시 입주');
    else if (data.moveInType === '날짜 지정') {
      await choose('moveInType', moveIn, '일자 선택');
      fill('moveInDate', pick('trade_info', '입주 가능 일자', 'input[type="text"]'), data.moveInDate, v => String(v).replace(/-/g, ''));
    } else if (data.moveInType === '협의 가능') {
      await choose('moveInType', moveIn, '즉시 입주');
      await choose('moveInNegotiable', moveIn, '협의 가능할 경우');
      note('입주 방식 협의 가능: 다방은 즉시 입주/일자 선택 중 하나를 고른 뒤 「협의 가능할 경우」를 덧붙이는 구조라 즉시 입주 + 협의 가능으로 넣었습니다.');
    }
    if (data.moveInNegotiable === true) await choose('moveInNegotiable', moveIn, '협의 가능할 경우');

    // ⑪ 층 수 — 전체 층을 고르면 해당 층 목록이 다시 만들어진다.
    await select('floorAll', pick('additional_info', '층 수', 'select', 0), String(data.floorAll) + '층');
    await select('floor', pick('additional_info', '층 수', 'select', 1), data.floor === '옥탑' ? '옥탑' : String(data.floor));
    if (data.floorPrivate === true) {
      const hide = pick('additional_info', '층 수', 'input[type="checkbox"]');
      if (hide() && !hide().disabled) {
        await toggle('floorPrivate', hide, true, '저/중/고 표기');
        note('층수 비공개: 다방은 해당 층을 고른 뒤 저/중/고 표기만 대신 노출합니다. 표기 구간은 화면에서 직접 골라 주세요.');
      } else note('층수 비공개: 다방은 해당 층을 반드시 고르게 되어 있어 완전한 비공개로 둘 수 없습니다.');
    }

    // ⑫ 방향
    const base = {'거실 기준': '거실', '안방 기준': '안방', '주실 기준': '거실'}[data.directionBase];
    if (data.directionBase === '주실 기준') {
      note('방향 기준 주실 기준: 다방은 안방/거실만 제공해 「거실」로 넣었습니다(공인중개사법의 주실 = 거실이나 안방).');
    }
    if (base) {
      await select('directionBase', pick('additional_info', '방향 기준', 'select', 0), base);
      await select('direction', pick('additional_info', '방향 기준', 'select', 1), data.direction);
    }

    // ⑬ 욕실·엘리베이터 — 같은 줄의 다른 칸이다.
    fill('bathrooms', pick('additional_info', '욕실 수', 'input'), data.bathrooms, v => String(v).replace(' 이상', ''));
    await choose('elevator', () => cellOf('additional_info', '엘리베이터'), data.elevator);

    // ⑭ 주차
    const parkingOk = await select('parking', pick('additional_info', '주차 가능 여부', 'select'), data.parking === '주차 가능' ? '가능' : '불가능');
    if (parkingOk && data.parking === '주차 가능') {
      const count = pick('additional_info', '주차 가능 여부', 'input[type="text"]');
      if (await ready(count)) fill('parkingCount', count, data.parkingCount);
      else miss('parkingCount', '주차 대수 입력란이 켜지지 않았습니다.');
    }
    if (filled(data.parkingPerHousehold)) note('세대당 주차 대수: 다방은 총 주차 대수만 받습니다.');

    // ⑮ 복층
    await choose('roomLayout.duplex', () => cellOf('additional_info', '복층 여부'), data.roomLayout === '복층형 원룸' ? '복층' : '단층');

    // ⑯ 시설
    await choose('heating', () => cellOf('facility_info', '난방 시설'), data.heating);
    const living = () => cellOf('facility_info', '생활 시설');
    for (const item of (data.appliances || [])) {
      if (item === '에어컨') {
        note('에어컨: 다방은 벽걸이형·스탠드형·천장형 중 하나를 고르게 되어 있는데 통합 폼에는 종류 정보가 없어 임의로 고르지 않았습니다.');
        continue;
      }
      if (labelInput(living(), item)) await choose('appliances.' + item, living, item);
      else note('가전·가구 옵션 ' + item + ': 다방 생활 시설에 대응 항목이 없습니다.');
    }
    const FACILITY = {
      'CCTV': ['보안 시설', 'CCTV'], '인터폰': ['보안 시설', '인터폰'], '비디오폰': ['보안 시설', '비디오폰'],
      '공동현관보안': ['보안 시설', '현관보안'], '사설경비': ['보안 시설', '사설경비'],
      '무인택배함': ['기타 시설', '무인택배함'], '테라스': ['기타 시설', '테라스'], '베란다/발코니': ['기타 시설', '베란다'],
    };
    for (const item of (data.facilities || [])) {
      const target = FACILITY[item];
      if (!target) { note('보안 및 시설 옵션 ' + item + ': 다방 시설 정보에 대응 항목이 없습니다.'); continue; }
      await choose('facilities.' + item, () => cellOf('facility_info', target[0]), target[1]);
    }

    // ⑰ 글
    fill('title', pick('detail_info', '제목', 'input,textarea'), data.title);
    fill('description', pick('detail_info', '상세설명', 'textarea,input'), data.description);
    fill('privateMemo', pick('detail_info', '비공개 메모', 'textarea,input'), data.privateMemo);

    if (filled(data.violation) && data.violation !== '해당 없음') {
      note('위반건축물 여부: 다방 등록 폼에 별도 입력란이 없어 상세 설명에 「위반건축물」로 표시해야 합니다.');
    }
    if (filled(data.loanAvailable)) note('대출 가능 여부: 다방 등록 폼에 대응 입력란이 없습니다.');
    if (filled(data.ownerPhone)) note('집주인 연락처: 다방 등록 폼에 집주인 연락처 입력란이 없습니다.');
    if (data.singleBuilding === true) note('단일동 여부: 다방은 「등기부등본 상에 동 정보가 없을 경우」 체크만 제공하며 주소를 고른 뒤에 켜집니다.');
    if (filled(data.photoCount)) note('사진: 브라우저 보안 정책상 WebView 스크립트가 파일 선택란에 기기 사진을 넣을 수 없어 「사진 추가」로 직접 골라 주셔야 합니다.');
    for (const message of (window.__flrPostcode ? window.__flrPostcode.notes : [])) note(message);

    // ⑱ 마지막에 주소 검색 화면을 띄운다 — 전체 화면 겹이라 다른 입력을 가린다.
    if (filled(data.address)) {
      const cell = addressCell();
      const search = cell && [...cell.querySelectorAll('button')].find(button => norm(text(button)) === '검색');
      if (search) {
        note('매물 기본 주소: 검색어를 넣고 카카오 주소 검색 화면을 띄웠습니다. 결과를 고르면 주소·동·호가 채워집니다.');
        press(search);
      } else miss('address', '매물 주소의 「검색」 버튼을 찾지 못했습니다.');
    }
  } catch (error) {
    output.violations.push('다방 자동 입력 오류: ' + String(error && error.stack ? error.stack : error));
  }
  for (const violation of (window.__FLR_VIOLATIONS__ || [])) {
    const detail = typeof violation === 'string' ? violation
      : [violation.kind, violation.target, violation.detail].filter(Boolean).join(' · ');
    output.violations.push('깐깐이 위반: ' + detail);
  }
  // 「임시저장」·「등록 완료」·#submit 은 어떤 경우에도 누르지 않는다. 이 어댑터는 채우기만 한다.
  publish();
})();
''';
