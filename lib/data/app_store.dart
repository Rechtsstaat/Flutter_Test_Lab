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

  /// How many listings 한방 registered this month — the number the completion
  /// screen reports back as "이번 달, 한방이 대신 N번 등록했어요".
  int get registeredThisMonth {
    final now = DateTime.now();
    return _listings
        .where(
          (listing) =>
              listing.createdAt.year == now.year &&
              listing.createdAt.month == now.month,
        )
        .length;
  }

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

  Listing? byId(String id) {
    for (final listing in _listings) {
      if (listing.id == id) return listing;
    }
    return null;
  }

  /// 광고 종료 / 거래 완료 move the listing to the 성사된 광고 tab and mark the
  /// picked channels removed; the untouched ones keep advertising.
  Future<Listing> close(
    Listing listing, {
    required ClosedReason reason,
    required Set<ListingPlatform> channels,
  }) async {
    final next = listing.copyWith(
      channels: {
        for (final entry in listing.channels.entries)
          entry.key: channels.contains(entry.key)
              ? ChannelState.removed
              : entry.value,
      },
      status: ListingStatus.closed,
      closedReason: reason,
      closedAt: DateTime.now(),
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
