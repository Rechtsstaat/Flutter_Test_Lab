import 'photo_transfer.dart';

enum ListingPlatform { zigbang, dabang, daangn }

/// 플랫폼을 지금 쓸 수 있는가.
///
/// **켜고 끄는 스위치는 [ListingPlatformConfig.status] 한 곳뿐이다.** 화면도 흐름도
/// 플랫폼 이름을 따로 적어 두지 않고 [livePlatforms] 와 [ListingPlatformConfig.isLive]
/// 만 본다 — 새 플랫폼을 붙이거나 잠시 내릴 때 고칠 곳이 한 군데라는 뜻이다.
enum PlatformStatus {
  /// 연동·등록·종료가 다 된다.
  live,

  /// 화면에는 회색으로 남지만 고를 수 없다. 왜인지는 [ListingPlatformConfig.pausedNote].
  paused,
}

/// 「지금 로그인돼 있나」를 확인하는 방법. **플랫폼마다 다르다** — 쿠키를 심는 쪽이 다르기
/// 때문이다(미러 실측 2026-09-18).
enum SessionCheck {
  /// 쿠키가 JS 에 보인다. 직방 `ceo_zauth` 는 **페이지가** 심고 HttpOnly 가 아니다.
  cookieVisible,

  /// 플랫폼에 직접 물어야 한다. 다방 `auth_key` 는 서버가 심고 **HttpOnly** 라
  /// `document.cookie` 에 아예 안 보인다 — 앱이 쿠키를 들여다보는 길이 없다.
  platformAsks,

  /// 로그인이 없는 플랫폼 (당근 미러).
  none,
}

/// 한방이 붙는 사이트.
///
/// 앱은 **실물**([live])에 붙는다. [mirror] 는 실물을 떠 온 재현 사이트로, 계정 없이
/// 어댑터를 재 보거나 통합 테스트를 돌릴 때만 쓴다:
///
/// ```sh
/// flutter run --dart-define=PLATFORM_SITE=mirror
/// ```
enum PlatformSite {
  live,
  mirror;

  static const PlatformSite active =
      String.fromEnvironment('PLATFORM_SITE') == 'mirror'
      ? PlatformSite.mirror
      : PlatformSite.live;
}

/// 남의 계정으로 어댑터를 재 보는 동안 거는 빗장.
///
/// 광고 목록(`listingsUrl`)과 광고 종료 화면에는 **지금 운영 중인 실제 매물**이 걸려
/// 있다. 폼 주입을 고치는 동안 그 자리에 들어갈 일은 없고, 「광고 종료」는 한 번 누르면
/// 되돌릴 수 없다. 빗장을 걸면 두 자리로 가는 길이 화면에서 아예 사라진다 — 등록 폼
/// 자체는 그대로 돌아간다.
///
/// ```sh
/// flutter run --dart-define=GUARD_LIVE_ADS=1
/// ```
const guardLiveAds = String.fromEnvironment('GUARD_LIVE_ADS') == '1';

/// 미러가 사는 호스트. Basic 인증(`mirror` / `money`)이 걸려 있다.
const mirrorHost = 'mirror-dimension-lab.pages.dev';

/// 한 사이트에서 한 플랫폼이 쓰는 주소들.
class PlatformUrls {
  const PlatformUrls({
    required this.root,
    required this.form,
    required this.dashboard,
    required this.login,
    required this.listings,
    this.villaForm,
    this.officetelForm,
    this.villaListings,
    this.officetelListings,
    this.signedOutPaths = const [],
    this.signedOutExactPaths = const [],
    this.signedOutHosts = const [],
    this.sessionCheckPath = '',
  });

  /// 이 호스트에서 이 플랫폼 몫인 경로의 머리. 실물은 호스트 전체(`/`), 미러는 한
  /// 호스트를 셋이 나눠 쓰므로 `/zigbang/` 처럼 갈린다.
  final String root;

  /// 기본 매물 등록 폼. 직방은 원룸 폼이다.
  final String form;
  final String dashboard;
  final String login;
  final String listings;

  /// 직방은 매물마다 폼이 다르다 — 방 2개 이상 빌라는 빌라 폼, 오피스텔은 오피스텔
  /// 폼이다(실물 라우트 2026-09-21). 없으면 [form] 하나로 받는다(미러·다방).
  final String? villaForm;
  final String? officetelForm;
  final String? villaListings;
  final String? officetelListings;

  /// 이 플랫폼이 쓰는 등록 폼 전부 — 사진 다리와 모바일 레이아웃이 「여기가 등록 폼인가」를
  /// 가릴 때 본다.
  List<String> get forms => [form, ?villaForm, ?officetelForm];

  /// 로그인 안 된 요청이 튕겨 가는 경로 (같은 호스트 안, 앞부분 일치).
  final List<String> signedOutPaths;

  /// 앞부분이 아니라 **그 경로 자체**일 때만 「로그인 안 됨」인 곳. 다방프로의 랜딩은
  /// `/` 라서 앞부분으로 견주면 모든 페이지가 걸린다.
  final List<String> signedOutExactPaths;

  /// 로그인 화면이 **다른 도메인**에 있는 경우 그 호스트 (직방 account.zigbang.com).
  final List<String> signedOutHosts;

  final String sessionCheckPath;

  String get host => Uri.parse(form).host;

  /// [url] 이 이 사이트에서 이 플랫폼의 페이지인가.
  bool owns(Uri url) => url.host == host && pageDirectory(url).startsWith(root);

  /// [url] 이 「로그인하라」는 화면인가.
  bool isSignedOut(Uri url) =>
      signedOutHosts.contains(url.host) ||
      (url.host == host &&
          (signedOutPaths.any((path) => url.path.startsWith(path)) ||
              signedOutExactPaths.any(
                (path) => pageDirectory(url) == pageDirectory(Uri(path: path)),
              )));

  /// [url] 이 아이디·비밀번호를 받는 **로그인 화면 자체**인가 (랜딩이 아니라).
  bool isLoginScreen(Uri url) =>
      signedOutHosts.contains(url.host) ||
      (url.host == host &&
          pageDirectory(url).startsWith(pageDirectory(Uri.parse(login))));
}

