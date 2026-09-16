import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum ListingPlatform { zigbang, dabang }

extension ListingPlatformConfig on ListingPlatform {
  String get label => this == ListingPlatform.zigbang ? '직방' : '다방';

  String get formUrl => this == ListingPlatform.zigbang
      ? 'https://mirror-dimension-lab.pages.dev/zigbang/form/oneroom/index.html'
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
      targetAvailable: false,
      unavailableReason: '주소는 미러의 주소 검색 모달에서 좌표와 함께 확정되어야 합니다. 앱에서 보관한 우편번호·법정동코드를 문자열만으로 WebView에 확정할 수 없습니다.',
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
          onWebResourceError: (error) =>
              setState(() => status = '웹 뷰 오류: ${error.description}'),
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
        limitations = [...unsupported, ...missing, ...violations];
      });
    } catch (_) {
      setState(() => status = '입력 결과를 해석하지 못했습니다.');
    }
  }

  Future<void> _inject(String url) async {
    final current = Uri.tryParse(url);
    final target = Uri.parse(widget.platform.formUrl);
    if (current?.host != target.host ||
        !current!.path.startsWith(target.path) ||
        _lastInjectedUrl == current.toString()) {
      return;
    }
    _lastInjectedUrl = current.toString();
    final payload = jsonEncode(widget.values);
    try {
      await controller.runJavaScript(
        widget.platform == ListingPlatform.zigbang
            ? _injectionScript(payload)
            : dabangInjectionScript(payload),
      );
    } catch (error) {
      if (mounted) setState(() => status = '자동 입력 JavaScript 오류: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
            title: Text('입력하지 못한 항목 ${limitations.length}개'),
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
  );
}

String _injectionScript(String payload) =>
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
    address: '매물 기본 주소: 미러는 좌표와 주소검색 모달의 결과를 함께 요구하는 읽기 전용 주소 입력입니다. 문자열만 주입해도 주소 상태가 확정되지 않아 자동 전송할 수 없습니다.',
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
  const esc = s => (window.CSS && CSS.escape) ? CSS.escape(String(s)) : String(s).replace(/[^a-zA-Z0-9_-]/g, '\\\\${r'$'}&');
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
  const normalize = value => String(value ?? '').replace(/[ \\t\\r\\n]+/g, '').replace(/향${r'$'}/, '').replace(/층${r'$'}/, '').replace(/개${r'$'}/, '');
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
  const mark = (key, ok) => { if (ok) output.applied++; else output.missing.push(key + ': 미러의 대상 DOM을 찾거나 선택하지 못했습니다.'); };
  try {
    if (typeof strict === 'function') {
      const strictResult = await strict(data);
      Object.assign(output, strictResult || {});
      window.ListingResult.postMessage(JSON.stringify(output)); return;
    }
    if (strict && typeof strict !== 'function' && !strictSet && !strictClick) output.violations.push('FLR.strict에 호출 가능한 helper가 없어 DOM 대체 입력을 사용했습니다.');
    for (const [key, reason] of Object.entries(unavailable)) if (data[key] !== undefined && data[key] !== '') output.unsupported.push(reason);
    const input = (key, value, transform = v => v) => { if (value === undefined || value === null || value === '') return; const el = find(names[key]); if (!el) return mark(key, false); setValue(el, transform(value)); mark(key, true); };
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
    const targetFloor = data.floor === '옥탑' ? '옥탑방' : /^\\d+${r'$'}/.test(String(data.floor)) ? data.floor + '층' : data.floor;
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
    if (data.manageMethod === '정액 관리비' && data.manageDetail) {
      const detailKeys = {
        electricity: '전기료', water: '수도료', gas: '가스사용료',
        heating: '난방비', internet: '인터넷', tv: '유선TV',
        normalManageCost: '청소비', etcManageCost: '기타'
      };
      for (const el of document.querySelectorAll('select[name${r'$'}=".type"]')) {
        const source = Object.keys(detailKeys).find(key => el.name.includes(key));
        if (!source) continue;
        const masterValue = data.manageDetail[detailKeys[source]];
        if (!masterValue) {
          output.unsupported.push('관리비 세부 ' + detailKeys[source] + ': 통합 폼 값이 없어 미러에 입력하지 않았습니다.');
          continue;
        }
        mark('manageDetail.' + detailKeys[source], await choose(el.name, masterValue));
      }
    }
    mark('roomLayout', await choose(names.roomLayout, ({'오픈형 원룸':'오픈형 원룸 (방1)','분리형 원룸':'분리형 원룸 (방1,거실1)','복층형 원룸':'복층형 원룸'})[data.roomLayout] || data.roomLayout));
    mark('bathrooms', await choose(names.bathrooms, String(data.bathrooms).replace(' 이상', '개'))); mark('directionBase', await clickText('directionCriterionType', data.directionBase === '주실 기준' ? '거실 기준' : data.directionBase)); mark('direction', await choose(names.direction, data.direction));
    mark('parking', await check('no-parking', data.parking === '주차 불가능')); if (data.parking === '주차 가능') input('parkingCount', data.parkingCount);
    mark('elevator', await clickText('isElevator', data.elevator)); mark('violation', await clickText('nonCompliantBuilding', data.violation === '해당 없음' ? '해당없음' : '해당'));
    mark('loanAvailable', await check('itemConditions.loanLease', data.loanAvailable === '가능')); mark('petAllowed', await check('itemConditions.pet', data.petAllowed === '가능'));
    const optionLabel = [...document.querySelectorAll('label')].find(label => label.textContent.trim() === '옵션');
    const optionScope = optionLabel?.parentElement?.parentElement || document;
    for (const option of (data.appliances || [])) { const button = [...optionScope.querySelectorAll('button')].find(b => b.textContent.trim() === option); if (button) { press(button); if (await waitFor(() => selectedButton(button))) output.applied++; else output.missing.push('appliances.' + option + ': 미러에서 선택 상태를 확인하지 못했습니다.'); } else output.unsupported.push('가전·가구 옵션 ' + option + ': 직방 원룸 미러에 대응 옵션이 없습니다.'); }
    const conditionIds = {'CCTV':'itemConditions.cctv','테라스':'itemConditions.terrace','전기차 충전시설':'itemConditions.evStation'}; for (const item of (data.facilities || [])) { if (conditionIds[item]) { if (await check(conditionIds[item], true)) output.applied++; else output.missing.push('facilities.' + item + ': 미러에서 선택 상태를 확인하지 못했습니다.'); } else output.unsupported.push('보안 및 시설 옵션 ' + item + ': 직방 원룸 미러에 대응 옵션이 없습니다.'); }
    if (data.moveInType === '즉시 입주') mark('moveInType', await check('moveInImmediately', true)); else if (data.moveInType === '날짜 지정') { mark('moveInType', await check('moveInImmediately', false)); input('moveInDate', data.moveInDate); } else output.unsupported.push('입주 방식 협의 가능: 직방 원룸 미러는 즉시 입주 또는 날짜 선택만 지원합니다.');
    if (data.moveInNegotiable === true) input('moveInNegotiable', '협의 가능');
    input('title', data.title); input('description', data.description); input('privateMemo', data.privateMemo); input('ownerPhone', data.ownerPhone);
    for (const key of ['building','unit','exclusiveArea','approvalDate','deposit','monthlyRent','managementFee','title','description','privateMemo','ownerPhone']) { const el = find(names[key]); if (el && String(el.value) !== '') output.verified++; }
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
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const normalize = value => String(value ?? '').replace(/[ \\t\\r\\n]+/g, '').replace(/층${r'$'}/, '');
  const setterFor = el => Object.getOwnPropertyDescriptor(
    el.tagName === 'SELECT' ? HTMLSelectElement.prototype :
    el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype,
    'value'
  )?.set;
  const setNative = (el, value) => {
    if (!el || value === undefined || value === null || value === '') return false;
    const setter = setterFor(el);
    if (setter) setter.call(el, String(value)); else el.value = String(value);
    ['input', 'change', 'blur'].forEach(type => el.dispatchEvent(new Event(type, {bubbles: true})));
    return true;
  };
  const press = el => {
    if (!el) return false;
    ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(type =>
      el.dispatchEvent(new MouseEvent(type, {bubbles: true, cancelable: true})));
    return true;
  };
  const row = (label, sectionId) => {
    const section = document.getElementById(sectionId);
    return [...(section || document).querySelectorAll('tr')]
      .find(el => normalize(el.querySelector('th')?.textContent).includes(normalize(label)));
  };
  const named = (name, index = 0) => document.querySelectorAll('[name="' + name + '"]')[index];
  const fill = (key, el, value, transform = v => v) => {
    if (value === undefined || value === null || value === '') return;
    const wanted = String(transform(value));
    if (setNative(el, wanted)) {
      output.applied++;
      if (String(el.value) === wanted) output.verified++;
      else output.missing.push(key + ': 값을 입력했지만 DOM에서 동일한 값을 다시 확인하지 못했습니다.');
    }
    else output.missing.push(key + ': 다방 미러의 대상 DOM을 찾지 못했습니다.');
  };
  const choose = async (key, label, value, sectionId) => {
    if (value === undefined || value === null || value === '') return;
    const scope = row(label, sectionId);
    if (!scope) { output.missing.push(key + ': ' + sectionId + '에서 "' + label + '" 행을 찾지 못했습니다.'); return; }
    const candidate = [...scope.querySelectorAll('label,button,[role="radio"],[role="option"]')]
      .find(el => normalize(el.textContent).includes(normalize(value)));
    const control = candidate?.matches('input') ? candidate : candidate?.querySelector('input');
    if (press(candidate)) {
      output.applied++; await sleep(120);
      const fresh = [...scope.querySelectorAll('label')].find(el => normalize(el.textContent).includes(normalize(value)))?.querySelector('input');
      if ((fresh || control)?.checked) output.verified++;
      else output.missing.push(key + ': 선택 이벤트 후 선택 상태를 확인하지 못했습니다.');
    }
    else output.missing.push(key + ': 다방 미러에서 "' + value + '" 선택지를 찾지 못했습니다.');
  };
  const selectRow = async (key, label, value, sectionId, index = 0) => {
    if (value === undefined || value === null || value === '') return false;
    const locate = () => row(label, sectionId)?.querySelectorAll('select')[index];
    let el = locate();
    if (!el || el.disabled) { output.unsupported.push(key + ': 현재 다방 폼 상태에서 선택란이 활성화되지 않았습니다.'); return false; }
    const option = [...el.options].find(o => normalize(o.textContent) === normalize(value) || String(o.value) === String(value));
    if (!option) { output.unsupported.push(key + ' ' + value + ': 다방 폼에 대응 선택지가 없습니다.'); return false; }
    setNative(el, option.value); output.applied++;
    await sleep(180); el = locate();
    if (el && el.value === option.value) { output.verified++; return true; }
    output.missing.push(key + ': 선택 후 DOM 값을 재확인하지 못했습니다.'); return false;
  };
  const unsupported = {
    address: '매물 기본 주소: 다방은 주소 검색 결과와 좌표를 함께 확정하므로 문자열만 안전하게 주입할 수 없습니다.',
    building: '동 정보: 다방은 주소 검색 결과가 확정되기 전에는 동 입력란을 비활성화하므로 주입하지 않습니다.',
    unit: '호수 정보: 다방은 주소 검색 결과가 확정되기 전에는 호수 입력란을 비활성화하므로 주입하지 않습니다.',
    manageBasis: '관리비 부과 기준: 다방 폼에 대응하는 독립 입력란이 없습니다.',
    manageMethod: '관리비 부과 방식: 다방은 관리비 없음/있음과 금액만 받아 정액·기타·확인 불가 구분을 전달할 수 없습니다.',
    manageDetail: '비목별 실비·정액 내역: 다방 폼은 통합 폼의 비목별 부과 방식을 지원하지 않습니다.',
    otherFeeReason: '기타 부과 법정 사유: 다방 폼에 대응 필드가 없습니다.',
    unknownFeeReason: '확인 불가 법정 사유: 다방 폼에 대응 필드가 없습니다.',
    parkingPerHousehold: '세대당 주차 대수: 다방 폼의 주차 항목에 독립 입력란이 없습니다.',
    loanAvailable: '대출 가능 여부: 다방 폼에 대출 가능 여부를 확정하는 독립 입력란이 없습니다.',
    violation: '위반건축물 여부: 현재 다방 미러 폼에 대응 입력란이 없습니다.',
    shortTerm: '단기 매물 여부: 다방은 단기 기간을 월 단위로 요구하지만 통합 폼에는 기간 정보가 없어 여부만으로 임의 설정하지 않습니다.',
    ownerPhone: '집주인 연락처: 다방 등록 폼에 집주인 연락처 입력란이 없습니다.',
    photoCount: '사진: 브라우저 보안 정책상 WebView JavaScript로 file input에 기기 파일을 할당할 수 없어 사용자가 직접 선택해야 합니다.'
  };
  try {
    for (const [key, reason] of Object.entries(unsupported)) {
      if (data[key] !== undefined && data[key] !== '' && data[key] !== false) output.unsupported.push(reason);
    }
    if (data.floorPrivate === true) output.unsupported.push('층수 비공개: 다방 폼은 실제 해당 층 입력을 요구하여 비공개 상태를 전달할 수 없습니다.');
    if (data.singleBuilding === true) output.unsupported.push('단일동 여부: 다방은 동 입력의 유무만 제공하여 통합 폼의 단일동 의미를 별도 상태로 저장할 수 없습니다.');
    if (data.directionBase === '주실 기준') output.unsupported.push('방향 기준 주실 기준: 다방은 안방/거실만 제공하여 정확히 대응하는 선택지가 없습니다. 의미를 변조하지 않기 위해 방향 기준과 방향을 모두 입력하지 않았습니다.');
    const supportedPropertyTypes = ['단독주택','다가구주택','상가주택'];
    if (data.propertyType && !supportedPropertyTypes.includes(data.propertyType)) {
      output.unsupported.push('매물 대분류 ' + data.propertyType + ': 다방 주거용 매물유형에 대응 선택지가 없습니다.');
    } else {
      await choose('propertyType', '매물유형', data.propertyType, 'room_info');
    }
    fill('exclusiveArea', named('room', 1), data.exclusiveArea);
    fill('supplyArea', named('supply', 1), data.supplyArea);
    await selectRow('buildingUse', '건축물용도', data.buildingUse, 'room_info');
    await selectRow('approvalDateType', '건축물승인', '사용승인일', 'room_info', 0);
    await selectRow('floorAll', '층 수', data.floorAll + '층', 'additional_info', 0);
    await selectRow('floor', '층 수', data.floor === '옥탑' ? '옥탑' : data.floor, 'additional_info', 1);
    await choose('trade', '거래 종류', data.trade, 'trade_info');
    if (data.trade === '매매') fill('salePrice', named('deposit'), data.salePrice);
    else if (data.trade === '전세') fill('deposit', named('deposit'), data.deposit);
    else if (data.trade === '월세') { fill('deposit', named('deposit'), data.deposit); fill('monthlyRent', named('price'), data.monthlyRent); }
    if (data.loan === '없음') await selectRow('loan', '융자금 여부', '없음', 'trade_info');
    else if (data.loan) output.unsupported.push('융자금 ' + data.loan + (data.loanAmount ? ' (' + data.loanAmount + '만원)' : '') + ': 다방은 시세 대비 비율 구간을 요구하므로 통합 폼의 금액만으로 임의 변환하지 않습니다.');
    await selectRow('noManagementFee', '관리비', data.noManagementFee === true ? '없음' : '있음', 'trade_info');
    await sleep(200);
    if (data.noManagementFee !== true) fill('managementFee', named('detailCost'), data.managementFee, v => String(Number(v) * 10000));
    fill('rooms', row('방 정보', 'room_info')?.querySelector('input:not([disabled])'), String(data.rooms).replace(' 이상',''));
    if (data.roomLayout === '복층형 원룸') {
      await choose('roomLayout.duplex', '복층 여부', '복층', 'additional_info');
    } else {
      await choose('roomLayout.duplex', '복층 여부', '단층', 'additional_info');
      const layout = data.roomLayout === '오픈형 원룸' ? '오픈형' : data.roomLayout === '분리형 원룸' ? '분리형' : null;
      if (layout) await choose('roomLayout', '방 정보', layout, 'room_info');
      else if (data.roomLayout) output.unsupported.push('방 구조 ' + data.roomLayout + ': 다방 미러의 오픈형/분리형 선택지에 정확히 대응하지 않습니다.');
    }
    fill('bathrooms', row('욕실 수', 'additional_info')?.querySelector('input'), String(data.bathrooms).replace(' 이상',''));
    if (data.directionBase !== '주실 기준') {
      const base = data.directionBase === '거실 기준' ? '거실' : '안방';
      await selectRow('directionBase', '방향 기준/방향', base, 'additional_info', 0);
      await selectRow('direction', '방향 기준/방향', data.direction, 'additional_info', 1);
    }
    const parkingOk = await selectRow('parking', '주차 가능 여부', data.parking === '주차 가능' ? '가능' : '불가능', 'additional_info');
    if (parkingOk && data.parking === '주차 가능') { await sleep(180); fill('parkingCount', row('주차 가능 여부', 'additional_info')?.querySelector('input'), data.parkingCount); }
    await choose('elevator', '엘리베이터', data.elevator, 'additional_info');
    await choose('heating', '난방 시설', data.heating, 'facility_info');
    for (const fee of (data.manageIncludes || [])) output.unsupported.push('관리비 포함 항목 ' + fee + ': 다방 미러는 총 관리비만 입력받아 개별 포함 비목을 전달할 수 없습니다.');
    for (const option of (data.appliances || [])) {
      if (option === '에어컨') output.unsupported.push('에어컨: 다방 폼은 벽걸이·스탠드 등 세부 종류를 요구하지만 통합 폼에는 종류 정보가 없어 임의 선택하지 않았습니다.');
      else await choose('option.' + option, '생활 시설', option, 'facility_info');
    }
    for (const option of (data.facilities || [])) await choose('option.' + option, option === 'CCTV' ? '보안 시설' : '기타 시설', option, 'facility_info');
    if (data.moveInType === '날짜 지정') await choose('moveInType', '입주 가능 일자', '일자 선택', 'trade_info');
    else if (data.moveInType === '즉시 입주') await choose('moveInType', '입주 가능 일자', '즉시 입주', 'trade_info');
    else if (data.moveInType === '협의 가능' && data.moveInNegotiable !== true) output.unsupported.push('입주 방식 협의 가능: 다방은 기본 일자 유형과 협의 체크를 함께 요구하므로 즉시 입주로 변조하지 않았습니다.');
    if (data.moveInNegotiable === true) await choose('moveInNegotiable', '입주 가능 일자', '협의 가능할 경우', 'trade_info');
    if (data.petAllowed === '가능') await choose('petAllowed', '방 정보', '반려동물', 'room_info');
    else if (data.petAllowed) output.unsupported.push('반려동물 ' + data.petAllowed + ': 다방은 허용 체크만 제공하여 불가능/확인 필요를 명시적으로 저장할 수 없습니다.');
    await choose('lh', 'LH', data.lh, 'trade_info');
    fill('approvalDate', row('건축물승인', 'room_info')?.querySelector('input'), String(data.approvalDate).replaceAll('-',''));
    fill('moveInDate', row('입주 가능 일자', 'trade_info')?.querySelector('input'), String(data.moveInDate).replaceAll('-',''));
    fill('title', row('제목', 'detail_info')?.querySelector('input,textarea'), data.title);
    fill('description', row('상세 설명', 'detail_info')?.querySelector('textarea,input'), data.description);
    fill('privateMemo', row('비공개 메모', 'detail_info')?.querySelector('textarea'), data.privateMemo);
    // Intentionally never click #submit, "임시저장", or "등록 완료". This adapter only fills the form.
  } catch (error) {
    output.violations.push('다방 자동 입력 오류: ' + String(error));
  }
  window.ListingResult.postMessage(JSON.stringify(output));
})();
''';
