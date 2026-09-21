import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart'
    show AndroidWebViewController;

import 'android_layout.dart';
import 'fields.dart';
import 'listing_rules.dart';
import 'mobile_layout.dart';
import 'photo_transfer.dart';
import 'remote_form.dart';
import 'takedown.dart';

/// The mirror serves `.../oneroom/index.html` as a 308 to `.../oneroom/`, and
/// the live sites drop the trailing slash, so the URL that finishes never
/// equals the configured one. Comparing the directory form keeps every
/// spelling pointing at one page.
String mirrorDirectory(Uri uri) => pageDirectory(uri);

/// One platform page living inside a native 한방 screen.
///
/// The hi-fi keeps the screen in 한방's hands while the platform's own page
/// runs underneath it, and lifts that page into view whenever the agent should
/// see it. That only works if the page outlives the widgets that show it, so
/// the [WebViewController] lives here rather than in a widget's state.
///
/// Besides loading, it listens for the agent pressing one of [watchLabels] —
/// the platform's own 등록 or 종료 button. Only trusted (human) clicks count,
/// so nothing an adapter dispatches can ever be mistaken for the agent.
class MirrorPage extends ChangeNotifier {
  MirrorPage({
    required this.platform,
    required Uri url,
    this.watchLabels = const [],
    this.loadTimeout,
  }) : initialUrl = url {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(_pressChannel, onMessageReceived: _pressed)
      // iOS uses this otherwise-unused channel as an exact, per-WebView
      // rendezvous point for the native all-frame script bridge.
      ..addJavaScriptChannel(_frameTargetChannel, onMessageReceived: (_) {})
      ..addJavaScriptChannel(_autoAnswerChannel, onMessageReceived: _autoAnswer)
      ..setOnJavaScriptConfirmDialog(_confirm)
      ..setOnJavaScriptAlertDialog(_alert);
    configure(controller);
    controller.setNavigationDelegate(
      NavigationDelegate(
        onHttpAuthRequest: (request) {
          // Only the mirror sits behind Basic auth. A live platform asking for
          // it is not something 한방 has credentials for.
          if (request.host == mirrorHost && initialUrl.host == mirrorHost) {
            request.onProceed(
              const WebViewCredential(user: 'mirror', password: 'money'),
            );
          } else {
            request.onCancel();
          }
        },
        onWebResourceError: (error) {
          // A failed CDN image or public-data call must not fail the page.
          if (error.isForMainFrame == false) return;
          fail('페이지를 열지 못했어요 (${error.description})');
        },
        onHttpError: (error) {
          final uri = error.request?.uri;
          final code = error.response?.statusCode ?? 0;
          // Only the page itself matters, and 401 is the Basic-auth handshake.
          if (uri == null || code == 401 || !_samePage(uri)) return;
          fail('페이지가 응답하지 않아요 (HTTP $code)');
        },
        onPageFinished: _pageFinished,
        // 다방프로는 한 장짜리 앱이라 로그인으로 되돌려 보내는 것도, 로그인 뒤 대시보드로
        // 가는 것도 페이지 로드 없이 **주소만** 바꾼다. 그것은 여기로만 들린다.
        onUrlChange: (change) => _urlChanged(change.url),
      ),
    );
    controller.loadRequest(url);
    final timeout = loadTimeout;
    if (timeout != null) {
      _timeout = Timer(timeout, () {
        if (!isSettled) fail('응답을 기다리다 멈췄어요');
      });
    }
  }

  static const _pressChannel = 'MirrorPress';
  static int _nextFrameTarget = 0;

  /// 어댑터가 「지금부터 내가 누른다」·「다 눌렀다」를 알리는 채널([autoAnswerScript]).
  static const _autoAnswerChannel = 'FlrAutoAnswer';

  final String _frameTargetChannel = 'FrameScriptTarget_${_nextFrameTarget++}';

  final ListingPlatform platform;
  final Uri initialUrl;
  final List<String> watchLabels;
  final Duration? loadTimeout;
  late final WebViewController controller;
  Timer? _timeout;
  bool _disposed = false;

  bool loaded = false;
  String? failure;

  /// 플랫폼 페이지의 `confirm()` 을 사람에게 묻는 곳. 화면이 붙여 준다.
  ///
  /// **붙이지 않으면 WebView 는 확인 창마다 「취소」로 답한다**(webview_flutter 의
  /// 기본값, iOS·Android 모두). 다방은 매물 유형을 바꿀 때와 관리비 부과 방식 탭을
  /// 바꿀 때 `confirm()` 으로 되묻고 「취소」면 아무것도 바꾸지 않는다 — 그래서 예전에는
  /// 오피스텔·아파트로도, 관리비 「기타부과」·「확인불가」로도 끝내 넘어가지 못했다
  /// (실물 번들 실측 2026-09-21).
  Future<bool> Function(String message)? onConfirm;

  /// 플랫폼 페이지의 `alert()` 을 사람에게 보여 주는 곳. 없으면 조용히 넘긴다.
  Future<void> Function(String message)? onAlert;

  /// 어댑터가 페이지를 다루는 중인가. 그동안의 확인 창은 어댑터가 부른 것이라 「확인」으로
  /// 답하고, 알림은 사람을 붙잡지 않고 [pageAlerts] 에 적어 둔다.
  bool autoAnswering = false;

