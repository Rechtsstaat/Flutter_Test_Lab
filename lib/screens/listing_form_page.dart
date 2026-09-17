import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_store.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../fields.dart';
import '../kakao_address.dart';
import '../models/listing.dart';
import 'publish_flow_page.dart';

/// 201 광고 등록 / 수정.
///
/// The 확정 note grants this screen freedom over its own input layout, so the
/// lo-fi's section-and-chip treatment replaces the old expansion tiles. What it
/// does not grant is dropping rows: all 50 master fields still render, still
/// validate under the same conditions, and still travel to the mirrors intact.
class ListingFormPage extends StatefulWidget {
  const ListingFormPage({
    super.key,
    this.store,
    this.initial,
    this.pickImages,
    this.remotePageBuilder,
  });

  final AppStore? store;

  /// Set when the detail screen's 수정 reopens an existing record.
  final Listing? initial;

  /// Lets integration tests observe the real destination page after the same
  /// user-driven form flow. Production continues to construct RemoteFormPage.
  final Future<List<XFile>> Function()? pickImages;
  final RemotePageBuilder? remotePageBuilder;

  @override
  State<ListingFormPage> createState() => _ListingFormPageState();
}

class _ListingFormPageState extends State<ListingFormPage> {
  final values = <String, dynamic>{};
  final textControllers = <String, TextEditingController>{};
  final photos = <XFile>[];
  final _channels = <ListingPlatform>{};

