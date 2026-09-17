import '../fields.dart';

/// 나의 광고 / 성사된 광고 — the two tabs the lo-fi splits the home list into.
enum ListingStatus { advertising, closed }

/// The lo-fi's 개선 note asks for 거래 완료 and 광고 종료 to stop sharing the word
/// "삭제", and for a listing another agent closed to leave the list on its own.
/// Keeping the reason on the record is what lets the home banner say which of
/// the three happened.
enum ClosedReason { dealDone, adEnded, takenByOthers }

extension ClosedReasonLabel on ClosedReason {
  String get label => switch (this) {
    ClosedReason.dealDone => '거래 완료',
    ClosedReason.adEnded => '광고 종료',
    ClosedReason.takenByOthers => '타 중개사 계약',
  };
}

/// Per-channel publishing state. The 과정 신뢰 screen renders one row per
/// channel straight from this.
enum ChannelState { pending, working, published, failed, removed }

extension ChannelStateLabel on ChannelState {
  String get publishLabel => switch (this) {
    ChannelState.pending => '대기 중',
    ChannelState.working => '올리는 중',
    ChannelState.published => '완료',
    ChannelState.failed => '확인 필요',
    ChannelState.removed => '내려감',
  };

  String get takedownLabel => switch (this) {
    ChannelState.pending => '대기 중',
    ChannelState.working => '내리는 중',
    ChannelState.published => '노출 중',
    ChannelState.failed => '확인 필요',
    ChannelState.removed => '삭제 완료',
  };
}

class Listing {
  Listing({
    required this.id,
    required this.createdAt,
    required this.values,
    required this.channels,
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

  List<ListingPlatform> get liveChannels => channels.entries
      .where((entry) => entry.value == ChannelState.published)
      .map((entry) => entry.key)
      .toList();

  Listing copyWith({
    Map<String, dynamic>? values,
    Map<ListingPlatform, ChannelState>? channels,
    List<String>? photoPaths,
    ListingStatus? status,
    ClosedReason? closedReason,
    DateTime? closedAt,
  }) => Listing(
    id: id,
    createdAt: createdAt,
    values: values ?? this.values,
    channels: channels ?? this.channels,
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
    return Listing(
      id: id,
      createdAt: createdAt,
      values: Map<String, dynamic>.from(json['values'] as Map? ?? const {}),
      channels: channels,
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
