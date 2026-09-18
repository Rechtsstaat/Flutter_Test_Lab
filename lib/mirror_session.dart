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
import 'photo_transfer.dart';
import 'remote_form.dart';

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
      ..addJavaScriptChannel(_frameTargetChannel, onMessageReceived: (_) {});
    configure(controller);
    controller.setNavigationDelegate(
      NavigationDelegate(
        onHttpAuthRequest: (request) {
          if (request.host == initialUrl.host) {
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

  /// The label of the platform button the agent pressed, once they have.
  String? pressedLabel;

  /// Whether this page has reached an end state the timeout should not
  /// override.
  bool get isSettled => failure != null || pressedLabel != null || loaded;

  /// Subclasses add their JavaScript channels here, before the first load.
  @protected
  void configure(WebViewController controller) {}

  /// 플랫폼이 로그인 화면으로 되돌려 보냈을 때 그것을 실패로 볼 것인가.
  ///
  /// 등록·종료 화면에서 그런 일이 벌어졌다면 **로그인이 풀린 것**이라 거기서 할 수 있는
  /// 일이 없다. 연동 화면([MirrorLogin])만 거기가 목적지라 아니라고 답한다.
  @protected
  bool get leavesOnSignedOut => true;

  /// Called for every finished main-frame load after the press watcher is in.
  @protected
  Future<void> onPage(Uri url) async => markLoaded();

  bool _samePage(Uri uri) =>
      uri.host == initialUrl.host && uri.path == initialUrl.path;

  Future<void> _pageFinished(String url) async {
    if (_disposed) return;
    if (watchLabels.isNotEmpty) {
      try {
        await controller.runJavaScript(pressWatcherScript(watchLabels));
      } catch (_) {
        // A page that navigates away mid-install gets the watcher next load.
      }
    }
    final uri = Uri.tryParse(url);
    if (uri == null || _disposed) return;
    if (leavesOnSignedOut && platform.isSignedOut(uri)) {
      fail('${platform.label} 로그인이 풀렸어요. 플랫폼 연동을 다시 해주세요.');
      return;
    }
    await onPage(uri);
  }

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
         url: Uri.parse(platform.formUrl),
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

  /// The adapter reported and the photos settled: the form is as full as 한방
  /// can make it, and the rest is the agent's.
  bool get filled => _resultIn && _photosDone;

  @override
  bool get isSettled => failure != null || pressedLabel != null || filled;

  /// Things the agent has to fix in the form before 등록 will go through.
  List<String> get blockers => [...missing, ...violations, ?photoFailure];

  /// Everything worth showing, blockers first.
  List<String> get reasons => [...blockers, ...unsupported, ...photoNotes];

  @override
  void configure(WebViewController controller) {
    controller.addJavaScriptChannel(
      'ListingResult',
      onMessageReceived: _receive,
    );
  }

  /// The mirror serves `.../oneroom/index.html` as a 308 to `.../oneroom/`, so
  /// the URL that finishes never equals the configured one. Comparing the
  /// directory form keeps both spellings pointing at one page.
  static String _directory(Uri uri) {
    var path = uri.path;
    if (path.endsWith('index.html')) {
      path = path.substring(0, path.length - 'index.html'.length);
    }
    return path.endsWith('/') ? path : '$path/';
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
    if (url.host != initialUrl.host ||
        _directory(url) != _directory(initialUrl) ||
        _lastInjectedUrl == url.toString()) {
      return;
    }
    _lastInjectedUrl = url.toString();
    _photosDone = platform.photoTarget == null || photos.isEmpty;
    markLoaded();
    filling = true;
    status = '${platform.label}에 입력하는 중…';
    notifyListeners();
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
      final payload = jsonEncode(values);
      await controller.runJavaScript(switch (platform) {
        ListingPlatform.zigbang => zigbangInjectionScript(payload),
        ListingPlatform.dabang => dabangInjectionScript(payload),
        ListingPlatform.daangn => daangnInjectionScript(payload),
      });
      await _transferPhotos();
    } catch (error) {
      status = '자동 입력 JavaScript 오류: $error';
      fail('자동 입력을 시작하지 못했어요');
    }
  }

  Future<void> _transferPhotos() async {
    final target = platform.photoTarget;
    if (target == null || photos.isEmpty) return;
    _photosDone = false;
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
    _photosDone = true;
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

  @override
  Future<void> onPage(Uri url) async {
    markLoaded();
    onLoginScreen = platform.isSignedOut(url);
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
    // 답은 **코드가 아니라 본문**에 있다 — 로그인 전에도 200 이 온다.
    case SessionCheck.platformAsks:
      final ask = jsonEncode(platform.sessionCheckPath);
      return '(() => {\n'
          "  fetch($ask, {credentials: 'same-origin', headers: {accept: 'application/json'}})\n"
          '    .then(response => response.ok ? response.json() : Promise.reject(response.status))\n'
          '    .then(body => { window.SessionProbe.postMessage(String(!!body.isLogin)); })\n'
          "    .catch(() => { try { window.SessionProbe.postMessage('unknown'); } catch (_) {} });\n"
          '})();';
    case SessionCheck.none:
      return "$open window.SessionProbe.postMessage('unknown');$close";
  }
}

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
/// only swaps the labels.
String pressWatcherScript(List<String> labels) =>
    '''
(() => {
  const labels = ${jsonEncode(labels)};
  if (window.__flrPressWatch) { window.__flrPressWatch.labels = labels; return; }
  const watch = window.__flrPressWatch = {labels};
  const norm = value => String(value || '').replace(/\\s+/g, ' ').trim();
  const blocked = el => el.disabled || el.getAttribute('aria-disabled') === 'true' ||
    el.classList.contains('cursor-not-allowed');
  // 사람이 누른 것만 센다. 어댑터가 보내는 합성 이벤트는 isTrusted 가 false 다.
  window.addEventListener('click', event => {
    if (!event.isTrusted) return;
    const el = event.target && event.target.closest &&
      event.target.closest('button, [role="button"], input[type="submit"], a');
    if (!el || blocked(el)) return;
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
        appBar: AppBar(title: Text('${widget.platform.label} 미러 입력')),
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
