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
import 'mobile_layout.dart';
import 'photo_transfer.dart';
import 'remote_form.dart';

/// The mirror serves `.../oneroom/index.html` as a 308 to `.../oneroom/`, so
/// the URL that finishes never equals the configured one. Comparing the
/// directory form keeps both spellings pointing at one page.
String mirrorDirectory(Uri uri) {
  var path = uri.path;
  if (path.endsWith('index.html')) {
    path = path.substring(0, path.length - 'index.html'.length);
  }
  return path.endsWith('/') ? path : '$path/';
}

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
    String? html,
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
    if (html != null) {
      controller.loadHtmlString(html, baseUrl: url.toString());
    } else {
      controller.loadRequest(url);
    }
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

  /// Called for every finished main-frame load after the press watcher is in.
  ///
  /// Landing anywhere but the page that was asked for means the platform sent
  /// the agent back to sign in — that is the only way a mirror page answers a
  /// request it will not serve.
  @protected
  Future<void> onPage(Uri url) async {
    if (url.host == initialUrl.host &&
        mirrorDirectory(url) != mirrorDirectory(initialUrl)) {
      fail(signInLost(platform));
      return;
    }
    markLoaded();
  }

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
    // Every mirror page the agent sees is a desktop page, 로그인 and 광고 목록
    // no less than the form, so all of them get restyled — and before
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
    if (mirrorDirectory(url) != mirrorDirectory(initialUrl)) {
      // 다방·직방은 로그인이 없으면 폼을 열어 주지 않고 로그인·랜딩으로 302 를
      // 보낸다. 여기서 멈추지 않으면 어댑터는 영영 돌지 않고, 화면은 3분짜리
      // [loadTimeout] 이 끝날 때까지 미러의 첫 화면을 들고 기다린다.
      if (!loaded) fail(signInLost(platform));
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

/// 0011's platform login: the platform's own sign-in page, shown as-is.
///
/// 한방 never sees what is typed — the credentials go from the platform's own
/// form to the platform's own endpoint, and the session it hands back lives in
/// the WebView's cookie store where only the platform can read it.
///
/// This used to be a stand-in page of 한방's own, on the premise that the
/// mirror began after login. It no longer does, and the stand-in's handover to
/// [ListingPlatformConfig.dashboardUrl] set no session, so the mirror bounced
/// every later request: onboarding reported 연동 완료 while the WebView sat on
/// 직방's 랜딩, and 매물 등록 then waited out its whole timeout on that screen.
class MirrorLogin extends MirrorPage {
  /// Opens the dashboard rather than the sign-in page, because a session that
  /// is still good should not ask the agent to type anything: if the platform
  /// serves the dashboard, they are already in. Only a bounce means otherwise,
  /// and then [ListingPlatformConfig.loginUrl] is where they are sent.
  MirrorLogin({required super.platform})
    : super(url: Uri.parse(platform.dashboardUrl));

  bool _sentToGate = false;

  /// Whether the platform let the agent in. Signing in is the one thing that
  /// stops the mirror from turning the dashboard away, so arriving there is
  /// the proof — and it is proof 한방 can see without reading anything the
  /// agent typed.
  bool get linked => loaded;

  @override
  Future<void> onPage(Uri url) async {
    if (url.host != initialUrl.host) return;
    if (mirrorDirectory(url) == mirrorDirectory(initialUrl)) {
      markLoaded();
      return;
    }
    // Turned away. Where a platform sends a stranger is not always where it
    // takes a password — 직방 lands on its /intro/ pitch — so go to the page
    // that does, once.
    if (_sentToGate) return;
    _sentToGate = true;
    final gate = Uri.parse(platform.loginUrl);
    if (mirrorDirectory(url) == mirrorDirectory(gate)) return;
    try {
      await controller.loadRequest(gate);
    } catch (_) {
      // The agent can still walk there from the landing page.
    }
  }
}

/// What 한방 says when a platform sends the agent back to its sign-in page.
String signInLost(ListingPlatform platform) =>
    '${platform.label} 로그인이 풀렸어요. 홈에서 ${platform.label}을 다시 연동해 주세요.';

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
