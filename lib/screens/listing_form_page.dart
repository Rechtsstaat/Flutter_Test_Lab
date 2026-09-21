import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../fields.dart';
import '../kakao_address.dart';
import '../listing_rules.dart';
import '../models/listing.dart';
import '../photo_transfer.dart';
import 'publish_flow_page.dart';

/// 201 광고 입력 폼 — one long page in the hi-fi's seven sections, ending in
/// 플랫폼 선택 and the 광고 등록 CTA.
///
/// The sections are the hi-fi's; the data underneath is the master rows the
/// adapters read (plus the hi-fi's own extras, see [HifiField]). **Whatever
/// passes this form, 직방 and 다방 both take** — the rules live in
/// `lib/listing_rules.dart` and were read off the live forms.
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

/// 두 플랫폼이 다 받는 사진 — 직방이 JPG·PNG 만, 장당 10MB까지 받는다.
const _photoTypes = {'image/jpeg', 'image/png'};
final _photoMaxBytes = PhotoTarget.zigbang.maxBytes;

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
      migrateLegacyValues(values);
    }
    final linked = widget.store?.linked ?? const <ListingPlatform>{};
    if (_channels.isEmpty) {
      _channels.addAll(linked.isEmpty ? livePlatforms : linked);
    }
    // 예전에 고른 것·연동해 둔 것 중에 잠시 내려 둔 플랫폼이 있으면 여기서 빠진다
    _channels.removeWhere((platform) => !platform.isLive);
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
      values[HifiField.duplex] ??= layout.startsWith('복층') ? '복층' : '단층';
      if (!layout.startsWith('복층')) {
        values[HifiField.structure] ??= layout.startsWith('분리') ? '분리형' : '오픈형';
      }
    }
    if (values['moveInType'] != null) {
      values['moveInImmediate'] ??= values['moveInType'] == '즉시 입주';
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

  /// Keeps the master rows in step with the hi-fi controls that feed them, and
  /// drops what a choice has switched off — a value the form no longer shows
  /// must not reach a platform.
  void _sync(String key) {
    switch (key) {
      case HifiField.structure || HifiField.duplex || 'rooms':
        final layout = roomLayoutFrom(
          structure: values[HifiField.structure] as String?,
          duplex: values[HifiField.duplex] as String?,
          rooms: roomCount(values),
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
      case 'moveInDate' || 'moveInImmediate':
        if (values['moveInImmediate'] == true) {
          values['moveInType'] = '즉시 입주';
        } else if (!_blank('moveInDate')) {
          values['moveInType'] = '날짜 지정';
        } else {
          values.remove('moveInType');
        }
      case 'trade':
        if (values['trade'] != '월세') {
          values.remove('shortTerm');
          _clear(['monthlyRent', 'shortTermMonths', 'shortTermNegotiation']);
        }
        if (values['trade'] == '매매') {
          _clear(['deposit', 'lh']);
        } else {
          _clear(['salePrice']);
        }
      case 'shortTerm':
        if (values['shortTerm'] != true) {
          _clear(['shortTermMonths', 'shortTermNegotiation']);
        }
      case 'loan':
        if (values['loan'] == '없음') _clear(['loanAmount']);
      case 'propertyType':
        if (!isComplexProperty(values)) _clear(['complexName']);
        final use = values['buildingUse'];
        if (isComplexProperty(values) &&
            use != null &&
            !complexBuildingUses.contains(use)) {
          values.remove('buildingUse');
        }
        if (!floorChoices(values).contains(_text('floor'))) {
          values.remove('floor');
        }
      case 'floorAll':
        if (!floorChoices(values).contains(_text('floor'))) {
          values.remove('floor');
        }
      case 'floorPrivate':
        if (values['floorPrivate'] != true) values.remove(HifiField.floorBand);
      case 'appliances':
        final list = values['appliances'] as List? ?? const [];
        if (!list.contains('에어컨')) values.remove('airconType');
      case 'manageBasis':
        if (values['manageBasis'] != '기타 직접 입력') _clear(['manageBasisNote']);
      case 'otherFeeReason':
        if (values['otherFeeReason'] != '기타') _clear(['otherFeeNote']);
      case 'ownerPhoneDuplicateReason':
        if (values['ownerPhoneDuplicateReason'] != '기타') {
          _clear(['ownerPhoneDuplicateNote']);
        }
      case 'mediationMethod':
        if (values['mediationMethod'] != '기타 방법으로 확인') {
          _clear(['mediationNote']);
        }
    }
  }

  void _clear(List<String> keys) {
    for (final key in keys) {
      values.remove(key);
      _controllers[key]?.clear();
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
          values.remove(field.key);
        case InputType.addressSearch:
          /* 카카오 주소 검색이 이 주소로 실제로 돌려주는 값 그대로다(2026-09-22 실측).
           * 지번으로 고른 주소라 [address] 는 지번이고, 도로명은 따로 들고 있는다. */
          values[field.key] = field.example;
          values['jibunAddress'] = field.example;
          values['roadAddress'] = '경북 포항시 남구 상공로6번길 60';
          values.remove('buildingName');
          values['postalCode'] = '37828';
          values['legalDongCode'] = '4711110200';
          values['sido'] = '경북';
          values['sigungu'] = '포항시 남구';
          values['bname'] = '대도동';
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
    /* 자동 채우기는 **실제 광고 하나**다 — 직방 원룸 광고 50459044
     * (경북 포항시 남구 대도동 168-7, 단독주택 오픈형 원룸, 월세 200/20).
     *
     * 단지명·단기·동 정보처럼 이 매물에 없는 조건부 칸은 비워 둔다. 예시가 켜 두면
     * 폼이 끈 칸에 값이 남는다. */
    for (final key in [
      'complexName',
      'building',
      'manageBasisNote',
      'otherFeeNote',
      'mediationNote',
      'ownerPhoneDuplicateNote',
      /* 의뢰인 성함·연락처는 **자동으로 채우지 않는다.**
       *
       * 두 곳 다 필수가 아니고(직방은 그 위에 「(선택사항)」이라 적어 두었다, 다방에는
       * 칸이 없다), 무엇보다 이 칸은 **실제 사람의 번호**를 적는 자리다. 예시 번호가
       * 앉아 있으면 연습이 남의 번호를 계정의 이름으로 조회하게 만들거나
       * ([sampleOwnerPhone]), 그대로 두고 올려 엉뚱한 사람의 번호가 광고에 실린다.
       * 비워 두면 등록은 그대로 되고, 필요한 사람이 제 손으로 적는다. */
      'ownerPhone',
      HifiField.ownerName,
    ]) {
      values.remove(key);
    }
    values['moveInImmediate'] = values['moveInType'] == '즉시 입주';
    if (values['moveInImmediate'] == true) values.remove('moveInDate');
    values['roomLayout'] = '오픈형 원룸';
    for (final key in [...values.keys]) {
      if (!fieldVisible(values, key) &&
          key != 'moveInType' &&
          key != 'moveInImmediate') {
        values.remove(key);
      }
    }
    _deriveFromMaster();
    _sync(HifiField.evCharger);
    for (final entry in _controllers.entries) {
      entry.value.text = _amountText(entry.key) ?? _text(entry.key);
    }
    setState(() => _showMissing = false);
  }

  /// A 비목 amount controller's text (`manageDetail.<item>.amount|note`).
  String? _amountText(String key) {
    if (!key.startsWith('manageDetail.')) return null;
    final parts = key.split('.');
    return '${feeItem(values, parts[1])[parts[2]] ?? ''}';
  }

  bool _visible(String key) => fieldVisible(values, key);
  bool _required(String key) => fieldRequired(values, key);

  List<String> _violations() {
    final violations = listingViolations(values, channels: _channels);
    /* 사진은 **필수 5~20장**이다.
     *
     * 직방이 그렇게 요구한다 — 「이미지 넣기」 창이 5장을 채우기 전에는 [확인] 을
     * 열어 주지 않는다. 통합 폼에서 5장을 못 채우면 직방 전송은 어차피 사진 없이
     * 끝나므로, 보내기 전에 여기서 막는다. JPG·PNG 가 아닌 사진과 10MB 를 넘는 사진은
     * 고를 때 걸러 낸다([_pickPhotos]). */
    if (photos.length < minListingPhotos || photos.length > maxListingPhotos) {
      violations.add('매물 사진 $minListingPhotos~$maxListingPhotos장');
    }
    if (_channels.isEmpty) violations.add('광고할 플랫폼');
    return violations.toSet().toList();
  }

  static String _label(String key) => fieldLabel(key);

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
          channels: livePlatforms.where(_channels.contains).toList(),
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
      setState(() {
        values.addAll(result.toFormValues());
        // 단지명은 카카오가 알려 준 건물명으로 먼저 채운다 — 다방 단지 목록에서 고를 때
        // 쓰는 이름이라, 다르면 사람이 고친다.
        final building = (result.buildingName ?? '').trim();
        if (isComplexProperty(values) &&
            building.isNotEmpty &&
            _blank('complexName')) {
          values['complexName'] = building;
          _controller('complexName').text = building;
        }
      });
    }
  }

  /// 사진을 고른다. 두 플랫폼이 다 받는 사진만 들인다 — 직방은 JPG·PNG 만, 장당
  /// 10MB까지 받는다. 시스템 선택기에는 JPEG 로 다시 저장해 달라고 부탁하므로(HEIC
  /// 도 JPEG 가 된다) 대개 그대로 통과하고, 그래도 못 받는 것은 이유를 적고 뺀다.
  Future<void> _pickPhotos() async {
    setState(() {
      _pickingPhotos = true;
      _photoError = null;
    });
    try {
      final selected =
          await (widget.pickImages?.call() ??
              ImagePicker().pickMultiImage(
                limit: maxListingPhotos,
                requestFullMetadata: false,
                imageQuality: 90,
                maxWidth: 3000,
                maxHeight: 3000,
              ));
      if (!mounted || selected.isEmpty) return;
      final accepted = <XFile>[];
      final rejected = <String>[];
      for (final photo in selected) {
        if (photos.any((existing) => existing.path == photo.path) ||
            accepted.any((existing) => existing.path == photo.path)) {
          continue;
        }
        String? problem;
        try {
          final mime = await validateListingPhoto(photo);
          if (!_photoTypes.contains(mime)) {
            problem = 'JPG·PNG 가 아니에요';
          } else if (await photo.length() > _photoMaxBytes) {
            problem = '10MB 를 넘어요';
          }
        } catch (error) {
          problem = '읽을 수 없어요';
        }
        if (problem == null) {
          accepted.add(photo);
        } else {
          rejected.add('${photo.name}($problem)');
        }
      }
      if (!mounted) return;
      if (photos.length + accepted.length > maxListingPhotos) {
        setState(() => _photoError = '사진은 최대 $maxListingPhotos장까지 올릴 수 있어요.');
        return;
      }
      setState(() {
        photos.addAll(accepted);
        values['photoCount'] = photos.length;
        if (rejected.isNotEmpty) {
          _photoError =
              '직방이 받지 않는 사진은 빼 두었어요: ${rejected.join(', ')}. '
              'JPG·PNG 사진을 장당 10MB 이하로 골라 주세요.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _photoError = '사진을 불러오지 못했어요: $e');
    } finally {
      if (mounted) setState(() => _pickingPhotos = false);
    }
  }

  Future<void> _pickDate(String key, {bool future = false}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = DateTime.tryParse(_text(key));
    final first = future ? today : DateTime(1900);
    final last = future ? DateTime(now.year + 5) : today;
    var initial = current ?? today;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
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
    bool integer = false,
    int? maxLength,
    bool counter = false,
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
    counter: counter,
    suffix: suffix,
    keyboard:
        keyboard ??
        (integer
            ? TextInputType.number
            : numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : lines > 1
            ? TextInputType.multiline
            : TextInputType.text),
    onChanged: (value) => _set(key, value.trim().isEmpty ? null : value),
  );

  Widget _dateInput(String key, {bool enabled = true, bool future = false}) =>
      _input(
        key,
        hint: 'YYYY-MM-DD',
        enabled: enabled,
        keyboard: TextInputType.datetime,
        suffix: IconButton(
          tooltip: '날짜 고르기',
          onPressed: enabled ? () => _pickDate(key, future: future) : null,
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
    final complex = isComplexProperty(values);
    return [
      _field(
        'propertyType',
        _select('propertyType', propertyTypes),
        below: Text(
          complex
              ? '다방은 단지를 골라 등록해요. 단지명·호·세대당 주차 대수를 꼭 적어 주세요.'
              : '원룸·투룸은 아래 「방 수」와 「구조」로 적어 주세요.',
          style: AppText.caption,
        ),
      ),
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
      if (_visible('complexName'))
        _field(
          'complexName',
          _input('complexName', hint: '예: 역삼래미안'),
          below: const Text(
            '다방 단지 목록에서 이 이름으로 단지를 찾아요.',
            style: AppText.caption,
          ),
        ),
      _pair(
        _field(
          'building',
          _input('building', hint: '예: 101', enabled: !single),
        ),
        _field('unit', _input('unit', hint: '예: 303')),
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
        'buildingUse',
        _select('buildingUse', complex ? complexBuildingUses : buildingUses),
        label: '건축물 법정 용도',
      ),
      _pair(
        _field('approvalDate', _dateInput('approvalDate')),
        _field(
          HifiField.householdCount,
          _input(HifiField.householdCount, hint: '숫자 입력', integer: true),
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
    final immediate = values['moveInImmediate'] == true;
    final loan = values['loan'] as String?;
    return [
      _field('trade', _segment('trade', _masterFields['trade']!.options)),
      if (values['trade'] == '매매')
        _field(
          'salePrice',
          _input('salePrice', hint: '예: 45000', integer: true),
          label: '매매 금액 (만원)',
        )
      else
        _pair(
          _field(
            'deposit',
            _input('deposit', hint: '예: 1000', integer: true),
            label: '보증금 (만원)',
          ),
          _visible('monthlyRent')
              ? _field(
                  'monthlyRent',
                  _input('monthlyRent', hint: '예: 65', integer: true),
                  label: '월세 (만원)',
                )
              : const SizedBox.shrink(),
        ),
      if (_visible('shortTerm'))
        Transform.translate(
          offset: const Offset(0, -Space.s8),
          child: _check(
            '단기 매물 (계약 기간 1년 미만)',
            values['shortTerm'] == true,
            (value) => _set('shortTerm', value),
          ),
        ),
      if (_visible('shortTermMonths'))
        _pair(
          _field(
            'shortTermMonths',
            _select(
              'shortTermMonths',
              _masterFields['shortTermMonths']!.options,
              label: (value) => '$value개월',
            ),
            label: '계약 기간',
          ),
          _field(
            'shortTermNegotiation',
            _select('shortTermNegotiation', shortTermNegotiations),
            label: '기간 협의',
          ),
        ),
      _field(
        'loan',
        _segment('loan', loanOptions),
        label: '융자금 (시세 대비)',
        below: loan == null || loan == '없음'
            ? null
            : _input('loanAmount', hint: '융자금 금액 (만원, 선택)', integer: true),
      ),
      _field(
        'moveInDate',
        _dateInput('moveInDate', enabled: !immediate, future: true),
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
        _input(
          HifiField.moveInNote,
          hint: '예: 퇴거일 협의 (10자 이내)',
          maxLength: moveInNoteMaxLength,
          counter: true,
        ),
        label: '입주가능일 추가 설명',
      ),
      _field(
        HifiField.eContract,
        _segment(HifiField.eContract, eContractOptions),
      ),
      if (_visible('lh'))
        _field('lh', _segment('lh', _masterFields['lh']!.options)),
    ];
  }

  List<Widget> _space() {
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
        _field(
          'floorAll',
          _input('floorAll', hint: '1~${maxFloorAll(values)}', integer: true),
        ),
        _field(
          'floor',
          _select(
            'floor',
            floorChoices(values),
            hint: '예: 2',
            label: _floorLabel,
          ),
        ),
      ),
      Transform.translate(
        offset: const Offset(0, -Space.s8),
        child: _check(
          '층수 비공개 (저/중/고로 표시)',
          values['floorPrivate'] == true,
          (value) => _set('floorPrivate', value),
        ),
      ),
      if (_visible(HifiField.floorBand))
        _field(
          HifiField.floorBand,
          _segment(HifiField.floorBand, floorBandOptions),
        ),
      _pair(
        _field(
          'rooms',
          _select('rooms', _masterFields['rooms']!.options, label: _countLabel),
        ),
        _visible(HifiField.structure)
            ? _field(
                HifiField.structure,
                _select(HifiField.structure, structureOptions),
              )
            : const SizedBox.shrink(),
      ),
      _field(
        'bathrooms',
        _select(
          'bathrooms',
          _masterFields['bathrooms']!.options,
          label: _countLabel,
        ),
      ),
      _field('directionBase', _segment('directionBase', directionBases)),
      _pair(
        _field(
          'direction',
          _select('direction', _masterFields['direction']!.options),
        ),
        _field(
          HifiField.entranceType,
          _select(HifiField.entranceType, entranceOptions),
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

  static const _tierLabels = {
    '10만원 미만': '10만원 미만',
    '10만원 이상': '10만원 이상',
    '10만원 이상 (세부내역 미고지)': '이상·내역 미고지',
  };

  List<Widget> _fee() {
    final none = values['noManagementFee'] == true;
    return [
      Transform.translate(
        offset: const Offset(0, -Space.s8),
        child: _check(
          '관리비 없음',
          none,
          (value) => _set('noManagementFee', value),
        ),
      ),
      if (_visible('manageMethod'))
        _field(
          'manageMethod',
          _select('manageMethod', _masterFields['manageMethod']!.options),
          label: '부과 방식',
        ),
      if (_visible('feeTier'))
        _field(
          'feeTier',
          _segment('feeTier', feeTiers, labels: _tierLabels),
          label: '정액 관리비 구간',
          below: Text(switch (values['feeTier']) {
            '10만원 이상' => '월 10만원 이상 정액이면 비목별 부과 방식과 금액을 모두 적어야 해요.',
            '10만원 이상 (세부내역 미고지)' => '의뢰인이 비목별 내역을 알려 주지 않았을 때 골라요.',
            _ => '총액과 포함 항목을 적어요.',
          }, style: AppText.caption),
        ),
      if (_visible('manageBasis'))
        _field(
          'manageBasis',
          _select('manageBasis', _masterFields['manageBasis']!.options),
          label: '부과 기준',
          below: _visible('manageBasisNote')
              ? _input(
                  'manageBasisNote',
                  hint: '기준을 직접 적어 주세요 (20자 이내)',
                  maxLength: 20,
                  counter: true,
                )
              : null,
        ),
      if (_visible('managementFee'))
        _field(
          'managementFee',
          _input('managementFee', hint: '예: 8', numeric: true),
          label: '관리비 총액 (만원)',
        ),
      if (_visible('manageIncludes'))
        _field(
          'manageIncludes',
          _chips('manageIncludes', manageFeeItems),
          label: '포함 항목',
        ),
      if (_visible('manageDetail')) ..._feeDetail(),
      if (_visible('otherFeeReason'))
        _field(
          'otherFeeReason',
          _select('otherFeeReason', _masterFields['otherFeeReason']!.options),
          label: '기타 부과 근거',
          below: _visible('otherFeeNote')
              ? _input(
                  'otherFeeNote',
                  hint: '근거를 직접 적어 주세요 (20자 이내)',
                  maxLength: 20,
                  counter: true,
                )
              : null,
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

  /// 정액 관리비 10만원 이상 — 직방·다방이 똑같이 비목마다 부과 방식과 금액을 받는다.
  void _setFeeItem(String item, String field, Object? value) {
    setState(() {
      final detail = Map<String, dynamic>.from(
        values['manageDetail'] as Map? ?? const {},
      );
      final entry = Map<String, dynamic>.from(detail[item] as Map? ?? const {});
      if (value == null || (value is String && value.trim().isEmpty)) {
        entry.remove(field);
      } else {
        entry[field] = value is String ? value.trim() : value;
      }
      if (field == 'type' &&
          value != '정액' &&
          value != '있음' &&
          item != commonFeeItem) {
        entry.remove('amount');
        _controllers['manageDetail.$item.amount']?.clear();
      }
      if (field == 'type' && value != '있음' && item == etcFeeItem) {
        entry.remove('note');
        _controllers['manageDetail.$item.note']?.clear();
      }
      detail[item] = entry;
      values['manageDetail'] = detail;
    });
  }

  Widget _feeAmount(
    String item, {
    required bool enabled,
    String hint = '금액 (원)',
  }) => _TextBox(
    controller: _controller('manageDetail.$item.amount'),
    hint: hint,
    enabled: enabled,
    keyboard: TextInputType.number,
    onChanged: (value) => _setFeeItem(item, 'amount', value),
  );

  List<Widget> _feeDetail() {
    Widget row(String item, List<String> ways, {required bool amount}) {
      final entry = feeItem(values, item);
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item, style: AppText.bodySmall),
            const SizedBox(height: Space.s4),
            _Segmented(
              options: ways,
              selected: entry['type'] as String?,
              label: (option) => option,
              compact: true,
              onTap: (option) => _setFeeItem(item, 'type', option),
            ),
            if (amount) ...[
              const SizedBox(height: Space.s8),
              _feeAmount(item, enabled: true),
            ],
          ],
        ),
      );
    }

    final etc = feeItem(values, etcFeeItem);
    final total = fixedFeeTotal(values);
    return [
      _FieldLabel('항목별 관리비', required: _required('manageDetail')),
      const SizedBox(height: Space.s8),
      row(commonFeeItem, commonFeeWays, amount: true),
      for (final item in usageFeeItems)
        row(item, feeItemWays, amount: feeItem(values, item)['type'] == '정액'),
      Padding(
        padding: const EdgeInsets.only(bottom: Space.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(etcFeeItem, style: AppText.bodySmall),
            const SizedBox(height: Space.s4),
            _Segmented(
              options: const ['없음', '있음'],
              selected: etc['type'] as String?,
              label: (option) => option,
              compact: true,
              onTap: (option) => _setFeeItem(etcFeeItem, 'type', option),
            ),
            if (etc['type'] == '있음') ...[
              const SizedBox(height: Space.s8),
              _TextBox(
                controller: _controller('manageDetail.$etcFeeItem.note'),
                hint: '내용 (예: 주차비, 20자 이내)',
                maxLength: 20,
                keyboard: TextInputType.text,
                onChanged: (value) => _setFeeItem(etcFeeItem, 'note', value),
              ),
              const SizedBox(height: Space.s8),
              _feeAmount(etcFeeItem, enabled: true),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: Space.s16),
        child: Text(
          '정액 합계 ${_won(total)}원 — 실비 항목은 쓴 만큼 따로 내요.',
          style: AppText.caption,
        ),
      ),
    ];
  }

  static String _won(num value) {
    final digits = value.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  List<Widget> _facilities() {
    final noParking = values['parking'] == '주차 불가능';
    final appliances = values['appliances'] as List? ?? const [];
    return [
      _pair(
        _field(
          'parkingCount',
          _input(
            'parkingCount',
            hint: '예: 1',
            integer: true,
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
      if (appliances.contains('에어컨'))
        _field(
          'airconType',
          _chips('airconType', airconTypes),
          label: '에어컨 종류',
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
      _field(
        'roomFeatures',
        _chips('roomFeatures', roomFeatureOptions),
        label: '방 특징',
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
      label: '매물 사진 (필수, $minListingPhotos~$maxListingPhotos장)',
      below: Text(
        _photoError ??
            '직방·다방 페이지에 사진이 자동으로 첨부돼요. 첫 장이 대표 사진이고, '
                'JPG·PNG 사진만 장당 10MB까지 올릴 수 있어요.',
        style: AppText.caption.copyWith(
          color: _photoError == null ? null : AppColor.statusError,
        ),
      ),
    ),
    _field(
      'title',
      _input(
        'title',
        hint: '$titleMinLength~$titleMaxLength자, 한글·영문·숫자·쉼표·마침표',
        maxLength: titleMaxLength,
        counter: true,
      ),
    ),
    _field(
      'description',
      _input(
        'description',
        hint: '$descriptionMinLength자 이상 입력해주세요. 전화번호·이메일·링크는 넣을 수 없어요.',
        lines: 5,
        maxLength: descriptionMaxLength,
        counter: true,
      ),
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
      'ownerPhoneDuplicateReason',
      _select('ownerPhoneDuplicateReason', ownerPhoneDuplicateReasons),
      label: '집주인 번호가 이미 쓰였을 때 사유 (선택)',
      below: _visible('ownerPhoneDuplicateNote')
          ? _input(
              'ownerPhoneDuplicateNote',
              hint: '사유를 5~32자로 적어 주세요',
              maxLength: 32,
              counter: true,
            )
          : const Text(
              '직방은 다른 매물에 이미 쓰인 집주인 번호면 사유를 꼭 고르게 해요.',
              style: AppText.caption,
            ),
    ),
    _field(
      'mediationMethod',
      _segment(
        'mediationMethod',
        mediationMethods,
        labels: const {'기타 방법으로 확인': '기타'},
      ),
      below: _visible('mediationNote')
          ? _input('mediationNote', hint: '확인한 방법을 적어 주세요')
          : null,
    ),
    _field(
      HifiField.brokerageRoute,
      _select(HifiField.brokerageRoute, brokerageRoutes),
      label: '중개 수임 경로',
    ),
    _field(
      'privateMemo',
      _input(
        'privateMemo',
        hint: '중개 업무에 필요한 내부 메모를 입력해주세요.',
        lines: 3,
        maxLength: privateMemoMaxLength,
        counter: true,
      ),
      label: '내부 비밀 메모',
    ),
  ];

  List<Widget> _platforms() {
    final linked = widget.store?.linked ?? const <ListingPlatform>{};
    return [
      const _FieldLabel('광고할 플랫폼', required: true),
      const SizedBox(height: Space.s8),
      for (final platform in ListingPlatform.values) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s8),
          child: SelectCard(
            platform: platform,
            selected: _channels.contains(platform),
            enabled: platform.isLive,
            note: platform.pausedNote,
            trailing: linked.contains(platform) ? '연동됨' : null,
            onTap: () => setState(() {
              if (!_channels.remove(platform)) _channels.add(platform);
            }),
          ),
        ),
        if (platform.isLive &&
            _channels.contains(platform) &&
            platformBlocker(platform, values) != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s12),
            child: Text(
              platformBlocker(platform, values)!,
              style: AppText.caption.copyWith(color: AppColor.statusError),
            ),
          ),
      ],
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
  bool counter = false,
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
    counterText: counter ? null : '',
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
    this.counter = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final TextInputType keyboard;
  final bool enabled;
  final int lines;
  final int? maxLength;

  /// 글자 수를 칸 아래에 보여 줄 것인가 — 플랫폼이 글자 수를 따지는 칸(제목·설명·메모).
  final bool counter;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      style: AppText.body,
      minLines: lines,
      maxLines: lines,
      maxLength: maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.none,
      keyboardType: keyboard,
      cursorColor: AppColor.actionPrimary,
      decoration: _boxDecoration(
        hint: hint,
        enabled: enabled,
        suffix: suffix,
        counter: counter,
      ),
      onChanged: onChanged,
    );
  }
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
            onTap: picking || photos.length >= maxListingPhotos ? null : onAdd,
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
                  Text(
                    '${photos.length}/$maxListingPhotos',
                    style: AppText.caption,
                  ),
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