  /// 어댑터가 도는 동안 페이지가 띄운 알림 — 사람이 봐야 할 말일 수 있어 남겨 둔다.
  final pageAlerts = <String>[];

  void _autoAnswer(JavaScriptMessage message) {
    autoAnswering = message.message == 'on';
  }

  /// 사진 다리가 페이지를 다루는 중인가 — 그동안도 사람을 붙잡지 않는다.
  @protected
  bool photosRunning = false;

  Future<bool> _confirm(JavaScriptConfirmDialogRequest request) async {
    if (_disposed) return false;
    if (autoAnswering || photosRunning) return true;
    final ask = onConfirm;
    // 사람이 누른 것의 확인 창은 **사람이 답한다.** 물을 화면이 없으면 예전처럼
    // 「취소」다 — 광고 종료처럼 되돌릴 수 없는 확인을 한방이 대신 누르지 않는다.
    return ask == null ? false : await ask(request.message);
  }

  Future<void> _alert(JavaScriptAlertDialogRequest request) async {
    if (_disposed) return;
    if (autoAnswering || photosRunning) {
      final message = request.message.trim();
      if (message.isNotEmpty && !pageAlerts.contains(message)) {
        pageAlerts.add(message);
      }
      return;
    }
    await onAlert?.call(request.message);
  }

  /// The label of the platform button the agent pressed, once they have.
  String? pressedLabel;

  /// Whether this page has reached an end state the timeout should not
  /// override.
  bool get isSettled => failure != null || pressedLabel != null || loaded;

  /// Subclasses add their JavaScript channels here, before the first load.
  @protected
  void configure(WebViewController controller) {}

  /// 눌림을 셀 범위를 좁히는 CSS 선택자, 또는 null(페이지 전체).
  /// 왜 좁히는지는 [pressWatcherScript] 에 적었다.
  @protected
  String? get pressScope => null;

  /// 눌림 감시를 지금 상태로 다시 깐다 — [pressScope] 가 바뀐 뒤에 부른다.
  /// 두 번째부터는 울타리와 글자만 바꿔 끼운다.
  @protected
  Future<void> installPressWatcher() async {
    if (watchLabels.isEmpty || _disposed) return;
    try {
      await controller.runJavaScript(
        pressWatcherScript(watchLabels, within: pressScope),
      );
    } catch (_) {
      // A page that navigates away mid-install gets the watcher next load.
    }
  }

  /// 플랫폼이 로그인 화면으로 되돌려 보냈을 때 그것을 실패로 볼 것인가.
  ///
  /// 등록·종료 화면에서 그런 일이 벌어졌다면 **로그인이 풀린 것**이라 거기서 할 수 있는
  /// 일이 없다. 연동 화면([MirrorLogin])만 거기가 목적지라 아니라고 답한다.
  @protected
  bool get leavesOnSignedOut => true;

  /// Called for every finished main-frame load after the press watcher is in,
  /// and after [leavesOnSignedOut] has had its say.
  @protected
  Future<void> onPage(Uri url) async => markLoaded();

  bool _samePage(Uri uri) =>
      uri.host == initialUrl.host && uri.path == initialUrl.path;

  Future<void> _pageFinished(String url) async {
    if (_disposed) return;
    await installPressWatcher();
    final uri = Uri.tryParse(url);
    if (uri == null || _disposed) return;
    if (leavesOnSignedOut && platform.isSignedOut(uri)) {
      fail(signInLost(platform));
      return;
    }
    // Every mirror page the agent stays on is a desktop page, 로그인 and 광고
    // 목록 no less than the form, so all of them get restyled — and before
    // [onPage], so an adapter never fills a form that is still 1200px wide.
    // Restyling is the least important thing here: if it throws, the page and
    // its automation carry on without it.
    final layout = mirrorMobileLayoutScript(platform, uri);
    if (layout != null) {
      try {
        await controller.runJavaScript(layout);
      } catch (_) {
        // A navigation during installation gets a fresh script next load.
      }
    }
    if (_disposed) return;
    await onPage(uri);
  }

  Future<void> _urlChanged(String? url) async {
    if (_disposed || url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (leavesOnSignedOut && platform.isSignedOut(uri)) {
      fail(signInLost(platform));
      return;
    }
    await onRoute(uri);
  }

  /// Called when the page's URL changes without (or before) a page load — a
  /// single-page app moving between its own screens.
  @protected
  Future<void> onRoute(Uri url) async {}

  void _pressed(JavaScriptMessage message) {
    if (_disposed) return;
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      pressedLabel = '${data['label'] ?? ''}';
    } catch (_) {
      pressedLabel = message.message;
    }
    _timeout?.cancel();
    notifyListeners();
  }

  /// 페이지가 답을 했으므로 감시 시계를 내린다.
  ///
  /// 이 시계는 「페이지가 끝내 안 떴다」를 잡는 것이다. 폼이 떠서 어댑터가 돌기
  /// 시작한 뒤의 기다림은 저마다 제 시간과 **제 이유**를 갖고 있으므로(어댑터
  /// [MirrorSession.adapterTimeout], 사진 한 장의 [settleBudget]), 그것들을
  /// 한꺼번에 「응답을 기다리다 멈췄어요」로 덮으면 사람에게 더 나쁜 말을 하게 된다.
  @protected
  void stopLoadTimeout() => _timeout?.cancel();

  @protected
  void markLoaded() {
    if (_disposed || loaded) return;
    loaded = true;
    notifyListeners();
  }

