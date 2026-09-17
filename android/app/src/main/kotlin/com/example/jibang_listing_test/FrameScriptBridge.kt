package com.example.jibang_listing_test

import android.webkit.WebView
import androidx.webkit.ScriptHandler
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi
import java.util.WeakHashMap

/**
 * Runs a script inside the Kakao postcode frame, which is cross-origin to the mirror page.
 *
 * The Kakao postcode service draws its result list in an iframe served from
 * `postcode.map.kakao.com`. JavaScript evaluated through
 * `WebViewController.runJavaScript` only ever reaches the main frame, and the
 * same-origin policy keeps that frame's document out of reach from the mirror
 * page, so nothing on the Flutter side can read or click a search result.
 *
 * AndroidX WebKit's answer to this is `WebViewCompat.addDocumentStartJavaScript`:
 * the script is evaluated in every frame whose origin is allowed, in that
 * frame's own context. webview_flutter_android hands out the underlying
 * [WebView] for the identifier the Dart side reads from
 * `AndroidWebViewController.webViewIdentifier`.
 *
 * The iOS counterpart is `ios/Runner/FrameScriptBridge.swift`.
 */
object FrameScriptBridge {
  private const val CHANNEL_NAME = "jikbang/frame_script"

  /**
   * The script each web view carries, so reopening a mirror on a web view that
   * is still alive replaces it rather than stacking a second one. Held weakly:
   * an entry dies with its web view.
   */
  private val installed = WeakHashMap<WebView, ScriptHandler>()

  /** Called once the plugins are registered, before any web view exists. */
  fun start(engine: FlutterEngine) {
    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
      .setMethodCallHandler { call, result ->
        if (call.method != "setFrameScript") {
          result.notImplemented()
          return@setMethodCallHandler
        }
        val source = call.argument<String>("script")
        val webViewId = call.argument<Number>("webView")?.toLong()
        val origins = call.argument<List<String>>("origins")
        if (source == null || webViewId == null || origins.isNullOrEmpty()) {
          result.error(
            "bad-arguments",
            "setFrameScript expects script, webView and origins.",
            null,
          )
          return@setMethodCallHandler
        }
        try {
          result.success(install(engine, webViewId, source, origins.toSet()))
        } catch (error: IllegalArgumentException) {
          // An origin rule WebView does not accept.
          result.error("bad-arguments", error.message, null)
        }
      }
  }

  /**
   * Returns whether the script went in, so the Dart side can say plainly that
   * automatic selection is off (a System WebView too old for document-start
   * scripts, or a web view that is already gone) rather than silently waiting
   * for a click that never comes.
   */
  private fun install(
    engine: FlutterEngine,
    webViewId: Long,
    source: String,
    origins: Set<String>,
  ): Boolean {
    if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
      return false
    }
    val webView = WebViewFlutterAndroidExternalApi.getWebView(engine, webViewId) ?: return false
    installed.remove(webView)?.remove()
    installed[webView] = WebViewCompat.addDocumentStartJavaScript(webView, source, origins)
    return true
  }
}