/// `.../oneroom/index.html` · `.../oneroom` · `.../oneroom/` 을 한 페이지로 읽는다.
/// 미러는 `index.html` 을 디렉터리로 308 을 보내고, 실물은 끝의 `/` 를 떼고 쓴다.
String pageDirectory(Uri uri) {
  var path = uri.path;
  if (path.endsWith('index.html')) {
    path = path.substring(0, path.length - 'index.html'.length);
  }
  return path.endsWith('/') ? path : '$path/';
}

extension ListingPlatformConfig on ListingPlatform {
  String get label => switch (this) {
    ListingPlatform.zigbang => '직방',
    ListingPlatform.dabang => '다방',
    ListingPlatform.daangn => '당근',
  };

  /// 지금 붙어 있는 사이트의 주소들. 기본은 **실물**이다 — [PlatformSite.active].
  PlatformUrls get urls => urlsOn(PlatformSite.active);

  /// [site] 에서 이 플랫폼이 쓰는 주소들.
  ///
  /// 실물 주소는 2026-09-20 에 각 사이트의 라우트 표(직방 CEO 의 Next.js 번들,
  /// 다방프로의 react-router 번들)와 로그인 안 된 요청의 응답으로 확인했다. 미러는
  /// 실물을 한 호스트 아래 `/zigbang/` · `/dabang/` · `/daangn/` 으로 펴 놓은 것이라
  /// 경로가 1:1 로 대응한다 (직방 폼만 미러가 `/form/oneroom/` 으로 줄여 적었다).
  PlatformUrls urlsOn(PlatformSite site) => switch ((this, site)) {
    // 직방 CEO. 로그인 안 된 요청은 전부 307 로 `/intro` 에 간다. 로그인은
    // `/account/login/email` 이 account.zigbang.com OAuth 로 **도메인을 건너가서**
    // 받고, 끝나면 `/OAuth/Callback` 이 `ceo_zauth` 를 심고 돌아온다.
    //
    // 등록 폼은 셋이다 — 원룸(방 1개), 빌라(방 2개 이상), 오피스텔. 폼마다 받는
    // 구조·거래 유형이 달라서 매물에 맞는 폼을 연다([formUrlFor], 실물 번들 실측
    // 2026-09-21). 아파트는 이 셋 어디로도 받지 않는다.
    (ListingPlatform.zigbang, PlatformSite.live) => const PlatformUrls(
      root: '/',
      form: 'https://ceo.zigbang.com/ads/oneroom/ad-item/new',
      villaForm: 'https://ceo.zigbang.com/ads/villa/ad-item/new',
      officetelForm: 'https://ceo.zigbang.com/ads/officetel/ad-item/new',
      dashboard: 'https://ceo.zigbang.com/dashboard',
      login: 'https://ceo.zigbang.com/account/login/email',
      listings: 'https://ceo.zigbang.com/ads/oneroom?status=open',
      villaListings: 'https://ceo.zigbang.com/ads/villa?status=open',
      officetelListings: 'https://ceo.zigbang.com/ads/officetel?status=open',
      signedOutPaths: ['/intro', '/account/login', '/error/401'],
      signedOutHosts: ['account.zigbang.com'],
    ),
    // 다방프로. 한 장짜리 앱(SPA)이라 로그인 안 된 요청도 200 으로 껍데기를 주고,
    // 그 안에서 랜딩 `/` 로 **주소만** 바꾼다 — 페이지 로드가 아니라 URL 변경으로 온다
    // (`/dashboard` · `/form/room` · `/room/dabang-list/public` 모두 실측).
    (ListingPlatform.dabang, PlatformSite.live) => const PlatformUrls(
      root: '/',
      form: 'https://pro.dabangapp.com/form/room',
      dashboard: 'https://pro.dabangapp.com/dashboard',
      login: 'https://pro.dabangapp.com/login',
      listings: 'https://pro.dabangapp.com/room/dabang-list/public',
      signedOutPaths: ['/login', '/intro'],
      signedOutExactPaths: ['/'],
      sessionCheckPath: '/api/v2/user/login/check',
    ),
    // 당근은 실물 중개사 화면을 아직 수집하지 못해 내려 둔 상태다([status]).
    // 실물 주소를 모르니 지어내지 않고 미러를 그대로 가리킨다.
    (ListingPlatform.daangn, PlatformSite.live) => urlsOn(PlatformSite.mirror),
    (ListingPlatform.zigbang, PlatformSite.mirror) => const PlatformUrls(
      root: '/zigbang/',
      form: 'https://$mirrorHost/zigbang/form/oneroom/',
      dashboard: 'https://$mirrorHost/zigbang/',
      login: 'https://$mirrorHost/zigbang/account/login/email/',
      listings: 'https://$mirrorHost/zigbang/ads/oneroom/?status=open',
      signedOutPaths: ['/zigbang/intro', '/zigbang/account/login'],
    ),
    (ListingPlatform.dabang, PlatformSite.mirror) => const PlatformUrls(
      root: '/dabang/',
      form: 'https://$mirrorHost/dabang/form/room/',
      dashboard: 'https://$mirrorHost/dabang/',
      login: 'https://$mirrorHost/dabang/login/',
      listings: 'https://$mirrorHost/dabang/room/dabang-list/public/',
      signedOutPaths: ['/dabang/login'],
      sessionCheckPath: '/dabang/api/v2/user/login/check',
    ),
    // 당근 미러에는 로그인이 없어 중개소 홈이 곧 시작점이다.
    (ListingPlatform.daangn, PlatformSite.mirror) => const PlatformUrls(
      root: '/daangn/',
      form: 'https://$mirrorHost/daangn/form/article/',
      dashboard: 'https://$mirrorHost/daangn/',
      login: 'https://$mirrorHost/daangn/',
      listings: 'https://$mirrorHost/daangn/',
    ),
  };

