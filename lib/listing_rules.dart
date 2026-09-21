/// 통합 폼이 지켜야 하는 규칙 — **직방과 다방이 둘 다 받아 주는 값만** 통과시킨다.
///
/// 규칙은 전부 실물에서 떠 왔다(2026-09-21, 로그인한 계정으로 폼을 열고 각 사이트가
/// 제출 전에 돌리는 검사 코드를 읽었다). 직방은 zod 스키마와 제출 직전 금칙어 검사,
/// 다방은 제출 버튼이 부르는 검사 함수와 관리비 상세입력 창의 검사다.
///
/// 한 곳이라도 못 받는 값을 통합 폼이 받아 주면, 그 값은 등록 흐름 한복판에서 사람
/// 손으로 고쳐야 하는 빈칸이 된다. 그래서 여기서 막는다 — 「통합 폼을 통과했다면 두 폼
/// 모두 정상적으로 채워진다」가 이 파일의 약속이다.
library;

import 'fields.dart';

/// 제목에 쓸 수 있는 글자. 직방은 한글·영문·숫자·공백·쉼표·마침표만(특수 기호 검사),
/// 다방은 한글·영문·숫자·공백과 `+ - / , . ㎡` 만 받는다(다른 글자가 섞이면 칸이 값을
/// **통째로** 거부한다). 둘 다 받는 것은 그 교집합이다.
final titlePattern = RegExp(r'^[a-zA-Z0-9ㄱ-ㅎㅏ-ㅣ가-힣㎡,. ]*$');

/// 직방이 제목·상세 설명·입주 추가 설명에서 막는 것(제출 직전 검사, 실물 번들).
final _email = RegExp(
  r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
  caseSensitive: false,
);
final _link = RegExp(
  r'(https?:\/\/[^\s가-힣]+)|(?:www\.)[a-zA-Z0-9]+(?:\.[a-zA-Z0-9]+)*\.[a-zA-Z]{2,}(?=[^a-zA-Z0-9.]|$)'
  r'|[a-zA-Z0-9]+(?:\.[a-zA-Z0-9]+)*\.(?:com|net|org|kr|co\.kr|or\.kr|go\.kr|ac\.kr|me)(?=[^a-zA-Z0-9.]|$)'
  r'|(?:bit\.ly|goo\.gl|t\.co|naver\.me|me2\.do|han\.gl)\/[a-zA-Z0-9_-]+(?=[^a-zA-Z0-9_-]|$)',
  caseSensitive: false,
);
final _phone = RegExp(r'0\d{1,2}[- .]?\d{3,4}[- .]?\d{4}|0\d{9,10}');

/// 다방이 동·호 칸에 받는 글자 — 한글·영문·숫자만(공백·하이픈도 안 된다).
final unitPattern = RegExp(r'^[a-zA-Z0-9ㄱ-ㅎㅏ-ㅣ가-힣]+$');

/// 다방·당근처럼 칸 옆에 「동」·「호」가 이미 붙어 있는 폼에 넣을 글자.
String bareUnit(Object? raw, String suffix) {
  var text = '${raw ?? ''}'.trim();
  if (text.endsWith(suffix)) text = text.substring(0, text.length - 1).trim();
  return text;
}

/// 직방 의뢰인 전화번호 — 숫자만 남겨 010 으로 시작해야 한다.
String ownerPhoneDigits(Object? raw) =>
    '${raw ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');

/// 직방이 제목·설명에서 막는 것이 있으면 그 이유. 금칙어 목록은 직방이 로그인한
/// 계정에 내려 주므로 여기서는 볼 수 없다 — 어댑터가 폼에서 다시 잰다.
String? contactProblem(String text) {
  if (_phone.hasMatch(text)) return '전화번호';
  if (_email.hasMatch(text)) return '이메일';
  if (_link.hasMatch(text)) return '외부 링크';
  return null;
}

String _text(Map<String, dynamic> values, String key) =>
    '${values[key] ?? ''}'.trim();
bool _blank(Map<String, dynamic> values, String key) =>
    _text(values, key).isEmpty;
num? _number(Map<String, dynamic> values, String key) =>
    num.tryParse(_text(values, key).replaceAll(',', ''));
bool _positiveInt(Map<String, dynamic> values, String key) {
  final value = _number(values, key);
  return value != null && value >= 1 && value == value.roundToDouble();
}

bool _decimals(num value, int places) {
  final scaled = value * _pow10(places);
  return (scaled - scaled.roundToDouble()).abs() < 1e-6;
}

int _pow10(int places) => [1, 10, 100, 1000][places];

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime? _date(Map<String, dynamic> values, String key) {
  final text = _text(values, key);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  // 2026-02-31 처럼 넘어가는 날짜를 거른다.
  final back =
      '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  return back == text ? parsed : null;
}

/// 전체 층 상한. 다방 주택/빌라는 50층까지만 고르게 하고, 단지(오피스텔·아파트)는
/// 그 단지의 최고층 + 5 까지 보여 준다. 직방은 80층까지다.
int maxFloorAll(Map<String, dynamic> values) =>
    isComplexProperty(values) ? 80 : 50;

