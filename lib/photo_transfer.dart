import 'dart:convert';

import 'package:image_picker/image_picker.dart';

import 'fields.dart';

const maxListingPhotoBytes = 30 * 1024 * 1024;

/// Read only the header here. The full image is streamed when transferring it.
Future<String> validateListingPhoto(XFile photo) async {
  final length = await photo.length();
  if (length == 0) throw FormatException('${photo.name}: 빈 사진 파일입니다.');
  if (length > maxListingPhotoBytes) {
    throw FormatException('${photo.name}: 사진 한 장은 최대 30MB입니다.');
  }
  final header = <int>[];
  await for (final chunk in photo.openRead(0, length < 32 ? length : 32)) {
    header.addAll(chunk);
  }
  bool starts(List<int> bytes) =>
      header.length >= bytes.length &&
      List.generate(bytes.length, (i) => header[i] == bytes[i]).every((v) => v);
  if (starts([0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
  if (starts([71, 73, 70, 56])) return 'image/gif';
  if (starts([66, 77])) return 'image/bmp';
  final ascii = String.fromCharCodes(header);
  if (ascii.length >= 12 &&
      ascii.startsWith('RIFF') &&
      ascii.substring(8).startsWith('WEBP')) {
    return 'image/webp';
  }
  if (ascii.length >= 12 && ascii.substring(4, 8) == 'ftyp') {
    final brand = ascii.substring(8, 12);
    if (['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].contains(brand)) {
      return 'image/heic';
    }
    if (['avif', 'avis'].contains(brand)) return 'image/avif';
  }
  throw FormatException(
    '${photo.name}: 지원하는 사진 파일(JPEG, PNG, GIF, WebP, BMP, HEIC, AVIF)이 아닙니다.',
  );
}

const _validatedPhotoTypes = {
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/bmp',
  'image/webp',
  'image/heic',
  'image/avif',
};

/// A platform form whose own upload handler receives the listing photos.
///
/// Each target tells the shared bridge where its photo input is, which nodes
/// are its photo cards and when a card has finished uploading.
enum PhotoTarget {
  /// 직방 — 사진을 **창 안에서** 받는다 (2026-09-08 현장조사 §3-6).
  ///
  /// 폼의 `input[name=images]` 는 값을 받아 적기만 하는 readonly 칸이고, 누르면
  /// 「이미지 넣기」 창이 열린다. 진짜 파일 입력은 그 창 안 Dropzone 에 숨어 있어
  /// 문서를 아무리 뒤져도 보이지 않는다 — 그래서 [modal] 이다. 고른 사진은 창의
  /// [확인] 을 눌러야 폼의 카드 목록으로 들어온다.
  ///
  /// 창에 적힌 규칙이 곧 여기 숫자들이다: JPG·JPEG·PNG 만, 장당 최대 10MB,
  /// **최소 5장 최대 20장**, 첫 장이 대표 사진.
  zigbang(
    label: '직방',
    platform: ListingPlatform.zigbang,
    acceptedTypes: {'image/jpeg', 'image/png'},
    minimum: 5,
    maximum: 20,
    maxBytes: 10 * 1024 * 1024,
    modal: true,
    locators: r'''
  // 창은 포털로 <body> 끝에 붙고 제목으로만 제 이름을 밝힌다. 닫히는 중인 창
  // (data-state=closed)은 아직 문서에 남아 있으므로 살아 있는 것만 고른다.
  const dialog = () => [...document.querySelectorAll('[role="dialog"]')]
      .find(box => box.getAttribute('data-state') !== 'closed' &&
          /이미지 넣기/.test(box.textContent || '')) || null;
  const input = () => { const box = dialog(); return box ? box.querySelector('input[type="file"]') : null; };
  const validInput = el => !!el && el.multiple && /image/.test(el.accept || '');
  const trigger = () => document.querySelector('input[name="images"]');
  // 사진 칸 — 트리거를 품으면서 카드 목록(ul)까지 함께 가진 **가장 가까운** 조상.
  // 창이 열리고 닫히는 동안에도 이 노드는 그대로라, 「사진 자리가 갈렸는가」를 잰다.
  const field = () => {
    let node = trigger();
    while (node && node !== document.body) {
      if (node.querySelector && node.querySelector('ul')) return node;
      node = node.parentElement;
    }
    return null;
  };
  const region = () => field();
  // 카드가 li 인지 div 인지는 실물에서 확인하지 못했다(현장조사는 창을 열고 곧바로
  // 닫았다). 목록의 자식이면 무엇이든 카드로 센다 — 늘 거기 있는 것은 전송 전에
  // 찍어 둔 [before] 에도 들어가므로 셈이 어긋나지 않는다.
  const cards = () => { const spot = field(); return spot ? [...spot.querySelectorAll('ul > *')] : []; };
  const cardId = card => card.getAttribute('data-id') || card.id ||
      (card.querySelector('img')
        ? 'img:' + String(card.querySelector('img').getAttribute('src') || '').slice(-24)
        : null) ||
      (card.parentElement ? 'nth:' + [...card.parentElement.children].indexOf(card) : null);
  const settled = card => !!cardId(card) && card.getAttribute('aria-disabled') !== 'true';
  // 폼 카드는 [확인] 뒤에야 생긴다. 「처리 중」을 창이 떠 있는지로 재면 카드가 영영
  // 자라지 않는 것으로 보이므로, 여기서는 따로 세지 않는다.
  const busy = () => false;
  // 손가락이 닿는 차례를 그대로 흉내 낸다 — 누르는 자리가 onClick 인지 onPointerDown
  // 인지는 그 페이지만 안다. 오래된 WebView 에 PointerEvent 가 없어도 click 은 간다.
  const tap = el => {
    if (!el) return false;
    try {
      el.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true}));
      el.dispatchEvent(new MouseEvent('mousedown', {bubbles: true}));
      el.dispatchEvent(new PointerEvent('pointerup', {bubbles: true}));
      el.dispatchEvent(new MouseEvent('mouseup', {bubbles: true}));
      el.dispatchEvent(new MouseEvent('click', {bubbles: true}));
    } catch (_) { /* click 하나로도 대개 열린다 */ }
    el.click();
    return true;
  };
  const present = () => validInput(input()) || !!trigger();
  // 창이 뜨는 데에는 시간이 걸린다. 되물을 때마다 다시 누르면 방금 연 창을 도로 닫으므로
  // 한 번 누르고 2초는 기다려 본다.
  const openPicker = () => {
    if (validInput(input())) return true;
    const now = Date.now();
    if (!openPicker.at || now - openPicker.at > 2000) { openPicker.at = now; tap(trigger()); }
    return validInput(input());
  };
  const confirm = () => {
    const box = dialog();
    return box ? [...box.querySelectorAll('button')].find(b => (b.textContent || '').trim() === '확인') : null;
  };
  // [확인] 은 직방이 사진을 다 받고 나서야 풀린다. 그때까지는 아직이라고 답한다.
  const sealPicker = () => {
    const box = dialog();
    if (!box) return true;
    const button = confirm();
    if (!button || button.disabled) return false;
    tap(button);
    return false;
  };
  const notices = () => [dialog()];
''',
  ),
  dabang(
    label: '다방',
    platform: ListingPlatform.dabang,
    acceptedTypes: _validatedPhotoTypes,
    locators: r'''
  // The mirror can render this input outside the expected section and gives it
  // generated class names. Locate it by native properties rather than CSS
  // structure or generated class names.
  const input = () => {
    const candidates = document.querySelectorAll('input[type="file"]');
    for (let index = 0; index < candidates.length; index++) {
      const candidate = candidates[index];
      if (candidate.multiple && candidate.accept === 'image/*') return candidate;
    }
    return null;
  };
  const validInput = el => !!el && el.multiple && el.accept === 'image/*';
  const region = () => document.getElementById('visual_info');
  const cards = () => [...document.querySelectorAll('section#visual_info [class*="SortableContainer"] [data-index]')];
  const cardId = card => card.dataset.id || null;
  const settled = card => !!card.dataset.id && card.getAttribute('aria-disabled') === 'false';
  const busy = () => false;
  const present = () => validInput(input());
  const openPicker = () => validInput(input());
  const sealPicker = () => true;
  const notices = () => [];
''',
  ),
  daangn(
    label: '당근',
    platform: ListingPlatform.daangn,
    // The Daangn mirror drops any file whose type is not in its accept list.
    acceptedTypes: {'image/png', 'image/jpeg', 'image/gif', 'image/webp'},
    locators: r'''
  // 사진 칸(#image-upload) 옆의 상자가 자리표시 → 격자로 바뀌고, 올리는 동안
  // cursor-not-allowed 로 잠긴다. 다 올라간 칸은 sortable 이 되고 data-mirror-key 를 받는다.
  const input = () => document.getElementById('image-upload');
  const validInput = el => !!el && el.multiple && /(^|,)image\//.test(el.accept || '');
  const box = () => {
    const el = input();
    return el && el.parentElement ? el.parentElement.querySelector('.transition-all') : null;
  };
  const region = () => box();
  const cards = () => {
    const grid = box() && box().querySelector('div.grid');
    return grid ? [...grid.querySelectorAll('[aria-roledescription="sortable"], .aspect-square')] : [];
  };
  const cardId = card => card.getAttribute('data-mirror-key');
  const settled = card => card.getAttribute('aria-roledescription') === 'sortable' && !!cardId(card);
  const busy = () => !!box() && box().classList.contains('cursor-not-allowed');
  const present = () => validInput(input());
  const openPicker = () => validInput(input());
  const sealPicker = () => true;
  const notices = () => [];
''',
  );

  const PhotoTarget({
    required this.label,
    required this.platform,
    required this.acceptedTypes,
    required this.locators,
    this.minimum = 1,
    this.maximum = 20,
    this.maxBytes = maxListingPhotoBytes,
    this.modal = false,
  });

  final String label;
  final ListingPlatform platform;

  /// 이 폼이 받아 주는 사진 장수. 플랫폼이 스스로 정해 둔 것이다 — 직방은 창에
  /// 「최소 5장, 최대 20장」이라고 적어 두었고, 5장을 못 채우면 [확인] 이 잠긴 채다.
  final int minimum;
  final int maximum;

  /// 장당 크기 한계. 넘는 사진은 전송을 접지 않고 건너뛰고 그 이유를 돌려준다.
  final int maxBytes;

  /// 사진을 **창 안에서** 받는가 (직방). 그러면 파일 입력에 닿기 전에 창을 열어야
  /// 하고([listingPhotoCommand] `open`), 고른 것을 한 번에 건넨 뒤 창의 확인 버튼으로
  /// 폼에 들여보내야 한다(`seal`).
  ///
  /// 한 번에 건네는 이유 — 직방은 5장 미만을 받지 않으므로 한 장씩 건네면 매번
  /// 거절당한다. 게다가 한 장씩 건넬 때 앞 장을 밀어내는지 쌓는지는 그 페이지만
  /// 아는 일이라, **사람이 파일 선택 창에서 하는 그대로** 고른 것을 한 번에 건넨다.
  final bool modal;

  /// The form pages this bridge may run on — the live form and the mirror's,
  /// as `[host, path]` pairs.
  List<List<String>> get formPages => [
    for (final site in PlatformSite.values)
      for (final form in platform.urlsOn(site).forms)
        [platform.urlsOn(site).host, pageDirectory(Uri.parse(form))],
  ];

  /// MIME types this mirror's upload handler keeps. Other photos are skipped
  /// with a reason instead of failing the whole transfer.
  final Set<String> acceptedTypes;

  /// JavaScript defining `input`, `validInput`, `present`, `region`, `cards`,
  /// `cardId`, `settled`, `busy`, `openPicker`, `sealPicker` and `notices` for
  /// [listingPhotoBridgeScript].
  final String locators;
}

/// The mirror owns the upload handler and its cards. Never synthesize cards or
/// success: a file is complete only once that handler settles a new card.
String listingPhotoBridgeScript(PhotoTarget target) =>
    '''
(() => {
  try {
  const LABEL = ${jsonEncode(target.label)};
  const MODAL = ${target.modal};
  const CAPACITY = ${target.maximum};
  const here = location.pathname.endsWith('/') ? location.pathname : location.pathname + '/';
  if (!${jsonEncode(target.formPages)}.some(([host, path]) => location.hostname === host && here.startsWith(path))) throw new Error(LABEL + ' 등록 폼이 아닙니다.');
${target.locators}$_photoBridgeBody''';

const _photoBridgeBody = r'''
  // 직방의 파일 입력은 창을 열기 전에는 문서에 없다. 그래서 「지금 보이는가」가 아니라
  // 「닿을 수 있는가」를 묻는다 — 창을 여는 것은 [open] 의 몫이다.
  if (!present()) {
    throw new Error(LABEL + ' 사진 선택란을 찾지 못했습니다.');
  }
  if (typeof File !== 'function' || typeof DataTransfer !== 'function') throw new Error('이 WebView는 사진 파일 전달을 지원하지 않습니다. 운영체제와 앱을 업데이트해 주세요.');

  // 업로드가 왜 실패했는지는 플랫폼 페이지만 안다. 실물은 사진을 제 저장소로 **진짜**
  // 올리므로 미러에서는 보이지 않던 이유로 실패할 수 있다(2026-09-20: 실기기에서만
  // 「현재 0장입니다」로 끝났고, 같은 방식을 크롬으로 재현하니 1초 만에 카드가 생겼다).
  //
  // 그래서 페이지가 내는 오류를 **엿듣기만** 한다. fetch·XHR 을 바꿔 끼우면 더 많이
  // 볼 수 있지만 하지 않는다 — 남의 계정으로 도는 실물 등록 폼이고, 우리 래퍼가 잘못
  // 되는 순간 그 사람의 업로드가 깨진다. 듣는 것은 페이지를 바꾸지 않는다.
  if (!window.__flrPhotoErrors) {
    const errors = window.__flrPhotoErrors = [];
    const keep = message => {
      const line = String(message || '').replace(/\s+/g, ' ').trim().slice(0, 160);
      if (line && errors.length < 8 && !errors.includes(line)) errors.push(line);
    };
    window.addEventListener('error', event => {
      if (event.message) keep('오류: ' + event.message);
      else if (event.target && event.target !== window && (event.target.src || event.target.href)) {
        keep('불러오기 실패: ' + String(event.target.src || event.target.href).slice(0, 100));
      }
    }, true);
    window.addEventListener('unhandledrejection', event => keep('처리되지 않은 오류: '
      + ((event.reason && (event.reason.message || event.reason)) || '')), true);
  }
  const said = el => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';

  // 플랫폼이 **사람에게 보여 준 말**. 업로드가 실패하면 대개 여기에 이유가 나온다.
  //
  // 모달·토스트만 뒤지면 놓친다. 실기기에서 사진 영역이 6번 움직이고도 카드가 안 생겼는데
  // 여기서는 아무 말도 못 건졌다(2026-09-20) — 다방은 실패를 **사진 자리 안에** 적는다.
  const TROUBLE = /실패|오류|에러|초과|용량|형식|다시 ?시도|불가|없습니다|않습니다/;
  const spoken = () => {
    const spots = [document.getElementById('modal-container'),
      ...document.querySelectorAll('[role="alert"], [class*="Toast"], [class*="toast"], [class*="Alert"]')];
    for (const spot of spots) {
      const line = said(spot);
      if (line) return line.slice(0, 300);
    }
    // 사진 자리에는 안내문이 늘 깔려 있다. 통째로 퍼 오면 정작 실패 문구가 뒤로 밀리므로,
    // **말썽처럼 들리는 잎사귀**부터 고른다. 직방은 사진을 창 안에서 받으므로 거절당한
    // 이유도 그 창에 적힌다 — [notices] 가 그런 자리를 함께 데려온다.
    const places = [region(), ...notices()].filter(Boolean);
    if (!places.length) return null;
    const complaints = [];
    for (const spot of places) {
      for (const el of spot.querySelectorAll('*')) {
        if (el.children.length) continue;
        const line = said(el);
        if (line && line.length < 120 && TROUBLE.test(line) && !complaints.includes(line)) {
          complaints.push(line);
        }
      }
    }
    if (complaints.length) return complaints.join(' / ').slice(0, 300);
    return said(places[0]).slice(0, 300) || null;
  };

  // 사진 자리의 **뼈대**. 카드가 어떤 모습으로 멈춰 있는지는 이것으로만 알 수 있다.
  // 사진·파일 이름·src 는 담지 않는다 — 태그·클래스·data-*·aria-* 뿐이다.
  const bones = () => {
    const spot = region();
    if (!spot) return null;
    const out = [];
    for (const el of spot.querySelectorAll('*')) {
      if (out.length >= 24) break;
      const marks = [];
      for (const a of el.attributes) {
        if (/^(data-|aria-)/.test(a.name) && a.name !== 'data-mirror-src') {
          marks.push(a.name + '=' + a.value.slice(0, 24));
        }
      }
      const cls = String(el.className || '').slice(0, 48);
      if (!marks.length && !/card|sortable|upload|image|photo|error|fail/i.test(cls)) continue;
      out.push(el.tagName.toLowerCase() + (cls ? '.' + cls : '') +
        (marks.length ? '[' + marks.join(' ') + ']' : ''));
    }
    return out;
  };
  /* 플랫폼이 「다 됐다」고 말해 주기를 기다리는 시간. 이만큼 같은 카드가 제 id 를 달고
   * 버티면 붙은 것으로 본다 — 자세한 이유는 [status] 의 규칙 ②에 적었다. */
  const PATIENCE = 4000;
  const bridge = window.__flrPhotos = {
    chunks: [], before: [], beforeCount: 0, size: 0, metadata: null,
    // 한 번에 건네는 플랫폼(직방)에서 **아직 건네지 않고 쥐고 있는** 파일들과 이번
    // 차례에 들어갈 장수. 한 장씩 건네는 플랫폼에서는 늘 한 장이다.
    queue: [], expected: 1,
    // 이 전송에서 **우리가 붙였다고 인정한** 카드들. 플랫폼이 끝내 aria-disabled 를
    // 풀지 않아도 다음 사진을 막지 않기 위해 기억한다.
    okIds: [],
    // 전송이 도는 동안만 미래를 가리킨다. 폼 어댑터가 이것을 보고 **폼을 건드리지
    // 않는다** — 다시 그려지는 순간 올라가던 사진 카드가 함께 지워지기 때문이다.
    until: 0,
    touch() { this.until = Date.now() + 60000; },
    /* 파일 입력에 닿을 수 있게 한다 — 직방은 여기서 「이미지 넣기」 창을 연다.
     *
     * 창은 곧바로 뜨지 않으므로 부르는 쪽이 준비될 때까지 되묻는다. 여러 번 불러도
     * 같은 창이 열려 있으면 아무 일도 하지 않는다. */
    open() {
      this.touch();
      if (validInput(input())) return {ready: true};
      let why = null;
      try { openPicker(); } catch (error) { why = String((error && error.message) || error); }
      return {ready: validInput(input()), why};
    },
    begin(metadata, remaining) {
      this.touch();
      const existing = cards();
      if (existing.length + remaining > CAPACITY) throw new Error(LABEL + '에 이미 있는 사진과 선택한 사진의 합계가 ' + CAPACITY + '장을 넘습니다.');
      // 한 번에 건네는 플랫폼에서는 **첫 장에서만** 자리를 잰다. 두 번째 장부터는
      // 이미 우리가 쥐고 있는 차례라, 다시 재면 제 손을 남의 손으로 착각한다.
      if (!this.queue.length) {
        if (busy() || existing.some(c => !settled(c) && !this.okIds.includes(cardId(c)))) throw new Error(LABEL + '에서 다른 사진을 처리 중입니다. 완료 후 다시 시도해 주세요.');
        this.before = existing.map(cardId);
        this.beforeCount = existing.length;
        this.expected = MODAL ? remaining : 1;
        this.holdId = null; this.heldSince = 0;
      }
      this.chunks = []; this.size = 0; this.metadata = metadata;
      return {count: existing.length};
    },
    append(encoded) {
      this.touch();
      const raw = atob(encoded);
      const bytes = new Uint8Array(raw.length);
      for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
      this.size += bytes.length;
      if (!this.metadata || this.size > this.metadata.size || this.size > 30 * 1024 * 1024) throw new Error('사진 전송 크기가 일치하지 않습니다.');
      this.chunks.push(bytes);
      return {bytes: this.size};
    },
    commit() {
      this.touch();
      const el = input();
      if (!el || !this.metadata || this.size !== this.metadata.size) throw new Error('사진 전송이 끊겼습니다.');
      const file = new File(this.chunks, this.metadata.name, {type: this.metadata.type, lastModified: this.metadata.lastModified});
      this.chunks = [];
      this.queue.push(file);
      // 아직 다 모이지 않았으면 쥐고만 있는다. 직방은 5장 미만을 받지 않는다.
      if (this.queue.length < this.expected) return {staged: this.queue.length, pending: this.expected - this.queue.length};
      const staged = this.queue;
      this.queue = [];
      const transfer = new DataTransfer();
      for (const one of staged) transfer.items.add(one);
      el.files = transfer.files;
      if (el.files.length !== staged.length || el.files[0].size !== staged[0].size) throw new Error('WebView가 사진 선택란에 파일을 전달하지 못했습니다.');

      /* 여기까지는 실기기에서도 통과했는데 그 뒤로 **아무 일도 일어나지 않았다**
       * (2026-09-20: 108초를 기다려 카드 0장, 플랫폼 메시지도 페이지 오류도 없음).
       * 크롬에서 같은 방식으로 넣으면 1초 만에 카드가 생기므로, 침묵의 이유를 폼 밖에서는
       * 알 수 없다. WebView 의 콘솔을 볼 방법이 없으니 **증거를 여기서 직접 모은다.** */

      // ① 크기만 맞는 File 은 껍데기일 수 있다. 플랫폼이 못 읽으면 조용히 실패한다.
      //    FileReader 로 실제로 읽어 본다 — 결과는 status() 가 실어 나른다.
      this.readBack = {state: '확인 중'};
      try {
        const first = el.files[0];
        const reader = new FileReader();
        reader.onload = () => {
          const got = reader.result ? new Uint8Array(reader.result).length : 0;
          this.readBack = got === first.size
            ? {state: '읽힘', bytes: got}
            : {state: '길이 다름', bytes: got, expected: first.size};
        };
        reader.onerror = () => { this.readBack = {state: '읽기 실패',
          why: String((reader.error && reader.error.message) || reader.error || '')}; };
        reader.readAsArrayBuffer(el.files[0]);
      } catch (e) {
        this.readBack = {state: '읽기 시도 실패', why: String((e && e.message) || e)};
      }

      // ② 사진 영역이 조금이라도 움직였는가. 한 번도 안 움직였다면 페이지는 우리가 넣은
      //    것을 **보지도 못한** 것이다.
      this.mutations = 0;
      this.peak = 0;
      this.peakAt = 0;
      this.peakBones = null;
      // ③ 우리가 사진을 넣은 그 사진 자리가 **아직 그 사진 자리인가.** 폼이 통째로 다시
      //    그려지면 노드가 바뀌고, 그때 올라가던 카드도 함께 사라진다. 관찰자도 옛 노드에
      //    붙은 채 남으므로 mutations 는 그 자리에서 멈춘다 — 그것만으로는 「페이지가
      //    조용하다」와 구분되지 않아 실기기에서 47초를 헛기다렸다(2026-09-20).
      this.spotNode = region();
      try {
        const spot = this.spotNode;
        if (spot) {
          if (this.watcher) this.watcher.disconnect();
          this.watcher = new MutationObserver(list => {
            this.mutations += list.length;
            // 끝난 뒤의 잔해만 보면 놓친다 — 카드가 잠깐 떴다 사라지는 것이 곧 단서다.
            const now = cards().length;
            if (now > this.peak) { this.peak = now; this.peakAt = Date.now(); this.peakBones = bones(); }
          });
          this.watcher.observe(spot, {subtree: true, childList: true, attributes: true});
        }
      } catch (_) { /* 관찰은 있으면 좋은 것일 뿐, 없다고 전송을 막지 않는다 */ }

      el.dispatchEvent(new Event('input', {bubbles: true}));
      el.dispatchEvent(new Event('change', {bubbles: true}));
      return {dispatched: true, files: staged.length};
    },
    /* 건넨 사진을 **폼으로** 들여보낸다 — 직방은 창의 [확인] 이 그 문이다.
     *
     * [확인] 은 직방이 사진을 다 받고 나서야 풀리므로, 잠겨 있는 동안은 아직이라고
     * 답한다. 창이 사라지면 끝난 것이다. 창을 쓰지 않는 플랫폼은 곧바로 끝이다. */
    seal() {
      this.touch();
      let sealed = false, why = null;
      try { sealed = sealPicker() === true; } catch (error) { why = String((error && error.message) || error); }
      return {sealed, why, count: cards().length, spoken: spoken(),
        errors: (window.__flrPhotoErrors || []).slice(0, 8)};
    },
    status() {
      this.touch();
      const current = cards();
      const fresh = current.filter(c => cardId(c) && !this.before.includes(cardId(c)));
      // 한 번에 건넨 플랫폼에서는 카드도 한꺼번에 앉는다.
      const want = this.expected || 1;
      const grown = !busy() && current.length === this.beforeCount + want && fresh.length === want;
      const id = grown ? cardId(fresh[fresh.length - 1]) : null;
      if (id !== this.holdId) { this.holdId = id; this.heldSince = id ? Date.now() : 0; }
      const stableFor = this.heldSince ? Date.now() - this.heldSince : 0;
      // 이 전송에서 이미 인정한 카드는 플랫폼이 잠가 둔 채로도 「끝난 것」으로 센다.
      const accepted = card => settled(card) || this.okIds.includes(cardId(card));
      // 규칙 ① — 플랫폼이 스스로 처리 완료를 말한다(aria-disabled 가 풀린다). 미러가 그랬다.
      const strict = grown && fresh.every(settled) && current.every(accepted);
      /* 규칙 ② — 실물 다방은 **서버 id 까지 받은 카드를** aria-disabled=true 로 둔 채
       * 두기도 한다(2026-09-20 실기기: data-id 가 붙은 카드가 aria-disabled=true).
       * 규칙 ①만 믿으면 이미 올라간 사진을 실패라고 말하게 되므로, 새 카드가 제 id 를
       * 그대로 달고 [PATIENCE] 만큼 버티면 붙은 것으로 본다. 우리가 만든 성공이 아니라
       * **플랫폼이 만들어 놓고 치우지 않은 카드**를 인정하는 것이다. */
      const patient = !strict && grown && stableFor >= PATIENCE;
      const ready = strict || patient;
      if (ready) for (const card of fresh) {
        const mark = cardId(card);
        if (mark && !this.okIds.includes(mark)) this.okIds.push(mark);
      }
      /* 폼이 다시 그려졌는가 / 카드가 떴다가 지워졌는가.
       *
       * 「지워졌다」로 접으려면 **카드가 정말 없어야** 한다. 다시 그려지면서 카드를
       * 그대로 안고 가는 경우까지 지워진 것으로 보면, 이미 올라간 사진을 한 번 더
       * 올려 남의 광고에 같은 사진이 두 장 붙는다. */
      const remade = !!this.spotNode && this.spotNode !== region();
      const gone = this.peak > this.beforeCount && current.length <= this.beforeCount &&
        Date.now() - (this.peakAt || 0) > 1200;
      const wiped = !ready && current.length <= this.beforeCount && (gone || remade);
      const el = input();
      return {ready, patient: patient || undefined, stableFor, want,
        count: current.length, id: ready ? id : null, remade, gone, wiped,
        errors: (window.__flrPhotoErrors || []).slice(0, 8), spoken: spoken(),
        readBack: this.readBack || null,
        mutations: this.mutations === undefined ? null : this.mutations,
        peak: this.peak === undefined ? null : this.peak,
        bones: this.peakBones || bones(),
        // React 업로더는 대개 다 읽고 나서 value 를 비운다. 그대로면 안 가져간 것이다.
        held: el ? (el.files ? el.files.length : null) : null};
    },
    clear() { this.chunks = []; this.queue = []; this.metadata = null; this.until = 0; return {cleared: true}; }
  };
  return JSON.stringify({ready: true, count: cards().length});
  } catch (e) {
    return JSON.stringify({error: String(e && (e.message || e))});
  }
})()
''';

String listingPhotoCommand(
  String method, [
  List<Object?> arguments = const [],
]) =>
    '''(() => { try {
      if (!window.__flrPhotos) throw new Error('사진 전송 중 페이지가 변경되었습니다.');
      return JSON.stringify(window.__flrPhotos.$method(...${jsonEncode(arguments)}));
    } catch (e) { return JSON.stringify({error: String(e.message || e)}); } })()''';

typedef PhotoJavaScriptRunner = Future<Object> Function(String script);

/// 플랫폼에 건네줄 사진 파일 이름.
///
/// image_picker 가 주는 이름은 `image_picker_C9F880C5-36DB-407B-B7C2-E96AE1FFEF20
/// -43530-00000CF60C116AE4.jpg` 같은 60자짜리 임시 이름이다. 남의 광고에 올라갈
/// 이름으로 마땅치 않고, 실물 업로드가 실기기에서만 조용히 실패하는 동안 **한 번도
/// 확인해 보지 않은 변수**이기도 하다(크롬에서 성공시킨 파일은 `hanbang-probe.jpg`,
/// 미러는 `probe.png` 였다). 짧고 단순한 이름으로 보낸다.
String uploadFileName(int number, String mime) {
  final extension = switch (mime) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/gif' => 'gif',
    'image/bmp' => 'bmp',
    'image/webp' => 'webp',
    'image/heic' => 'heic',
    'image/avif' => 'avif',
    _ => 'jpg',
  };
  return 'photo-$number.$extension';
}

/// 카드가 안 생겼을 때 **어디까지 갔는지**를 한 문장으로 옮긴다.
///
/// 실기기에서 첨부가 108초 동안 아무 말 없이 실패했다(2026-09-20). 폼 밖에서는
/// 「0장」밖에 보이지 않아, 파일이 잘못된 것인지 페이지가 못 본 것인지 가릴 수 없었다.
/// WebView 의 콘솔을 볼 방법이 없으므로 브리지가 모아 온 증거를 사람이 읽을 말로 바꾼다.
String describePhotoSilence(Map<String, dynamic> state) {
  final readBack = state['readBack'];
  final mutations = state['mutations'];
  final held = state['held'];

  final read = readBack is Map ? readBack['state'] : null;
  final why = readBack is Map ? readBack['why'] : null;
  final parts = <String>[];

  if (read == null) {
    parts.add('파일 확인 결과 없음');
  } else if (read == '읽힘') {
    parts.add('넣은 파일은 정상으로 읽힙니다');
  } else {
    // 여기가 켜지면 원인은 파일이다 — 크기만 맞는 껍데기를 넘긴 것이다.
    parts.add('넣은 파일을 되읽지 못했습니다($read${why == null || why == '' ? '' : ': $why'})');
  }
  if (mutations is num) {
    parts.add(mutations == 0
        // 페이지가 우리가 넣은 것을 보지도 못했다는 뜻이다.
        ? '사진 영역이 한 번도 움직이지 않았습니다'
        : '사진 영역이 $mutations번 움직였습니다');
  }
  if (held is num && held > 0) {
    parts.add('선택란은 아직 파일 $held개를 쥐고 있습니다');
  }
  final peak = state['peak'];
  if (peak is num && peak > 0 && (state['count'] as num? ?? 0) == 0) {
    // 떴다가 사라졌다 = 카드가 생기기는 했는데 누군가 치웠다는 뜻이다.
    parts.add('카드가 한때 $peak장까지 보였다가 사라졌습니다');
  }
  if (state['remade'] == true) {
    // 여기가 켜지면 원인은 업로드가 아니라 **폼**이다. 다방은 주소를 고를 때 폼을 처음
    // 상태로 되돌리고, 그때 올라가던 사진 카드도 함께 지운다(2026-09-20 실측).
    parts.add('사진 자리가 통째로 다시 그려졌습니다');
  }
  final bones = state['bones'];
  if (bones is List && bones.isNotEmpty) {
    // 카드가 어떤 모습으로 멈춰 있는지. 셀렉터를 고쳐야 하는지 여기서 드러난다.
    parts.add('사진 자리: ${bones.take(12).join(' | ')}');
  }
  return '${parts.join(', ')}.';
}

/// 카드가 앉기를 기다릴 시간. 사진 크기를 따라 늘어난다.
///
/// 미러는 파일을 받는 즉시 카드를 만들어 크기가 상관없었지만, **실물은 사진을 제
/// 저장소로 진짜 올린 뒤에** 카드를 만든다. 고정 45초는 휴대폰에서 찍은 몇 MB짜리
/// 사진에는 모자랄 수 있고, 모자라면 「현재 0장입니다」로 끝나 실패와 구분되지 않는다.
///
/// 그래도 한없이 기다리지는 않는다 — 사진마다 이만큼씩 붙들면 등록 흐름 전체가 멈춘다.
Duration settleBudget(
  Duration base,
  int bytes, {
  Duration cap = const Duration(seconds: 120),
  Duration perMegabyte = const Duration(seconds: 20),
}) {
  final megabytes = bytes / (1024 * 1024);
  final grown = base + perMegabyte * megabytes;
  return grown > cap ? cap : grown;
}

/// Each bridge call is bounded and awaited. The browser's staging buffer holds
/// only the current file (at most 96 KiB per call from the native stream).
/// The mirror retains already uploaded files for its photo cards separately.
///
/// Photos whose format [target] does not take are skipped rather than failing
/// the batch. The returned list holds one reason per skipped photo.
Future<List<String>> transferListingPhotos({
  required PhotoTarget target,
  required List<XFile> photos,
  required PhotoJavaScriptRunner evaluate,
  required void Function(int completed, int total) onProgress,
  bool Function()? isCancelled,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final label = target.label;
  if (photos.isEmpty || photos.length > target.maximum) {
    throw FormatException(
      '$label에 첨부할 실제 사진 ${target.minimum}~${target.maximum}장을 선택해 주세요.',
    );
  }
  Future<Map<String, dynamic>> run(String operation, String script) async {
    if (isCancelled?.call() == true) throw StateError('사진 전송이 취소되었습니다.');
    Object? result;
    try {
      result = await evaluate(script);
    } catch (error) {
      throw StateError('$label WebView $operation JavaScript 실행 실패: $error');
    }
    // Android and WKWebView differ in whether returned strings are JSON quoted.
    Map<String, dynamic> data;
    try {
      for (var i = 0; i < 2 && result is String; i++) {
        result = jsonDecode(result);
      }
      data = Map<String, dynamic>.from(result as Map);
    } catch (error) {
      throw StateError('$label WebView $operation 응답 해석 실패: $error');
    }
    if (data['error'] != null) {
      throw StateError('$label WebView $operation 오류: ${data['error']}');
    }
    return data;
  }

  // Sort out what the target takes before touching the WebView, so the
  // bridge's capacity check counts only the photos that will really arrive.
  final accepted = <({int number, XFile photo, String mime, int bytes})>[];
  final skipped = <String>[];
  for (var index = 0; index < photos.length; index++) {
    final photo = photos[index];
    final String mime;
    try {
      mime = await validateListingPhoto(photo);
    } catch (error) {
      throw StateError('${index + 1}번 사진 (${photo.name}) 전송 실패: $error');
    }
    final bytes = await photo.length();
    if (!target.acceptedTypes.contains(mime)) {
      final kinds = target.acceptedTypes
          .map((type) => type.split('/').last.toUpperCase())
          .join('·');
      skipped.add(
        '${index + 1}번 사진 (${photo.name}): $label 폼은 $kinds 사진만 받아 '
        '${mime.split('/').last.toUpperCase()} 사진은 첨부하지 않았습니다. 화면에서 직접 올려 주세요.',
      );
    } else if (bytes > target.maxBytes) {
      // 플랫폼이 스스로 정해 둔 한계다. 그냥 건네면 그쪽 업로더가 조용히 떨어뜨린다.
      skipped.add(
        '${index + 1}번 사진 (${photo.name}): $label 폼은 사진 한 장이 '
        '${(target.maxBytes / (1024 * 1024)).round()}MB까지라 '
        '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB인 이 사진은 첨부하지 않았습니다. '
        '화면에서 직접 올려 주세요.',
      );
    } else {
      accepted.add((number: index + 1, photo: photo, mime: mime, bytes: bytes));
    }
  }
  /* 플랫폼이 정한 최소 장수를 못 채우면 **건네지 않는다.**
   *
   * 직방은 5장 미만이면 창의 [확인] 이 잠긴 채라 어차피 폼으로 들어가지 못한다.
   * 절반만 올려 두고 실패했다고 말하는 것보다, 손대지 않고 왜 못 했는지 말하는 편이
   * 낫다 — 사람이 화면에서 이어서 올릴 수 있다. */
  if (accepted.length < target.minimum) {
    if (accepted.isNotEmpty) {
      skipped.add(
        '$label 폼은 사진 ${target.minimum}장 이상을 요구하는데 보낼 수 있는 사진이 '
        '${accepted.length}장뿐이라 첨부하지 않았습니다. 화면에서 직접 올려 주세요.',
      );
    }
    return skipped;
  }

  final bridgeStart = Stopwatch()..start();
  while (true) {
    try {
      await run('사진 첨부 초기화', listingPhotoBridgeScript(target));
      break;
    } catch (error) {
      if (bridgeStart.elapsed >= const Duration(seconds: 20)) {
        throw StateError('$label 사진 선택란이 준비되지 않았습니다: $error');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// 파일 입력에 닿을 수 있게 한다. 직방은 여기서 「이미지 넣기」 창이 열린다.
  Future<void> openPicker() async {
    if (!target.modal) return;
    final watch = Stopwatch()..start();
    while (true) {
      final state = await run('사진 선택 창 열기', listingPhotoCommand('open'));
      if (state['ready'] == true) return;
      if (watch.elapsed >= const Duration(seconds: 20)) {
        final why = state['why'];
        throw StateError(
          '$label 사진 선택 창을 열지 못했습니다'
          '${why == null ? '' : ' ($why)'}. 화면에서 직접 올려 주셔야 합니다.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// 사진 한 장을 브리지로 흘려보낸다. 한 번에 건네는 플랫폼에서는 마지막 장에서만
  /// 실제로 폼에 전달된다 — 그 판단은 브리지의 `commit` 이 한다.
  Future<void> send(
    int number,
    XFile photo,
    String mime,
    int bytes,
    int remaining,
  ) async {
    await run(
      '$number번 사진 전송 시작',
      listingPhotoCommand('begin', [
        {
          'name': uploadFileName(number, mime),
          'type': mime,
          'size': bytes,
          'lastModified': (await photo.lastModified()).millisecondsSinceEpoch,
        },
        remaining,
      ]),
    );
    await for (final chunk in photo.openRead()) {
      const chunkSize = 96 * 1024;
      for (var offset = 0; offset < chunk.length; offset += chunkSize) {
        final end = offset + chunkSize < chunk.length
            ? offset + chunkSize
            : chunk.length;
        await run(
          '$number번 사진 데이터 추가',
          listingPhotoCommand('append', [
            base64Encode(chunk.sublist(offset, end)),
          ]),
        );
      }
    }
    await run('$number번 사진 선택 이벤트 전달', listingPhotoCommand('commit'));
  }

  /// 건넨 사진을 폼으로 들여보낸다 — 직방은 창의 [확인] 을 누르는 일이다. 창이 끝내
  /// [확인] 을 열어 주지 않으면 그 자리에서 본 것을 그대로 적고 멈춘다.
  Future<void> seal(Duration budget) async {
    if (!target.modal) return;
    final watch = Stopwatch()..start();
    while (true) {
      final state = await run('사진 확인 버튼 누르기', listingPhotoCommand('seal'));
      if (state['sealed'] == true) return;
      if (watch.elapsed >= budget) {
        final spoken = state['spoken'];
        final errors = (state['errors'] as List?) ?? const [];
        throw StateError(
          '$label 사진 창이 ${watch.elapsed.inSeconds}초 동안 확인 버튼을 열어 주지 않았습니다.'
          '${spoken == null ? '' : ' 플랫폼 화면: 「$spoken」'}'
          '${errors.isEmpty ? '' : ' 페이지 오류: ${errors.join(' / ')}'}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// 카드가 앉기를 기다린다. 앉았으면 `null`, 못 앉았으면 마지막으로 본 상태를
  /// 돌려준다 — 그 상태가 다시 붙여 볼지 말지를 가른다.
  Future<Map<String, dynamic>?> settle(Duration budget) async {
    final watch = Stopwatch()..start();
    while (true) {
      final state = await run('사진 카드 완료 상태 확인', listingPhotoCommand('status'));
      if (state['ready'] == true) return null;
      // 몇 초를 기다린 끝인지는 사람에게 그대로 말해 준다. 아래에서 예산을 적어 버리면
      // 3초 만에 접은 것을 47초 기다렸다고 말하게 된다.
      state['waited'] = watch.elapsed.inSeconds;
      // 폼이 사진을 쓸어 갔다면 기다림은 낭비다. 남은 예산을 흘려보내지 않고 바로
      // 돌아가 다시 붙인다.
      if (state['wiped'] == true) return state;
      if (watch.elapsed >= budget) return state;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Never giveUp(Map<String, dynamic> state, int bytes, Duration budget) {
    // 무엇을 봤는지 그대로 적는다. 「0장입니다」만으로는 업로드가 실패한 것인지
    // 아직 올라가는 중인지 알 수 없어, 실물에서 몇 번을 더 재 봐야 했다.
    final spoken = state['spoken'];
    final errors = (state['errors'] as List?) ?? const [];
    throw StateError(
      '$label 사진 카드의 처리 완료를 확인하지 못했습니다. '
      '${state['waited'] ?? budget.inSeconds}초를 '
      '기다렸고 현재 ${state['count']}장입니다 '
      '(${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB). '
      '${describePhotoSilence(state)}'
      '${spoken == null ? '' : ' 플랫폼 화면: 「$spoken」'}'
      '${errors.isEmpty ? '' : ' 페이지 오류: ${errors.join(' / ')}'}',
    );
  }

  onProgress(0, accepted.length);
  try {
    if (target.modal) {
      /* 직방 — 고른 것을 **한 번에** 건넨다.
       *
       * 창을 열고, 사진을 다 흘려보내고, [확인] 으로 폼에 들여보낸 다음, 폼의 카드
       * 목록이 그만큼 자랐는지 본다. 한 장만 다시 붙일 수는 없는 길이라 중간에 쓸려
       * 가면 처음부터 다시 한다. */
      final total = accepted.fold<int>(0, (sum, one) => sum + one.bytes);
      final budget = settleBudget(
        timeout,
        total,
        cap: const Duration(minutes: 4),
      );
      for (var attempt = 1; ; attempt++) {
        await openPicker();
        for (var index = 0; index < accepted.length; index++) {
          final (:number, :photo, :mime, :bytes) = accepted[index];
          try {
            await send(number, photo, mime, bytes, accepted.length - index);
          } catch (error) {
            throw StateError('$number번 사진 (${photo.name}) 전송 실패: $error');
          }
          // 마지막 장은 아직 「보냈다」고 말하지 않는다 — 한 번에 건네는 길에서는
          // [확인] 을 누르고 카드가 앉기 전까지 아무것도 붙지 않은 것과 같다.
          if (index + 1 < accepted.length) onProgress(index + 1, accepted.length);
        }
        await seal(budget);
        final state = await settle(budget);
        if (state == null) {
          onProgress(accepted.length, accepted.length);
          break;
        }
        if (state['wiped'] == true && attempt == 1) {
          await Future<void>.delayed(const Duration(seconds: 2));
          onProgress(0, accepted.length);
          continue;
        }
        giveUp(state, total, budget);
      }
    } else {
      for (var index = 0; index < accepted.length; index++) {
        final (:number, :photo, :mime, :bytes) = accepted[index];
        try {
          /* 폼이 사진을 지웠으면 한 번 더 붙인다.
           *
           * 다방은 주소를 고르는 순간 폼을 처음 상태로 되돌린다(2026-09-20 실측). 사진을
           * 폼 입력 **뒤에** 붙이도록 순서를 바꿔 그 되돌림을 피했지만, 되돌리는 것이
           * 주소뿐이라는 보장은 없다. 카드가 떴다가 사라진 것은 업로드 실패와 다르므로
           * 실패로 접지 않고 그 자리에서 다시 붙인다. */
          for (var attempt = 1; ; attempt++) {
            await send(number, photo, mime, bytes, accepted.length - index);
            final budget = settleBudget(timeout, bytes);
            final state = await settle(budget);
            if (state == null) break;
            if (state['wiped'] == true && attempt == 1) {
              await Future<void>.delayed(const Duration(seconds: 2));
              continue;
            }
            giveUp(state, bytes, budget);
          }
          onProgress(index + 1, accepted.length);
        } catch (error) {
          throw StateError('$number번 사진 (${photo.name}) 전송 실패: $error');
        }
      }
    }
  } finally {
    // Preserve uploaded cards on a partial failure, but release staging bytes.
    try {
      await run('사진 전송 임시 데이터 정리', listingPhotoCommand('clear'));
    } catch (_) {}
  }
  return skipped;
}