  /// [url] 이 어느 사이트의 이 플랫폼 몫인가. 어느 쪽도 아니면 null.
  ///
  /// 활성 사이트만이 아니라 **둘 다** 본다 — 모바일 레이아웃과 사진 첨부는 페이지
  /// 주소만 보고 판단하므로, 미러로 돌리는 테스트에서도 같은 코드가 돈다.
  PlatformSite? siteOf(Uri url) {
    for (final site in PlatformSite.values) {
      if (urlsOn(site).owns(url)) return site;
    }
    return null;
  }

  /// The listing form 한방 fills.
  String get formUrl => urls.form;

  /// 이 매물을 받는 등록 폼. 직방만 매물에 따라 갈린다([zigbangFormFor]).
  String formUrlFor(Map<String, dynamic> values) => switch (this) {
    ListingPlatform.zigbang => switch (zigbangFormFor(values)) {
      ZigbangForm.villa => urls.villaForm ?? urls.form,
      ZigbangForm.officetel => urls.officetelForm ?? urls.form,
      _ => urls.form,
    },
    _ => urls.form,
  };

  /// 이 매물이 걸리는 광고 목록. 직방은 폼마다 목록도 따로다.
  String listingsUrlFor(Map<String, dynamic> values) => switch (this) {
    ListingPlatform.zigbang => switch (zigbangFormFor(values)) {
      ZigbangForm.villa => urls.villaListings ?? urls.listings,
      ZigbangForm.officetel => urls.officetelListings ?? urls.listings,
      _ => urls.listings,
    },
    _ => urls.listings,
  };

  /// The page a signed-in agent lands on (직방 CEO 대시보드, 다방프로 대시보드,
  /// 당근부동산 중개소 홈). 로그인이 안 돼 있으면 **플랫폼이** 이 주소를 로그인 화면으로
  /// 되돌려 보낸다 — 그래서 0011 연동은 이 주소만 열면 된다.
  String get dashboardUrl => urls.dashboard;

  /// The platform's own sign-in page.
  String get loginUrl => urls.login;

  /// Where the agent's live listings are managed — 2022 등록된 광고 보기 and
  /// 3021 광고 종료 open this.
  String get listingsUrl => urls.listings;

  /// The platform's own final 등록 button. Adapters never press it; the agent
  /// does, and 한방 hears the press.
  List<String> get submitLabels => switch (this) {
    ListingPlatform.zigbang => const ['매물 등록 완료'],
    ListingPlatform.dabang => const ['등록 완료'],
    ListingPlatform.daangn => const ['매물 등록하기'],
  };

  /// 플랫폼이 매물에 붙여 주는 번호를 **그 플랫폼이 부르는 이름** (미러 실측
  /// 2026-09-21: 직방 카드는 「등록번호 : 50144198」, 다방 카드는 번호만 「58948955」를
  /// 달고 검색창이 「매물번호」라고 적는다).
  ///
  /// 사람에게 말을 걸 때 쓴다 — 목록에서 눈으로 견줄 글자가 플랫폼마다 다르기
  /// 때문이다. 번호를 **읽어 내는** 쪽은 두 이름을 모두 받아 준다([listingNumberScript]).
  String get listingNumberLabel => switch (this) {
    ListingPlatform.zigbang => '등록번호',
    ListingPlatform.dabang => '매물번호',
    ListingPlatform.daangn => '매물번호',
  };

  /// The platform's own "take this listing down" buttons on [listingsUrl].
  /// The 당근 mirror has not captured one yet.
  List<String> get takedownLabels => switch (this) {
    ListingPlatform.zigbang => const ['매물 종료하기', '매물 종료'],
    ListingPlatform.dabang => const ['광고 종료', '거래 완료'],
    ListingPlatform.daangn => const ['거래완료', '미노출'],
  };

  /// 지금 쓸 수 있는가. **여기가 유일한 스위치다.**
  ///
  /// 당근은 내리기(거래완료·미노출) 자리를 아직 수집하지 못해 잠시 내려 뒀다.
  /// 다시 켜려면 이 한 줄을 `live` 로 되돌리면 된다 — 화면·흐름은 그대로 따라온다.
  PlatformStatus get status => switch (this) {
    ListingPlatform.zigbang => PlatformStatus.live,
    ListingPlatform.dabang => PlatformStatus.live,
    ListingPlatform.daangn => PlatformStatus.paused,
  };

  bool get isLive => status == PlatformStatus.live;

  /// 회색 카드에 적어 주는 말. 쓸 수 있는 플랫폼에는 없다.
  String? get pausedNote => switch (status) {
    PlatformStatus.live => null,
    PlatformStatus.paused => '준비 중',
  };

  /// 로그인 화면이 있는 플랫폼인가. 당근은 실물 로그인을 아직 수집하지 못했다.
  ///
  /// `!= daangn` 이 아니라 **switch 로 적는다** — 플랫폼이 하나 늘면 컴파일러가
  /// 여기를 짚어 준다. 「빠뜨린 설정이 조용히 기본값을 갖는」 일이 없게.
  bool get hasLogin => switch (this) {
    ListingPlatform.zigbang => true,
    ListingPlatform.dabang => true,
    ListingPlatform.daangn => false,
  };

  /// 지금 보고 있는 주소가 「로그인하라」는 화면인가 (활성 사이트 기준).
  bool isSignedOut(Uri url) => urls.isSignedOut(url);

  /// 세션 쿠키 이름 (실측). 다방 것은 HttpOnly 라 JS 에서는 보이지 않는다.
  String get sessionCookie => switch (this) {
    ListingPlatform.zigbang => 'ceo_zauth',
    ListingPlatform.dabang => 'auth_key',
    ListingPlatform.daangn => '',
  };

  SessionCheck get sessionCheck => switch (this) {
    ListingPlatform.zigbang => SessionCheck.cookieVisible,
    ListingPlatform.dabang => SessionCheck.platformAsks,
    ListingPlatform.daangn => SessionCheck.none,
  };

  /// 플랫폼에게 「로그인돼 있나」를 묻는 주소 (페이지와 같은 출처의 경로). 답은
  /// **코드가 아니라 본문**으로 온다 — 로그인 전에도 200 이다.
  String get sessionCheckPath => urls.sessionCheckPath;