/// 해당 층으로 고를 수 있는 것. 반지하·옥탑은 주택/빌라만 받는다(다방 단지 폼은
/// 1층부터 전체 층까지만 보여 준다).
List<String> floorChoices(Map<String, dynamic> values) {
  final all = int.tryParse(_text(values, 'floorAll'));
  final top = all == null
      ? maxFloorAll(values)
      : all.clamp(1, maxFloorAll(values));
  return [
    if (!isComplexProperty(values)) '반지하',
    for (var i = 1; i <= top; i++) '$i',
    if (!isComplexProperty(values)) '옥탑',
  ];
}

/// 이 매물이 지금 보여 줘야 하는 칸인가.
bool fieldVisible(Map<String, dynamic> values, String key) {
  final trade = values['trade'];
  final rent = trade == '월세' || trade == '전세';
  final fee = values['noManagementFee'] != true;
  final method = fee ? values['manageMethod'] : null;
  final tier = method == '정액 관리비' ? values['feeTier'] : null;
  final parking = values['parking'] == '주차 가능';
  return switch (key) {
    'complexName' => isComplexProperty(values),
    'deposit' || 'lh' => rent,
    'monthlyRent' || 'shortTerm' => trade == '월세',
    'shortTermMonths' ||
    'shortTermNegotiation' => trade == '월세' && values['shortTerm'] == true,
    'salePrice' => trade == '매매',
    'loanAmount' => values['loan'] != null && values['loan'] != '없음',
    'manageMethod' => fee,
    'feeTier' => method == '정액 관리비',
    'manageBasis' => method == '기타 부과' || tier != null,
    'manageBasisNote' =>
      (method == '기타 부과' || tier != null) &&
          values['manageBasis'] == '기타 직접 입력',
    'managementFee' || 'manageIncludes' =>
      method == '기타 부과' || (tier != null && tier != '10만원 이상'),
    'manageDetail' => tier == '10만원 이상',
    'otherFeeReason' => method == '기타 부과',
    'otherFeeNote' => method == '기타 부과' && values['otherFeeReason'] == '기타',
    'unknownFeeReason' => method == '확인 불가',
    'parkingCount' ||
    HifiField.monthlyParkingFee ||
    'parkingPerHousehold' => parking,
    HifiField.structure => roomCount(values) == 1,
    HifiField.floorBand => values['floorPrivate'] == true,
    'airconType' => (values['appliances'] as List? ?? const []).contains('에어컨'),
    'moveInDate' => values['moveInImmediate'] != true,
    'mediationNote' => values['mediationMethod'] == '기타 방법으로 확인',
    'ownerPhoneDuplicateNote' => values['ownerPhoneDuplicateReason'] == '기타',
    _ => true,
  };
}