  @protected
  void fail(String reason) {
    if (_disposed || failure != null || pressedLabel != null) return;
    failure = reason;
    _timeout?.cancel();
    notifyListeners();
  }

  /// Back first closes whatever overlay the page put up (the Kakao search).
  /// Answers whether it did, in which case the route should stay.
  Future<bool> closeOverlay() async {
    try {
      final closed = await controller.runJavaScriptReturningResult(
        "typeof window.__flrClosePostcode === 'function' && "
        "window.__flrClosePostcode()",
      );
      return closed == true || closed.toString() == 'true';
    } catch (_) {
      return false;
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timeout?.cancel();
    super.dispose();
  }
}

/// The page the listing is registered on: loads the platform's form, runs its
/// adapter, attaches the photos, then waits for the agent's own 등록 press.
class MirrorSession extends MirrorPage {
  MirrorSession({
    required super.platform,
    required this.values,
    this.photos = const [],
    this.onListingResult,
    this.onPhotoTransferComplete,
    super.loadTimeout = const Duration(minutes: 3),
  }) : super(
         url: Uri.parse(platform.formUrlFor(values)),
         watchLabels: platform.submitLabels,
       ) {
    status = '${platform.label} 페이지를 여는 중…';
  }

  /// The Kakao postcode result list lives in a cross-origin iframe that only a
  /// native frame script can reach: a WKWebView user script on iOS, an
  /// AndroidX document-start script on Android. Both bridges are named
  /// `FrameScriptBridge`.
  static const _frameScripts = MethodChannel('jikbang/frame_script');

  final Map<String, dynamic> values;
  final List<XFile> photos;
  final void Function(WebViewController, Map<String, dynamic>)? onListingResult;
  final void Function(WebViewController, String?)? onPhotoTransferComplete;

  late String status;
  bool filling = false;
  bool picksAddress = false;
  bool _resultIn = false;
  bool _photosDone = true;
  String? _lastInjectedUrl;

  List<String> missing = const [];
  List<String> violations = const [];
  List<String> unsupported = const [];
  List<String> photoNotes = const [];
  String? photoStatus;
  String? photoFailure;

  /// Set when the form's fields never showed up — the page may have changed.
  String? formNotice;

  /// How long a live form gets to render its fields after the page loads.
  static const formReadyTimeout = Duration(seconds: 20);

  /// How long the adapter gets to finish before the photos go in anyway. The
  /// Dabang adapter waits for the address on its own (up to a minute) and then
  /// fills some 40 fields, so this has to be generous.
  static const adapterTimeout = Duration(minutes: 3);

  /// The adapter reported and the photos settled: the form is as full as 한방
  /// can make it, and the rest is the agent's.
  bool get filled => _resultIn && _photosDone;

  @override
  bool get isSettled => failure != null || pressedLabel != null || filled;

  /// Things the agent has to fix in the form before 등록 will go through.
  List<String> get blockers => [
    ?formNotice,
    ...missing,
    ...violations,
    ?photoFailure,
  ];

  /// Everything worth showing, blockers first.
  List<String> get reasons => [
    ...blockers,
    ...unsupported,
    ...photoNotes,
    for (final alert in pageAlerts) '${platform.label} 알림: $alert',
  ];

  @override
  void configure(WebViewController controller) {
    controller.addJavaScriptChannel(
      'ListingResult',
      onMessageReceived: _receive,
    );
  }

  void _receive(JavaScriptMessage message) {
    try {
      final result = jsonDecode(message.message) as Map<String, dynamic>;
      missing = List<String>.from(result['missing'] as List? ?? const []);
      violations = List<String>.from(result['violations'] as List? ?? const []);
      unsupported = List<String>.from(
        result['unsupported'] as List? ?? const [],
      );
      final picker = picksAddress ? ' · 주소 자동 선택' : '';
      status =
          '입력 ${result['applied'] ?? 0}건 · 검증 ${result['verified'] ?? 0}건$picker';
      _resultIn = true;
      if (filled) filling = false;
      notifyListeners();
      onListingResult?.call(controller, result);
    } catch (_) {
      status = '입력 결과를 해석하지 못했습니다.';
      notifyListeners();
    }
  }