  /// The form whose own upload handler takes the selected photos, if any.
  PhotoTarget? get photoTarget => switch (this) {
    ListingPlatform.zigbang => PhotoTarget.zigbang,
    ListingPlatform.dabang => PhotoTarget.dabang,
    ListingPlatform.daangn => PhotoTarget.daangn,
  };

  /// Zigbang and Dabang search addresses through the Kakao postcode window.
  /// Daangn searches its own same-origin endpoint inside the page, so its
  /// adapter picks the result itself.
  bool get usesKakaoPostcode => switch (this) {
    ListingPlatform.zigbang => true,
    ListingPlatform.dabang => true,
    ListingPlatform.daangn => false,
  };
}

/// 통합 폼이 받는 사진 장수 — **사진을 받는 플랫폼들의 규칙을 모두 만족시키는 구간.**
///
/// 지금은 직방이 가장 깐깐하다: 「이미지 넣기」 창이 5장을 채우기 전에는 [확인] 을
/// 열어 주지 않는다(2026-09-08 현장조사 §3-6). 한 곳이라도 못 받는 장수를 통합 폼이
/// 받아 주면, 그 사진은 등록 흐름 한복판에서 조용히 떨어져 나간다.
int get minListingPhotos => ListingPlatform.values
    .map((platform) => platform.photoTarget?.minimum ?? 0)
    .reduce((a, b) => a > b ? a : b);

int get maxListingPhotos => ListingPlatform.values
    .map((platform) => platform.photoTarget?.maximum ?? 0)
    .where((limit) => limit > 0)
    .reduce((a, b) => a < b ? a : b);

enum InputType {
  text,
  number,
  date,
  choice,
  toggle,
  multiSelect,
  addressSearch,
  loan,
  manageDetails,
  photoPicker,
}

class MasterField {
  const MasterField({
    required this.number,
    required this.key,
    required this.label,
    required this.type,
    required this.example,
    this.required = false,
    this.options = const [],
    this.visibleWhenKey,
    this.visibleWhenValue,
    this.maxLength,
    this.targetAvailable = true,
    this.unavailableReason,
  });

  final int number;
  final String key;
  final String label;
  final InputType type;
  final String example;
  final bool required;
  final List<String> options;
  final String? visibleWhenKey;
  final String? visibleWhenValue;
  final int? maxLength;
  final bool targetAvailable;
  final String? unavailableReason;
}

class FieldGroup {
  const FieldGroup(this.title, this.fields);
  final String title;
  final List<MasterField> fields;
}

/// 매물 종류 — **건물의 형태**다. 방이 몇 개인지, 원룸이면 오픈형인지 분리형인지는
/// 따로 받는다([roomCount], [HifiField.structure]).
///
/// 다방은 이것을 그대로 대분류(주택/빌라·오피스텔·아파트)와 소분류(빌라/연립/다세대·
/// 단독주택·다가구주택·상가주택)로 받고, 직방은 여기에 방 수를 더해 원룸·빌라·오피스텔
/// 폼 가운데 하나를 연다([zigbangFormFor]). 예전의 「오픈형 원룸」·「투룸 빌라」 같은 섞인
/// 이름은 그 원룸이 다가구주택에 있는지 빌라에 있는지를 말하지 못해, 다방 소분류를
/// 늘 「빌라/연립/다세대」로 잘못 골랐다.
const propertyTypes = ['빌라/연립/다세대', '단독주택', '다가구주택', '상가주택', '오피스텔', '아파트'];

/// 단지를 골라야 하는 매물. 다방은 주소 대신 시/도→시/군/구→동→단지와 평형을 받고,
/// 호와 세대당 주차 수를 필수로 받는다(실물 실측 2026-09-21).
const complexPropertyTypes = {'오피스텔', '아파트'};

bool isComplexProperty(Map<String, dynamic> values) =>
    complexPropertyTypes.contains(values['propertyType']);

/// 방 개수. 「5 이상」은 5 로 센다. 아직 없으면 1.
int roomCount(Map<String, dynamic> values) =>
    int.tryParse(
      '${values['rooms'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), ''),
    ) ??
    1;

/// 직방이 매물을 받는 폼.
///
/// 폼마다 받는 구조가 다르다(실물 번들 2026-09-21): 원룸 폼은 오픈형·분리형·복층형
/// 원룸만, 빌라 폼은 투룸·쓰리룸·포룸+ 만, 오피스텔 폼은 원룸부터 쓰리룸+ 까지.
/// 거래 유형도 원룸 폼만 전세·월세이고 빌라·오피스텔 폼은 매매까지 받는다.
enum ZigbangForm { oneroom, villa, officetel }

/// 직방이 이 매물을 받는 폼. 받지 않으면 null — 아파트는 직방이 원룸·빌라·오피스텔
/// 광고로 받지 않는다(주소가 아파트면 「광고배너상품 이용불가」로 막는다).
ZigbangForm? zigbangFormFor(Map<String, dynamic> values) {
  final type = values['propertyType'];
  if (type == '오피스텔') return ZigbangForm.officetel;
  if (type == '아파트' || !propertyTypes.contains(type)) return null;
  return roomCount(values) >= 2 ? ZigbangForm.villa : ZigbangForm.oneroom;
}

/// 건축물대장의 용도 — **다방 목록의 글자 그대로**다(실물 실측 2026-09-21).
///
/// 다방은 이 목록에서 고르게 하고, 직방은 「단독주택」이 아니면 「그 외(직접 입력)」에
/// 이 글자를 적게 한다. 그래서 다방 글자를 쓰면 두 곳 모두에 그대로 들어간다.
const buildingUses = [
  '단독주택',
  '공동주택',
  '제1종근린생활시설',
  '제2종근린생활시설',
  '업무시설',
  '숙박시설',
  '문화 및 집회시설',
  '종교시설',
  '판매시설',
  '운수시설',
  '의료시설',
  '교육연구시설',
  '노유자(노인 및 어린이 시설)',
  '수련시설',
  '운동시설',
  '위락시설',
  '공장',
  '창고시설',
  '위험물 저장 및 처리 시설',
  '자동차 관련 시설',
  '동물 및 식물 관련 시설',
  '자원순환 관련 시설',
  '교정 및 군사 시설',
  '방송통신시설',
  '발전시설',
  '묘지 관련 시설',
  '관광 휴게시설',
  '장례시설',
  '야영장 시설',
  '미등기건물',
  '그 밖에 토지의 정착물',
];