/// 칸 옆에 빨간 별을 붙일 것인가 — 지금 보이는 칸 가운데 채워야 하는 것.
///
/// **별의 근거는 실물 두 폼뿐이다.** 직방·다방 중 **한 곳이라도** 그 칸에 별을
/// 달면 필수, 두 곳 다 달지 않으면 선택이다. 한 곳에만 있는 칸이라도 통합 폼은
/// 받아 둔다 — 받아 두되 억지로 막지는 않는다.
///
/// 실물 확인 2026-09-22(로그인한 계정으로 두 폼을 열어 별표를 세어 봄):
///
///  · 직방 원룸 폼(`span.text-red-500` 이 붙은 25줄) — 주소·동·호·건물 종류·
///    거래 유형·전용면적·사용승인일·입주 가능일·전체 층·해당 층·구조·주실 방향·
///    화장실 수·총 주차대수·위반건축물·엘리베이터·관리비 부과 방식(+기준·월 평균·
///    포함 항목·실비 세부 내역)·매물 사진·한줄 요약·상세 설명·중개 의뢰를 받은 방법.
///  · 다방 주택/빌라 폼(`th` 의 `*`) — 매물유형·매물 주소·매물 크기·방 정보·
///    건축물용도·건축물승인·거래 종류·가격 정보·관리비·입주 가능 일자·층 수·
///    방향 기준/방향·욕실 수·엘리베이터·주차 가능 여부·복층 여부·일반 사진·제목·
///    상세설명. 매매·전세·월세 셋을 다 눌러 보았고 별이 붙는 줄은 같다 — **LH
///    전세임대 여부\***만 전세·월세에서 나타나고 매매에서는 줄 자체가 없다
///    ([fieldVisible] 의 `'lh' => rent` 와 같다).
///
/// **보지 못한 폼이 있다.** 직방 빌라(「빌라 매물의 광고수량을 모두 이용중입니다」로
/// 폼이 열리지 않는다 — 남의 운영 중인 광고를 종료해야 열린다)와 직방 오피스텔
/// (상품이 없어 원룸 폼으로 되돌려진다), 다방 오피스텔·아파트(대분류가 바뀌지
/// 않는다). 그 폼들의 별표는 **확인한 적이 없다** — 여기 적힌 것은 직방 원룸과
/// 다방 주택/빌라 둘뿐이다.
///
/// 그래서 **선택**으로 내려온 것들(전에는 통합 폼이 막고 있었다): 공급면적(다방
/// 「공급면적(선택)」·직방엔 칸이 없다), 융자금(두 곳 다 별이 없다), 대출 가능
/// 여부·전자계약(직방 「매물 조건」 체크, 별 없음), 반려동물(직방 체크 · 다방
/// 「방 특징(선택)」), 난방 방식·에어컨 종류(다방 「난방/냉방 시설」, 별 없음),
/// 총 세대수(직방 「총 세대 수」 · 다방 「세대(가구수)」, 둘 다 별 없음), 현관 구조
/// (다방 「현관 유형」, 별 없음), 월 주차비(두 폼 어디에도 칸이 없다), 그리고
/// 의뢰인 성함·연락처
/// (직방이 「(선택사항)」이라고 적어 두었고 다방에는 칸이 없다).
bool fieldRequired(Map<String, dynamic> values, String key) {
  if (!fieldVisible(values, key)) return false;
  return switch (key) {
    'building' => values['singleBuilding'] != true,
    // 두 폼이 별을 단 줄, 그리고 그 줄이 갈라 놓은 조건부 칸.
    'complexName' ||
    'deposit' ||
    'lh' ||
    'monthlyRent' ||
    'salePrice' ||
    'shortTermMonths' ||
    'shortTermNegotiation' ||
    'manageMethod' ||
    'feeTier' ||
    'manageBasis' ||
    'manageBasisNote' ||
    'managementFee' ||
    'manageIncludes' ||
    'manageDetail' ||
    'otherFeeReason' ||
    'otherFeeNote' ||
    'unknownFeeReason' ||
    'parkingCount' ||
    HifiField.structure ||
    'moveInDate' ||
    'ownerPhoneDuplicateNote' ||
    'mediationNote' => true,
    'parkingPerHousehold' => isComplexProperty(values),
    // 다방 「복층 여부*」. 직방은 구조의 한 갈래(복층형 원룸)로 받는다.
    HifiField.duplex => true,
    /* 저/중/고만은 두 폼의 별표를 따르지 않는다. 다방은 「표기를 원할 경우 선택」이라
     * 적어 두었지만, 이 칸은 **「층수 비공개」를 켠 사람에게만** 보인다. 켜 놓고 비우면
     * 다방에 넣을 표기가 없어 실제 층이 그대로 나간다 — 숨기려고 켠 사람에게는 그것이
     * 틀린 광고다. 켜지 않은 사람은 이 칸을 보지도 않으므로 막는 것도 아니다. */
    HifiField.floorBand => true,
    // 한 곳에만 있고, 그 한 곳도 별을 달지 않은 칸 — 받아 두되 막지 않는다.
    HifiField.householdCount ||
    HifiField.entranceType ||
    HifiField.eContract ||
    HifiField.monthlyParkingFee ||
    HifiField.ownerName ||
    'airconType' ||
    'ownerPhone' => false,
    // 입주 방식은 [moveInDate] 로 받고, 방 구조는 구조·복층에서 세워진다
    // ([roomLayoutFrom]) — 사람이 직접 채우는 칸이 아니다.
    'moveInType' || 'roomLayout' => false,
    _ => _requiredByField[key] ?? false,
  };
}

final _requiredByField = {
  for (final field in groups.expand((group) => group.fields))
    field.key: field.required,
};

