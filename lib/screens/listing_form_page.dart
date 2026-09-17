import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../fields.dart';
import '../kakao_address.dart';
import '../models/listing.dart';
import 'publish_flow_page.dart';

/// 201 광고 입력 폼 — one long page in the hi-fi's seven sections, ending in
/// 플랫폼 선택 and the 광고 등록 CTA.
///
/// The sections are the hi-fi's; the data underneath is still the 50 master
/// rows the mirror adapters read (plus the hi-fi's own extras, see
/// [HifiField]). Where the hi-fi draws one control for what the master keeps as
/// two rows — 구조 + 복층 여부 → 방 구조, 입주가능일 + its checkboxes → 입주 방식 —
/// the form writes both.
class ListingFormPage extends StatefulWidget {
  const ListingFormPage({
    super.key,
    this.store,
    this.initial,
    this.pickImages,
    this.remotePageBuilder,
  });

  final AppStore? store;

  /// Set when 102's 수정 reopens an existing record.
  final Listing? initial;

  /// Lets tests supply photos without the system picker.
  final Future<List<XFile>> Function()? pickImages;

  /// Lets tests put their own widget where the platform page would be.
  final RemotePageBuilder? remotePageBuilder;

  @override
  State<ListingFormPage> createState() => _ListingFormPageState();
}

class _ListingFormPageState extends State<ListingFormPage> {
  final values = <String, dynamic>{};
  final _controllers = <String, TextEditingController>{};
  final photos = <XFile>[];
  final _channels = <ListingPlatform>{};

  bool _pickingPhotos = false;
  String? _photoError;
  bool _showMissing = false;