/// 다방은 오피스텔·아파트의 건축물용도를 이 셋으로만 받는다.
const complexBuildingUses = ['공동주택', '업무시설', '숙박시설'];

/// 관리비에 포함되는 비목 — 직방·다방이 **똑같이** 쓰는 여덟 가지다(직방 「관리비
/// 포함 항목」, 다방 상세입력 창 「포함 항목」, 실물 실측 2026-09-21).
const manageFeeItems = [
  '일반(공용) 관리비',
  '전기',
  '수도',
  '가스',
  '난방',
  '인터넷',
  'TV',
  '기타 관리비',
];

/// 정액 관리비가 10만원 이상일 때 직방·다방이 비목마다 부과 방식과 금액을 따로 받는
/// 사용료. 공용 관리비와 기타 관리비는 줄이 따로 있다.
const usageFeeItems = ['전기', '수도', '가스', '난방', '인터넷', 'TV'];
const commonFeeItem = '일반(공용) 관리비';
const etcFeeItem = '기타 관리비';

/// 정액 관리비의 구간. 다방 상세입력 창의 세 가지와 같고, 직방은 「10만원 미만」을
/// 「기타 · 관리비 월 10만원 미만」으로, 나머지 둘을 「정액 관리비」의 「고지 받았습니다 /
/// 받지 않았습니다」로 받는다.
const feeTiers = ['10만원 미만', '10만원 이상', '10만원 이상 (세부내역 미고지)'];

/// 비목 하나의 부과 방식. 「해당 없음」은 직방에만 있고 다방에는 「실비」로 들어간다.
const feeItemWays = ['정액', '실비', '해당 없음'];
const commonFeeWays = ['정액', '실비'];

const loanOptions = ['없음', '시세 30% 미만', '시세 30% 이상'];
const directionBases = ['거실 기준', '안방 기준'];
const shortTermNegotiations = ['이내 협의가능', '이상 협의가능'];
const airconTypes = ['벽걸이형', '스탠드형', '천장형'];
const roomFeatureOptions = ['신축', '큰길가'];

/// 직방이 집주인 전화번호를 [확인] 했을 때 이미 다른 매물에 쓰인 번호면 고르게 하는
/// 사유(필수, 실물 2026-09-21). 쓰일지는 [확인] 을 눌러 봐야 알아서 미리 받아 둔다.
const ownerPhoneDuplicateReasons = ['의뢰인 다주택 보유', '법인 소유', '관리인·대리인 위임', '기타'];

/// 직방 「중개 의뢰를 받은 방법」(필수).
const mediationMethods = ['전화로 확인', '만나서 확인', '기타 방법으로 확인'];

/// The hi-fi splits the master 가전·가구 row into two chip groups. Together
/// they are **both** platforms' lists: 직방 「옵션」 and 다방 「생활 시설」 (+ 에어컨,
/// whose type goes to 다방 「냉방 시설」).
const homeApplianceOptions = [
  '에어컨',
  '세탁기',
  '건조기',
  '냉장고',
  '가스레인지',
  '인덕션',
  '전자레인지',
  '가스오븐',
  '식기세척기',
  'TV',
  '비데',
];
const furnitureOptions = [
  '침대',
  '책상',
  '책장',
  '옷장',
  '붙박이장',
  '신발장',
  '식탁',
  '쇼파',
  '싱크대',
  '샤워부스',
  '욕조',
];
const _appliances = [...homeApplianceOptions, ...furnitureOptions];

/// 보안·부대시설 — 다방 「보안 시설」·「기타 시설」과 직방 「매물 조건」을 합친 것.
const securityOptions = [
  '경비원',
  '비디오폰',
  '인터폰',
  '카드키',
  'CCTV',
  '사설경비',
  '공동현관보안',
  '방범창',
  '화재경보기',
  '베란다/발코니',
  '테라스',
  '마당',
  '무인택배함',
];
const evChargerFacility = '전기차 충전시설';
const _facilities = [...securityOptions, evChargerFacility];

