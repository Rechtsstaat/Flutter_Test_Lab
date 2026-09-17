import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'android_layout.dart';
import 'fields.dart';
import 'photo_transfer.dart';
import 'remote_form.dart';

/// The master field data and the mirror engine now live in their own
/// libraries. Re-exporting them keeps every existing import of main.dart
/// working, so this change stays a pure move.
export 'fields.dart';
export 'remote_form.dart';

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
  const ListingFormPage({super.key, this.pickImages, this.remotePageBuilder});

  /// Lets integration tests observe the real destination page after the same
  /// user-driven form flow. Production continues to construct [RemoteFormPage]
  /// below.
  final Future<List<XFile>> Function()? pickImages;
  final Widget Function(
    Map<String, dynamic> values,
    ListingPlatform platform,
    List<XFile> photos,
  )?
  remotePageBuilder;
  @override
  State<ListingFormPage> createState() => _ListingFormPageState();
}

class _ListingFormPageState extends State<ListingFormPage> {
  final values = <String, dynamic>{};
  final textControllers = <String, TextEditingController>{};
  final photos = <XFile>[];
  bool _pickingPhotos = false;
  String? _photoError;
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
            for (final fee in manageFeeItems)
              fee: (values['manageIncludes'] as List? ?? const []).contains(fee)
                  ? '정액 부과'
                  : '실비 부과',
          };
        case InputType.addressSearch:
          values[field.key] = field.example;
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

  void _send(ListingPlatform platform) {
    final violations = _violations();
    if (violations.isNotEmpty) {
      setState(() => error = '필수/제한 확인: ${violations.join(', ')}');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          final targetValues = Map<String, dynamic>.from(values);
          final targetPhotos = List<XFile>.unmodifiable(photos);
          if (targetPhotos.isEmpty) targetValues.remove('photoCount');
          return widget.remotePageBuilder?.call(
                targetValues,
                platform,
                targetPhotos,
              ) ??
              RemoteFormPage(
                values: targetValues,
                platform: platform,
                photos: targetPhotos,
              );
        },
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
      padding: const EdgeInsets.all(16) + androidBottomInset(context),
      children: [
        const Text(
          '직방·다방·당근 통합 명세 50개 항목',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('플랫폼마다 지원하지 않는 항목은 전송 결과에서 명확히 안내합니다.'),
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
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _violations().isEmpty
              ? () => _send(ListingPlatform.daangn)
              : null,
          icon: const Icon(Icons.send),
          label: const Text('당근에 보내기'),
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
          ...manageFeeItems.map(
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
        throw const FormatException('사진은 최대 20장까지 선택할 수 있습니다.');
      }
      for (final photo in selected) {
        await validateListingPhoto(photo);
      }
      if (!mounted) return;
      setState(() {
        photos
          ..clear()
          ..addAll(selected);
        values['photoCount'] = photos.length;
        error = null;
      });
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => _photoError = '사진을 열지 못했습니다. 사진 접근 권한을 확인해 주세요. (${e.code})',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _photoError = '사진 선택 오류: $e');
    } finally {
      if (mounted) setState(() => _pickingPhotos = false);
    }
  }

  Widget _photoField(String title) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title (선택, 최대 20장)'),
        const SizedBox(height: 8),
        const Text(
          '사진 없이도 전송할 수 있습니다. 사진을 선택하면 1~20장을 다방·당근 미러에 자동 첨부합니다(당근은 PNG·JPEG·GIF·WebP만). 직방 미러는 사진 첨부를 아직 지원하지 않으며, 장당 최대 30MB입니다.',
        ),
        OutlinedButton.icon(
          onPressed: _pickingPhotos ? null : _pickPhotos,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(
            _pickingPhotos ? '사진을 불러오는 중…' : '사진 선택 (${photos.length}/20장)',
          ),
        ),
        if (_photoError != null)
          Text(_photoError!, style: const TextStyle(color: Colors.red)),
        if (photos.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < photos.length; i++)
                SizedBox(
                  width: 100,
                  child: Column(
                    children: [
                      Image.file(
                        File(photos[i].path),
                        width: 100,
                        height: 80,
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                        errorBuilder: (_, _, _) => const SizedBox(
                          height: 80,
                          child: Icon(Icons.image),
                        ),
                      ),
                      Text(i == 0 ? '대표사진' : '${i + 1}번 사진'),
                      IconButton(
                        tooltip: '${i + 1}번 사진 삭제',
                        icon: const Icon(Icons.close),
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
    ),
  );
}