  static final _masterFields = {
    for (final field in groups.expand((group) => group.fields))
      field.key: field,
  };

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      values.addAll(initial.values);
      photos.addAll(initial.photoPaths.map(XFile.new));
      _channels.addAll(initial.channels.keys);
    }
    final linked = widget.store?.linked ?? const <ListingPlatform>{};
    if (_channels.isEmpty) {
      _channels.addAll(linked.isEmpty ? ListingPlatform.values : linked);
    }
    // The hi-fi only asks for 주실 방향 and only offers a "주차 불가" box, so
    // the master rows behind them start from those readings.
    values.putIfAbsent('directionBase', () => '주실 기준');
    values.putIfAbsent('trade', () => '월세');
    values.putIfAbsent('parking', () => '주차 가능');
    _deriveFromMaster();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Fills the hi-fi-only controls from master rows (for 수정 and 자동 채우기).
  void _deriveFromMaster() {
    final layout = '${values['roomLayout'] ?? ''}';
    if (layout.isNotEmpty) {
      values[HifiField.duplex] = layout.startsWith('복층') ? '복층' : '단층';
      if (!layout.startsWith('복층')) {
        values[HifiField.structure] = layout.startsWith('분리') ? '분리형' : '오픈형';
      }
      values[HifiField.structure] ??= '오픈형';
    }
    if (values['moveInType'] != null) {
      values['moveInImmediate'] ??= values['moveInType'] == '즉시 입주';
      values['moveInNegotiable'] ??= values['moveInType'] == '협의 가능';
    }
    final facilities = values['facilities'];
    if (facilities is List && values[HifiField.evCharger] == null) {
      values[HifiField.evCharger] = facilities.contains(evChargerFacility)
          ? '있음'
          : '없음';
    }
  }

  String _text(String key) => '${values[key] ?? ''}'.trim();
  bool _blank(String key) => _text(key).isEmpty;

  void _set(String key, Object? value) {
    setState(() {
      if (value == null || (value is String && value.isEmpty)) {
        values.remove(key);
      } else {
        values[key] = value;
      }
      _sync(key);
    });
  }

  /// Keeps the master rows in step with the hi-fi controls that feed them.
  void _sync(String key) {
    switch (key) {
      case HifiField.structure || HifiField.duplex:
        final layout = roomLayoutFrom(
          structure: values[HifiField.structure] as String?,
          duplex: values[HifiField.duplex] as String?,
        );
        if (layout == null) {
          values.remove('roomLayout');
        } else {
          values['roomLayout'] = layout;
        }
      case HifiField.evCharger:
        final list = List<String>.from(values['facilities'] as List? ?? []);
        list.remove(evChargerFacility);
        if (values[key] == '있음') list.add(evChargerFacility);
        values['facilities'] = list;
      case 'moveInDate' || 'moveInNegotiable' || 'moveInImmediate':
        if (values['moveInImmediate'] == true) {
          values['moveInType'] = '즉시 입주';
        } else if (!_blank('moveInDate')) {
          values['moveInType'] = '날짜 지정';
        } else if (values['moveInNegotiable'] == true) {
          values['moveInType'] = '협의 가능';
        } else {
          values.remove('moveInType');
        }
      case 'loanAmount':
        if (!_blank('loanAmount')) values['loan'] = '있음';
    }
  }

  TextEditingController _controller(String key) => _controllers.putIfAbsent(
    key,
    () => TextEditingController(text: _text(key)),
  );

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
            for (final fee in manageFeeItems)
              fee: (values['manageIncludes'] as List? ?? const []).contains(fee)
                  ? '정액 부과'
                  : '실비 부과',
          };
        case InputType.addressSearch:
          values[field.key] = field.example;
          values['roadAddress'] = field.example;
          // Drop details left over from an earlier real search.
          values.remove('jibunAddress');
          values.remove('buildingName');
          values['postalCode'] = '06236';
          values['legalDongCode'] = '1168010100';
        case InputType.photoPicker:
          values[field.key] = photos.length;
        default:
          values[field.key] = field.example;
      }
    }
    for (final entry in HifiField.examples.entries) {
      final example = entry.value;
      values[entry.key] = example is List
          ? List<String>.of(example.cast())
          : example;
    }
    values['moveInImmediate'] = values['moveInType'] == '즉시 입주';
    // An immediate move-in has no date; leaving the example in would show a
    // date in a field the form has switched off.
    if (values['moveInImmediate'] == true) values.remove('moveInDate');
    values.remove(HifiField.structure);
    _deriveFromMaster();
    _sync(HifiField.evCharger);
    for (final entry in _controllers.entries) {
      entry.value.text = _text(entry.key);
    }
    setState(() => _showMissing = false);
  }

  bool _visible(String key) {
    final trade = values['trade'];
    final rent = trade == '월세' || trade == '전세';
    final fee = values['noManagementFee'] != true;
    final fixed = fee && values['manageMethod'] == '정액 관리비';
    return switch (key) {
      'deposit' || 'lh' => rent,
      'monthlyRent' => trade == '월세',
      'salePrice' => trade == '매매',
      'manageMethod' => fee,
      'manageBasis' || 'managementFee' || 'manageIncludes' => fixed,
      'manageDetail' =>
        fixed && (num.tryParse(_text('managementFee')) ?? 0) >= 10,
      'otherFeeReason' => fee && values['manageMethod'] == '기타 부과',
      'unknownFeeReason' => fee && values['manageMethod'] == '확인 불가',
      'parkingCount' ||
      HifiField.monthlyParkingFee ||
      'parkingPerHousehold' => values['parking'] == '주차 가능',
      _ => true,
    };
  }

  /// Whether a row gets the red asterisk right now.
  bool _required(String key) {
    if (!_visible(key)) return false;
    return switch (key) {
      'building' => values['singleBuilding'] != true,
      'deposit' || 'lh' || 'monthlyRent' || 'salePrice' => true,
      'manageBasis' || 'managementFee' || 'manageIncludes' => true,
      'moveInDate' => values['moveInImmediate'] != true,
      'parkingCount' || HifiField.monthlyParkingFee => true,
      HifiField.ownerName ||
      'ownerPhone' ||
      HifiField.structure ||
      HifiField.duplex => true,
      'moveInType' => false,
      _ => _masterFields[key]?.required ?? false,
    };
  }

  List<String> _violations() {
    final violations = <String>[];
    for (final field in groups.expand((g) => g.fields)) {
      if (!_visible(field.key)) continue;
      // These rows are conditional; their conditions are checked below.
      if (const {
        'deposit',
        'manageBasis',
        'managementFee',
        'manageIncludes',
        'manageDetail',
        'otherFeeReason',
        'unknownFeeReason',
        'photoCount',
        'roomLayout',
      }.contains(field.key)) {
        continue;
      }
      final value = values[field.key];
      if (field.required &&
          (value == null || value == '' || (value is List && value.isEmpty))) {
        violations.add(_label(field.key));
      }
    }
    if (_visible('deposit') && _blank('deposit')) violations.add('보증금');
    if (values['trade'] == '매매' && _blank('salePrice')) {
      violations.add('매매 금액');
    }
    if (values['parking'] == '주차 가능') {
      if (_blank('parkingCount')) violations.add('주차 가능 대수');
      if (_blank(HifiField.monthlyParkingFee)) violations.add('월 주차비');
    }
    if (values['singleBuilding'] != true && _blank('building')) {
      violations.add('동');
    }
    if (values['loan'] == '있음' && _blank('loanAmount')) {
      violations.add('융자금');
    }
    if (values['noManagementFee'] != true) {
      if (values['manageMethod'] == '정액 관리비') {
        if (_blank('manageBasis')) violations.add('관리비 부과 기준');
        if (_blank('managementFee')) violations.add('관리비 기본 금액');
        final includes = values['manageIncludes'];
        if (includes is! List || includes.isEmpty) {
          violations.add('관리비 포함 항목');
        }
        if (_visible('manageDetail')) {
          final details = values['manageDetail'];
          if (details is! Map ||
              manageFeeItems.any((fee) => '${details[fee] ?? ''}'.isEmpty)) {
            violations.add('비목별 실비·정액 내역');
          }
        }
      } else if (values['manageMethod'] == '기타 부과' &&
          _blank('otherFeeReason')) {
        violations.add('기타 부과 법정 사유');
      } else if (values['manageMethod'] == '확인 불가' &&
          _blank('unknownFeeReason')) {
        violations.add('확인 불가 법정 사유');
      }
    }
    if (values['moveInType'] == '날짜 지정' && _blank('moveInDate')) {
      violations.add('입주가능일');
    }
    if (_visible('lh') && _blank('lh')) violations.add('LH 전세임대 여부');
    for (final key in [
      HifiField.structure,
      HifiField.duplex,
      HifiField.ownerName,
      'ownerPhone',
    ]) {
      if (_blank(key)) violations.add(_label(key));
    }
    if (photos.length > 20) violations.add('매물 사진은 최대 20장');
    if (_text('title').length > 30) violations.add('매물 제목은 최대 30자');
    if (_text('description').length > 1000) {
      violations.add('매물 상세 설명은 최대 1000자');
    }
    if (_channels.isEmpty) violations.add('광고할 플랫폼');
    return violations.toSet().toList();
  }

  static String _label(String key) => switch (key) {
    'propertyType' => '매물 종류',
    'address' => '주소',
    'building' => '동',
    'unit' => '호',
    'exclusiveArea' => '전용면적',
    'supplyArea' => '공급면적',
    'floorAll' => '전체 층 수',
    'floor' => '해당 층 수',
    'buildingUse' => '건축물 법정 용도',
    'approvalDate' => '사용승인일',
    'trade' => '거래 유형',
    'monthlyRent' => '월세',
    'manageMethod' => '관리비 부과 방식',
    'rooms' => '방 수',
    'bathrooms' => '욕실 수',
    'directionBase' => '방향 기준',
    'direction' => '주실 방향',
    'parking' => '주차 가능 여부',
    'elevator' => '엘리베이터 유무',
    'violation' => '위반건축물 해당 여부',
    'loanAvailable' => '전세자금대출 가능 여부',
    'petAllowed' => '반려동물 허용',
    'moveInType' => '입주가능일',
    'title' => '매물 제목',
    'description' => '매물 상세 설명',
    HifiField.structure => '구조',
    HifiField.duplex => '복층 여부',
    HifiField.ownerName => '임대인 성함',
    'ownerPhone' => '연락처',
    _ => _masterFields[key]?.label ?? key,
  };

  /// 임시 저장 — a half-filled listing survives leaving the screen, with no
  /// channel published.
  Future<void> _saveDraft() async {
    final store = widget.store;
    if (store == null) return;
    await store.save(_compose());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('임시 저장했어요')));
    Navigator.of(context).pop();
  }

  Listing _compose() {
    final record = Map<String, dynamic>.from(values);
    if (photos.isEmpty) record.remove('photoCount');
    final initial = widget.initial;
    return Listing(
      id:
          initial?.id ??
          'L${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      createdAt: initial?.createdAt ?? DateTime.now(),
      values: record,
      channels: {
        for (final platform in _channels)
          platform: initial?.channels[platform] ?? ChannelState.pending,
      },
      channelDates: initial?.channelDates ?? const {},
      photoPaths: photos.map((photo) => photo.path).toList(),
    );
  }

  void _publish() {
    if (_violations().isNotEmpty) {
      setState(() => _showMissing = true);
      return;
    }
    final targetValues = Map<String, dynamic>.from(values);
    final targetPhotos = List<XFile>.unmodifiable(photos);
    if (targetPhotos.isEmpty) targetValues.remove('photoCount');

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PublishFlowPage(
          store: widget.store,
          listing: _compose(),
          values: targetValues,
          photos: targetPhotos,
          channels: ListingPlatform.values.where(_channels.contains).toList(),
          remotePageBuilder: widget.remotePageBuilder,
        ),
      ),
    );
  }

  Future<void> _searchAddress() async {
    final result = await Navigator.of(context).push<KakaoAddress>(
      MaterialPageRoute(builder: (_) => const KakaoAddressSearchPage()),
    );
    if (result != null && mounted) {
      setState(() => values.addAll(result.toFormValues()));
    }
  }

  Future<void> _pickPhotos() async {
    setState(() {
      _pickingPhotos = true;
      _photoError = null;
    });
    try {
      final selected =
          await (widget.pickImages?.call() ??
              ImagePicker().pickMultiImage(
                limit: 20,
                requestFullMetadata: false,
              ));
      if (!mounted || selected.isEmpty) return;
      if (photos.length + selected.length > 20) {
        setState(() => _photoError = '사진은 최대 20장까지 올릴 수 있어요.');
        return;
      }
      setState(() {
        photos.addAll(selected);
        values['photoCount'] = photos.length;
      });
    } catch (e) {
      if (mounted) setState(() => _photoError = '사진을 불러오지 못했어요: $e');
    } finally {
      if (mounted) setState(() => _pickingPhotos = false);
    }
  }

  Future<void> _pickDate(String key) async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_text(key));
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    final text =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    _controller(key).text = text;
    _set(key, text);
  }

  // ---- building blocks -----------------------------------------------------

  Widget _field(String key, Widget child, {String? label, Widget? below}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Space.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldLabel(label ?? _label(key), required: _required(key)),
            const SizedBox(height: Space.s8),
            child,
            if (below != null) ...[const SizedBox(height: Space.s8), below],
          ],
        ),
      );

  Widget _pair(Widget left, Widget right) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: Space.s12),
      Expanded(child: right),
    ],
  );

  Widget _input(
    String key, {
    required String hint,
    bool numeric = false,
    int? maxLength,
    int lines = 1,
    bool enabled = true,
    TextInputType? keyboard,
    Widget? suffix,
  }) => _TextBox(
    controller: _controller(key),
    hint: hint,
    enabled: enabled,
    lines: lines,
    maxLength: maxLength,
    suffix: suffix,
    keyboard:
        keyboard ??
        (numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : lines > 1
            ? TextInputType.multiline
            : TextInputType.text),
    onChanged: (value) => _set(key, value.trim().isEmpty ? null : value),
  );

  Widget _dateInput(String key, {bool enabled = true}) => _input(
    key,
    hint: 'YYYY-MM-DD',
    enabled: enabled,
    keyboard: TextInputType.datetime,
    suffix: IconButton(
      tooltip: '날짜 고르기',
      onPressed: enabled ? () => _pickDate(key) : null,
      icon: const Icon(
        Icons.calendar_today_outlined,
        size: 18,
        color: AppColor.iconSecondary,
      ),
    ),
  );

  Widget _select(
    String key,
    List<String> options, {
    String hint = '선택해주세요',
    String Function(String)? label,
  }) => _SelectBox(
    title: _label(key),
    value: values[key] as String?,
    hint: hint,
    options: options,
    label: label ?? (value) => value,
    onChanged: (value) => _set(key, value),
  );

  Widget _segment(
    String key,
    List<String> options, {
    Map<String, String> labels = const {},
  }) => _Segmented(
    options: options,
    selected: values[key] as String?,
    label: (option) => labels[option] ?? option,
    onTap: (option) => _set(key, option),
  );

  Widget _chips(String key, List<String> options, {bool multi = true}) {
    final selected = multi
        ? List<String>.from(values[key] as List? ?? const [])
        : [if (values[key] != null) '${values[key]}'];
    return _ChipGrid(
      options: options,
      selected: selected.toSet(),
      label: optionLabel,
      onTap: (option) {
        if (!multi) {
          _set(key, selected.contains(option) ? null : option);
          return;
        }
        if (!selected.remove(option)) selected.add(option);
        _set(key, selected);
      },
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) =>
      _CheckLine(label: label, value: value, onChanged: onChanged);

  // ---- sections ------------------------------------------------------------

  List<Widget> _basic() {
    final single = values['singleBuilding'] == true;
    return [
      _field(
        'address',
        _TapBox(
          text: _text('address'),
          hint: '주소를 검색해주세요',
          onTap: _searchAddress,
        ),
        below: _blank('address')
            ? null
            : Text(_addressDetail(), style: AppText.caption),
      ),
      _pair(
        _field(
          'building',
          _input('building', hint: '예: 101동', enabled: !single),
        ),
        _field('unit', _input('unit', hint: '예: 303호')),
      ),
      Transform.translate(
        offset: const Offset(0, -Space.s8),
        child: _check('단일동', single, (value) {
          if (value) _controller('building').clear();
          setState(() {
            values['singleBuilding'] = value;
            if (value) values.remove('building');
          });
        }),
      ),
      _field(
        'propertyType',
        _select('propertyType', _masterFields['propertyType']!.options),
      ),
      _field(
        'buildingUse',
        _select('buildingUse', _masterFields['buildingUse']!.options),
        label: '건축물 법정 용도',
      ),
      _pair(
        _field('approvalDate', _dateInput('approvalDate')),
        _field(
          HifiField.householdCount,
          _input(HifiField.householdCount, hint: '숫자 입력', numeric: true),
          label: '총 세대수',
        ),
      ),
      _field(
        'violation',
        _segment(
          'violation',
          _masterFields['violation']!.options,
          labels: const {'위반건축물 해당': '해당'},
        ),
      ),
    ];
  }

  String _addressDetail() {
    final jibun = _text('jibunAddress');
    return [
      if (jibun.isNotEmpty && jibun != _text('address')) '지번 $jibun',
      '우편번호 ${values['postalCode'] ?? '-'}',
    ].join(' · ');
  }

  List<Widget> _trade() {
    final noLoan = values['loan'] == '없음';
    final immediate = values['moveInImmediate'] == true;
    return [
      _field('trade', _segment('trade', _masterFields['trade']!.options)),
      if (values['trade'] == '매매')
        _field(
          'salePrice',
          _input('salePrice', hint: '예: 45000', numeric: true),
          label: '매매 금액 (만원)',
        )
      else
        _pair(
          _field(
            'deposit',
            _input('deposit', hint: '예: 1000', numeric: true),
            label: '보증금 (만원)',
          ),
          _visible('monthlyRent')
              ? _field(
                  'monthlyRent',
                  _input('monthlyRent', hint: '예: 65', numeric: true),
                  label: '월세 (만원)',
                )
              : const SizedBox.shrink(),
        ),
      Transform.translate(
        offset: const Offset(0, -Space.s8),
        child: _check(
          '단기 매물',
          values['shortTerm'] == true,
          (value) => _set('shortTerm', value),
        ),
      ),
      _field(
        'loanAmount',
        _input('loanAmount', hint: '예: 1000', numeric: true, enabled: !noLoan),
        label: '융자금 (만원)',
        below: _check('융자금 없음', noLoan, (value) {
          if (value) _controller('loanAmount').clear();
          setState(() {
            if (value) {
              values['loan'] = '없음';
              values.remove('loanAmount');
            } else {
              values.remove('loan');
            }
          });
        }),
      ),
      _field(
        'moveInDate',
        _dateInput('moveInDate', enabled: !immediate),
        label: '입주가능일',
        below: Wrap(
          spacing: Space.s16,
          children: [
            _check('즉시 입주', immediate, (value) {
              if (value) _controller('moveInDate').clear();
              if (value) values.remove('moveInDate');
              _set('moveInImmediate', value);
            }),
            _check(
              '협의 가능',
              values['moveInNegotiable'] == true,
              (value) => _set('moveInNegotiable', value),
            ),
          ],
        ),
      ),
      _field(
        HifiField.moveInNote,
        _input(HifiField.moveInNote, hint: '예: 5월 말 퇴거 예정, 협의 가능', lines: 3),
        label: '입주가능일 추가 설명',
      ),
      _field(
        HifiField.eContract,
        _segment(HifiField.eContract, eContractOptions),
        label: '전자계약 가능 여부',
      ),
      if (_visible('lh'))
        _field('lh', _segment('lh', _masterFields['lh']!.options)),
    ];
  }

  List<Widget> _space() {
    final floorAll = int.tryParse(_text('floorAll'));
    final floors = [
      '지하 1층',
      '반지하',
      for (var i = 1; i <= (floorAll ?? 80); i++) '$i',
      '옥탑',
    ];
    return [
      _pair(
        _field(
          'exclusiveArea',
          _input('exclusiveArea', hint: '예: 40', numeric: true),
          label: '전용면적 (m²)',
        ),
        _field(
          'supplyArea',
          _input('supplyArea', hint: '예: 46', numeric: true),
          label: '공급면적 (m²)',
        ),
      ),
      _pair(
        _field('floorAll', _input('floorAll', hint: '예: 5', numeric: true)),
        _field(
          'floor',
          _select('floor', floors, hint: '예: 2', label: _floorLabel),
        ),
      ),
      Transform.translate(
        offset: const Offset(0, -Space.s8),
        child: _check(
          '층수 비공개',
          values['floorPrivate'] == true,
          (value) => _set('floorPrivate', value),
        ),
      ),
      _field(
        HifiField.floorBand,
        _select(HifiField.floorBand, floorBandOptions),
        label: '층군 구분',
      ),
      _pair(
        _field(
          'rooms',
          _select('rooms', _masterFields['rooms']!.options, label: _countLabel),
        ),
        _field(
          HifiField.structure,
          _select(HifiField.structure, structureOptions),
        ),
      ),
      _field(
        'bathrooms',
        _select(
          'bathrooms',
          _masterFields['bathrooms']!.options,
          label: _countLabel,
        ),
      ),
      _pair(
        _field(
          'direction',
          _select('direction', _masterFields['direction']!.options),
        ),
        _field(
          HifiField.entranceType,
          _select(HifiField.entranceType, entranceOptions),
          label: '현관 구조 유형',
        ),
      ),
      _field(HifiField.duplex, _segment(HifiField.duplex, duplexOptions)),
    ];
  }

  /// "1" → "1개", "5 이상" → "5개 이상".
  static String _countLabel(String value) => value.endsWith(' 이상')
      ? '${value.substring(0, value.length - 3)}개 이상'
      : '$value개';

  static String _floorLabel(String value) =>
      int.tryParse(value) == null ? value : '$value층';

  List<Widget> _fee() {
    final none = values['noManagementFee'] == true;
    final details = Map<String, String>.from(
      values['manageDetail'] as Map? ?? const <String, String>{},
    );
    return [
      _pair(
        _field(
          'manageMethod',
          none
              ? const _TapBox(text: '관리비 없음', hint: '', onTap: null)
              : _select('manageMethod', _masterFields['manageMethod']!.options),
          label: '부과 방식',
        ),
        _field(
          'managementFee',
          _input(
            'managementFee',
            hint: '예: 12',
            numeric: true,
            enabled: _visible('managementFee'),
          ),
          label: '기본 금액 (만원)',
        ),
      ),
      Transform.translate(
        offset: const Offset(0, -Space.s8),
        child: _check(
          '관리비 없음',
          none,
          (value) => _set('noManagementFee', value),
        ),
      ),
      if (_visible('manageBasis'))
        _field(
          'manageBasis',
          _select('manageBasis', _masterFields['manageBasis']!.options),
          label: '부과 기준',
        ),
      if (_visible('manageIncludes'))
        _field(
          'manageIncludes',
          _ChipGrid(
            options: manageFeeItems,
            selected: Set<String>.from(
              values['manageIncludes'] as List? ?? const [],
            ),
            label: _feeLabel,
            onTap: (option) {
              final list = List<String>.from(
                values['manageIncludes'] as List? ?? [],
              );
              if (!list.remove(option)) list.add(option);
              _set('manageIncludes', list);
            },
          ),
          label: '포함 항목',
        ),
      if (_visible('manageDetail'))
        _field(
          'manageDetail',
          Column(
            children: [
              for (final fee in manageFeeItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(fee, style: AppText.bodySmall),
                      ),
                      Expanded(
                        child: _Segmented(
                          options: const ['정액 부과', '실비 부과'],
                          selected: details[fee],
                          label: (option) => option,
                          compact: true,
                          onTap: (option) {
                            details[fee] = option;
                            _set('manageDetail', details);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          label: '비목별 실비·정액 내역',
        ),
      if (_visible('otherFeeReason'))
        _field(
          'otherFeeReason',
          _select('otherFeeReason', _masterFields['otherFeeReason']!.options),
          label: '기타 부과 사유',
        ),
      if (_visible('unknownFeeReason'))
        _field(
          'unknownFeeReason',
          _select(
            'unknownFeeReason',
            _masterFields['unknownFeeReason']!.options,
          ),
          label: '확인 불가 사유',
        ),
    ];
  }

  static String _feeLabel(String fee) => switch (fee) {
    '수도료' => '수도',
    '가스사용료' => '가스',
    '전기료' => '전기',
    '난방비' => '난방',
    _ => fee,
  };

  List<Widget> _facilities() {
    final noParking = values['parking'] == '주차 불가능';
    return [
      _pair(
        _field(
          'parkingCount',
          _input(
            'parkingCount',
            hint: '예: 1',
            numeric: true,
            enabled: !noParking,
          ),
          label: '주차 가능 대수',
        ),
        _field(
          HifiField.monthlyParkingFee,
          _input(
            HifiField.monthlyParkingFee,
            hint: '예: 3',
            numeric: true,
            enabled: !noParking,
          ),
          label: '월 주차비 (만원)',
        ),
      ),
      Transform.translate(
        offset: const Offset(0, -Space.s8),
        child: _check('주차 불가', noParking, (value) {
          if (value) {
            for (final key in [
              'parkingCount',
              HifiField.monthlyParkingFee,
              'parkingPerHousehold',
            ]) {
              _controller(key).clear();
              values.remove(key);
            }
          }
          _set('parking', value ? '주차 불가능' : '주차 가능');
        }),
      ),
      if (!noParking)
        _field(
          'parkingPerHousehold',
          _input('parkingPerHousehold', hint: '예: 0.7', numeric: true),
          label: '세대당 주차 대수',
        ),
      _pair(
        _field(
          'elevator',
          _select('elevator', _masterFields['elevator']!.options),
        ),
        _field(
          'petAllowed',
          _select('petAllowed', _masterFields['petAllowed']!.options),
        ),
      ),
      _pair(
        _field(
          'loanAvailable',
          _select('loanAvailable', _masterFields['loanAvailable']!.options),
          label: '전세자금대출 가능 여부',
        ),
        _field(
          HifiField.evCharger,
          _select(HifiField.evCharger, availabilityOptions),
          label: '전기차 충전 설비',
        ),
      ),
      _field(
        'appliances',
        _chips('appliances', homeApplianceOptions),
        label: '기본 가전 옵션',
      ),
      _field(
        'appliances',
        _chips('appliances', furnitureOptions),
        label: '가구 및 수납 옵션',
      ),
      _field(
        'facilities',
        _chips('facilities', securityOptions),
        label: '보안 및 부대시설',
      ),
      _field(
        'heating',
        _chips('heating', _masterFields['heating']!.options, multi: false),
        label: '난방 방식',
      ),
    ];
  }

  List<Widget> _media() => [
    _field(
      'photoCount',
      _PhotoStrip(
        photos: photos,
        picking: _pickingPhotos,
        onAdd: _pickPhotos,
        onRemove: (index) => setState(() {
          photos.removeAt(index);
          values['photoCount'] = photos.length;
        }),
      ),
      label: '매물 사진 (선택, 최대 20장)',
      below: Text(
        _photoError ?? '다방·당근 페이지에는 사진이 자동으로 첨부돼요. 직방은 아직 직접 올려야 해요.',
        style: AppText.caption.copyWith(
          color: _photoError == null ? null : AppColor.statusError,
        ),
      ),
    ),
    _field('title', _input('title', hint: '최대 30자로 입력해주세요', maxLength: 30)),
    _field(
      'description',
      _input('description', hint: '입력해주세요', lines: 4, maxLength: 1000),
    ),
    _field(HifiField.tags, _chips(HifiField.tags, tagOptions), label: '관심 태그'),
  ];

  List<Widget> _client() => [
    _pair(
      _field(HifiField.ownerName, _input(HifiField.ownerName, hint: '이름 입력')),
      _field(
        'ownerPhone',
        _input(
          'ownerPhone',
          hint: '010-0000-0000',
          keyboard: TextInputType.phone,
        ),
      ),
    ),
    _field(
      HifiField.brokerageRoute,
      _select(HifiField.brokerageRoute, brokerageRoutes),
      label: '중개 수임 경로',
    ),
    _field(
      'privateMemo',
      _input('privateMemo', hint: '중개 업무에 필요한 내부 메모를 입력해주세요.', lines: 3),
      label: '내부 비밀 메모',
    ),
  ];

  List<Widget> _platforms() {
    final linked = widget.store?.linked ?? const <ListingPlatform>{};
    return [
      const _FieldLabel('광고할 플랫폼', required: true),
      const SizedBox(height: Space.s8),
      for (final platform in ListingPlatform.values)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s8),
          child: SelectCard(
            platform: platform,
            selected: _channels.contains(platform),
            trailing: linked.contains(platform) ? '연동됨' : null,
            onTap: () => setState(() {
              if (!_channels.remove(platform)) _channels.add(platform);
            }),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    final missing = _violations();
    return Scaffold(
      backgroundColor: AppColor.bgPage,
      appBar: BackTitleBar(
        title: editing ? '광고 수정' : '새 광고 등록',
        actions: [
          BarAction('자동 채우기', onPressed: _autoFill),
          if (widget.store != null) BarAction('임시 저장', onPressed: _saveDraft),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.s16,
            Space.gutter,
            Space.s16,
          ),
          children: [
            _Section(
              title: '기본 정보',
              subtitle: '매물을 식별할 수 있는 기본 정보를 입력해주세요.',
              children: _basic(),
            ),
            _Section(
              title: '거래 및 가격 정보',
              subtitle: '계약 조건과 입주 정보를 입력해주세요.',
              children: _trade(),
            ),
            _Section(
              title: '공간 및 건물 구조',
              subtitle: '매물의 면적과 구조 정보를 입력해주세요.',
              children: _space(),
            ),
            _Section(
              title: '관리비',
              subtitle: '관리비 부과 방식과 포함 항목을 입력해주세요.',
              children: _fee(),
            ),
            _Section(
              title: '시설 및 옵션',
              subtitle: '매물의 시설과 옵션 정보를 입력해주세요.',
              children: _facilities(),
            ),
            _Section(
              title: '사진 및 광고 채널',
              subtitle: '매물 사진과 광고할 플랫폼을 확인해주세요.',
              children: _media(),
            ),
            _Section(
              title: '의뢰인 정보',
              subtitle: '임대인과 중개 의뢰 정보를 입력해주세요.',
              children: _client(),
            ),
            _Section(
              title: '플랫폼 선택',
              subtitle: '광고할 플랫폼을 선택해주세요.',
              last: true,
              children: _platforms(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _Footer(
        missing: missing,
        expanded: _showMissing,
        onToggle: () => setState(() => _showMissing = !_showMissing),
        onPublish: missing.isEmpty ? _publish : null,
      ),
    );
  }
}

// ---- presentation pieces ---------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.children,
    this.last = false,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool last;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: AppText.heading),
      const SizedBox(height: Space.s4),
      Text(subtitle, style: AppText.bodySmall),
      const SizedBox(height: Space.s24),
      ...children,
      if (!last) const SectionRule(vertical: Space.s16),
    ],
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.required});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: text,
      children: [
        if (required)
          const TextSpan(
            text: ' *',
            style: TextStyle(color: AppColor.statusError),
          ),
      ],
    ),
    style: AppText.label.copyWith(color: AppColor.textPrimary),
  );
}

InputDecoration _boxDecoration({
  required String hint,
  required bool enabled,
  Widget? suffix,
}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.r12),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: AppText.body.copyWith(color: AppColor.textDisabled),
    filled: true,
    fillColor: enabled ? AppColor.bgSurface : AppColor.bgSubtle,
    isDense: true,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(
      horizontal: Space.s16,
      vertical: 13,
    ),
    suffixIcon: suffix,
    enabledBorder: border(AppColor.borderSubtle),
    disabledBorder: border(AppColor.borderFaint),
    focusedBorder: border(AppColor.borderFocus),
    border: border(AppColor.borderSubtle),
  );
}

class _TextBox extends StatelessWidget {
  const _TextBox({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.keyboard,
    this.enabled = true,
    this.lines = 1,
    this.maxLength,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final TextInputType keyboard;
  final bool enabled;
  final int lines;
  final int? maxLength;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    style: AppText.body,
    minLines: lines,
    maxLines: lines,
    maxLength: maxLength,
    maxLengthEnforcement: MaxLengthEnforcement.none,
    keyboardType: keyboard,
    cursorColor: AppColor.actionPrimary,
    decoration: _boxDecoration(hint: hint, enabled: enabled, suffix: suffix),
    onChanged: onChanged,
  );
}

/// A read-only box that opens something — the address search, or a
/// derived value that is not typed.
class _TapBox extends StatelessWidget {
  const _TapBox({required this.text, required this.hint, required this.onTap});

  final String text;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: Space.s16, vertical: 13),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: onTap == null ? AppColor.bgSubtle : AppColor.bgSurface,
        borderRadius: BorderRadius.circular(Radii.r12),
        border: Border.all(color: AppColor.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.isEmpty ? hint : text,
              style: AppText.body.copyWith(
                color: text.isEmpty
                    ? AppColor.textDisabled
                    : AppColor.textPrimary,
              ),
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.search_rounded,
              size: 20,
              color: AppColor.iconSecondary,
            ),
        ],
      ),
    ),
  );
}