/// 이름 붙은 칸이 비었을 때 사람에게 보여 줄 이름.
String fieldLabel(String key) => switch (key) {
  'propertyType' => '매물 종류',
  'address' => '주소',
  'complexName' => '단지명',
  'building' => '동',
  'unit' => '호',
  'exclusiveArea' => '전용면적',
  'supplyArea' => '공급면적',
  'floorAll' => '전체 층 수',
  'floor' => '해당 층 수',
  'buildingUse' => '건축물 법정 용도',
  'approvalDate' => '사용승인일',
  'trade' => '거래 유형',
  'deposit' => '보증금',
  'monthlyRent' => '월세',
  'salePrice' => '매매 금액',
  'shortTermMonths' => '단기 계약 기간',
  'shortTermNegotiation' => '단기 계약 기간 협의',
  'loan' => '융자금',
  'manageMethod' => '관리비 부과 방식',
  'feeTier' => '정액 관리비 구간',
  'manageBasis' => '관리비 부과 기준',
  'manageBasisNote' => '부과 기준 내용',
  'managementFee' => '관리비 총액',
  'manageIncludes' => '관리비 포함 항목',
  'manageDetail' => '항목별 관리비',
  'otherFeeReason' => '기타 부과 근거',
  'otherFeeNote' => '기타 부과 근거 내용',
  'unknownFeeReason' => '확인 불가 사유',
  'rooms' => '방 수',
  'bathrooms' => '욕실 수',
  'directionBase' => '방향 기준',
  'direction' => '주실 방향',
  'parking' => '주차 가능 여부',
  'parkingCount' => '주차 가능 대수',
  'parkingPerHousehold' => '세대당 주차 대수',
  'elevator' => '엘리베이터 유무',
  'violation' => '위반건축물 해당 여부',
  'loanAvailable' => '전세자금대출 가능 여부',
  'petAllowed' => '반려동물 허용',
  'heating' => '난방 방식',
  'airconType' => '에어컨 종류',
  'moveInType' => '입주가능일',
  'moveInDate' => '입주가능일',
  'photoCount' => '매물 사진',
  'title' => '매물 제목',
  'description' => '매물 상세 설명',
  'lh' => 'LH 전세임대 여부',
  'ownerPhone' => '연락처',
  'mediationMethod' => '중개 의뢰 확인 방법',
  'mediationNote' => '기타 확인 방법',
  'ownerPhoneDuplicateNote' => '중복 사유 내용',
  HifiField.householdCount => '총 세대수',
  HifiField.structure => '구조',
  HifiField.duplex => '복층 여부',
  HifiField.entranceType => '현관 구조 유형',
  HifiField.floorBand => '층군 구분',
  HifiField.eContract => '전자계약 가능 여부',
  HifiField.monthlyParkingFee => '월 주차비',
  HifiField.ownerName => '임대인 성함',
  _ => key,
};

/// 이 플랫폼이 이 매물을 받지 못하는 까닭, 받으면 null.
///
/// 칸 하나가 아니라 **매물 전체**가 걸리는 경우다 — 사람이 그 플랫폼을 빼거나 매물을
/// 고쳐야 한다.
String? platformBlocker(ListingPlatform platform, Map<String, dynamic> values) {
  switch (platform) {
    case ListingPlatform.zigbang:
      final type = values['propertyType'];
      if (type == '아파트') {
        return '직방은 아파트를 원룸·빌라·오피스텔 광고로 받지 않아요. 직방을 빼 주세요.';
      }
      if (values['trade'] == '매매' &&
          zigbangFormFor(values) == ZigbangForm.oneroom) {
        return '직방 원룸 광고는 전세·월세만 받아요. 매매는 방 2개 이상 빌라·오피스텔만 올릴 수 있어요.';
      }
      return null;
    case ListingPlatform.dabang:
    case ListingPlatform.daangn:
      return null;
  }
}

/// 비목 하나(정액 10만원 이상)의 값. 없으면 빈 지도.
Map<String, dynamic> feeItem(Map<String, dynamic> values, String item) {
  final detail = values['manageDetail'];
  if (detail is! Map) return const {};
  final entry = detail[item];
  return entry is Map ? Map<String, dynamic>.from(entry) : const {};
}

num? _amount(Map<String, dynamic> item) =>
    num.tryParse('${item['amount'] ?? ''}'.replaceAll(',', ''));

/// 정액 10만원 이상일 때 매달 정액으로 걷는 돈(원) — 공용 관리비(정액)·정액 사용료·
/// 기타 관리비를 더한 것.
num fixedFeeTotal(Map<String, dynamic> values) {
  var total = 0 as num;
  final common = feeItem(values, commonFeeItem);
  total += _amount(common) ?? 0;
  for (final item in usageFeeItems) {
    final entry = feeItem(values, item);
    if (entry['type'] == '정액') total += _amount(entry) ?? 0;
  }
  final etc = feeItem(values, etcFeeItem);
  if (etc['type'] == '있음') total += _amount(etc) ?? 0;
  return total;
}

