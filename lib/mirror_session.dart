import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart'
    show AndroidWebViewController;

import 'android_layout.dart';
import 'design/tokens.dart';
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
    String? html,
  }) : initialUrl = url {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(_pressChannel, onMessageReceived: _pressed);
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
        ? await _installFramePicker(address)
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
  Future<bool> _installFramePicker(String address) async {
    final script = addressPickerFrameScript(jsonEncode(address));
    final native = controller.platform;
    // iOS finds the newest web view on its own. Android has to be told which
    // one, and only lets the script into the Kakao origins.
    final Object arguments = native is AndroidWebViewController
        ? {
            'script': script,
            'webView': native.webViewIdentifier,
            'origins': kakaoPostcodeOrigins,
          }
        : script;
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

/// 0011's platform login. The mirror starts after login, so the WebView shows
/// a stand-in login page first and then the platform's signed-in dashboard.
/// 한방 never reads what is typed: the page clears its fields before leaving
/// and only reports that a login was submitted.
class MirrorLogin extends MirrorPage {
  MirrorLogin({required super.platform})
    : super(
        url: Uri.parse(platform.dashboardUrl),
        html: loginStandInHtml(platform),
      );

  bool submitted = false;
  bool get linked => submitted && loaded;

  @override
  void configure(WebViewController controller) {
    controller.addJavaScriptChannel(
      'LoginBridge',
      onMessageReceived: (_) {
        submitted = true;
        notifyListeners();
      },
    );
  }

  @override
  Future<void> onPage(Uri url) async {
    if (submitted && url.host == initialUrl.host) markLoaded();
  }
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

/// A neutral login page standing in for the platform's own. It posts nothing
/// anywhere: the fields are wiped before it moves on.
String loginStandInHtml(ListingPlatform platform) {
  final name = const HtmlEscape().convert(platform.label);
  final color =
      '#${(platform.color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
  return '''
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<title>$name 로그인</title>
<style>
  * { box-sizing: border-box; }
  /* The simulator's WebKit does not fall back to a Hangul face from
     -apple-system, so name one first. */
  body { margin: 0; padding: 40px 24px; font: 15px/1.5 "Apple SD Gothic Neo", -apple-system, BlinkMacSystemFont, "Noto Sans KR", sans-serif; color: #20232b; background: #fff; }
  input, button { font-family: inherit; }
  .mark { width: 48px; height: 48px; border-radius: 12px; background: $color; color: #fff; display: flex; align-items: center; justify-content: center; font-weight: 700; }
  h1 { font-size: 22px; margin: 20px 0 4px; }
  p { margin: 0 0 24px; color: #626a78; font-size: 13px; }
  label { display: block; font-size: 13px; font-weight: 600; margin: 16px 0 6px; color: #4d5360; }
  input { width: 100%; height: 48px; border: 1px solid #d2d6de; border-radius: 10px; padding: 0 14px; font-size: 15px; }
  input:focus { outline: none; border-color: $color; }
  button { width: 100%; height: 50px; margin-top: 28px; border: 0; border-radius: 10px; background: $color; color: #fff; font-size: 16px; font-weight: 600; }
  .note { margin-top: 20px; padding: 12px 14px; border-radius: 10px; background: #f2f4f7; color: #626a78; font-size: 12px; }
</style>
</head>
<body>
  <div class="mark">$name</div>
  <h1>$name 중개사 로그인</h1>
  <p>로그인하면 한방이 이 계정으로 광고를 올릴 수 있어요.</p>
  <form id="login" autocomplete="off">
    <label for="id">아이디</label>
    <input id="id" name="id" autocomplete="off" autocapitalize="off" placeholder="아이디 입력">
    <label for="pw">비밀번호</label>
    <input id="pw" name="pw" type="password" autocomplete="off" placeholder="비밀번호 입력">
    <button type="submit">로그인</button>
  </form>
  <div class="note">미러 환경의 임시 로그인 화면입니다. 실제 계정 정보를 입력하지 마세요. 입력한 값은 어디에도 보내지 않습니다.</div>
<script>
  document.getElementById('login').addEventListener('submit', event => {
    event.preventDefault();
    for (const input of event.target.querySelectorAll('input')) input.value = '';
    try { window.LoginBridge.postMessage('submitted'); } catch (_) {}
    setTimeout(() => { location.href = ${jsonEncode(platform.dashboardUrl)}; }, 300);
  });
</script>
</body>
</html>
''';
}

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