/// The hi-fi's select box: looks like an input, opens a sheet of choices.
class _SelectBox extends StatelessWidget {
  const _SelectBox({
    required this.title,
    required this.value,
    required this.hint,
    required this.options,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final String? value;
  final String hint;
  final List<String> options;
  final String Function(String) label;
  final ValueChanged<String?> onChanged;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColor.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.r24)),
      ),
      builder: (context) => _OptionSheet(
        title: title,
        options: options,
        selected: value,
        label: label,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: title,
    value: value,
    child: GestureDetector(
      onTap: () => _open(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.fromLTRB(Space.s16, 13, Space.s12, 13),
        decoration: BoxDecoration(
          color: AppColor.bgSurface,
          borderRadius: BorderRadius.circular(Radii.r12),
          border: Border.all(color: AppColor.borderSubtle),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null ? hint : label(value!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(
                  color: value == null
                      ? AppColor.textDisabled
                      : AppColor.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColor.iconTertiary,
            ),
          ],
        ),
      ),
    ),
  );
}

class _OptionSheet extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.label,
  });

  final String title;
  final List<String> options;
  final String? selected;
  final String Function(String) label;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.7,
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Space.s12),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColor.borderDefault,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s24,
              Space.s16,
              Space.s24,
              Space.s8,
            ),
            child: Text(title, style: AppText.title),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: Space.s16),
              children: [
                for (final option in options)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.s24,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label(option),
                              style: option == selected
                                  ? AppText.bodyStrong.copyWith(
                                      color: AppColor.textBrand,
                                    )
                                  : AppText.body,
                            ),
                          ),
                          if (option == selected)
                            const Icon(
                              Icons.check_rounded,
                              color: AppColor.actionPrimary,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Two to four equal buttons; the chosen one takes the brand tint.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.selected,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final List<String> options;
  final String? selected;
  final String Function(String) label;
  final ValueChanged<String> onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (index, option) in options.indexed) ...[
        if (index > 0) const SizedBox(width: Space.s8),
        Expanded(
          child: _OptionTile(
            label: label(option),
            selected: option == selected,
            height: compact ? 40 : 48,
            onTap: () => onTap(option),
          ),
        ),
      ],
    ],
  );
}