  @override
  Future<void> onPage(Uri url) async {
    if (url.host != initialUrl.host || _lastInjectedUrl == url.toString()) {
      return;
    }
    // 미러는 `.../oneroom/index.html` 을 `.../oneroom/` 으로 308 을 보내므로 끝난
    // 주소가 설정한 주소와 글자 그대로 같은 적이 없다. 디렉터리 모양으로 견준다.
    // (로그인이 풀려 폼 대신 로그인 화면이 온 경우는 [leavesOnSignedOut] 이 이미
    // 걸러 냈다.)
    if (mirrorDirectory(url) != mirrorDirectory(initialUrl)) return;
    _lastInjectedUrl = url.toString();
    _photosDone = platform.photoTarget == null || photos.isEmpty;
    markLoaded();
    filling = true;
    status = '${platform.label}에 입력하는 중…';
    notifyListeners();
    // 실물 폼은 페이지 로드가 끝난 뒤에 그려진다(직방 Next.js, 다방 SPA). 어댑터가 빈
    // 화면을 훑지 않도록 폼의 뼈대가 뜰 때까지 기다린다. 그사이 로그인 화면으로
    // 되돌려졌다면 [_urlChanged] 가 이미 끝을 냈다.
    if (!await _formReady()) {
      if (failure != null) return;
      formNotice =
          '${platform.label} 등록 폼의 입력란을 찾지 못했어요. 화면 구성이 바뀌었을 수 있어 '
          '자동 입력이 일부만 됐을 수 있습니다.';
    }
    if (failure != null || _disposed) return;
    // 폼은 떴다. 여기서부터는 채우기와 사진 첨부가 **차례로** 돌고(사진은 폼이 되돌아갈
    // 때 쓸려 가므로 나란히 돌릴 수 없다) 저마다 제 시간과 제 이유를 갖고 있다.
    stopLoadTimeout();
    final address = '${values['address'] ?? ''}';
    final kakao = platform.usesKakaoPostcode;
    picksAddress = kakao && address.isNotEmpty
        ? await _installFramePicker([
            address,
            '${values['roadAddress'] ?? ''}',
            '${values['jibunAddress'] ?? ''}',
          ])
        : false;
    try {
      // The bridge has to be in place before the adapter presses anything that
      // can open the address search.
      if (kakao) {
        await controller.runJavaScript(
          postcodeBridgeScript(jsonEncode(values['address'] ?? '')),
        );
      }
      final payload = jsonEncode(
        platform == ListingPlatform.daangn
            ? legacyDaangnValues(values)
            : values,
      );
      // 어댑터가 누르는 것에 페이지가 되묻는 확인 창은 「확인」으로 답한다. 어댑터가
      // 끝나면 스스로 끈다([autoAnswerScript]).
      autoAnswering = true;
      await controller.runJavaScript(switch (platform) {
        ListingPlatform.zigbang => zigbangInjectionScript(payload),
        ListingPlatform.dabang => dabangInjectionScript(payload),
        ListingPlatform.daangn => daangnInjectionScript(payload),
      });
      await _adapterDone();
      await _transferPhotos();
    } catch (error) {
      status = '자동 입력 JavaScript 오류: $error';
      fail('자동 입력을 시작하지 못했어요');
    }
  }