  bool _pickingPhotos = false;
  String? _photoError;
  String? error;
  bool _showAllGroups = false;

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
  }

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
              manageFeeItems.any((fee) => '${details[fee] ?? ''}'.isEmpty)) {
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
    if (photos.length > 20) {
      violations.add('45. 실제로 선택된 매물 사진 최대 20장');
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

  /// 임시저장 — the 확정 note asks for it explicitly: a half-filled listing has
  /// to survive leaving the screen, so it is saved with no channels published.
  Future<void> _saveDraft() async {
    final store = widget.store;
    if (store == null) return;
    await store.save(_compose(const {}));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('임시 저장했어요')));
    Navigator.of(context).pop();
  }

  Listing _compose(Map<ListingPlatform, ChannelState> channels) {
    final record = Map<String, dynamic>.from(values);
    if (photos.isEmpty) record.remove('photoCount');
    return Listing(
      id:
          widget.initial?.id ??
          'L${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      createdAt: widget.initial?.createdAt ?? DateTime.now(),
      values: record,
      channels: channels.isEmpty
          ? {for (final platform in _channels) platform: ChannelState.pending}
          : channels,
      photoPaths: photos.map((photo) => photo.path).toList(),
    );
  }

  void _publish() {
    final violations = _violations();
    if (violations.isNotEmpty) {
      setState(() {
        error = '필수/제한 확인: ${violations.join(', ')}';
        _showAllGroups = true;
      });
      return;
    }
    if (_channels.isEmpty) {
      setState(() => error = '등록할 채널을 한 곳 이상 선택해 주세요.');
      return;
    }
    final targetValues = Map<String, dynamic>.from(values);
    final targetPhotos = List<XFile>.unmodifiable(photos);
    if (targetPhotos.isEmpty) targetValues.remove('photoCount');

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PublishFlowPage(
          store: widget.store,
          listing: _compose(const {}),
          values: targetValues,
          photos: targetPhotos,
          channels: ListingPlatform.values.where(_channels.contains).toList(),
          remotePageBuilder: widget.remotePageBuilder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: _bar(editing ? '광고 수정' : '광고 등록'),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Insets.gutter,
                4,
                Insets.gutter,
                24,
              ),
              children: [
                Text(
                  editing ? '매물 정보를\n수정해 주세요' : '매물 정보를\n입력해 주세요',
                  style: Type.display,
                ),
                const SizedBox(height: 22),
                _ChannelPicker(
                  linked: widget.store?.linked ?? const {},
                  selected: _channels,
                  onToggle: (platform) => setState(() {
                    if (!_channels.remove(platform)) _channels.add(platform);
                  }),
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(error!),
                ],
                const SizedBox(height: 22),
                for (final (index, group) in groups.indexed) ...[
                  if (index == 0 || _showAllGroups || _opened.contains(index))
                    _Group(
                      title: group.title,
                      children: group.fields
                          .where(_visible)
                          .map(_field)
                          .toList(),
                    )
                  else
                    _CollapsedGroup(
                      title: group.title,
                      count: group.fields.where(_visible).length,
                      onOpen: () => setState(() => _opened.add(index)),
                    ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          _Footer(
            channels: _channels.length,
            canPublish: _violations().isEmpty && _channels.isNotEmpty,
            onDraft: widget.store == null ? null : _saveDraft,
            onPublish: _publish,
          ),
        ],
      ),
    );
  }

  final _opened = <int>{};

  PreferredSizeWidget _bar(String title) => AppBar(
    backgroundColor: Brand.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.chevron_left_rounded, size: 30, color: Brand.ink),
      onPressed: () => Navigator.of(context).maybePop(),
    ),
    title: Text(title, style: Type.title),
    centerTitle: false,
    titleSpacing: 0,
    actions: [
      TextButton(
        onPressed: _autoFill,
        child: const Text(
          '자동 채우기',
          style: TextStyle(color: Brand.blue, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );

  // ---- field renderers -----------------------------------------------------

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
      return _Row(
        title: title,
        child: Switch.adaptive(
          activeTrackColor: Brand.blue,
          value: values[field.key] == true,
          onChanged: (v) => setState(() => values[field.key] = v),
        ),
      );
    }
    if (field.type == InputType.choice) {
      // Short option sets read better as the lo-fi's segmented chips; long
      // statutory lists (29 building uses, 16 property types) stay a menu.
      if (field.options.length <= 4) {
        return _Block(
          title: title,
          child: _ChipRow(
            options: field.options,
            selected: {if (values[field.key] != null) '${values[field.key]}'},
            onTap: (option) => setState(() => values[field.key] = option),
          ),
        );
      }
      return _Block(
        title: title,
        child: _Dropdown(
          value: values[field.key] as String?,
          hint: field.example,
          options: field.options,
          onChanged: (v) => setState(() => values[field.key] = v),
        ),
      );
    }
    if (field.type == InputType.multiSelect) {
      final selected = List<String>.from(
        values[field.key] as List? ?? const [],
      );
      return _Block(
        title: title,
        child: _ChipRow(
          options: field.options,
          selected: selected.toSet(),
          onTap: (option) => setState(() {
            if (!selected.remove(option)) selected.add(option);
            values[field.key] = selected;
          }),
        ),
      );
    }
    final controller = textControllers.putIfAbsent(
      field.key,
      () => TextEditingController(text: values[field.key]?.toString() ?? ''),
    );
    return _Block(
      title: title,
      child: _Input(
        controller: controller,
        hint: field.example,
        numeric: field.type == InputType.number,
        maxLength: field.maxLength,
        maxLines: field.key == 'description' ? 5 : 1,
        onChanged: (v) => setState(() => values[field.key] = v),
      ),
    );
  }

  Widget _addressSearchField(MasterField field, String title) {
    final address = values[field.key] as String? ?? '';
    final controller = textControllers.putIfAbsent(
      field.key,
      () => TextEditingController(text: address),
    );
    if (controller.text != address) controller.text = address;
    return _Block(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Input(
                  controller: controller,
                  hint: '예) 역삼동 123-4',
                  onChanged: (v) => setState(() => values[field.key] = v),
                ),
              ),
              const SizedBox(width: 8),
              _SearchButton(onTap: () => _searchAddress(field)),
            ],
          ),
          const SizedBox(height: 8),
          Text(_addressHint(), style: Type.caption),
        ],
      ),
    );
  }

  String _addressHint() {
    final address = '${values['address'] ?? ''}'.trim();
    if (address.isEmpty) {
      return '카카오 우편번호 서비스로 도로명·지번·우편번호·법정동 코드를 함께 저장합니다.';
    }
    final jibun = '${values['jibunAddress'] ?? ''}'.trim();
    return [
      if (jibun.isNotEmpty && jibun != address) '지번 $jibun',
      '우편번호 ${values['postalCode'] ?? '-'} · 법정동 ${values['legalDongCode'] ?? '-'}',
    ].join('\n');
  }

  Future<void> _searchAddress(MasterField field) async {
    final result = await Navigator.of(context).push<KakaoAddress>(
      MaterialPageRoute(builder: (_) => const KakaoAddressSearchPage()),
    );
    if (result != null && mounted) {
      setState(() {
        values.addAll(result.toFormValues());
        textControllers[field.key]?.text = '${values[field.key] ?? ''}';
      });
    }
  }

  Widget _loanField(MasterField field, String title) => _Block(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChipRow(
          options: const ['없음', '있음'],
          labels: const {'없음': '융자금 없음', '있음': '융자금 있음'},
          selected: {if (values[field.key] != null) '${values[field.key]}'},
          onTap: (option) => setState(() {
            values[field.key] = option;
            if (option != '있음') values.remove('loanAmount');
          }),
        ),
        if (values[field.key] == '있음') ...[
          const SizedBox(height: 10),
          _Input(
            hint: '융자금 금액 (만원)',
            numeric: true,
            onChanged: (value) => values['loanAmount'] = value,
          ),
        ],
      ],
    ),
  );

  Widget _manageDetailsField(MasterField field, String title) {
    final details = Map<String, String>.from(
      values[field.key] as Map? ?? const <String, String>{},
    );
    return _Block(
      title: title,
      child: Column(
        children: [
          for (final fee in manageFeeItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(width: 92, child: Text(fee, style: Type.body)),
                  Expanded(
                    child: _ChipRow(
                      options: const ['정액 부과', '실비 부과'],
                      selected: {if (details[fee] != null) details[fee]!},
                      onTap: (option) => setState(() {
                        details[fee] = option;
                        values[field.key] = details;
                      }),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
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
      if (selected.length > 20) {
        setState(() => _photoError = '사진은 최대 20장까지 선택할 수 있어요.');
        return;
      }
      setState(() {
        photos
          ..clear()
          ..addAll(selected);
        values['photoCount'] = photos.length;
      });
    } catch (e) {
      if (mounted) setState(() => _photoError = '사진 선택 오류: $e');
    } finally {
      if (mounted) setState(() => _pickingPhotos = false);
    }
  }

  Widget _photoField(String title) => _Block(
    title: '$title (선택, 최대 20장)',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '사진 없이도 전송할 수 있습니다. 사진을 선택하면 1~20장을 다방·당근 미러에 자동 첨부합니다(당근은 PNG·JPEG·GIF·WebP만). 직방 미러는 사진 첨부를 아직 지원하지 않으며, 장당 최대 30MB입니다.',
          style: Type.caption,
        ),
        const SizedBox(height: 10),
        BrandButton(
          _pickingPhotos ? '사진을 불러오는 중…' : '사진 선택 (${photos.length}/20장)',
          kind: BrandButtonKind.outlined,
          onPressed: _pickingPhotos ? null : _pickPhotos,
        ),
        if (_photoError != null) ...[
          const SizedBox(height: 8),
          Text(
            _photoError!,
            style: const TextStyle(color: Brand.danger, fontSize: 13),
          ),
        ],
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < photos.length; i++)
                SizedBox(
                  width: 100,
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(photos[i].path),
                          width: 100,
                          height: 80,
                          fit: BoxFit.cover,
                          cacheWidth: 200,
                          errorBuilder: (_, _, _) => const SizedBox(
                            height: 80,
                            child: PhotoPlaceholder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        i == 0 ? '대표사진' : '${i + 1}번 사진',
                        style: Type.caption,
                      ),
                      IconButton(
                        tooltip: '${i + 1}번 사진 삭제',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          photos.removeAt(i);
                          values['photoCount'] = photos.length;
                        }),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

// ---- presentation pieces ---------------------------------------------------

class _ChannelPicker extends StatelessWidget {
  const _ChannelPicker({
    required this.linked,
    required this.selected,
    required this.onToggle,
  });

  final Set<ListingPlatform> linked;
  final Set<ListingPlatform> selected;
  final ValueChanged<ListingPlatform> onToggle;

  @override
  Widget build(BuildContext context) {
    final choices = linked.isEmpty ? ListingPlatform.values : linked.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('등록할 채널'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final platform in ListingPlatform.values)
              if (choices.contains(platform))
                GestureDetector(
                  onTap: () => onToggle(platform),
                  child: AnimatedContainer(
                    duration: Motion.quick,
                    padding: const EdgeInsets.fromLTRB(8, 7, 14, 7),
                    decoration: BoxDecoration(
                      color: selected.contains(platform)
                          ? platform.tint
                          : Brand.canvas,
                      borderRadius: BorderRadius.circular(Insets.radiusPill),
                      border: Border.all(
                        color: selected.contains(platform)
                            ? platform.color
                            : Brand.hairline,
                        width: selected.contains(platform) ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PlatformBadge(
                          platform,
                          size: 24,
                          dimmed: !selected.contains(platform),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          platform.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: selected.contains(platform)
                                ? Brand.ink
                                : Brand.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => FadeSlideIn(
    offset: -8,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.dangerTint,
        borderRadius: BorderRadius.circular(Insets.radiusField),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 13, height: 1.45, color: Brand.danger),
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 12),
        child: Text(title, style: Type.title.copyWith(fontSize: 16)),
      ),
      ...children,
    ],
  );
}

class _CollapsedGroup extends StatelessWidget {
  const _CollapsedGroup({
    required this.title,
    required this.count,
    required this.onOpen,
  });

  final String title;
  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onOpen,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Brand.canvas,
        borderRadius: BorderRadius.circular(Insets.radiusField),
      ),
      child: Row(
        children: [
          Text(title, style: Type.body.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text('$count개 항목', style: Type.caption),
          const Spacer(),
          const Icon(Icons.expand_more_rounded, color: Brand.inkMuted),
        ],
      ),
    ),
  );
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [SectionLabel(title), child],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(child: Text(title, style: Type.body)),
        child,
      ],
    ),
  );
}

class _Input extends StatelessWidget {
  const _Input({
    this.controller,
    required this.hint,
    this.numeric = false,
    this.maxLength,
    this.maxLines = 1,
    this.onChanged,
  });

  final TextEditingController? controller;
  final String hint;
  final bool numeric;
  final int? maxLength;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    style: Type.body,
    maxLength: maxLength,
    maxLines: maxLines,
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: Type.bodyMuted,
      filled: true,
      fillColor: Brand.canvas,
      counterStyle: Type.caption,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Insets.radiusField),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Insets.radiusField),
        borderSide: const BorderSide(color: Brand.blue, width: 1.4),
      ),
    ),
    onChanged: onChanged,
  );
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Brand.blueTint,
        borderRadius: BorderRadius.circular(Insets.radiusField),
      ),
      child: const Text(
        '주소검색',
        style: TextStyle(
          color: Brand.blue,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
  );
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.options,
    required this.selected,
    required this.onTap,
    this.labels = const {},
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onTap;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final option in options)
        GestureDetector(
          onTap: () => onTap(option),
          child: AnimatedContainer(
            duration: Motion.quick,
            curve: Motion.enter,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: selected.contains(option) ? Brand.blueFaint : Brand.canvas,
              borderRadius: BorderRadius.circular(Insets.radiusField),
              border: Border.all(
                color: selected.contains(option) ? Brand.blue : Brand.hairline,
                width: selected.contains(option) ? 1.4 : 1,
              ),
            ),
            child: Text(
              labels[option] ?? option,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected.contains(option) ? Brand.blue : Brand.ink,
              ),
            ),
          ),
        ),
    ],
  );
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.hint,
    required this.options,
    required this.onChanged,
  });

  final String? value;
  final String hint;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    style: Type.body,
    hint: Text(hint, style: Type.bodyMuted),
    decoration: InputDecoration(
      filled: true,
      fillColor: Brand.canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Insets.radiusField),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Insets.radiusField),
        borderSide: const BorderSide(color: Brand.blue, width: 1.4),
      ),
    ),
    items: options
        .map((o) => DropdownMenuItem(value: o, child: Text(o)))
        .toList(),
    onChanged: onChanged,
  );
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.channels,
    required this.canPublish,
    required this.onDraft,
    required this.onPublish,
  });

  final int channels;
  final bool canPublish;
  final VoidCallback? onDraft;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(Insets.gutter, 12, Insets.gutter, 16),
    decoration: const BoxDecoration(
      color: Brand.surface,
      border: Border(top: BorderSide(color: Brand.hairline)),
    ),
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          if (onDraft != null) ...[
            Expanded(
              child: BrandButton(
                '임시저장',
                kind: BrandButtonKind.outlined,
                onPressed: onDraft,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: 2,
            child: BrandButton(
              channels == 0 ? '채널을 선택해 주세요' : '선택한 $channels개 채널에 등록하기',
              onPressed: canPublish ? onPublish : null,
            ),
          ),
        ],
      ),
    ),
  );
}
