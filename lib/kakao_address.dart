import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'android_layout.dart';
import 'design/components.dart';

/// Address chosen in the Kakao Postcode service (keyless, free).
/// https://postcode.map.kakao.com/guide
class KakaoAddress {
  const KakaoAddress({
    required this.roadAddress,
    required this.jibunAddress,
    required this.postalCode,
    this.legalDongCode,
    this.buildingName,
    this.sido = '',
    this.sigungu = '',
    this.bname = '',
    this.apartment = false,
    this.userSelectedJibun = false,
  });

  factory KakaoAddress.fromPostcode(Map<String, dynamic> data) {
    String pick(String key) => '${data[key] ?? ''}'.trim();
    String firstNonEmpty(String a, String b) => a.isNotEmpty ? a : b;
    final building = pick('buildingName');
    final bcode = pick('bcode');
    return KakaoAddress(
      // When the user picks "선택 안함", the service fills the auto* fields.
      roadAddress: firstNonEmpty(pick('roadAddress'), pick('autoRoadAddress')),
      jibunAddress: firstNonEmpty(
        pick('jibunAddress'),
        pick('autoJibunAddress'),
      ),
      postalCode: pick('zonecode'),
      legalDongCode: bcode.isEmpty ? null : bcode,
      buildingName: building.isEmpty ? null : building,
      sido: pick('sido'),
      sigungu: pick('sigungu'),
      bname: pick('bname'),
      apartment: pick('apartment') == 'Y',
      userSelectedJibun: pick('userSelectedType') == 'J',
    );
  }

  final String roadAddress;
  final String jibunAddress;
  final String postalCode;
  final String? legalDongCode;
  final String? buildingName;

  /// 시·도 / 시·군·구 / 법정동 — 다방은 오피스텔·아파트를 주소가 아니라 이 세 단계를
  /// 골라 찾은 단지 목록에서 받는다. 법정동 코드([legalDongCode])로 먼저 고르고, 코드가
  /// 맞지 않을 때 이 이름으로 고른다.
  final String sido;
  final String sigungu;
  final String bname;

  /// 카카오가 공동주택(아파트)으로 아는 건물인가.
  final bool apartment;
  final bool userSelectedJibun;

  /// The address line the user actually tapped (road or jibun).
  String get displayAddress {
    if (userSelectedJibun && jibunAddress.isNotEmpty) return jibunAddress;
    return roadAddress.isNotEmpty ? roadAddress : jibunAddress;
  }

  /// Values stored in the unified form when this result is chosen.
  Map<String, dynamic> toFormValues() => {
    'address': displayAddress,
    'roadAddress': roadAddress.isEmpty ? null : roadAddress,
    'jibunAddress': jibunAddress.isEmpty ? null : jibunAddress,
    'postalCode': postalCode.isEmpty ? null : postalCode,
    'legalDongCode': legalDongCode,
    'buildingName': buildingName,
    'sido': sido.isEmpty ? null : sido,
    'sigungu': sigungu.isEmpty ? null : sigungu,
    'bname': bname.isEmpty ? null : bname,
  };
}

const postcodeChannelName = 'KakaoPostcode';

/// Without a base URL the page has an opaque origin, and the widget's iframe
/// cannot post the selected address back to it.
const postcodeBaseUrl = 'https://localhost/';

/// Page hosting the Postcode widget in embed mode. `window.open` popups do
/// not work inside a WebView, so the guide recommends `embed()`.
const postcodeHtml =
    '''
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>html, body, #layer { margin: 0; padding: 0; width: 100%; height: 100%; }</style>
</head>
<body>
<div id="layer"></div>
<script>
  function send(message) { $postcodeChannelName.postMessage(JSON.stringify(message)); }
  function start() {
    var Postcode = (window.kakao && kakao.Postcode) || (window.daum && daum.Postcode);
    if (!Postcode) { send({type: 'error', message: '우편번호 서비스를 초기화하지 못했습니다.'}); return; }
    new Postcode({
      width: '100%',
      height: '100%',
      oncomplete: function (data) { send({type: 'complete', data: data}); }
    }).embed(document.getElementById('layer'), {autoClose: false});
    send({type: 'ready'});
  }
</script>
<script src="https://t1.kakaocdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js"
  onload="start()"
  onerror="send({type: 'error', message: '우편번호 서비스 스크립트를 불러오지 못했습니다. 인터넷 연결을 확인하세요.'})"></script>
</body>
</html>
''';

/// Full-screen search; pops with the chosen [KakaoAddress].
class KakaoAddressSearchPage extends StatefulWidget {
  const KakaoAddressSearchPage({super.key});

  @override
  State<KakaoAddressSearchPage> createState() => _KakaoAddressSearchPageState();
}

class _KakaoAddressSearchPageState extends State<KakaoAddressSearchPage> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(postcodeChannelName, onMessageReceived: _receive)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              _fail('주소 검색 화면을 불러오지 못했습니다: ${error.description}');
            }
          },
        ),
      )
      ..loadHtmlString(postcodeHtml, baseUrl: postcodeBaseUrl);
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _controller.loadHtmlString(postcodeHtml, baseUrl: postcodeBaseUrl);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  void _receive(JavaScriptMessage message) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (json['type']) {
      case 'ready':
        if (mounted) setState(() => _loading = false);
      case 'error':
        _fail('${json['message']}');
      case 'complete':
        if (_completed || !mounted) return;
        final address = KakaoAddress.fromPostcode(
          Map<String, dynamic>.from(json['data'] as Map),
        );
        if (address.displayAddress.isEmpty) return;
        _completed = true;
        Navigator.pop(context, address);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const BackTitleBar(title: '주소 검색'),
    body: _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _retry, child: const Text('다시 시도')),
                ],
              ),
            ),
          )
        : Padding(
            // Keep the Kakao results clear of the Android navigation bar.
            padding: androidBottomInset(context),
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loading) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
  );
}