  /// Polls for [formReadyScript] until the form's own fields exist.
  Future<bool> _formReady() async {
    final probe = formReadyScript(platform);
    final until = DateTime.now().add(formReadyTimeout);
    while (!_disposed && failure == null) {
      try {
        final ready = await controller.runJavaScriptReturningResult(probe);
        if (ready == true || ready.toString() == 'true') return true;
      } catch (_) {
        // A page mid-navigation answers nothing; ask again.
      }
      if (DateTime.now().isAfter(until)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  /// 어댑터가 제 차례를 마칠 때까지 기다린다. **사진은 그 뒤에 붙인다.**
  /// 왜 그래야 하는지는 [awaitFormAdapter] 에 적었다.
  Future<void> _adapterDone() async {
    if (platform.photoTarget == null || photos.isEmpty) return;
    photoStatus = '폼 입력이 끝나면 사진을 붙입니다…';
    notifyListeners();
    await awaitFormAdapter(
      evaluate: controller.runJavaScriptReturningResult,
      timeout: adapterTimeout,
      isCancelled: () => _disposed || failure != null,
    );
  }

  /// 사진이 끝났다고 어댑터에게 알린다.
  ///
  /// 직방 어댑터는 이 말을 듣고서야 카카오 주소 검색을 띄운다 — 사진 창이 떠 있는
  /// 동안은 `body` 의 포인터가 막혀 사람이 주소를 고를 수 없기 때문이다. 붙이지
  /// 못했더라도 알린다: 주소는 고를 수 있어야 한다.
  Future<void> _releaseAdapter() async {
    try {
      await controller.runJavaScript('$photosDoneFlag = true;');
    } catch (_) {
      // 페이지가 넘어가는 중이면 답이 없다. 어댑터도 5분이면 스스로 넘어간다.
    }
  }

  Future<void> _transferPhotos() async {
    final target = platform.photoTarget;
    if (target == null || photos.isEmpty) {
      await _releaseAdapter();
      return;
    }
    _photosDone = false;
    photosRunning = true;
    try {
      final skipped = await transferListingPhotos(
        target: target,
        photos: photos,
        evaluate: controller.runJavaScriptReturningResult,
        isCancelled: () => failure != null,
        onProgress: (completed, total) {
          photoStatus = completed == total
              ? '사진 $completed장 첨부 확인 완료'
              : '사진 첨부 중… $completed/$total장 완료';
          notifyListeners();
        },
      );
      if (skipped.isNotEmpty) {
        photoNotes = skipped;
        photoStatus ??= '첨부할 수 있는 사진이 없습니다.';
      }
    } catch (error) {
      photoStatus = '사진 첨부가 중단되었습니다.';
      photoFailure = '사진 첨부: $error';
    }
    photosRunning = false;
    _photosDone = true;
    await _releaseAdapter();
    if (filled) filling = false;
    notifyListeners();
    onPhotoTransferComplete?.call(controller, photoFailure);
  }

  /// The user script has to be registered before the Kakao frame loads, which
  /// is why this runs with the rest of the injection rather than when the
  /// address search opens.
  Future<bool> _installFramePicker(List<String> addresses) async {
    final alternatives = addresses
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList();
    final script = addressPickerFrameScript(jsonEncode(alternatives));
    final native = controller.platform;
    // Android identifies its WebView directly. iOS maps the unique JS channel
    // registered above back to the exact WKUserContentController.
    final Object arguments = native is AndroidWebViewController
        ? {
            'script': script,
            'webView': native.webViewIdentifier,
            'origins': kakaoPostcodeOrigins,
          }
        : {'script': script, 'targetChannel': _frameTargetChannel};
    try {
      final installed = await _frameScripts.invokeMethod<bool>(
        'setFrameScript',
        arguments,
      );
      return installed ?? false;
    } on MissingPluginException {
      // The tests have no frame-script bridge: the agent picks.
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// 플랫폼의 **광고 목록** 페이지. 두 가지 일을 한다.
///
/// 1. 매물 번호를 알아낸다 — 목록의 카드를 한방이 아는 것(제목·주소·호·금액)과 견주어
///    이 매물의 번호를 읽는다([listingNumberScript]). 등록을 마친 직후 조용히 한 번
///    돌고, 그때 못 읽었으면 내릴 때 다시 돈다.
/// 2. [mark] 면 그 번호의 카드를 화면 가운데로 올리고 테를 둘러
///    ([takedownCardScript]), **그 카드 안에서 누른 종료만** 이 매물의 종료로 센다.
///
/// 누르는 것은 사람이다. 한방은 어느 카드가 그 매물인지만 말해 준다.
class MirrorListings extends MirrorPage {
  MirrorListings({
    required super.platform,
    required this.values,
    String? number,
    this.mark = false,
    super.loadTimeout = const Duration(minutes: 2),
  }) : _number = number,
       super(
         url: Uri.parse(platform.listingsUrlFor(values)),
         // 표를 붙이지 않는 자리(등록 직후의 조용한 확인)는 누름을 듣지 않는다.
         watchLabels: mark ? platform.takedownLabels : const [],
       );

  /// 이 매물의 통합 폼 값 — 목록의 카드와 견줄 재료.
  final Map<String, dynamic> values;

  /// 찾은 카드에 표를 붙이고 눌림을 그 안으로 가둘 것인가.
  final bool mark;

  String? _number;

  /// 플랫폼이 이 매물에 붙인 번호. 들고 온 것이거나, 목록에서 읽어 낸 것이다.
  String? get number => _number;

  /// 번호를 찾는 일이 끝났는가 — 찾았든, 목록을 다 읽고도 못 찾았든.
  bool numberSettled = false;

  /// 무엇이 같아서 그 카드라고 보았는가 (「제목·주소·호」). 화면에 적지는 않지만,
  /// 엉뚱한 번호를 물어 왔을 때 어디서 어긋났는지 여기서부터 본다.
  List<String> matchedOn = const [];

  /// 목록에서 그 번호의 카드를 찾아 표를 붙였는가.
  bool cardFound = false;

  /// 플랫폼 자신의 검색창에 번호를 넣어 봤는가.
  bool searched = false;

  /// 목록을 다 뒤지고도 그 카드를 찾지 못했는가.
  bool cardGaveUp = false;

  /// 한방이 이 매물을 목록에서 짚어 주기를 포기했는가 — 번호도 못 읽었거나,
  /// 번호는 알아도 그 카드가 이 페이지에 없거나.
  bool get gaveUp =>
      cardGaveUp || (numberSettled && _number == null) || failure != null;

  /// **표가 붙은 카드 안에서 누른 것만 센다.**
  ///
  /// 아직 찾는 중일 때도 울타리는 쳐 둔다. 그사이에 사람이 옆 매물의 종료를 눌렀다면
  /// 그것은 이 매물의 종료가 아니고, 그것을 이 매물의 종료로 적는 것이 이 화면이
  /// 할 수 있는 가장 나쁜 일이다.
  ///
  /// 끝내 못 찾았을 때만 울타리를 푼다 — 그때는 사람이 제 손으로 찾아 눌러야 하고,
  /// 울타리가 남아 있으면 그 누름을 한방이 못 듣는다.
  @override
  String? get pressScope => cardFound || !gaveUp ? takedownCardSelector : null;

  @override
  void configure(WebViewController controller) {
    controller
      ..addJavaScriptChannel('ListingNumber', onMessageReceived: _numberIn)
      ..addJavaScriptChannel('TakedownCard', onMessageReceived: _cardIn);
  }

  /// 이 페이지에 번호를 읽는 스크립트를 이미 걸었는가. 스크립트는 목록이 그려질
  /// 때까지 스스로 기다리므로, 두 번 걸면 기다리는 고리가 둘이 된다.
  bool _probing = false;

  @override
  Future<void> onPage(Uri url) async {
    markLoaded();
    // 페이지를 새로 실었다면 앞에 건 것은 그 페이지와 함께 사라졌다.
    _probing = false;
    await _work();
  }

  /// 다방프로는 한 장짜리 앱이라 목록으로 가는 것도 페이지 로드 없이 주소만 바뀐다.
  /// 그때는 스크립트가 그대로 살아 있으므로 표만 다시 붙인다.
  @override
  Future<void> onRoute(Uri url) async {
    if (!loaded) return;
    await _work();
  }

  Future<void> _work() async {
    if (_disposed) return;
    try {
      if (_number != null) {
        await _markCard();
      } else if (!_probing) {
        _probing = true;
        await controller.runJavaScript(listingNumberScript(platform, values));
      }
    } catch (_) {
      // 넘어가는 중인 페이지는 답이 없다. 다음 로드에서 다시 건다.
      _probing = false;
    }
  }

  Future<void> _markCard() async {
    final number = _number;
    if (!mark || number == null || _disposed) return;
    await controller.runJavaScript(takedownCardScript(platform, number));
  }

  void _numberIn(JavaScriptMessage message) {
    if (_disposed) return;
    try {
      final result = jsonDecode(message.message) as Map<String, dynamic>;
      final found = '${result['number'] ?? ''}'.trim();
      if (found.isNotEmpty) {
        _number = found;
        matchedOn = List<String>.from(result['why'] as List? ?? const []);
      }
    } catch (_) {
      // 해석하지 못한 답은 「못 찾았다」와 같다.
    }
    numberSettled = true;
    stopLoadTimeout();
    if (_number != null) {
      unawaited(_markCard());
    } else {
      // 번호를 못 읽었으면 여기서 끝이다 — 울타리를 풀어 사람이 직접 찾을 수 있게.
      unawaited(installPressWatcher());
    }
    notifyListeners();
  }

  void _cardIn(JavaScriptMessage message) {
    if (_disposed) return;
    final bool found;
    final bool over;
    try {
      final result = jsonDecode(message.message) as Map<String, dynamic>;
      found = result['found'] == true;
      over = result['gaveUp'] == true;
      searched = result['searched'] == true;
    } catch (_) {
      return;
    }
    final changed = cardFound != found || cardGaveUp != over;
    cardFound = found;
    cardGaveUp = over;
    // 울타리가 생겼거나 없어졌다 — 감시를 다시 깐다.
    if (changed) unawaited(installPressWatcher());
    notifyListeners();
  }
}

/// 0011 플랫폼 연동 — **플랫폼 자신의 로그인 화면**에서 로그인하게 한다.
///
/// 앱은 로그인 화면을 따로 부르지 않고 **대시보드 주소만 연다.** 로그인이 안 돼 있으면
/// 플랫폼이 알아서 로그인 화면으로 되돌려 보내고(직방은 랜딩 `/intro`, 다방은 `/login`),
/// 이미 돼 있으면 로그인 화면 없이 바로 대시보드가 뜬다 — 실물이 그렇게 움직인다.
///
/// 한방은 아이디도 비밀번호도 보지 않는다. 사람이 플랫폼 화면에 직접 넣고, 앱은
/// **세션이 생겼는지만** 확인한다. 그 확인법이 플랫폼마다 다르다 (미러 실측):
///
/// | 플랫폼 | 열쇠 | 확인법 |
/// |---|---|---|
/// | 직방 | `ceo_zauth` — **페이지가** 심고 HttpOnly 아님 | `document.cookie` 로 보인다 |
/// | 다방 | `auth_key` — 서버가 심고 **HttpOnly** | 안 보인다. 플랫폼에 `login/check` 로 묻는다 |
/// | 당근 | 없음 (수집 없음) | 화면이 뜨면 연결로 본다 |
class MirrorLogin extends MirrorPage {
  /// 로그인 화면이 아니라 **대시보드 주소**를 연다. 아직 살아 있는 세션이라면 아무것도
  /// 타이핑하게 해서는 안 되기 때문이다 — 플랫폼이 대시보드를 내주면 이미 들어와 있는
  /// 것이고, 되돌려 보낼 때만 플랫폼 자신의 로그인 화면이 뜬다.
  MirrorLogin({required super.platform})
    : super(url: Uri.parse(platform.dashboardUrl));

  /// 세션이 실제로 있는가. 「제출했다」가 아니라 **플랫폼이 인정했는가**다.
  bool linked = false;

  /// 무엇을 보고 그렇게 판단했는지 (화면에 적어 주고, 나중에 원인을 찾을 때 쓴다).
  SessionEvidence evidence = SessionEvidence.none;

  /// 지금 보고 있는 것이 로그인 화면인가 (대시보드가 아니라).
  bool onLoginScreen = false;

  /// 여기서는 로그인 화면이 목적지다 — 튕겨 온 것을 실패로 보지 않는다.
  @override
  bool get leavesOnSignedOut => false;

  @override
  void configure(WebViewController controller) {
    controller.addJavaScriptChannel('SessionProbe', onMessageReceived: _probed);
  }

  /// 랜딩에서 로그인 화면으로 한 번 넘겼는가. 한 번만 넘긴다 — 사람이 랜딩으로 돌아가
  /// 둘러보는 것까지 막으면 안 된다.
  bool _sentToLogin = false;

  @override
  Future<void> onPage(Uri url) async {
    markLoaded();
    onLoginScreen = platform.isSignedOut(url);
    // 실물은 로그인 안 된 대시보드 요청을 로그인 화면이 아니라 **랜딩**으로 보낸다
    // (직방 `/intro`, 다방프로 `/`). 거기서 「로그인」을 찾아 누르게 하지 않고 플랫폼
    // 자신의 로그인 화면을 바로 연다 — 여전히 아이디·비밀번호는 플랫폼 화면에 들어간다.
    if (onLoginScreen &&
        platform.hasLogin &&
        !_sentToLogin &&
        !platform.urls.isLoginScreen(url)) {
      _sentToLogin = true;
      notifyListeners();
      await controller.loadRequest(Uri.parse(platform.loginUrl));
      return;
    }
    if (!platform.hasLogin) {
      // 로그인이 없는 플랫폼은 화면이 떴다는 것 말고 볼 것이 없다.
      _settle(true, SessionEvidence.page);
      return;
    }
    notifyListeners();
    try {
      await controller.runJavaScript(sessionProbeScript(platform));
    } catch (_) {
      _settle(!onLoginScreen, SessionEvidence.page);
    }
  }

  /// 다방프로는 로그인을 마치면 페이지를 새로 싣지 않고 주소만 대시보드로 바꾼다.
  /// 그 순간 다시 물어야 연동이 끝난 줄 안다.
  @override
  Future<void> onRoute(Uri url) async {
    if (!loaded || !platform.hasLogin) return;
    await onPage(url);
  }

  void _probed(JavaScriptMessage message) {
    switch (message.message) {
      case 'true':
        _settle(
          true,
          platform.sessionCheck == SessionCheck.cookieVisible
              ? SessionEvidence.cookie
              : SessionEvidence.platform,
        );
      case 'false':
        _settle(false, SessionEvidence.none);
      default:
        // 물어보지 못했다(문지기·네트워크). 그러면 **화면**으로 판단한다 —
        // 플랫폼이 로그인 화면으로 되돌려 보내지 않았다는 것 자체가 신호다.
        _settle(!onLoginScreen, SessionEvidence.page);
    }
  }

  void _settle(bool value, SessionEvidence how) {
    final next = value ? how : SessionEvidence.none;
    if (linked == value && evidence == next) return;
    linked = value;
    evidence = next;
    notifyListeners();
  }
}

/// 무엇을 보고 「연결됐다」고 판단했는가.
enum SessionEvidence {
  /// 쿠키가 JS 에 그대로 보였다 (직방).
  cookie,

  /// 플랫폼이 물음에 그렇다고 답했다 (다방 `login/check`).
  platform,

  /// 로그인 화면으로 되돌려 보내지 않았다 — 화면으로만 판단했다.
  page,

  none;

  String get label => switch (this) {
    SessionEvidence.cookie => '쿠키 확인',
    SessionEvidence.platform => '플랫폼이 확인',
    SessionEvidence.page => '화면으로 확인',
    SessionEvidence.none => '',
  };
}

/// 페이지 안에서 「지금 로그인돼 있나」를 확인하고 `SessionProbe` 로 답하는 스크립트.
/// 답은 `'true'` · `'false'` · 그 밖(못 물어봤다) 셋 중 하나다.
String sessionProbeScript(ListingPlatform platform) {
  const open = '(() => { try {';
  const close = '} catch (_) {} })();';
  switch (platform.sessionCheck) {
    // 직방: 페이지 JS 가 심은 쿠키라 document.cookie 에 그대로 있다.
    case SessionCheck.cookieVisible:
      final name = jsonEncode('${platform.sessionCookie}=');
      return '$open window.SessionProbe.postMessage(String('
          'document.cookie.split("; ").some(c => c.startsWith($name))));$close';
    // 다방: auth_key 가 HttpOnly 라 JS 로는 볼 수 없다. 플랫폼에 직접 묻는 수밖에 없고,
    // 답은 **코드가 아니라 본문**에 있다 — 로그인 전에도 200 이 온다. 실물은
    // `{"code":200,"result":false}` 처럼 `result` 에, 미러는 `isLogin` 에 싣는다.
    case SessionCheck.platformAsks:
      final ask = jsonEncode(platform.sessionCheckPath);
      return '(() => {\n'
          "  fetch($ask, {credentials: 'same-origin', headers: {accept: 'application/json'}})\n"
          '    .then(response => response.ok ? response.json() : Promise.reject(response.status))\n'
          "    .then(body => { window.SessionProbe.postMessage(String(typeof body.isLogin === 'boolean' ? body.isLogin : body.result === true)); })\n"
          "    .catch(() => { try { window.SessionProbe.postMessage('unknown'); } catch (_) {} });\n"
          '})();';
    case SessionCheck.none:
      return "$open window.SessionProbe.postMessage('unknown');$close";
  }
}

/// 플랫폼 페이지가 띄운 확인·알림 창을 한방 화면 위에 그대로 띄운다 —
/// [MirrorPage.onConfirm] · [MirrorPage.onAlert] 에 붙인다.
///
/// 사람이 페이지에서 누른 것에 페이지가 되묻는 창이다(다방 「매물 유형을 변경할 경우
/// 매물정보가 초기화 됩니다」, 광고 종료 확인 등). 한방은 답을 지어내지 않고 묻기만 한다.
void attachPlatformDialogs(MirrorPage page, BuildContext Function() context) {
  page.onConfirm = (message) async {
    final at = context();
    if (!at.mounted) return false;
    final answer = await showDialog<bool>(
      context: at,
      builder: (dialog) => AlertDialog(
        title: Text('${page.platform.label}에서 묻고 있어요'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return answer == true;
  };
  page.onAlert = (message) async {
    final at = context();
    if (!at.mounted) return;
    await showDialog<void>(
      context: at,
      builder: (dialog) => AlertDialog(
        title: Text('${page.platform.label} 알림'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  };
}

/// What 한방 says when a platform sends the agent back to its sign-in page.
String signInLost(ListingPlatform platform) =>
    '${platform.label} 로그인이 풀렸어요. 플랫폼 연동을 다시 해주세요.';

/// 로그아웃이 지워야 하는 나머지 반쪽 — 플랫폼이 웹뷰에 심어 둔 로그인.
///
/// 저장소는 앱에 하나뿐이라(안드로이드 `CookieManager`·`WebStorage`, iOS 는 기본
/// `WKWebsiteDataStore`) 어느 컨트롤러에서 지우든 **세 플랫폼이 한꺼번에** 지워진다.
/// 그래서 「직방만 연동 해제」에는 쓸 수 없다.
///
/// 쿠키만으로는 모자란다. 세션을 쿠키에 담는 플랫폼도 있고 토큰을 localStorage 에
/// 두는 플랫폼도 있어서, 어느 쪽인지 모르는 채로 둘 다 지운다.
Future<void> clearPlatformSessions() async {
  await WebViewCookieManager().clearCookies();
  final controller = WebViewController();
  await controller.clearLocalStorage();
  await controller.clearCache();
}

/// Installs a capture-phase listener that reports trusted presses of the
/// buttons named in [labels] to the `MirrorPress` channel. Installing it twice
/// only swaps the labels (and [within]).
///
/// [within] 은 「이 상자 안에서 누른 것만 센다」는 울타리다 (CSS 선택자). 광고 목록에는
/// 같은 글자의 종료 버튼이 매물 수만큼 있고, 그중 **한방이 표를 붙인 카드 안에서** 누른
/// 것만이 이 매물을 내린 것이다 — 울타리가 없으면 옆 매물을 내린 누름을 이 매물의
/// 종료로 적게 된다. 울타리가 없는 자리(등록 폼)는 지금처럼 페이지 전체를 본다.
String pressWatcherScript(List<String> labels, {String? within}) =>
    '''
(() => {
  const labels = ${jsonEncode(labels)};
  const within = ${jsonEncode(within)};
  if (window.__flrPressWatch) {
    window.__flrPressWatch.labels = labels;
    window.__flrPressWatch.within = within;
    return;
  }
  const watch = window.__flrPressWatch = {labels, within};
  const norm = value => String(value || '').replace(/\\s+/g, ' ').trim();
  const blocked = el => el.disabled || el.getAttribute('aria-disabled') === 'true' ||
    el.classList.contains('cursor-not-allowed');
  // 사람이 누른 것만 센다. 어댑터가 보내는 합성 이벤트는 isTrusted 가 false 다.
  window.addEventListener('click', event => {
    if (!event.isTrusted) return;
    const el = event.target && event.target.closest &&
      event.target.closest('button, [role="button"], input[type="submit"], a');
    if (!el || blocked(el)) return;
    if (watch.within && !el.closest(watch.within)) return;
    const label = norm(el.innerText || el.value || el.textContent);
    if (!watch.labels.includes(label)) return;
    try {
      window.MirrorPress.postMessage(JSON.stringify({label, url: location.href}));
    } catch (_) {}
  }, true);
})();
''';

/// The WebView for a [MirrorPage], sized by its parent.
class MirrorWebView extends StatelessWidget {
  const MirrorWebView(this.page, {super.key});

  final MirrorPage page;

  @override
  Widget build(BuildContext context) => WebViewWidget(
    key: ObjectKey(page.controller),
    controller: page.controller,
  );
}

/// A bare page for one mirror: the adapter's status and reasons above the
/// WebView. Kept for diagnostics and the WKWebView integration tests; the app
/// itself embeds [MirrorSession] in the Process Hub.
class RemoteFormPage extends StatefulWidget {
  const RemoteFormPage({
    super.key,
    required this.values,
    required this.platform,
    this.photos = const [],
    this.onPhotoTransferComplete,
    this.onListingResult,
  });
  final Map<String, dynamic> values;
  final ListingPlatform platform;
  final List<XFile> photos;

  /// Test/diagnostic observation point. It fires only after the remote photo
  /// transfer has settled, whether it succeeded or produced a concrete error.
  final void Function(WebViewController controller, String? failure)?
  onPhotoTransferComplete;

  /// Test/diagnostic observation point for each result the adapter publishes.
  final void Function(
    WebViewController controller,
    Map<String, dynamic> result,
  )?
  onListingResult;

  @override
  State<RemoteFormPage> createState() => _RemoteFormPageState();
}

class _RemoteFormPageState extends State<RemoteFormPage> {
  late final MirrorSession session = MirrorSession(
    platform: widget.platform,
    values: widget.values,
    photos: widget.photos,
    onListingResult: widget.onListingResult,
    onPhotoTransferComplete: widget.onPhotoTransferComplete,
    loadTimeout: null,
  )..addListener(_changed);

  @override
  void initState() {
    super.initState();
    attachPlatformDialogs(session, () => context);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    session
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Future<void> _handleBack(bool didPop, Object? result) async {
    if (didPop) return;
    if (await session.closeOverlay()) return;
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final reasons = session.reasons;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        appBar: AppBar(title: Text('${widget.platform.label} 매물 입력')),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(12),
              child: Text(
                [
                  session.failure ?? session.status,
                  ?session.photoStatus,
                ].join('\n'),
              ),
            ),
            if (reasons.isNotEmpty)
              ExpansionTile(
                title: Text('직접 확인할 항목 ${reasons.length}개'),
                subtitle: const Text('사유 전체 보기'),
                children: [
                  for (final reason in reasons)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.info_outline),
                      title: SelectableText(reason),
                    ),
                ],
              ),
            Expanded(
              child: Padding(
                padding: androidBottomInset(context),
                child: MirrorWebView(session),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
