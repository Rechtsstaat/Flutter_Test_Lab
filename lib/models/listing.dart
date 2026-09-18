import '../fields.dart';

/// 진행 중 (anything still live or in progress) / 종료 (nothing left live).
enum ListingStatus { advertising, closed }

/// Why a listing stopped advertising. The hi-fi's 102 only offers
/// "광고를 종료할래요", but records written by the lo-fi build may carry the
/// other two, so they stay readable.
enum ClosedReason { dealDone, adEnded, takenByOthers }

extension ClosedReasonLabel on ClosedReason {
  String get label => switch (this) {
    ClosedReason.dealDone => '거래 완료',
    ClosedReason.adEnded => '광고 종료',
    ClosedReason.takenByOthers => '타 중개사 계약',
  };
}

/// Per-channel state. The Process Hub renders one row per channel straight
/// from this, and the home card and 광고 상태 card reuse the same reading.
///
/// [needsCheck] is 205's "확인이 필요해요": the adapter finished, but the agent
/// still has to look at the form and press the platform's own 등록 button.
/// [failed] is 206's "연결이 어려워요": the platform page never came up.
enum ChannelState { pending, working, needsCheck, published, failed, removed }

extension ChannelStateLabel on ChannelState {
  /// The short status a listing card and the 광고 상태 card print.
  String get statusLabel => switch (this) {
    ChannelState.pending => '미등록',
    ChannelState.working => '입력 중',
    ChannelState.needsCheck => '확인 필요',
    ChannelState.published => '광고 중',
    ChannelState.failed => '연결 오류',
    ChannelState.removed => '광고 종료',
  };
}

class Listing {
  Listing({
    required this.id,
    required this.createdAt,
    required this.values,
    required this.channels,
    this.channelDates = const {},
    this.photoPaths = const [],
    this.status = ListingStatus.advertising,
    this.closedReason,
    this.closedAt,
  });

  final String id;
  final DateTime createdAt;

  /// The full 50-row master record. Keeping it whole is what lets 수정 reopen
  /// the form pre-filled and lets each mirror adapter receive exactly what it
  /// received the first time.
  final Map<String, dynamic> values;
  final Map<ListingPlatform, ChannelState> channels;

  /// When each channel last reached [ChannelState.published] or
  /// [ChannelState.removed] — the 등록일 / 종료일 the status cards print.
  final Map<ListingPlatform, DateTime> channelDates;
  final List<String> photoPaths;
  final ListingStatus status;
  final ClosedReason? closedReason;
  final DateTime? closedAt;

  String get title {
    final given = '${values['title'] ?? ''}'.trim();
    if (given.isNotEmpty) return given;
    final address = '${values['address'] ?? ''}'.trim();
    return address.isEmpty ? '이름 없는 매물' : address;
  }

  String get address => '${values['address'] ?? ''}'.trim();

  /// The address without its 시·도 / 시·군·구 prefix, plus the building name —
  /// "효자로 62 테라비아타in 지곡".
  String get placeName {
    final parts = address.split(RegExp(r'\s+'))..removeWhere((p) => p.isEmpty);
    while (parts.length > 2 &&
        RegExp(r'(특별시|광역시|특별자치시|특별자치도|도|시|군|구)$').hasMatch(parts.first)) {
      parts.removeAt(0);
    }
    final building = '${values['buildingName'] ?? ''}'.trim();
    final place = [...parts, if (building.isNotEmpty) building].join(' ');
    return place.isEmpty ? title : place;
  }

  /// A value with its unit, unless it is not a bare number ("반지하", "옥탑")
  /// or already carries the unit.
  String _suffixed(String key, String suffix) {
    final raw = '${values[key] ?? ''}'.trim();
    if (raw.isEmpty) return '';
    return RegExp(r'^\d+$').hasMatch(raw) ? '$raw$suffix' : raw;
  }

  /// 101's card name: place and unit.
  String get headline =>
      [placeName, _suffixed('unit', '호')].where((p) => p.isNotEmpty).join(' ');

  /// 102's heading: place, 동 (unless it is a single building) and unit.
  String get fullName => [
    placeName,
    if (values['singleBuilding'] != true) _suffixed('building', '동'),
    _suffixed('unit', '호'),
  ].where((p) => p.isNotEmpty).join(' ');