/// The specification's 50 input rows, preserved individually in five sections,
/// and the rows the live forms turned out to need on top of them (51~).
final List<FieldGroup> groups = [
  FieldGroup('1. 매물 기본 정보', [
    MasterField(
      number: 1,
      key: 'propertyType',
      label: '매물 종류',
      type: InputType.choice,
      required: true,
      example: '단독주택',
      options: propertyTypes,
    ),
    MasterField(
      number: 2,
      key: 'address',
      label: '매물 기본 주소',
      type: InputType.addressSearch,
      required: true,
      example: '경북 포항시 남구 대도동 168-7',
      unavailableReason:
          '여기서 저장한 주소는 직방·다방의 카카오 주소 검색 창에 검색어로 그대로 넘어갑니다. 좌표와 우편번호는 그 창에서 결과를 골라야 확정되므로, 전송 화면에서 한 번 눌러 주세요.',
    ),
    MasterField(
      number: 51,
      key: 'complexName',
      label: '단지명',
      type: InputType.text,
      example: '포항자이',
    ),
    MasterField(
      number: 3,
      key: 'building',
      label: '동 정보',
      type: InputType.text,
      example: '101',
    ),
    MasterField(
      number: 4,
      key: 'singleBuilding',
      label: '단일동 여부',
      type: InputType.toggle,
      example: 'true',
    ),
    MasterField(
      number: 5,
      key: 'unit',
      label: '호수 정보',
      type: InputType.text,
      required: true,
      example: '105',
    ),
    MasterField(
      number: 6,
      key: 'exclusiveArea',
      label: '전용면적 (㎡)',
      type: InputType.number,
      required: true,
      example: '26',
    ),
    MasterField(
      number: 7,
      key: 'supplyArea',
      label: '공급면적 (㎡)',
      type: InputType.number,
      required: true,
      example: '30',
    ),
    MasterField(
      number: 8,
      key: 'floorAll',
      label: '전체 층',
      type: InputType.number,
      required: true,
      example: '4',
    ),
    MasterField(
      number: 9,
      key: 'floor',
      label: '해당 층',
      type: InputType.choice,
      required: true,
      example: '3',
      options: ['반지하', ...List.generate(80, (i) => '${i + 1}'), '옥탑'],
    ),
    MasterField(
      number: 10,
      key: 'floorPrivate',
      label: '층수 비공개 여부',
      type: InputType.toggle,
      example: 'false',
    ),
    MasterField(
      number: 11,
      key: 'buildingUse',
      label: '건축물 용도',
      type: InputType.choice,
      required: true,
      example: '단독주택',
      options: buildingUses,
    ),
    MasterField(
      number: 12,
      key: 'approvalDate',
      label: '사용승인일',
      type: InputType.date,
      required: true,
      example: '2013-10-21',
    ),
  ]),
  FieldGroup('2. 가격 및 관리비 정보', [
    MasterField(
      number: 13,
      key: 'trade',
      label: '거래 유형',
      type: InputType.choice,
      required: true,
      example: '월세',
      options: ['월세', '전세', '매매'],
    ),
    MasterField(
      number: 14,
      key: 'deposit',
      label: '보증금 (만원)',
      type: InputType.number,
      required: true,
      example: '200',
    ),
    MasterField(
      number: 15,
      key: 'monthlyRent',
      label: '월세 금액 (만원)',
      type: InputType.number,
      required: true,
      example: '20',
      visibleWhenKey: 'trade',
      visibleWhenValue: '월세',
    ),
    MasterField(
      number: 16,
      key: 'salePrice',
      label: '매매 금액 (만원)',
      type: InputType.number,
      example: '45000',
      visibleWhenKey: 'trade',
      visibleWhenValue: '매매',
      unavailableReason:
          '직방 원룸 폼은 매매를 받지 않습니다. 방 2개 이상 빌라·오피스텔만 직방에 매매로 올릴 수 있습니다.',
    ),
    MasterField(
      number: 17,
      key: 'shortTerm',
      label: '단기 매물 여부',
      type: InputType.toggle,
      example: 'false',
      visibleWhenKey: 'trade',
      visibleWhenValue: '월세',
    ),
    MasterField(
      number: 52,
      key: 'shortTermMonths',
      label: '단기 계약 기간 (개월)',
      type: InputType.choice,
      example: '6',
      options: List.generate(11, (i) => '${i + 1}'),
      visibleWhenKey: 'shortTerm',
      visibleWhenValue: 'true',
    ),
    MasterField(
      number: 53,
      key: 'shortTermNegotiation',
      label: '단기 계약 기간 협의',
      type: InputType.choice,
      example: '이내 협의가능',
      options: shortTermNegotiations,
      visibleWhenKey: 'shortTerm',
      visibleWhenValue: 'true',
    ),
    MasterField(
      number: 18,
      key: 'loan',
      label: '융자금',
      type: InputType.loan,
      required: true,
      example: '없음',
      options: loanOptions,
    ),
    MasterField(
      number: 19,
      key: 'noManagementFee',
      label: '관리비 없음',
      type: InputType.toggle,
      example: 'false',
    ),
    MasterField(
      number: 20,
      key: 'manageMethod',
      label: '관리비 부과 방식',
      type: InputType.choice,
      required: true,
      example: '정액 관리비',
      options: ['정액 관리비', '기타 부과', '확인 불가'],
    ),
    MasterField(
      number: 54,
      key: 'feeTier',
      label: '정액 관리비 구간',
      type: InputType.choice,
      example: '10만원 미만',
      options: feeTiers,
      visibleWhenKey: 'manageMethod',
      visibleWhenValue: '정액 관리비',
    ),
    MasterField(
      number: 21,
      key: 'manageBasis',
      label: '관리비 부과 기준',
      type: InputType.choice,
      example: '직전월 관리비 기준',
      options: ['직전월 관리비 기준', '3개월 평균 관리비', '1년 평균 관리비', '기타 직접 입력'],
    ),
    MasterField(
      number: 55,
      key: 'manageBasisNote',
      label: '부과 기준 직접 입력',
      type: InputType.text,
      example: '최근 6개월 평균',
      maxLength: 20,
      visibleWhenKey: 'manageBasis',
      visibleWhenValue: '기타 직접 입력',
    ),
    MasterField(
      number: 22,
      key: 'managementFee',
      label: '관리비 총액 (만원)',
      type: InputType.number,
      example: '9',
    ),
    MasterField(
      number: 23,
      key: 'manageIncludes',
      label: '관리비 포함 항목',
      type: InputType.multiSelect,
      example: '수도,인터넷,TV',
      options: manageFeeItems,
    ),
    MasterField(
      number: 24,
      key: 'manageDetail',
      label: '항목별 관리비 (정액 10만원 이상)',
      type: InputType.manageDetails,
      example: '일반(공용) 관리비:정액 50000, 전기:실비',
    ),
    MasterField(
      number: 25,
      key: 'otherFeeReason',
      label: '기타 부과 근거',
      type: InputType.choice,
      example: '관리규약에 따라 부과',
      options: [
        '관리규약에 따라 부과',
        '면적 및 세대별 부과',
        '전체 세대 균등 부과',
        '계량기별 실비 부과',
        '기타',
      ],
      visibleWhenKey: 'manageMethod',
      visibleWhenValue: '기타 부과',
    ),
    MasterField(
      number: 56,
      key: 'otherFeeNote',
      label: '기타 부과 근거 직접 입력',
      type: InputType.text,
      example: '세대별 균등 부과',
      maxLength: 20,
      visibleWhenKey: 'otherFeeReason',
      visibleWhenValue: '기타',
    ),
    MasterField(
      number: 26,
      key: 'unknownFeeReason',
      label: '확인 불가 사유',
      type: InputType.choice,
      example: '미등기·신축 건물 사유',
      options: ['단독주택 사유', '상가 건물 사유', '미등기·신축 건물 사유'],
      visibleWhenKey: 'manageMethod',
      visibleWhenValue: '확인 불가',
    ),
  ]),
  FieldGroup('3. 방 구조 및 건물 조건', [
    MasterField(
      number: 27,
      key: 'roomLayout',
      label: '방 구조',
      type: InputType.choice,
      example: '오픈형 원룸',
      options: ['오픈형 원룸', '분리형 원룸', '복층형 원룸'],
    ),
    MasterField(
      number: 28,
      key: 'rooms',
      label: '방 개수',
      type: InputType.choice,
      required: true,
      example: '1',
      options: ['1', '2', '3', '4', '5 이상'],
    ),
    MasterField(
      number: 29,
      key: 'bathrooms',
      label: '욕실 수',
      type: InputType.choice,
      required: true,
      example: '1',
      options: ['1', '2', '3', '4', '5'],
    ),
    MasterField(
      number: 30,
      key: 'directionBase',
      label: '방향 기준',
      type: InputType.choice,
      required: true,
      example: '안방 기준',
      options: directionBases,
    ),
    MasterField(
      number: 31,
      key: 'direction',
      label: '주실 방향',
      type: InputType.choice,
      required: true,
      example: '동향',
      options: ['동향', '서향', '남향', '북향', '북동향', '남동향', '북서향', '남서향'],
    ),
    MasterField(
      number: 32,
      key: 'parking',
      label: '주차 가능 여부',
      type: InputType.choice,
      required: true,
      example: '주차 가능',
      options: ['주차 가능', '주차 불가능'],
    ),
    MasterField(
      number: 33,
      key: 'parkingCount',
      label: '총 주차 대수',
      type: InputType.number,
      example: '7',
      visibleWhenKey: 'parking',
      visibleWhenValue: '주차 가능',
    ),
    MasterField(
      number: 34,
      key: 'parkingPerHousehold',
      label: '세대당 주차 대수',
      type: InputType.number,
      example: '0.7',
      visibleWhenKey: 'parking',
      visibleWhenValue: '주차 가능',
      unavailableReason: '직방은 총 주차대수만 받습니다. 다방은 오피스텔·아파트에서 세대당 주차 수를 필수로 받습니다.',
    ),
    MasterField(
      number: 35,
      key: 'elevator',
      label: '엘리베이터 유무',
      type: InputType.choice,
      required: true,
      example: '없음',
      options: ['있음', '없음'],
    ),
    MasterField(
      number: 36,
      key: 'violation',
      label: '위반건축물 여부',
      type: InputType.choice,
      required: true,
      example: '해당 없음',
      options: ['해당 없음', '위반건축물 해당'],
    ),
    MasterField(
      number: 37,
      key: 'loanAvailable',
      label: '대출 가능 여부',
      type: InputType.choice,
      required: true,
      example: '불가능',
      options: ['가능', '불가능', '확인 필요'],
    ),
    MasterField(
      number: 38,
      key: 'petAllowed',
      label: '반려동물 가능 여부',
      type: InputType.choice,
      required: true,
      example: '불가능',
      options: ['가능', '불가능', '확인 필요'],
    ),
    MasterField(
      number: 39,
      key: 'heating',
      label: '난방 방식',
      type: InputType.choice,
      required: true,
      example: '개별난방',
      options: ['개별난방', '중앙난방', '지역난방'],
      unavailableReason: '직방 폼에는 난방 방식 입력 항목이 없습니다.',
    ),
  ]),
  FieldGroup('4. 시설 및 옵션', [
    MasterField(
      number: 40,
      key: 'appliances',
      label: '가전·가구 옵션',
      type: InputType.multiSelect,
      example: '에어컨,냉장고,세탁기,가스레인지,신발장,싱크대',
      options: _appliances,
    ),
    MasterField(
      number: 57,
      key: 'airconType',
      label: '에어컨 종류',
      type: InputType.multiSelect,
      example: '벽걸이형',
      options: airconTypes,
    ),
    MasterField(
      number: 41,
      key: 'facilities',
      label: '보안 및 시설 옵션',
      type: InputType.multiSelect,
      example: 'CCTV',
      options: _facilities,
    ),
    MasterField(
      number: 60,
      key: 'roomFeatures',
      label: '방 특징',
      type: InputType.multiSelect,
      example: '큰길가',
      options: roomFeatureOptions,
    ),
  ]),
  FieldGroup('5. 입주 및 매물 상세 설명', [
    MasterField(
      number: 42,
      key: 'moveInType',
      label: '입주 방식',
      type: InputType.choice,
      required: true,
      example: '즉시 입주',
      options: ['즉시 입주', '날짜 지정'],
    ),
    MasterField(
      number: 43,
      key: 'moveInDate',
      label: '입주 가능일',
      type: InputType.date,
      example: '2026-10-01',
      visibleWhenKey: 'moveInType',
      visibleWhenValue: '날짜 지정',
    ),
    MasterField(
      number: 44,
      key: 'moveInNegotiable',
      label: '입주 협의 가능 여부',
      type: InputType.toggle,
      example: 'false',
    ),
    MasterField(
      number: 45,
      key: 'photoCount',
      label: '매물 사진 첨부',
      type: InputType.photoPicker,
      required: true,
      example: '0',
      unavailableReason:
          '사진은 5장 이상 20장 이하로 필수입니다 — 직방이 그렇게 요구합니다(첫 장이 대표 사진). '
          '직방은 JPG·PNG 만, 장당 10MB까지 받습니다. 선택한 사진은 직방·다방 등록 폼에 자동으로 첨부됩니다.',
    ),
    MasterField(
      number: 46,
      key: 'title',
      label: '매물 제목 (한줄 요약)',
      type: InputType.text,
      required: true,
      example: '종합운동장 근교 밝은 원룸',
      maxLength: titleMaxLength,
    ),
    MasterField(
      number: 47,
      key: 'description',
      label: '매물 상세 설명',
      type: InputType.text,
      required: true,
      example:
          '종합운동장 근교의 밝고 깔끔한 오픈형 원룸입니다. 남구 대도동 주택가에 있어 조용하고, 주변에 마트와 버스 정류장이 가까워 생활이 편리합니다. 아직 세입자가 거주 중이라 약속 후 방을 보실 수 있습니다.',
      maxLength: descriptionMaxLength,
    ),
    MasterField(
      number: 48,
      key: 'lh',
      label: 'LH 전세임대 여부',
      type: InputType.choice,
      example: '불가능',
      options: ['가능', '불가능'],
      unavailableReason: '직방 폼은 LH 전세임대 여부를 입력받지 않습니다.',
    ),
    MasterField(
      number: 49,
      key: 'privateMemo',
      label: '비공개 메모 (내부용)',
      type: InputType.text,
      example: '대도 화이트하우스',
      maxLength: privateMemoMaxLength,
    ),
    MasterField(
      number: 50,
      key: 'ownerPhone',
      label: '집주인 연락처',
      type: InputType.text,
      example: '010-1234-5678',
    ),
    MasterField(
      number: 61,
      key: 'ownerPhoneDuplicateReason',
      label: '집주인 번호 중복 시 사유',
      type: InputType.choice,
      example: '의뢰인 다주택 보유',
      options: ownerPhoneDuplicateReasons,
    ),
    MasterField(
      number: 62,
      key: 'ownerPhoneDuplicateNote',
      label: '중복 사유 직접 입력',
      type: InputType.text,
      example: '형제 공동 소유',
      maxLength: 32,
      visibleWhenKey: 'ownerPhoneDuplicateReason',
      visibleWhenValue: '기타',
    ),
    MasterField(
      number: 58,
      key: 'mediationMethod',
      label: '중개 의뢰 확인 방법',
      type: InputType.choice,
      required: true,
      example: '전화로 확인',
      options: mediationMethods,
    ),
    MasterField(
      number: 59,
      key: 'mediationNote',
      label: '기타 확인 방법',
      type: InputType.text,
      example: '문자로 확인',
      visibleWhenKey: 'mediationMethod',
      visibleWhenValue: '기타 방법으로 확인',
    ),
  ]),
];

