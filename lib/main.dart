import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const ListingPrototypeApp());

class ListingPrototypeApp extends StatelessWidget {
  const ListingPrototypeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Used only by the local simulator verification command. It keeps the
    // production/default entry point on the master form.
    final automationPreview = const bool.fromEnvironment('AUTOMATION_PREVIEW');
    final autoPayload = {
      for (final field in groups.expand((group) => group.fields))
        field.key: field.example,
    };
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '통합 매물 등록 테스트',
      theme: ThemeData(colorSchemeSeed: Colors.orange, useMaterial3: true),
      home: automationPreview
          ? ZigbangPreviewPage(payload: autoPayload)
          : const MasterListingFormPage(),
    );
  }
}

enum InputType { text, longText, date, number, select, multiSelect, file }

class FieldSpec {
  const FieldSpec({
    required this.key,
    required this.label,
    required this.required,
    required this.type,
    required this.example,
    this.options = const [],
    this.hint,
    this.visibleWhenKey,
    this.visibleWhenValue,
  });
  final String key;
  final String label;
  final bool required;
  final InputType type;
  final String example;
  final List<String> options;
  final String? hint;

  /// Makes a supporting input appear only when another select has this value.
  /// This is used for the recreated Zigbang form's conditional inputs.
  final String? visibleWhenKey;
  final String? visibleWhenValue;
}

class FieldGroup {
  const FieldGroup(this.name, this.fields);
  final String name;
  final List<FieldSpec> fields;
}