/// 통합 폼을 통과하지 못하는 까닭들. 비었으면 두 플랫폼 모두 받는다.
///
/// [channels] 는 고른 플랫폼이다 — 플랫폼 하나만 걸리는 규칙(직방 아파트 등)은 그
/// 플랫폼을 골랐을 때만 막는다. 사진은 파일을 읽어야 해서 폼 화면이 따로 잰다.
List<String> listingViolations(
  Map<String, dynamic> values, {
  required Set<ListingPlatform> channels,
}) {
  final problems = <String>[];
  void need(String key) {
    final value = values[key];
    if (value == null ||
        (value is String && value.trim().isEmpty) ||
        (value is List && value.isEmpty)) {
      problems.add(fieldLabel(key));
    }
  }

  // ---- 칸이 비었는가 --------------------------------------------------------
  for (final key in [
    'propertyType',
    'address',
    'complexName',
    'building',
    'unit',
    'exclusiveArea',
    'supplyArea',
    'floorAll',
    'floor',
    'buildingUse',
    'approvalDate',
    'trade',
    'deposit',
    'monthlyRent',
    'salePrice',
    'shortTermMonths',
    'shortTermNegotiation',
    'loan',
    'manageMethod',
    'feeTier',
    'manageBasis',
    'manageBasisNote',
    'managementFee',
    'manageIncludes',
    'otherFeeReason',
    'otherFeeNote',
    'unknownFeeReason',
    'rooms',
    'bathrooms',
    'directionBase',
    'direction',
    'parking',
    'parkingCount',
    'parkingPerHousehold',
    'elevator',
    'violation',
    'loanAvailable',
    'petAllowed',
    'heating',
    'airconType',
    'moveInDate',
    'title',
    'description',
    'lh',
    'ownerPhone',
    'mediationMethod',
    'mediationNote',
    'ownerPhoneDuplicateNote',
    HifiField.householdCount,
    HifiField.structure,
    HifiField.duplex,
    HifiField.entranceType,
    HifiField.floorBand,
    HifiField.eContract,
    HifiField.monthlyParkingFee,
    HifiField.ownerName,
  ]) {
    if (fieldRequired(values, key)) need(key);
  }
  if (values['moveInImmediate'] != true && _blank(values, 'moveInDate')) {
    problems.add('입주가능일');
  }

  // ---- 채웠는데 두 곳 중 한 곳이 못 받는 값 -------------------------------------
  final type = values['propertyType'];
  if (!_blank(values, 'propertyType') && !propertyTypes.contains(type)) {
    problems.add('매물 종류를 다시 골라 주세요');
  }
  for (final (key, suffix, label) in [
    ('building', '동', '동'),
    ('unit', '호', '호'),
  ]) {
    if (!fieldVisible(values, key) || _blank(values, key)) continue;
    if (key == 'building' && values['singleBuilding'] == true) continue;
    final bare = bareUnit(values[key], suffix);
    if (!unitPattern.hasMatch(bare)) {
      problems.add('$label은 한글·영문·숫자만 쓸 수 있어요 (다방)');
    }
  }

  final exclusive = _number(values, 'exclusiveArea');
  final supply = _number(values, 'supplyArea');
  if (!_blank(values, 'exclusiveArea') &&
      (exclusive == null || exclusive <= 0 || !_decimals(exclusive, 2))) {
    problems.add('전용면적은 0보다 큰 수(소수 둘째 자리까지)로 적어 주세요');
  }
  if (!_blank(values, 'supplyArea') &&
      (supply == null || supply <= 0 || !_decimals(supply, 2))) {
    problems.add('공급면적은 0보다 큰 수(소수 둘째 자리까지)로 적어 주세요');
  }
  if (exclusive != null && supply != null && supply < exclusive) {
    problems.add('공급면적은 전용면적보다 작을 수 없어요');
  }

  final floorAll = int.tryParse(_text(values, 'floorAll'));
  if (!_blank(values, 'floorAll') &&
      (floorAll == null || floorAll < 1 || floorAll > maxFloorAll(values))) {
    problems.add('전체 층은 1~${maxFloorAll(values)}층으로 적어 주세요');
  }
  if (!_blank(values, 'floor') &&
      !floorChoices(values).contains(_text(values, 'floor'))) {
    problems.add(
      isComplexProperty(values)
          ? '해당 층은 1층부터 전체 층 사이로 골라 주세요 (오피스텔·아파트는 반지하·옥탑을 받지 않아요)'
          : '해당 층은 반지하·옥탑이나 전체 층 이하로 골라 주세요',
    );
  }

  if (isComplexProperty(values) &&
      !_blank(values, 'buildingUse') &&
      !complexBuildingUses.contains(values['buildingUse'])) {
    problems.add('오피스텔·아파트의 건축물 용도는 공동주택·업무시설·숙박시설 중 하나예요 (다방)');
  } else if (!_blank(values, 'buildingUse') &&
      !buildingUses.contains(values['buildingUse'])) {
    problems.add('건축물 법정 용도를 다시 골라 주세요');
  }

  if (!_blank(values, 'approvalDate')) {
    final approval = _date(values, 'approvalDate');
    if (approval == null) {
      problems.add('사용승인일은 YYYY-MM-DD 형식으로 적어 주세요');
    } else if (approval.isAfter(_today())) {
      problems.add('사용승인일은 오늘 이후일 수 없어요');
    }
  }
  // 총 세대수는 이제 선택이다(두 폼 다 별이 없다). 그래도 **적었다면** 숫자여야 한다 —
  // 필수 여부가 아니라 칸이 보이는지로 묻는다.
  if (fieldVisible(values, HifiField.householdCount) &&
      !_blank(values, HifiField.householdCount) &&
      !_positiveInt(values, HifiField.householdCount)) {
    problems.add('총 세대수는 1 이상의 정수로 적어 주세요');
  }

  // 가격 — 다방은 0 을 받지 않고(「입력값을 확인해주세요」), 만원 단위 정수만 받는다.
  for (final (key, label) in [
    ('deposit', '보증금'),
    ('monthlyRent', '월세'),
    ('salePrice', '매매 금액'),
  ]) {
    if (fieldVisible(values, key) &&
        !_blank(values, key) &&
        !_positiveInt(values, key)) {
      problems.add('$label은 1만원 이상의 정수(만원)로 적어 주세요');
    }
  }
  if (fieldVisible(values, 'loanAmount') &&
      !_blank(values, 'loanAmount') &&
      !_positiveInt(values, 'loanAmount')) {
    problems.add('융자금 금액은 1만원 이상의 정수(만원)로 적어 주세요');
  }

  _feeProblems(values, problems);

  final bathrooms = int.tryParse(_text(values, 'bathrooms'));
  if (!_blank(values, 'bathrooms') &&
      (bathrooms == null || bathrooms < 1 || bathrooms > 5)) {
    problems.add('욕실 수는 1~5개로 골라 주세요 (직방)');
  }
  if (!_blank(values, 'directionBase') &&
      !directionBases.contains(values['directionBase'])) {
    problems.add('방향 기준은 거실 기준과 안방 기준 중에서 골라 주세요');
  }
  if (fieldVisible(values, 'parkingCount') &&
      !_blank(values, 'parkingCount') &&
      !_positiveInt(values, 'parkingCount')) {
    problems.add('주차 가능 대수는 1 이상의 정수로 적어 주세요');
  }
  final perHousehold = _number(values, 'parkingPerHousehold');
  if (fieldVisible(values, 'parkingPerHousehold') &&
      !_blank(values, 'parkingPerHousehold') &&
      (perHousehold == null || perHousehold <= 0)) {
    problems.add('세대당 주차 대수는 0보다 큰 수로 적어 주세요');
  }

  if (fieldVisible(values, 'moveInDate') && !_blank(values, 'moveInDate')) {
    final moveIn = _date(values, 'moveInDate');
    if (moveIn == null) {
      problems.add('입주가능일은 YYYY-MM-DD 형식으로 적어 주세요');
    } else if (moveIn.isBefore(_today())) {
      problems.add('입주가능일은 오늘 이후로 골라 주세요 (다방)');
    }
  }
  final note = _text(values, HifiField.moveInNote);
  if (note.length > moveInNoteMaxLength) {
    problems.add('입주가능일 추가 설명은 최대 $moveInNoteMaxLength자예요 (직방)');
  }
  if (note.isNotEmpty && contactProblem(note) != null) {
    problems.add('입주가능일 추가 설명에 ${contactProblem(note)}를 넣을 수 없어요 (직방)');
  }

  final title = _text(values, 'title');
  if (title.isNotEmpty) {
    if (title.length < titleMinLength || title.length > titleMaxLength) {
      problems.add('매물 제목은 $titleMinLength~$titleMaxLength자로 적어 주세요');
    }
    if (!titlePattern.hasMatch(title)) {
      problems.add('매물 제목에는 한글·영문·숫자·쉼표·마침표만 쓸 수 있어요');
    }
  }
  final description = _text(values, 'description');
  if (description.isNotEmpty) {
    if (description.length < descriptionMinLength ||
        description.length > descriptionMaxLength) {
      problems.add(
        '매물 상세 설명은 $descriptionMinLength~$descriptionMaxLength자로 적어 주세요 '
        '(지금 ${description.length}자)',
      );
    }
    final contact = contactProblem(description);
    if (contact != null) {
      problems.add('매물 상세 설명에 $contact를 넣을 수 없어요 (직방)');
    }
    if (values['violation'] == '위반건축물 해당' && !description.contains('위반건축물')) {
      problems.add('위반건축물이면 상세 설명에 「위반건축물」이라고 적어야 해요 (다방)');
    }
  }
  if (_text(values, 'privateMemo').length > privateMemoMaxLength) {
    problems.add('내부 비밀 메모는 최대 $privateMemoMaxLength자예요 (직방)');
  }
  final duplicateNote = _text(values, 'ownerPhoneDuplicateNote');
  if (fieldVisible(values, 'ownerPhoneDuplicateNote') &&
      duplicateNote.isNotEmpty &&
      (duplicateNote.length < 5 || duplicateNote.length > 32)) {
    problems.add('중복 사유 내용은 5~32자로 적어 주세요 (직방)');
  }
  if (!_blank(values, 'ownerPhone') &&
      !RegExp(
        r'^010\d{7,8}$',
      ).hasMatch(ownerPhoneDigits(values['ownerPhone']))) {
    problems.add('연락처는 010으로 시작하는 휴대전화 번호로 적어 주세요 (직방)');
  }

  for (final platform in channels) {
    final blocker = platformBlocker(platform, values);
    if (blocker != null) problems.add(blocker);
  }
  return problems.toSet().toList();
}