  /// "아파트 · 59m² · 8층"
  String get factLine => [
    '${values['propertyType'] ?? ''}'.trim(),
    if ('${values['exclusiveArea'] ?? ''}'.trim().isNotEmpty)
      '${values['exclusiveArea']}m²',
    _suffixed('floor', '층'),
  ].where((p) => p.isNotEmpty).join(' · ');

  /// "월세 1000/65", "전세 1억 8000", "매매 12억" — the one line the card and the
  /// detail sheet both lead with.
  String get priceLine {
    final trade = '${values['trade'] ?? ''}'.trim();
    String won(Object? raw) {
      final man = num.tryParse('${raw ?? ''}'.replaceAll(',', ''));
      if (man == null) return '${raw ?? ''}';
      if (man < 10000) return _thousands(man);
      final eok = man ~/ 10000;
      final rest = (man % 10000).toInt();
      return rest == 0 ? '$eok억' : '$eok억 ${_thousands(rest)}';
    }

    return switch (trade) {
      '월세' => '월세 ${won(values['deposit'])}/${won(values['monthlyRent'])}',
      '전세' => '전세 ${won(values['deposit'])}',
      '매매' => '매매 ${won(values['salePrice'])}',
      _ => trade.isEmpty ? '금액 미입력' : trade,
    };
  }

  static String _thousands(num value) {
    final digits = value.toInt().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// 지금 내릴 수 있는 광고. 잠시 내려 둔 플랫폼은 예전 기록에 남아 있어도 뺀다 —
  /// 그 플랫폼으로는 종료 흐름을 돌릴 수 없기 때문이다.
  List<ListingPlatform> get liveChannels => channels.entries
      .where(
        (entry) =>
            entry.value == ChannelState.published && entry.key.isLive,
      )
      .map((entry) => entry.key)
      .toList();

  Listing copyWith({
    Map<String, dynamic>? values,
    Map<ListingPlatform, ChannelState>? channels,
    Map<ListingPlatform, DateTime>? channelDates,
    List<String>? photoPaths,
    ListingStatus? status,
    ClosedReason? closedReason,
    DateTime? closedAt,
  }) => Listing(
    id: id,
    createdAt: createdAt,
    values: values ?? this.values,
    channels: channels ?? this.channels,
    channelDates: channelDates ?? this.channelDates,
    photoPaths: photoPaths ?? this.photoPaths,
    status: status ?? this.status,
    closedReason: closedReason ?? this.closedReason,
    closedAt: closedAt ?? this.closedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'values': values,
    'channels': {
      for (final entry in channels.entries) entry.key.name: entry.value.name,
    },
    'channelDates': {
      for (final entry in channelDates.entries)
        entry.key.name: entry.value.toIso8601String(),
    },
    'photoPaths': photoPaths,
    'status': status.name,
    if (closedReason != null) 'closedReason': closedReason!.name,
    if (closedAt != null) 'closedAt': closedAt!.toIso8601String(),
  };

  /// Unknown enum names are dropped rather than thrown on, so a store written
  /// by an older build still opens instead of taking the whole list with it.
  static Listing? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final createdAt = DateTime.tryParse('${json['createdAt']}');
    if (id is! String || createdAt == null) return null;
    final rawChannels = json['channels'];
    final channels = <ListingPlatform, ChannelState>{};
    if (rawChannels is Map) {
      for (final entry in rawChannels.entries) {
        final platform = _byName(ListingPlatform.values, '${entry.key}');
        final state = _byName(ChannelState.values, '${entry.value}');
        if (platform != null && state != null) channels[platform] = state;
      }
    }
    final rawDates = json['channelDates'];
    final channelDates = <ListingPlatform, DateTime>{};
    if (rawDates is Map) {
      for (final entry in rawDates.entries) {
        final platform = _byName(ListingPlatform.values, '${entry.key}');
        final date = DateTime.tryParse('${entry.value}');
        if (platform != null && date != null) channelDates[platform] = date;
      }
    }
    return Listing(
      id: id,
      createdAt: createdAt,
      values: Map<String, dynamic>.from(json['values'] as Map? ?? const {}),
      channels: channels,
      channelDates: channelDates,
      photoPaths: List<String>.from(json['photoPaths'] as List? ?? const []),
      status:
          _byName(ListingStatus.values, '${json['status']}') ??
          ListingStatus.advertising,
      closedReason: _byName(ClosedReason.values, '${json['closedReason']}'),
      closedAt: DateTime.tryParse('${json['closedAt']}'),
    );
  }

  static T? _byName<T extends Enum>(List<T> values, String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