const groups = <FieldGroup>[
  FieldGroup('기본 정보', [
    FieldSpec(
      key: 'address',
      label: '주소',
      required: true,
      type: InputType.text,
      example: '서울특별시 강남구 테헤란로 123',
    ),
    FieldSpec(
      key: 'dong',
      label: '동',
      required: true,
      type: InputType.number,
      example: '101',
    ),
    FieldSpec(
      key: 'ho',
      label: '호',
      required: true,
      type: InputType.number,
      example: '301',
    ),
    FieldSpec(
      key: 'singleBuilding',
      label: '단일동 건물 여부',
      required: false,
      type: InputType.select,
      example: '아니오',
      options: ['아니오', '예'],
    ),
    FieldSpec(
      key: 'buildingUse',
      label: '건축물 법정 용도',
      required: true,
      type: InputType.select,
      example: '공동주택',
      options: ['공동주택', '단독주택', '제1종 근린생활시설', '제2종 근린생활시설', '업무시설', '기타'],
    ),
    FieldSpec(
      key: 'approvalDate',
      label: '사용승인일',
      required: true,
      type: InputType.date,
      example: '2020-05-15',
    ),
    FieldSpec(
      key: 'totalFamilies',
      label: '총 세대수',
      required: false,
      type: InputType.number,
      example: '24',
    ),
    FieldSpec(
      key: 'violation',
      label: '위반건축물 해당 여부',
      required: true,
      type: InputType.select,
      example: '해당 없음',
      options: ['해당 없음', '해당 있음'],
    ),
  ]),
  FieldGroup('거래 및 가격 정보', [
    FieldSpec(
      key: 'deposit',
      label: '보증금 (만원)',
      required: true,
      type: InputType.number,
      example: '1000',
    ),
    FieldSpec(
      key: 'monthlyRent',
      label: '월세 금액 (만원)',
      required: true,
      type: InputType.number,
      example: '65',
    ),
    FieldSpec(
      key: 'loan',
      label: '융자금 세부 금액 및 비율',
      required: false,
      type: InputType.text,
      example: '융자금 없음',
    ),
    FieldSpec(
      key: 'moveIn',
      label: '입주가능일',
      required: true,
      type: InputType.select,
      example: '즉시 입주',
      options: ['즉시 입주', '날짜 협의'],
    ),
    FieldSpec(
      key: 'moveInDetail',
      label: '입주가능일 추가 설명란',
      required: false,
      type: InputType.text,
      example: '5월 말 퇴거 예정 협의 가능',
    ),
    FieldSpec(
      key: 'digitalContract',
      label: '전자계약 가능 여부',
      required: false,
      type: InputType.select,
      example: '가능',
      options: ['가능', '불가능'],
    ),
    FieldSpec(
      key: 'lhLease',
      label: 'LH 전세임대 여부',
      required: true,
      type: InputType.select,
      example: '불가능',
      options: ['불가능', '가능'],
      hint: '명세상 기본값은 불가능입니다.',
    ),
  ]),
  FieldGroup('공간 및 건물 구조', [
    FieldSpec(
      key: 'exclusiveArea',
      label: '전용면적 (㎡)',
      required: true,
      type: InputType.number,
      example: '23.14',
    ),
    FieldSpec(
      key: 'supplyArea',
      label: '공급면적 (㎡)',
      required: false,
      type: InputType.number,
      example: '29.75',
    ),
    FieldSpec(
      key: 'buildingFloor',
      label: '전체 층수',
      required: true,
      type: InputType.select,
      example: '5',
      options: ['1', '2', '3', '4', '5', '10', '15', '20', '30', '50'],
    ),
    FieldSpec(
      key: 'floor',
      label: '해당 층수',
      required: true,
      type: InputType.select,
      example: '3',
      options: ['반지하', '1', '2', '3', '4', '5', '옥탑'],
    ),
    FieldSpec(
      key: 'floorBand',
      label: '층군 구분',
      required: false,
      type: InputType.select,
      example: '중층',
      options: ['저층', '중층', '고층'],
    ),
    FieldSpec(
      key: 'roomLayout',
      label: '방 수 및 원룸 구조',
      required: true,
      type: InputType.select,
      example: '1개 / 분리형',
      options: ['1개 / 오픈형', '1개 / 분리형', '2개', '3개', '4개 이상'],
    ),
    FieldSpec(
      key: 'duplex',
      label: '복층 여부',
      required: true,
      type: InputType.select,
      example: '단층',
      options: ['단층', '복층'],
    ),
    FieldSpec(
      key: 'bathrooms',
      label: '욕실 수',
      required: true,
      type: InputType.select,
      example: '1',
      options: ['1', '2', '3개 이상'],
    ),
    FieldSpec(
      key: 'direction',
      label: '주실 방향',
      required: true,
      type: InputType.select,
      example: '남향',
      options: ['남향', '동향', '서향', '북향', '남동향', '남서향', '북동향', '북서향'],
    ),
    FieldSpec(
      key: 'entrance',
      label: '현관 구조 유형',
      required: false,
      type: InputType.select,
      example: '복도식',
      options: ['복도식', '계단식', '기타'],
    ),
  ]),
  FieldGroup('관리비 정보', [
    FieldSpec(
      key: 'manageMethod',
      label: '관리비 부과 방식',
      required: true,
      type: InputType.select,
      example: '정액 관리비',
      options: ['정액 관리비', '기타', '확인 불가'],
    ),
    FieldSpec(
      key: 'manageCost',
      label: '기본 관리비 금액 (만원)',
      required: true,
      type: InputType.number,
      example: '5',
    ),
    FieldSpec(
      key: 'manageBasis',
      label: '관리비 부과 기준',
      required: true,
      type: InputType.select,
      example: '직전월 관리비 기준',
      options: ['직전월 관리비 기준', '최근 3개월 관리비 평균', '최근 1년 관리비 평균', '직접 입력'],
    ),
    FieldSpec(
      key: 'manageIncludes',
      label: '관리비 포함 비목',
      required: true,
      type: InputType.multiSelect,
      example: '수도료, 가스 사용료, 인터넷 사용료',
      options: [
        '일반(공용) 관리비',
        '전기료',
        '수도료',
        '가스 사용료',
        '난방비',
        '인터넷 사용료',
        'TV 사용료',
        '기타 관리비',
      ],
    ),
  ]),
  FieldGroup('시설 및 옵션 정보', [
    FieldSpec(
      key: 'parking',
      label: '주차 가능 여부 및 대수',
      required: true,
      type: InputType.text,
      example: '가능 / 총 12대',
    ),
    FieldSpec(
      key: 'elevator',
      label: '엘리베이터 유무',
      required: true,
      type: InputType.select,
      example: '있음',
      options: ['있음', '없음'],
    ),
    FieldSpec(
      key: 'pets',
      label: '반려동물 허용 여부',
      required: true,
      type: InputType.select,
      example: '허용',
      options: ['허용', '불가'],
    ),
    FieldSpec(
      key: 'leaseLoan',
      label: '전세자금대출 가능 여부',
      required: true,
      type: InputType.select,
      example: '가능',
      options: ['가능', '불가능'],
    ),
    FieldSpec(
      key: 'appliances',
      label: '기본 가전 옵션',
      required: false,
      type: InputType.multiSelect,
      example: '냉장고, 세탁기, 에어컨',
      options: ['에어컨', '냉장고', '세탁기', '가스레인지', '인덕션'],
    ),
    FieldSpec(
      key: 'microwave',
      label: '추가 가전 전자레인지',
      required: false,
      type: InputType.select,
      example: '있음',
      options: ['있음', '없음'],
    ),
    FieldSpec(
      key: 'furniture',
      label: '가구 및 수납 옵션',
      required: false,
      type: InputType.multiSelect,
      example: '침대, 옷장, 책상',
      options: ['책상', '책장', '침대', '옷장', '신발장', '싱크대'],
    ),
    FieldSpec(
      key: 'security',
      label: '보안 및 부대시설',
      required: false,
      type: InputType.multiSelect,
      example: 'CCTV',
      options: ['CCTV'],
    ),
    FieldSpec(
      key: 'hvac',
      label: '세부 난방 및 냉방 방식',
      required: false,
      type: InputType.multiSelect,
      example: '에어컨',
      hint: '재현 직방 폼에서 선택 가능한 냉방 옵션입니다.',
      options: ['에어컨'],
    ),
    FieldSpec(
      key: 'evCharging',
      label: '전기차 충전 설비',
      required: false,
      type: InputType.select,
      example: '없음',
      options: ['있음', '없음'],
    ),
  ]),
  FieldGroup('매물 소개', [
    FieldSpec(
      key: 'photos',
      label: '매물 사진',
      required: true,
      type: InputType.file,
      example: 'room-1.jpg, room-2.jpg',
      hint: '테스트 단계에서는 파일명 또는 설명을 입력합니다.',
    ),
    FieldSpec(
      key: 'floorPlan',
      label: '평면도 이미지',
      required: false,
      type: InputType.file,
      example: 'floor-plan.jpg',
    ),
    FieldSpec(
      key: 'virtualTour',
      label: '360도 가상현실 파노라마 사진',
      required: false,
      type: InputType.file,
      example: 'tour-360.jpg',
    ),
    FieldSpec(
      key: 'video',
      label: '동영상 파일',
      required: false,
      type: InputType.file,
      example: 'room-tour.mp4',
    ),
    FieldSpec(
      key: 'title',
      label: '매물 제목',
      required: true,
      type: InputType.text,
      example: '강남역 도보 5분, 깔끔한 분리형 원룸',
    ),
    FieldSpec(
      key: 'description',
      label: '매물 상세 설명',
      required: true,
      type: InputType.longText,
      example: '남향의 밝은 분리형 원룸입니다. 풀옵션이며 즉시 입주 가능합니다.',
    ),
    FieldSpec(
      key: 'tags',
      label: '관심 태그',
      required: false,
      type: InputType.select,
      example: 'A',
      hint: '재현 HTML의 익명화된 태그 코드입니다.',
      options: [
        '선택안함',
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
        'G',
        'H',
        'I',
        'J',
        'K',
        'L',
        'M',
        'N',
        'O',
        'P',
        'Q',
        'R',
        'S',
        'T',
        'U',
        'V',
        'W',
        'X',
        'Y',
      ],
    ),
  ]),
  FieldGroup('의뢰인 및 관리 정보', [
    FieldSpec(
      key: 'lessor',
      label: '임대인 성함 및 연락처',
      required: true,
      type: InputType.text,
      example: '김임대 / 010-1234-5678',
    ),
    FieldSpec(
      key: 'mediation',
      label: '중개 수임 경로',
      required: false,
      type: InputType.select,
      example: '전화로 확인',
      options: ['전화로 확인', '만나서 확인', '기타 방법으로 확인'],
    ),
    FieldSpec(
      key: 'mediationDetail',
      label: '기타 중개 수임 경로 상세',
      required: false,
      type: InputType.text,
      example: '지인 소개로 확인',
      hint: '기타 방법으로 확인을 선택한 경우에만 입력합니다.',
      visibleWhenKey: 'mediation',
      visibleWhenValue: '기타 방법으로 확인',
    ),
    FieldSpec(
      key: 'secretMemo',
      label: '내부 비밀 메모',
      required: false,
      type: InputType.longText,
      example: '집주인 연락 가능 시간: 평일 오후',
    ),
  ]),
];