/// 두 플랫폼이 모두 받아 주는 글자 수 — 짧은 쪽 상한과 긴 쪽 하한이다(실물 실측
/// 2026-09-21).
///
/// - 제목: 직방 한줄 요약 **7~32자**, 다방 제목 40자 → 7~32자
/// - 상세 설명: 직방 **50~2000자**, 다방 **1000자** → 50~1000자
/// - 비밀 메모: 직방 **200자**, 다방 제한 없음 → 200자
/// - 입주 추가 설명: 직방 **10자**
const titleMinLength = 7;
const titleMaxLength = 32;
const descriptionMinLength = 50;
const descriptionMaxLength = 1000;
const privateMemoMaxLength = 200;
const moveInNoteMaxLength = 10;

/// Rows the hi-fi form asks for on top of the 50 master rows. They travel with
/// the listing and show on 102. Adapters read the ones a platform has a place
/// for (총 세대수·현관 구조·층군·전자계약·임대인 성함 …).
abstract final class HifiField {
  static const householdCount = 'householdCount';
  static const moveInNote = 'moveInNote';
  static const eContract = 'eContract';
  static const floorBand = 'floorBand';
  static const structure = 'structure';
  static const duplex = 'duplex';
  static const entranceType = 'entranceType';
  static const monthlyParkingFee = 'monthlyParkingFee';
  static const evCharger = 'evCharger';
  static const tags = 'tags';
  static const ownerName = 'ownerName';
  static const brokerageRoute = 'brokerageRoute';

