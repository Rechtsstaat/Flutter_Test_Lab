import Flutter
import WebKit

/// Runs a script inside every frame of the web view, including cross-origin ones.
///
/// The Kakao postcode service draws its result list in an iframe served from
/// `postcode.map.kakao.com`. JavaScript evaluated through
/// `WebViewController.runJavaScript` only ever reaches the main frame, and the
/// same-origin policy keeps that frame's document out of reach from the mirror
/// page, so nothing on the Flutter side can read or click a search result.
///
/// WKWebView's own answer to this is `WKUserScript` with
/// `forMainFrameOnly: false`: the script is evaluated in each frame's own
/// context, where it is same-origin with that frame's document. webview_flutter
/// never exposes the `WKWebViewConfiguration` it builds, so this bridge takes
/// the content controller from the one call the plugin makes on it that we can
/// see — registering the JavaScript channel the Dart side asks for.
final class FrameScriptBridge: NSObject {
  static let shared = FrameScriptBridge()

  private static let channelName = "jikbang/frame_script"

  /// Maps the unique no-op JavaScript channel created by each MirrorPage to
  /// that page's exact content controller. Values are weak so this registry
  /// never extends a WebView's lifetime.
  private let targets = NSMapTable<NSString, WKUserContentController>(
    keyOptions: .strongMemory,
    valueOptions: .weakMemory
  )
  private var installedTargets = Set<String>()

  /// Swaps `addScriptMessageHandler:name:` for our version. Called once, before
  /// any web view exists.
  static func start(with registrar: FlutterPluginRegistrar) {
    WKUserContentController.flrInstallHook()
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "setFrameScript" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let source = arguments["script"] as? String,
        let targetChannel = arguments["targetChannel"] as? String
      else {
        result(
          FlutterError(
            code: "bad-arguments",
            message: "setFrameScript expects script and targetChannel.",
            details: nil
          )
        )
        return
      }
      result(shared.install(source: source, targetChannel: targetChannel))
    }
  }

  fileprivate func remember(_ controller: WKUserContentController, channel: String) {
    guard channel.hasPrefix("FrameScriptTarget_") else { return }
    targets.setObject(controller, forKey: channel as NSString)
  }

  /// Adds `source` to the exact content controller identified by the Dart
  /// page's unique channel. Returns whether that controller was available, so the Dart side
  /// can say plainly that automatic selection is off rather than silently
  /// waiting for a click that never comes.
  private func install(source: String, targetChannel: String) -> Bool {
    guard let controller = targets.object(forKey: targetChannel as NSString) else {
      return false
    }
    if installedTargets.contains(targetChannel) { return true }
    controller.addUserScript(
      WKUserScript(
        source: source,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: false
      )
    )
    installedTargets.insert(targetChannel)
    return true
  }
}

extension WKUserContentController {
  private static var hooked = false

  static func flrInstallHook() {
    guard !hooked else { return }
    hooked = true
    guard
      let original = class_getInstanceMethod(self, #selector(add(_:name:))),
      let replacement = class_getInstanceMethod(self, #selector(flr_add(_:name:)))
    else { return }
    method_exchangeImplementations(original, replacement)
  }

  /// After the exchange this body runs in place of `add(_:name:)`, and the call
  /// to `flr_add` below reaches the original implementation.
  @objc dynamic func flr_add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
    FrameScriptBridge.shared.remember(self, channel: name)
    flr_add(scriptMessageHandler, name: name)
  }
}