class MasterListingFormPage extends StatefulWidget {
  const MasterListingFormPage({super.key});
  @override
  State<MasterListingFormPage> createState() => _MasterListingFormPageState();
}

class _MasterListingFormPageState extends State<MasterListingFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  List<FieldSpec> get _fields =>
      groups.expand((group) => group.fields).toList();
  bool _isVisible(FieldSpec field) =>
      field.visibleWhenKey == null ||
      _controllers[field.visibleWhenKey]!.text == field.visibleWhenValue;
  bool get _canSubmit => _fields
      .where((field) => field.required)
      .every((field) => _controllers[field.key]!.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in _fields)
        field.key: TextEditingController(
          text: field.key == 'lhLease' ? '불가능' : '',
        ),
    };
    for (final controller in _controllers.values) {
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _autoFill() {
    for (final field in _fields) {
      _controllers[field.key]!.text = field.example;
    }
  }

  Map<String, String> get _payload => {
    for (final field in _fields)
      field.key: _controllers[field.key]!.text.trim(),
  };
  void _sendToZigbang() {
    if (_canSubmit && (_formKey.currentState?.validate() ?? false)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ZigbangPreviewPage(payload: _payload),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('통합 매물 입력'),
      actions: [TextButton(onPressed: _autoFill, child: const Text('자동 채우기'))],
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '테스트용 마스터 폼 · ${_fields.length}개 항목',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '필수 29개를 모두 입력하면 직방 전송 버튼이 활성화됩니다.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ...groups.map(_buildGroup),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _canSubmit ? _sendToZigbang : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('직방에 보내기'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );

  Widget _buildGroup(FieldGroup group) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 10),
          ...group.fields.where(_isVisible).map(_buildField),
        ],
      ),
    ),
  );

  Widget _buildField(FieldSpec field) {
    final label = '${field.label}${field.required ? ' *' : ' (선택)'}';
    final controller = _controllers[field.key]!;
    final decoration = InputDecoration(
      labelText: label,
      hintText: field.hint,
      border: const OutlineInputBorder(),
      isDense: true,
    );
    if (field.type == InputType.select) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          key: ValueKey('${field.key}-${controller.text}'),
          initialValue: controller.text.isEmpty ? null : controller.text,
          decoration: decoration,
          items: field.options
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              )
              .toList(),
          onChanged: (value) => controller.text = value ?? '',
          validator: field.required
              ? (value) =>
                    (value == null || value.isEmpty) ? '필수 입력 항목입니다.' : null
              : null,
        ),
      );
    }
    if (field.type == InputType.multiSelect) {
      final selected = controller.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InputDecorator(
          decoration: decoration.copyWith(
            helperText: '복수 선택 가능',
            errorText: field.required && selected.isEmpty
                ? '필수 입력 항목입니다.'
                : null,
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: field.options
                .map(
                  (option) => FilterChip(
                    label: Text(option),
                    selected: selected.contains(option),
                    onSelected: (isSelected) {
                      final next = {...selected};
                      if (isSelected) {
                        next.add(option);
                      } else {
                        next.remove(option);
                      }
                      controller.text = field.options
                          .where(next.contains)
                          .join(', ');
                    },
                  ),
                )
                .toList(),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: field.type == InputType.number
            ? const TextInputType.numberWithOptions(decimal: true)
            : field.type == InputType.date
            ? TextInputType.datetime
            : TextInputType.text,
        minLines: field.type == InputType.longText ? 3 : 1,
        maxLines: field.type == InputType.longText ? 5 : 1,
        decoration: decoration.copyWith(
          helperText: field.type == InputType.file ? '테스트용: 파일명/설명 입력' : null,
        ),
        validator: field.required
            ? (value) =>
                  value == null || value.trim().isEmpty ? '필수 입력 항목입니다.' : null
            : null,
      ),
    );
  }
}