  /// What 자동 채우기 puts in each of them.
  static const examples = <String, Object>{
    householdCount: '10',
    moveInNote: '퇴거일 협의',
    eContract: '불가능',
    floorBand: '중층',
    structure: '오픈형',
    duplex: '단층',
    entranceType: '계단식',
    monthlyParkingFee: '0',
    evCharger: '없음',
    tags: ['주차가능', '조용한 동네'],
    ownerName: '홍길동',
    brokerageRoute: '일반 의뢰',
  };
}

const eContractOptions = ['가능', '불가능'];
const floorBandOptions = ['저층', '중층', '고층'];
const structureOptions = ['오픈형', '분리형'];
const duplexOptions = ['단층', '복층'];
const entranceOptions = ['계단식', '복도식', '복합식'];
const availabilityOptions = ['있음', '없음'];
const tagOptions = ['역세권', '주차가능', '풀옵션', '조용한 동네', '채광 좋은 집'];
const brokerageRoutes = ['일반 의뢰', '전속 중개', '공동 중개', '기존 고객'];

String optionLabel(String value) => switch (value) {
  '공동현관보안' => '현관보안',
  '베란다/발코니' => '베란다',
  _ => value,
};

/// The master 방 구조 row, rebuilt from the hi-fi's 구조 and 복층 여부. Only a
/// one-room listing has one — 투룸 이상은 방 수가 곧 구조다.
String? roomLayoutFrom({String? structure, String? duplex, int rooms = 1}) {
  if (rooms > 1) return null;
  if (duplex == '복층') return '복층형 원룸';
  if (structure == null) return null;
  return '$structure 원룸';
}

/// 지금 쓸 수 있는 플랫폼만. **고르기·연동·등록·종료는 전부 이것으로 돈다** —
/// 새 플랫폼이 들어오면 enum 에 값을 더하고 설정만 채우면 여기에 저절로 들어오고,
/// 잠시 내리면 여기서 저절로 빠진다.
///
/// 화면에 **회색으로 남겨 보여 주는** 자리(고르는 카드)만 [ListingPlatform.values] 를
/// 그대로 쓰고, 고를 수 없게 막는다.
List<ListingPlatform> get livePlatforms => ListingPlatform.values
    .where((platform) => platform.isLive)
    .toList(growable: false);