/// Chips in a three-column grid, as the hi-fi lays out every option group.
class _ChipGrid extends StatelessWidget {
  const _ChipGrid({
    required this.options,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final List<String> options;
  final Set<String> selected;
  final String Function(String) label;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - Space.s8 * 2) / 3;
      return Wrap(
        spacing: Space.s8,
        runSpacing: Space.s8,
        children: [
          for (final option in options)
            SizedBox(
              width: width,
              child: _OptionTile(
                label: label(option),
                selected: selected.contains(option),
                height: 40,
                onTap: () => onTap(option),
              ),
            ),
        ],
      );
    },
  );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.height,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.quick,
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        decoration: BoxDecoration(
          color: selected ? AppColor.bgBrandSubtle : AppColor.bgSurface,
          borderRadius: BorderRadius.circular(Radii.r12),
          border: Border.all(
            color: selected ? AppColor.borderFocus : AppColor.borderSubtle,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? AppColor.textPrimary : AppColor.textSecondary,
          ),
        ),
      ),
    ),
  );
}

class _CheckLine extends StatelessWidget {
  const _CheckLine({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: value,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: Motion.quick,
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: value ? AppColor.actionPrimary : AppColor.bgSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: value ? AppColor.actionPrimary : AppColor.borderFocus,
                  width: 1.5,
                ),
              ),
              child: value
                  ? const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: AppColor.textOnColor,
                    )
                  : null,
            ),
            const SizedBox(width: Space.s8),
            ExcludeSemantics(child: Text(label, style: AppText.caption)),
          ],
        ),
      ),
    ),
  );
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.photos,
    required this.picking,
    required this.onAdd,
    required this.onRemove,
  });

  final List<XFile> photos;
  final bool picking;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  static const _tile = 92.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _tile,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        Tooltip(
          message: '사진 추가',
          child: GestureDetector(
            onTap: picking || photos.length >= 20 ? null : onAdd,
            child: Container(
              width: _tile,
              height: _tile,
              decoration: BoxDecoration(
                color: AppColor.bgSurface,
                borderRadius: BorderRadius.circular(Radii.r12),
                border: Border.all(color: AppColor.borderSubtle),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  picking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColor.actionPrimary,
                          ),
                        )
                      : const Icon(
                          Icons.photo_camera_outlined,
                          color: AppColor.iconTertiary,
                        ),
                  const SizedBox(height: Space.s4),
                  Text('${photos.length}/20', style: AppText.caption),
                ],
              ),
            ),
          ),
        ),
        for (var i = 0; i < photos.length; i++)
          Padding(
            padding: const EdgeInsets.only(left: Space.s8),
            child: SizedBox(
              width: _tile,
              height: _tile,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.r12),
                    child: Image.file(
                      File(photos[i].path),
                      fit: BoxFit.cover,
                      cacheWidth: 240,
                      errorBuilder: (_, _, _) => const PhotoPlaceholder(),
                    ),
                  ),
                  if (i == 0)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColor.bgOverlay.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '대표',
                          style: AppText.caption.copyWith(
                            color: AppColor.textOnColor,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      tooltip: '${i + 1}번 사진 삭제',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onRemove(i),
                      icon: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColor.bgInverse.withValues(alpha: 0.9),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: AppColor.textOnColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.missing,
    required this.expanded,
    required this.onToggle,
    required this.onPublish,
  });

  final List<String> missing;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onPublish;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColor.bgPage,
      border: Border(top: BorderSide(color: AppColor.borderFaint)),
    ),
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.s8,
      Space.gutter,
      Space.s12,
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (missing.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '필수 항목 ${missing.length}개를 채우면 등록할 수 있어요',
                            style: AppText.caption.copyWith(
                              color: AppColor.textSecondary,
                            ),
                          ),
                        ),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_up_rounded,
                          size: 18,
                          color: AppColor.iconSecondary,
                        ),
                      ],
                    ),
                    if (expanded) ...[
                      const SizedBox(height: Space.s4),
                      Text(
                        missing.join(' · '),
                        style: AppText.caption.copyWith(
                          color: AppColor.statusError,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            const SizedBox(height: Space.s4),
          BrandButton('광고 등록', onPressed: onPublish),
        ],
      ),
    ),
  );
}