void _feeProblems(Map<String, dynamic> values, List<String> problems) {
  if (values['noManagementFee'] == true) return;
  final method = values['manageMethod'];
  final tier = method == '정액 관리비' ? values['feeTier'] : null;
  final basisNote = _text(values, 'manageBasisNote');
  if (fieldVisible(values, 'manageBasisNote') && basisNote.length > 20) {
    problems.add('부과 기준 내용은 최대 20자예요 (직방)');
  }
  final otherNote = _text(values, 'otherFeeNote');
  if (fieldVisible(values, 'otherFeeNote') && otherNote.length > 20) {
    problems.add('기타 부과 근거 내용은 최대 20자예요 (직방)');
  }

  final fee = _number(values, 'managementFee');
  if (fieldVisible(values, 'managementFee') &&
      !_blank(values, 'managementFee')) {
    // 직방은 1,000원부터 받고, 원 단위 정수로 넣는다.
    if (fee == null || fee < 0.1 || !_decimals(fee, 1)) {
      problems.add('관리비 총액은 0.1만원(1,000원) 이상, 소수 첫째 자리까지 적어 주세요');
    } else if (tier == '10만원 미만' && fee >= 10) {
      problems.add('관리비가 10만원 이상이면 「10만원 이상」 구간을 골라 주세요');
    } else if (tier == '10만원 이상 (세부내역 미고지)' && fee < 10) {
      problems.add('관리비가 10만원 미만이면 「10만원 미만」 구간을 골라 주세요');
    }
  }

  if (tier != '10만원 이상') return;
  final common = feeItem(values, commonFeeItem);
  final commonAmount = _amount(common);
  if (!commonFeeWays.contains(common['type']) ||
      commonAmount == null ||
      commonAmount < 1000 ||
      commonAmount != commonAmount.roundToDouble()) {
    problems.add('일반(공용) 관리비의 부과 방식과 금액(1,000원 이상)');
  }
  for (final item in usageFeeItems) {
    final entry = feeItem(values, item);
    if (!feeItemWays.contains(entry['type'])) {
      problems.add('$item 관리비의 부과 방식');
      continue;
    }
    final amount = _amount(entry);
    if (entry['type'] == '정액' &&
        (amount == null || amount < 1 || amount != amount.roundToDouble())) {
      problems.add('$item 관리비 금액(원)');
    }
  }
  final etc = feeItem(values, etcFeeItem);
  if (etc['type'] != '없음' && etc['type'] != '있음') {
    problems.add('기타 관리비 여부');
  } else if (etc['type'] == '있음') {
    final what = '${etc['note'] ?? ''}'.trim();
    final amount = _amount(etc);
    if (what.isEmpty || what.length > 20) {
      problems.add('기타 관리비 내용(최대 20자)');
    }
    if (amount == null || amount < 1000 || amount != amount.roundToDouble()) {
      problems.add('기타 관리비 금액(1,000원 이상)');
    }
  }
  if (fixedFeeTotal(values) < 100000) {
    problems.add('정액으로 걷는 관리비가 10만원 미만이면 「10만원 미만」 구간을 골라 주세요');
  }
}

