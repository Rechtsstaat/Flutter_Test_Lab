import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../fields.dart';
import '../models/listing.dart';

/// Everything the app remembers between launches: which platforms the agent
/// linked, and every listing they registered. One JSON file keeps the two in
/// step — a listing's channel rows are only meaningful next to the accounts
/// that produced them.
class AppStore extends ChangeNotifier {
  AppStore({Directory? directory}) : _directory = directory;

  static const fileName = 'hanbang_store.json';

  final Directory? _directory;
  File? _file;

  bool _loaded = false;
  bool get loaded => _loaded;

  final List<Listing> _listings = [];
  List<Listing> get listings => List.unmodifiable(_listings);

  final Set<ListingPlatform> _linked = {};
  Set<ListingPlatform> get linked => Set.unmodifiable(_linked);

  /// The lo-fi's splash decides between onboarding and home on exactly this.
  bool get onboarded => _onboarded;
  bool _onboarded = false;

  List<Listing> get advertising => _listings
      .where((listing) => listing.status == ListingStatus.advertising)
      .toList();

  List<Listing> get closed => _listings
      .where((listing) => listing.status == ListingStatus.closed)
      .toList();

  Future<void> load() async {
    final file = await _resolve();
    try {
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map<String, dynamic>) _apply(raw);
      }
    } on FormatException {
      // A half-written or hand-edited store must not brick the app. Starting
      // empty is recoverable; refusing to launch is not.
    } on FileSystemException {
      // Same reasoning: read failures fall back to an empty store.
    }
    _loaded = true;
    notifyListeners();
  }

  void _apply(Map<String, dynamic> raw) {
    _listings
      ..clear()
      ..addAll(
        (raw['listings'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(Listing.fromJson)
            .whereType<Listing>(),
      );
    _linked
      ..clear()
      ..addAll(
        (raw['linked'] as List? ?? const [])
            .map((name) => _platform('$name'))
            .whereType<ListingPlatform>(),
      );
    _onboarded = raw['onboarded'] == true;
    _sort();
  }

  static ListingPlatform? _platform(String name) {
    for (final platform in ListingPlatform.values) {
      if (platform.name == name) return platform;
    }
    return null;
  }

  Future<File> _resolve() async {
    final directory = _directory ?? await getApplicationDocumentsDirectory();
    return _file ??= File('${directory.path}/$fileName');
  }

  Future<void> _persist() async {
    final file = await _resolve();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'onboarded': _onboarded,
        'linked': _linked.map((platform) => platform.name).toList(),
        'listings': _listings.map((listing) => listing.toJson()).toList(),
      }),
    );
  }

  void _sort() => _listings.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> completeOnboarding(Set<ListingPlatform> platforms) async {
    _linked
      ..clear()
      ..addAll(platforms);
    _onboarded = true;
    notifyListeners();
    await _persist();
  }

  /// 로그아웃 — 0011 부터 다시 지날 수 있게 되돌린다. 매물 기록은 남긴다:
  /// 지워지는 것은 「어느 플랫폼에 연결돼 있나」뿐이다. 플랫폼이 웹뷰에 심어 둔
  /// 로그인은 여기서 못 지운다 — [clearPlatformSessions] 가 짝이다.
  Future<void> signOut() async {
    _linked.clear();
    _onboarded = false;
    notifyListeners();
    await _persist();
  }

  Future<void> save(Listing listing) async {
    final index = _listings.indexWhere((item) => item.id == listing.id);
    if (index == -1) {
      _listings.add(listing);
    } else {
      _listings[index] = listing;
    }
    _sort();
    notifyListeners();
    await _persist();
  }

  /// 플랫폼이 이 매물에 붙인 번호를 적어 둔다.
  ///
  /// 등록 직후에 읽어 두지만, 그때 목록이 아직 안 그려졌거나 닮은 매물이 둘이어서
  /// 못 읽는 일이 있다. 내릴 때 뒤늦게 읽어 내면 여기로 들어온다 — 이미 적힌 것과
  /// 같으면 저장소를 건드리지 않는다.
  Future<Listing> rememberNumber(
    Listing listing,
    ListingPlatform platform,
    String number,
  ) async {
    final current = byId(listing.id) ?? listing;
    if (current.channelNumbers[platform] == number) return current;
    final next = current.copyWith(
      channelNumbers: {...current.channelNumbers, platform: number},
    );
    await save(next);
    return next;
  }

  Listing? byId(String id) {
    for (final listing in _listings) {
      if (listing.id == id) return listing;
    }
    return null;
  }

  /// 301 marks the picked channels removed; the untouched ones keep
  /// advertising. 301 says "선택한 플랫폼에서만 광고가 내려갑니다", so the listing
  /// only leaves 진행 중 once nothing is left live — or still waiting on the
  /// agent's check — anywhere.
  Future<Listing> close(
    Listing listing, {
    required ClosedReason reason,
    required Set<ListingPlatform> channels,
  }) async {
    final remaining = {
      for (final entry in listing.channels.entries)
        entry.key: channels.contains(entry.key)
            ? ChannelState.removed
            : entry.value,
    };
    final stillLive = remaining.values.any(
      (state) =>
          state == ChannelState.published || state == ChannelState.needsCheck,
    );
    final now = DateTime.now();
    final next = listing.copyWith(
      channels: remaining,
      channelDates: {
        ...listing.channelDates,
        for (final platform in channels) platform: now,
      },
      status: stillLive ? ListingStatus.advertising : ListingStatus.closed,
      closedReason: stillLive ? null : reason,
      closedAt: stillLive ? null : now,
    );
    await save(next);
    return next;
  }

  Future<void> remove(String id) async {
    _listings.removeWhere((listing) => listing.id == id);
    notifyListeners();
    await _persist();
  }
}