class ZigbangPreviewPage extends StatefulWidget {
  const ZigbangPreviewPage({super.key, required this.payload});
  final Map<String, String> payload;
  @override
  State<ZigbangPreviewPage> createState() => _ZigbangPreviewPageState();
}

class _ZigbangPreviewPageState extends State<ZigbangPreviewPage> {
  late final WebViewController _webViewController;
  String _status = '직방 재현 페이지를 불러오는 중…';
  bool _isSuccess = false;
  bool _injectionStarted = false;
  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ListingInjectionResult',
        onMessageReceived: _handleInjectionMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _injectPayload()),
      )
      ..loadFlutterAsset('assets/zigbang/zigbang_listing_form.html');
  }

  void _handleInjectionMessage(JavaScriptMessage message) {
    try {
      final result = jsonDecode(message.message) as Map<String, dynamic>;
      if (result['phase'] == 'probe') {
        if (!mounted) return;
        setState(() {
          _status = result['available'] == true
              ? '직방 재현 폼 연결 확인됨. 정보를 입력하는 중…'
              : '실패: 직방 재현 페이지의 주입 함수를 찾지 못했습니다.';
        });
        return;
      }
      final applied = (result['applied'] as List<dynamic>? ?? const []).length;
      final missing = (result['missing'] as List<dynamic>? ?? const []).length;
      final unsupported =
          (result['unsupported'] as List<dynamic>? ?? const []).length;
      if (!mounted) return;
      setState(() {
        _isSuccess = result['ok'] == true;
        _status = _isSuccess
            ? '성공: 직방 재현 폼에 $applied개 값을 입력했습니다. '
                  '(재현 폼 미지원 $unsupported개, 대상 누락 $missing개)'
            : '실패: ${result['error'] ?? '입력 가능한 대상이 부족합니다.'} '
                  '(적용 $applied개, 대상 누락 $missing개, 미지원 $unsupported개)';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _status = '실패: 웹뷰 결과 해석 오류 — $error');
      }
    }
  }

  Future<void> _injectPayload() async {
    if (_injectionStarted) return;
    _injectionStarted = true;
    try {
      // A local SingleFile page can signal page-finished before its large inline
      // script has completed on WKWebView. Do not ask WKWebView to return a
      // value: the page posts a serialised result through ListingInjectionResult.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _webViewController.runJavaScript('''
        (() => {
          const send = (message) => ListingInjectionResult.postMessage(JSON.stringify(message));
          const available = typeof window.fillListingForm === 'function';
          send({phase: 'probe', arithmetic: 1 + 1, available: available});
          try {
            if (!available) {
              send({phase: 'result', ok: false, applied: [], missing: [], unsupported: [], error: 'fillListingForm is unavailable'});
              return;
            }
            const result = window.fillListingForm(${jsonEncode(widget.payload)});
            result.phase = 'result';
            send(result);
          } catch (error) {
            send({phase: 'result', ok: false, applied: [], missing: [], unsupported: [], error: String(error)});
          }
        })()
      ''');
    } catch (error) {
      if (mounted) setState(() => _status = '실패: 웹뷰 주입 오류 — $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      title: const Text('직방 폼 입력 결과'),
    ),
    body: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: _isSuccess ? Colors.green.shade50 : Colors.orange.shade50,
          child: Row(
            children: [
              Icon(
                _isSuccess ? Icons.check_circle : Icons.info_outline,
                color: _isSuccess ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_status)),
            ],
          ),
        ),
        Expanded(child: WebViewWidget(controller: _webViewController)),
      ],
    ),
  );
}