/// 예전 통합 폼의 이름 → 지금 다방 목록의 이름(건축물 용도).
const _legacyUses = {
  '노유자시설': '노유자(노인 및 어린이 시설)',
  '위험물저장 및 처리시설': '위험물 저장 및 처리 시설',
  '자동차관련시설': '자동차 관련 시설',
  '동물 및 식물관련시설': '동물 및 식물 관련 시설',
  '자원순환관련시설': '자원순환 관련 시설',
  '교정 및 군사시설': '교정 및 군사 시설',
  '묘지관련시설': '묘지 관련 시설',
  '관광휴게시설': '관광 휴게시설',
  '야영장시설': '야영장 시설',
};

/// 예전 관리비 포함 항목 → 지금 여덟 비목.
const _legacyIncludes = {
  '청소비': '일반(공용) 관리비',
  '승강기유지비': '일반(공용) 관리비',
  '주차비': '일반(공용) 관리비',
  '경비비': '일반(공용) 관리비',
  '전기료': '전기',
  '수도료': '수도',
  '가스사용료': '가스',
  '난방비': '난방',
  '인터넷': '인터넷',
  '유선TV': 'TV',
  '기타': '기타 관리비',
};

/// 예전 통합 폼으로 저장해 둔 매물을 지금의 말로 옮긴다 — 102 의 수정으로 다시 열 때.
///
/// 옮길 수 없는 값(「주실 기준」, 금액만 있는 융자금처럼 두 플랫폼이 받지 못하던 것)은
/// 지운다. 빈칸은 폼이 다시 물어보지만, 틀린 값은 아무도 다시 묻지 않는다.
void migrateLegacyValues(Map<String, dynamic> values) {
  const legacyTypes = <String, (String, String, String?, String?)>{
    '오픈형 원룸': ('빌라/연립/다세대', '1', '오픈형', '단층'),
    '분리형 원룸': ('빌라/연립/다세대', '1', '분리형', '단층'),
    '복층형 원룸': ('빌라/연립/다세대', '1', null, '복층'),
    '투룸 빌라': ('빌라/연립/다세대', '2', null, null),
    '쓰리룸 이상 빌라': ('빌라/연립/다세대', '3', null, null),
    '오피스텔 원룸형': ('오피스텔', '1', null, null),
    '오피스텔 분리/투룸형': ('오피스텔', '2', null, null),
  };
  final type = values['propertyType'];
  final legacy = legacyTypes[type];
  if (legacy != null) {
    final (kind, rooms, structure, duplex) = legacy;
    values['propertyType'] = kind;
    values.putIfAbsent('rooms', () => rooms);
    if (structure != null) {
      values.putIfAbsent(HifiField.structure, () => structure);
    }
    if (duplex != null) values.putIfAbsent(HifiField.duplex, () => duplex);
  } else if (type != null && !propertyTypes.contains(type)) {
    values.remove('propertyType');
  }
  if (values['trade'] == '단기') {
    values['trade'] = '월세';
    values['shortTerm'] = true;
  }
  if (values['trade'] != '월세') values.remove('shortTerm');
  if (!directionBases.contains(values['directionBase'])) {
    values.remove('directionBase');
  }
  if (values['bathrooms'] == '3 이상') values['bathrooms'] = '3';
  if (values['floor'] == '지하 1층') values.remove('floor');
  if (!loanOptions.contains(values['loan'])) {
    values.remove('loan');
    values.remove('loanAmount');
  }
  final use = values['buildingUse'];
  if (_legacyUses.containsKey(use)) values['buildingUse'] = _legacyUses[use];
  final includes = values['manageIncludes'];
  if (includes is List) {
    values['manageIncludes'] = {
      for (final item in includes)
        if (manageFeeItems.contains(item)) '$item' else ?_legacyIncludes[item],
    }.toList();
  }
  final detail = values['manageDetail'];
  if (detail is Map && detail.values.any((entry) => entry is! Map)) {
    values.remove('manageDetail');
  }
  if (values['manageMethod'] == '정액 관리비' && values['feeTier'] == null) {
    final fee = num.tryParse('${values['managementFee'] ?? ''}');
    if (fee != null && fee < 10) values['feeTier'] = '10만원 미만';
  }
  if (values['otherFeeReason'] == '의뢰인 미고지') values.remove('otherFeeReason');
  values['unknownFeeReason'] = switch (values['unknownFeeReason']) {
    '상가 및 상가주택 사유' => '상가 건물 사유',
    '미등기 건물 사유' => '미등기·신축 건물 사유',
    final other => other,
  };
  if (values['unknownFeeReason'] == null) values.remove('unknownFeeReason');
  if (values['moveInType'] == '협의 가능') {
    values.remove('moveInType');
    values['moveInNegotiable'] = true;
  }
  final note = '${values[HifiField.moveInNote] ?? ''}';
  if (note.length > moveInNoteMaxLength) values.remove(HifiField.moveInNote);
}

/// 당근 어댑터에 줄 값 — 당근은 잠시 내려 둔 동안 **예전 통합 폼의 말**을 그대로
/// 쓴다(「오픈형 원룸」·「투룸 빌라」, 「수도료」·「유선TV」…). 지금 통합 폼의 값을 그
/// 말로 옮겨 건넨다. 당근을 다시 켤 때 어댑터를 새 말로 옮기면 이 함수는 지우면 된다.
Map<String, dynamic> legacyDaangnValues(Map<String, dynamic> source) {
  final values = Map<String, dynamic>.from(source);
  final rooms = roomCount(source);
  values['propertyType'] = switch (source['propertyType']) {
    '빌라/연립/다세대' when rooms >= 3 => '쓰리룸 이상 빌라',
    '빌라/연립/다세대' when rooms == 2 => '투룸 빌라',
    '빌라/연립/다세대' => source['roomLayout'] ?? '오픈형 원룸',
    '오피스텔' when rooms >= 2 => '오피스텔 분리/투룸형',
    '오피스텔' => '오피스텔 원룸형',
    final other => other,
  };
  final legacyUse = {
    for (final entry in _legacyUses.entries) entry.value: entry.key,
  };
  final use = source['buildingUse'];
  if (legacyUse.containsKey(use)) values['buildingUse'] = legacyUse[use];
  const includes = {
    '일반(공용) 관리비': '청소비',
    '전기': '전기료',
    '수도': '수도료',
    '가스': '가스사용료',
    '난방': '난방비',
    '인터넷': '인터넷',
    'TV': '유선TV',
    '기타 관리비': '기타',
  };
  final list = source['manageIncludes'];
  if (list is List) {
    values['manageIncludes'] = [
      for (final item in list) includes[item] ?? item,
    ];
  }
  if (source['feeTier'] == '10만원 이상') {
    values['managementFee'] = '${fixedFeeTotal(source) / 10000}';
    values['manageDetail'] = {
      for (final item in usageFeeItems)
        includes[item]!: switch (feeItem(source, item)['type']) {
          '정액' => '정액 부과',
          '실비' => '실비 부과',
          _ => '해당 없음',
        },
      '기타': feeItem(source, etcFeeItem)['type'] == '있음' ? '정액 부과' : '해당 없음',
    };
  }
  values['unknownFeeReason'] = switch (source['unknownFeeReason']) {
    '상가 건물 사유' => '상가 및 상가주택 사유',
    '미등기·신축 건물 사유' => '미등기 건물 사유',
    final other => other,
  };
  return values;
}
