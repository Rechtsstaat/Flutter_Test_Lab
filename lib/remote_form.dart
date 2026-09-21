/// The JavaScript 한방 runs inside each platform page: the Kakao postcode
/// bridge, the per-platform adapters, and the frame script that picks a Kakao
/// result. `MirrorSession` decides when each one runs.
///
/// The adapters were written against the mirror, which was captured from the
/// live pages, so they find fields by what the live page itself carries —
/// `name` attributes, section ids, row headings, ARIA roles. Nothing here may
/// depend on the `data-mirror*` / `data-flr*` markup the mirror adds on top.
library;

import 'dart:convert';

import 'fields.dart';

/// Answers `true` once the platform's listing form has rendered its own
/// fields. The live forms draw themselves after the page load finishes (직방 is
/// Next.js, 다방프로 a single-page app), so the adapter waits for this first.
/// 어댑터가 **이제 사진을 붙여도 된다**고 세우는 표식. 세 어댑터가 모두 시작할 때
/// 내리고 끝날 때(오류로 빠져나온 길에서도) 세운다.
///
/// 다방·당근은 제 차례를 다 마친 뒤에 세운다. 직방은 주소 검색 **직전에** 세우고
/// [photosDoneFlag] 를 기다린다 — 사진 창이 떠 있는 동안은 주소를 고를 수 없어서다.
const formDoneFlag = 'window.__flrFormDone';

/// 사진 첨부가 끝났다고 네이티브가 세워 주는 표식. 직방 어댑터만 이것을 기다린다.
const photosDoneFlag = 'window.__flrPhotosDone';

/// 표식이 설 때까지 기다린다. 섰으면 `true`, 시간이 다했거나 [isCancelled] 가
/// 끊었으면 `false`.
///
/// **왜 필요한가** — [WebViewController.runJavaScript] 는 async 어댑터의 *첫
/// await 에서* 돌아온다. 그래서 이것이 없으면 사진 첨부가 폼 입력과 나란히 돈다.
/// 다방은 주소를 고르는 순간 폼을 처음 상태로 되돌리므로(2026-09-20 실측), 그
/// 되돌림이 방금 올라간 사진 카드를 함께 쓸어 간다. 값은 어댑터의 `reconcile` 이
/// 다시 넣지만 **사진은 아무도 다시 붙여 주지 않는다.**
///
/// 끝내 말이 없어도 [false] 로 돌아가 사진을 붙여 본다 — 못 붙이는 것보다 낫고,
/// 그래도 지워지면 `transferListingPhotos` 가 한 번 더 붙인다.
Future<bool> awaitFormAdapter({
  required Future<Object> Function(String script) evaluate,
  required Duration timeout,
  bool Function()? isCancelled,
  Duration poll = const Duration(milliseconds: 300),
}) async {
  final watch = Stopwatch()..start();
  while (isCancelled?.call() != true) {
    try {
      final done = await evaluate('$formDoneFlag === true');
      if (done == true || done.toString() == 'true') return true;
    } catch (_) {
      // 페이지가 넘어가는 중이면 아무 답이 없다. 다시 묻는다.
    }
    if (watch.elapsed >= timeout) return false;
    await Future<void>.delayed(poll);
  }
  return false;
}

String formReadyScript(ListingPlatform platform) {
  final selector = switch (platform) {
    ListingPlatform.zigbang => '[name="sizeM2"], [name="title"]',
    ListingPlatform.dabang => '#room_info th, #trade_info th',
    ListingPlatform.daangn => '#image-upload',
  };
  return '!!document.querySelector(${jsonEncode(selector)})';
}

String postcodeBridgeScript(String query) =>
    '''
(() => {
  const query = $query;
  // WKWebView 에는 팝업 창이 없다. 카카오 우편번호의 open() 은 window.open() 을 쓰는데,
  // webview_flutter 는 그 요청을 같은 웹뷰에 실어 버려서 미러 폼이 빈 화면으로 덮인다.
  // 그래서 daum.Postcode 를 감싸 두고, open() 이 오면 같은 인스턴스를 embed() 로
  // 이 페이지 안의 전체 화면 겹에 그린다. 미러가 넘긴 oncomplete 는 그대로 살아 있으므로
  // 주소를 고르면 미러의 원래 흐름(동/호 활성화 · 건축물대장 창 · lat 채움)이 그대로 돈다.
  if (window.__flrPostcode) { window.__flrPostcode.query = query || window.__flrPostcode.query; return; }
  const SRC = 'https://t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js';
  const bridge = window.__flrPostcode = {query: query || '', notes: [], open: false};
  window.daum = window.daum || {};
  let Real = Object.prototype.hasOwnProperty.call(window.daum, 'Postcode') ? window.daum.Postcode : null;
  let loading = null;

  const ensureReal = () => {
    if (Real) return Promise.resolve(Real);
    if (loading) return loading;
    loading = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = SRC;
      script.onload = () => Real ? resolve(Real) : reject(new Error('카카오 우편번호 스크립트가 Postcode 를 등록하지 않았습니다.'));
      script.onerror = () => reject(new Error('카카오 우편번호 스크립트를 내려받지 못했습니다.'));
      setTimeout(() => { if (!Real) reject(new Error('카카오 우편번호 스크립트 응답이 없습니다.')); }, 10000);
      document.head.appendChild(script);
    });
    return loading;
  };

  const closeOverlay = fromHistory => {
    const overlay = document.getElementById('flr-postcode-overlay');
    if (!overlay) return false;
    overlay.remove();
    document.documentElement.style.overflow = overlay.dataset.prevOverflow || '';
    bridge.open = false;
    if (!fromHistory && history.state && history.state.flrPostcode) history.back();
    return true;
  };
  bridge.close = () => closeOverlay(false);
  // Flutter 의 뒤로가기(PopScope)가 먼저 이 겹을 닫는다.
  window.__flrClosePostcode = () => closeOverlay(false);
  window.addEventListener('popstate', () => closeOverlay(true));

  const buildOverlay = () => {
    closeOverlay(true);
    const overlay = document.createElement('div');
    overlay.id = 'flr-postcode-overlay';
    overlay.dataset.prevOverflow = document.documentElement.style.overflow || '';
    overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#fff;display:flex;flex-direction:column;';
    const bar = document.createElement('div');
    bar.style.cssText = 'flex:none;display:flex;align-items:center;justify-content:space-between;' +
      'padding:calc(env(safe-area-inset-top) + 10px) 14px 10px;border-bottom:1px solid #e5e5e5;' +
      'background:#fff;font:600 16px/1.4 -apple-system,BlinkMacSystemFont,sans-serif;color:#222;';
    const title = document.createElement('span');
    title.textContent = '주소 검색';
    const close = document.createElement('button');
    close.type = 'button';
    close.textContent = '닫기';
    close.setAttribute('aria-label', '주소 검색 닫기');
    close.style.cssText = 'border:0;background:transparent;color:#326cf9;font:600 16px -apple-system,sans-serif;padding:8px 4px;';
    close.addEventListener('click', () => closeOverlay(false));
    const host = document.createElement('div');
    host.style.cssText = 'flex:1;min-height:0;width:100%;background:#fff;';
    bar.append(title, close);
    overlay.append(bar, host);
    document.body.appendChild(overlay);
    document.documentElement.style.overflow = 'hidden';
    history.pushState({flrPostcode: true}, '', location.href);
    bridge.open = true;
    return host;
  };

  const showFailure = (host, error) => {
    const reason = error && error.message ? error.message : String(error);
    host.innerHTML = '';
    const note = document.createElement('p');
    note.style.cssText = 'padding:24px;font:14px/1.7 -apple-system,sans-serif;color:#444;';
    note.textContent = '카카오 주소 검색 화면을 열지 못했습니다. ' + reason + ' 네트워크 상태를 확인한 뒤 「검색」을 다시 눌러 주세요.';
    host.appendChild(note);
    bridge.notes.push('주소 검색: ' + reason);
  };

  function Postcode(options) {
    const source = options || {};
    // 미러가 넘긴 oncomplete/onclose 는 그대로 부르고, 그 앞뒤로 겹만 정리한다.
    const wrapped = Object.assign({}, source, {
      width: '100%',
      height: '100%',
      oncomplete: value => {
        closeOverlay(false);
        if (typeof source.oncomplete === 'function') source.oncomplete(value);
      },
      onclose: state => {
        closeOverlay(true);
        if (typeof source.onclose === 'function') source.onclose(state);
      },
    });
    const self = this instanceof Postcode ? this : Object.create(Postcode.prototype);
    let inner = Real ? new Real(wrapped) : null;
    const draw = (host, extra) => {
      if (!inner) inner = new Real(wrapped);
      const params = Object.assign({autoClose: false}, extra || {});
      if (!params.q && bridge.query) params.q = bridge.query;
      inner.embed(host, params);
    };
    self.open = extra => {
      const host = buildOverlay();
      ensureReal().then(() => draw(host, extra)).catch(error => showFailure(host, error));
      return self;
    };
    self.embed = (element, extra) => {
      ensureReal().then(() => draw(element, extra))
        .catch(error => bridge.notes.push('주소 검색: ' + (error.message || String(error))));
      return self;
    };
    return self;
  }

  // 직방 미러는 페이지가 뜰 때 카카오 스크립트를 스스로 불러온다. 그 스크립트가 늦게
  // 도착해 daum.Postcode 에 대입해도 setter 가 받아서 원본만 갈아 끼우고, 미러가 보는
  // 값은 계속 이 래퍼다.
  Object.defineProperty(window.daum, 'Postcode', {
    configurable: true,
    enumerable: true,
    get: () => Postcode,
    set: value => { if (value !== Postcode) Real = value; },
  });
  ensureReal().catch(error => bridge.notes.push('주소 검색: ' + (error.message || String(error))));
})();
''';

/// 직방 CEO 등록 폼(원룸·빌라·오피스텔)을 채운다.
///
/// 실물에서 떠 온 것(2026-09-21): 칸 이름·Radix 부품·관리비 세 갈래(정액 관리비의
/// 고지 받음/안 받음 · 기타 · 확인 불가)·입주 가능일 달력·의뢰인 전화번호 [확인].
/// 「광고등록 규정 동의」와 「매물 등록 완료」는 누르지 않는다.
String zigbangInjectionScript(String payload) =>
    '(async () => {\n  const data = $payload;\n$_zigbangAdapterBody';

const _zigbangAdapterBody = r'''
  window.__flrFormDone = false;
  window.__flrPhotosDone = false;
  /* 어댑터가 누르는 동안 페이지가 되묻는 확인 창은 한방이 「확인」으로 답한다
   * ([MirrorPage.autoAnswering]). 끝날 때 끈다 — 그 뒤의 확인 창은 사람의 것이다. */
  const auto = on => { try { if (window.FlrAutoAnswer) window.FlrAutoAnswer.postMessage(on ? 'on' : 'off'); } catch (_) {} };
  auto(true);
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const output = {applied: 0, missing: [], unsupported: [], verified: 0, violations: []};
  const publish = () => { try { window.ListingResult.postMessage(JSON.stringify(output)); } catch (_) {} };
  const note = message => { if (!output.unsupported.includes(message)) output.unsupported.push(message); };
  const miss = (key, why) => { const line = key + ': ' + why; if (!output.missing.includes(line)) output.missing.push(line); };
  const ok = () => { output.applied++; output.verified++; };
  const mark = (key, done, why) => {
    if (done) ok();
    else miss(key, why || '폼에서 대상 입력란을 찾거나 선택하지 못했습니다.');
    return done;
  };
  const text = el => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
  const norm = value => String(value === undefined || value === null ? '' : value).replace(/\s+/g, '');
  const digits = value => String(value === undefined || value === null ? '' : value).replace(/[^0-9]/g, '');
  const filled = value => value !== undefined && value !== null && value !== '' &&
    !(Array.isArray(value) && value.length === 0);
  const waitFor = async (predicate, timeout = 2000) => {
    const until = Date.now() + timeout;
    for (;;) {
      let value = null;
      try { value = predicate(); } catch (_) { value = null; }
      if (value) return value;
      if (Date.now() >= until) return null;
      await sleep(50);
    }
  };
  const esc = s => (window.CSS && CSS.escape) ? CSS.escape(String(s)) : String(s).replace(/[^a-zA-Z0-9_-]/g, '\\$&');
  const byName = name => document.querySelector('[name="' + esc(name) + '"]');
  const byId = id => document.getElementById(id);

  /* ── 조작 ───────────────────────────────────────────────────
   * 직방 CEO 는 Next.js + react-hook-form + Radix 다. 눌림은 사람의 손가락 차례대로
   * 한 번만 보낸다 — `el.click()` 을 덧붙이면 체크박스가 두 번 뒤집혀 제자리로 돌아온다. */
  const press = el => {
    if (!el) return false;
    const init = {bubbles: true, cancelable: true, composed: true, view: window, button: 0};
    try { el.dispatchEvent(new PointerEvent('pointerdown', init)); } catch (_) {}
    el.dispatchEvent(new MouseEvent('mousedown', init));
    try { el.dispatchEvent(new PointerEvent('pointerup', init)); } catch (_) {}
    el.dispatchEvent(new MouseEvent('mouseup', init));
    el.dispatchEvent(new MouseEvent('click', init));
    return true;
  };
  const valueSetter = el => Object.getOwnPropertyDescriptor(
    el.tagName === 'SELECT' ? HTMLSelectElement.prototype :
    el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype, 'value').set;
  const setValue = (el, value) => {
    if (!el) return false;
    try { el.focus(); } catch (_) {}
    valueSetter(el).call(el, String(value));
    ['input', 'change'].forEach(type => el.dispatchEvent(new Event(type, {bubbles: true})));
    try { el.blur(); } catch (_) {}
    el.dispatchEvent(new Event('focusout', {bubbles: true}));
    return true;
  };
  /// 글자 칸. 숫자 칸(금액·면적)은 폼이 「1,000」처럼 다듬어 되돌려 주므로 [same] 으로 견준다.
  const fillIn = async (key, locate, value, same) => {
    if (!filled(value)) return false;
    const el = typeof locate === 'function' ? locate() : byName(locate);
    if (!el) return mark(key, false, '입력란을 찾지 못했습니다.');
    if (el.disabled) return mark(key, false, '입력란이 잠겨 있어 값을 넣지 못했습니다.');
    const wanted = String(value);
    setValue(el, wanted);
    const settled = await waitFor(() => {
      const now = typeof locate === 'function' ? locate() : byName(locate);
      return now && (same ? same(now.value, wanted) : now.value === wanted) ? now : null;
    }, 1500);
    if (settled) return mark(key, true);
    const now = typeof locate === 'function' ? locate() : byName(locate);
    return mark(key, false, '넣은 값은 「' + wanted + '」인데 폼은 「' + String(now ? now.value : '').slice(0, 40) + '」로 읽습니다.');
  };
  const sameDigits = (got, wanted) => !!digits(wanted) && digits(got) === digits(wanted);
  const sameNumber = (got, wanted) => Number(String(got).replace(/,/g, '')) === Number(String(wanted).replace(/,/g, ''));
  const selected = el => !!el && (el.getAttribute('aria-checked') === 'true' ||
    el.getAttribute('aria-pressed') === 'true' || el.getAttribute('data-state') === 'checked' ||
    (el.classList.contains('text-orange-500') && el.classList.contains('border-orange-500')));
  /// 같은 이름을 나눠 쓰는 단추 묶음(라디오처럼 쓰는 button). 글자가 **정확히** 같은
  /// 단추를 누른다 — 「해당」과 「해당없음」처럼 한쪽이 다른 쪽을 품는 이름이 있다.
  const buttonGroup = name => {
    const first = byName(name);
    if (!first) return [];
    let scope = first.parentElement;
    while (scope && scope !== document.body && scope.querySelectorAll('button').length < 2) scope = scope.parentElement;
    return scope ? [...scope.querySelectorAll('button')] : [first];
  };
  const pick = async (key, name, label) => {
    if (!filled(label)) return false;
    const buttons = buttonGroup(name);
    const target = buttons.find(b => norm(text(b)) === norm(label));
    if (!target) return mark(key, false, '「' + label + '」 단추를 찾지 못했습니다.');
    if (!selected(target)) press(target);
    return mark(key, !!await waitFor(() => selected(target) ? target : null, 2000),
      '「' + label + '」을 눌렀지만 선택되지 않았습니다.');
  };
  /// Radix 체크박스(button[role=checkbox]).
  const check = async (key, el, wanted) => {
    if (!el) return mark(key, false, '체크박스를 찾지 못했습니다.');
    const on = () => el.getAttribute('aria-checked') === 'true';
    if (on() !== wanted) press(el);
    return mark(key, !!await waitFor(() => on() === wanted, 2000), '체크 상태가 바뀌지 않았습니다.');
  };
  /* Radix Select 는 보이는 단추 + 숨은 <select> 다. 숨은 것만 바꾸면 폼이 모른다 —
   * 단추를 열고 목록에서 고른 뒤, 숨은 값과 단추 글자를 둘 다 되읽는다. */
  const openList = () => [...document.querySelectorAll('[role="listbox"]')].find(list => list.offsetParent !== null || list.getClientRects().length) || null;
  const chooseIn = async (key, locate, label, match) => {
    if (!filled(label)) return false;
    // 목록이 바뀌면 숨은 <select> 가 새로 그려진다 — 붙잡아 두지 않고 늘 다시 찾는다.
    const at = () => typeof locate === 'function' ? locate() : locate;
    const select = at();
    if (!select) return mark(key, false, '선택란을 찾지 못했습니다.');
    const options = [...select.options];
    const exact = options.find(o => norm(o.textContent) === norm(label));
    const option = exact || (match ? options.find(o => match(o.textContent.trim(), o.value)) : null);
    if (!option) {
      note(key + ' ' + label + ': 직방 선택지에 없습니다 (' + options.map(o => o.textContent.trim()).join(', ').slice(0, 80) + ').');
      return false;
    }
    let trigger = select.previousElementSibling;
    if (!trigger || trigger.getAttribute('role') !== 'combobox') {
      let scope = select.parentElement;
      while (scope && !scope.querySelector('[role="combobox"]')) scope = scope.parentElement;
      trigger = scope ? scope.querySelector('[role="combobox"]') : null;
    }
    // 숨은 <select> 는 아무것도 고르지 않았어도 첫 선택지를 값으로 들고 있다(화장실 수 「1개」).
    // 폼이 정말 받았는지는 보이는 단추의 글자로 안다.
    if (select.value === option.value && trigger && norm(text(trigger)) === norm(option.textContent)) {
      return mark(key, true);
    }
    if (!trigger || trigger.disabled) return mark(key, false, '선택 단추가 잠겨 있습니다.');
    press(trigger);
    const list = await waitFor(openList, 2000);
    if (!list) return mark(key, false, '선택 목록이 열리지 않았습니다.');
    const item = [...list.querySelectorAll('[role="option"]')].find(o => norm(text(o)) === norm(option.textContent));
    if (!item) {
      document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));
      return mark(key, false, '목록에서 「' + option.textContent.trim() + '」을 찾지 못했습니다.');
    }
    press(item);
    const done = await waitFor(() => {
      const now = at();
      return now && now.value === option.value && norm(text(trigger)) === norm(option.textContent);
    }, 2500);
    await waitFor(() => !openList(), 1500);
    return mark(key, !!done, '「' + option.textContent.trim() + '」을 골랐지만 폼이 받지 않았습니다.');
  };
  const choose = (key, name, label, match) => chooseIn(key, () => byName(name), label, match);
  const dialogWith = words => [...document.querySelectorAll('[role="dialog"], [role="alertdialog"]')]
    .find(box => box.getAttribute('data-state') !== 'closed' && words.some(word => text(box).includes(word))) || null;

  const form = /\/ads\/villa\//.test(location.pathname) ? 'villa'
    : /\/ads\/officetel\//.test(location.pathname) ? 'officetel' : 'oneroom';
  const rooms = Math.max(1, parseInt(String(data.rooms || '1'), 10) || 1);
  const bare = (value, suffix) => { let s = String(value === undefined || value === null ? '' : value).trim(); if (s.endsWith(suffix)) s = s.slice(0, -1).trim(); return s; };
  const won = man => String(Math.round(Number(man) * 10000));

  try {
    /* ⓪ 폼이 열렸는가 — 직방은 **폼을 열어 주지 않을 때가 있다.**
     *
     * 실물 확인 2026-09-21: 남은 광고 수량이 없으면 「빌라 매물의 광고수량을 모두
     * 이용중입니다」, 그 종류의 상품을 사지 않았으면 「오피스텔(도시형생활주택) 매물
     * 광고상품 구매 후 이용할 수 있습니다」라는 알림창이 뜨고 폼 본문은 **비어 있다.**
     * 그대로 채우러 들어가면 쉰 줄이 모두 「입력란을 찾지 못했습니다」로 쏟아져, 정작
     * 사람이 알아야 할 한 가지(수량·상품)가 그 속에 묻힌다. 그래서 먼저 본다. */
    const shut = dialogWith(['광고수량', '광고상품', '상품 구매', '등록이 불가능']);
    if (shut || !byName('title')) {
      miss('폼', shut
        ? '직방이 이 매물 종류의 등록 폼을 열어 주지 않았습니다: ' + text(shut).slice(0, 200)
        : '직방 등록 폼이 화면에 없습니다. 로그인과 매물 종류를 확인해 주세요.');
      publish();
      window.__flrFormDone = true;
      auto(false);
      return;
    }

    // ① 건물 종류 — 직방은 **건축물 용도**를 묻는다(「중개대상물 종류」는 건축물대장의 용도,
    //    예) 공동주택·제1종 근린생활시설). 오피스텔 폼은 오피스텔 · 도시형생활주택 · 그 외다.
    if (form === 'officetel') {
      await pick('propertyType', 'residence.residenceType', '오피스텔');
    } else if (data.buildingUse === '단독주택') {
      await pick('propertyType', 'residence.residenceType', '단독주택');
    } else if (filled(data.buildingUse)) {
      if (await pick('propertyType', 'residence.residenceType', '그 외(직접 입력)')) {
        await waitFor(() => { const el = byName('residence.residenceTypeDescription'); return el && !el.disabled; }, 1500);
        await fillIn('buildingUse', 'residence.residenceTypeDescription', data.buildingUse);
      }
    }

    // ② 동·호
    if (data.singleBuilding === true) await check('singleBuilding', byId('haveNoDong'), true);
    else {
      await check('singleBuilding', byId('haveNoDong'), false);
      await fillIn('building', 'dongDetail.dong', bare(data.building, '동'));
    }
    await fillIn('unit', 'ho', bare(data.unit, '호'));

    // ③ 거래 유형 — 고르면 금액 칸이 그 유형의 틀로 다시 그려진다. 단기는 월세에서만 켜진다.
    if (await pick('trade', 'sales.salesType', data.trade)) {
      await waitFor(() => byName(data.trade === '매매' ? 'sales.salesPrice' : 'sales.deposit'), 2000);
      if (data.trade === '매매') await fillIn('salePrice', 'sales.salesPrice', data.salePrice, sameNumber);
      else await fillIn('deposit', 'sales.deposit', data.deposit, sameNumber);
      if (data.trade === '월세') await fillIn('monthlyRent', 'sales.rent', data.monthlyRent, sameNumber);
    }
    if (data.trade === '월세') {
      await check('shortTerm', byId('isShortTerm'), data.shortTerm === true);
      if (data.shortTerm === true) {
        note('단기 매물: 직방은 계약 기간을 따로 받지 않고 상세 설명에 적게 합니다 (' +
          (data.shortTermMonths || '?') + '개월, ' + (data.shortTermNegotiation || '') + '). 상세 설명에 계약 기간이 있는지 확인해 주세요.');
      }
    }

    // ④ 면적·사용승인일 — 사용승인일은 직방이 오피스텔 대장에서 채울 때 쓰는 모양(yyyyMMdd)으로 넣는다.
    await fillIn('exclusiveArea', 'sizeM2', data.exclusiveArea, sameNumber);
    await fillIn('approvalDate', 'approveDate', digits(data.approvalDate), sameDigits);

    // ⑤ 입주 가능일 — 날짜 칸은 읽기 전용이고, 누르면 뜨는 달력 창에서 골라야 폼이 받는다.
    if (data.moveInType === '즉시 입주') {
      await check('moveInType', byId('moveInImmediately'), true);
    } else if (filled(data.moveInDate)) {
      await check('moveInType', byId('moveInImmediately'), false);
      await pickMoveInDate(data.moveInDate);
    }
    const extra = filled(data.moveInNote) ? String(data.moveInNote) : data.moveInNegotiable === true ? '협의 가능' : '';
    if (extra) await fillIn('moveInNote', 'moveInDateExtra', extra.slice(0, 10));

    // ⑥ 층 — 전체 층을 고르면 해당 층 목록이 다시 만들어진다.
    if (await choose('floorAll', 'floorAll', String(data.floorAll) + '층')) {
      const floorLabel = data.floor === '옥탑' ? '옥탑방' : data.floor === '반지하' ? '반지하' : String(data.floor) + '층';
      await waitFor(() => { const el = byName('floor'); return el && [...el.options].some(o => norm(o.textContent) === norm(floorLabel)); }, 2500);
      await choose('floor', 'floor', floorLabel);
    }
    if (data.floorPrivate === true) note('층수 비공개: 직방은 해당 층을 그대로 적게 되어 있어 실제 층으로 넣었습니다.');

    // ⑦ 구조 — 폼마다 선택지가 다르다(원룸 · 빌라 · 오피스텔).
    const oneRoom = data.duplex === '복층' ? '복층형 원룸' : data.structure === '분리형' ? '분리형 원룸 (방1,거실1)' : '오픈형 원룸 (방1)';
    const layout = form === 'villa' ? (rooms >= 4 ? '포룸+' : rooms === 3 ? '쓰리룸' : '투룸')
      : form === 'officetel' ? (rooms >= 3 ? '쓰리룸+' : rooms === 2 ? '투룸 (방2,거실1)' : oneRoom)
      : oneRoom;
    await choose('roomLayout', 'roomType', layout);
    if (layout.endsWith('+')) note('구조 ' + layout + ': 직방은 상세 설명에 방 개수를 꼭 적게 합니다 (방 ' + data.rooms + '개).');

    // ⑧ 주실 방향 · 화장실
    await pick('directionBase', 'directionCriterionType', data.directionBase);
    await choose('direction', 'roomDirection', String(data.direction || '').replace(/향$/, ''));
    await choose('bathrooms', 'bathroomCnt', String(data.bathrooms || '').replace(/[^0-9]/g, '') + '개');

    // ⑨ 주차 · 세대 수
    if (data.parking === '주차 불가능') await check('parking', byId('no-parking'), true);
    else {
      await check('parking', byId('no-parking'), false);
      await fillIn('parkingCount', 'parkingAndHousehold.totalParkingCnt', data.parkingCount, sameNumber);
    }
    if (filled(data.householdCount)) {
      // 「주차 불가능」을 켜면 직방은 총 세대 수 칸도 함께 잠근다(주차 정보의 일부다).
      if (data.parking === '주차 불가능') note('총 세대 수: 직방은 「주차 불가능」이면 세대 수를 받지 않아 비워 두었습니다(다방에는 들어갑니다).');
      else await fillIn('householdCount', 'parkingAndHousehold.householdCnt', data.householdCount, sameNumber);
    }
    if (filled(data.parkingPerHousehold)) note('세대당 주차 대수: 직방은 총 주차대수만 받습니다.');

    // ⑩ 위반건축물 · 융자금 · 엘리베이터
    await pick('violation', 'nonCompliantBuilding', data.violation === '위반건축물 해당' ? '해당' : '해당없음');
    if (data.loan === '없음') await pick('loan', 'noLoan', '융자금 없음');
    else if (data.loan === '시세 30% 미만') await pick('loan', 'loanUnder30', '융자금 30%이하');
    else if (filled(data.loan)) note('융자금 ' + data.loan + ': 직방은 「융자금 없음」과 「30% 이하」만 고르게 되어 있어 비워 두었습니다. 상세 설명에 융자금을 적어 주세요.');
    await pick('elevator', 'isElevator', data.elevator);

    // ⑪ 옵션 — 직방 「옵션」에 있는 것만 누르고, 나머지는 다방(생활 시설)에만 들어간다.
    const optionLabel = [...document.querySelectorAll('label')].find(label => text(label) === '옵션');
    let optionScope = optionLabel ? optionLabel.parentElement : null;
    while (optionScope && optionScope.querySelectorAll('button').length < 12) optionScope = optionScope.parentElement;
    const optionButtons = optionScope ? [...optionScope.querySelectorAll('button')] : [];
    const zigbangOptions = ['에어컨', '냉장고', '세탁기', '가스레인지', '인덕션', '전자레인지', '책상', '책장', '침대', '옷장', '신발장', '싱크대'];
    const wantedOptions = (data.appliances || []).filter(item => zigbangOptions.includes(item));
    for (const button of optionButtons) {
      const label = text(button);
      if (!zigbangOptions.includes(label)) continue;
      const wanted = wantedOptions.includes(label);
      if (selected(button) !== wanted) press(button);
      mark('appliances.' + label, !!await waitFor(() => selected(button) === wanted, 1500), '옵션 선택 상태가 바뀌지 않았습니다.');
    }
    const elsewhere = (data.appliances || []).filter(item => !zigbangOptions.includes(item));
    if (elsewhere.length) note('가전·가구 ' + elsewhere.join(', ') + ': 직방 옵션에 없어 다방에만 들어갑니다.');

    // ⑫ 관리비
    await fillManageCost();

    // ⑬ 매물 설명
    await fillIn('title', 'title', data.title);
    await fillIn('description', 'description', data.description);
    if (filled(data.privateMemo)) await fillIn('privateMemo', 'secretMemo', data.privateMemo);

    // ⑭ 매물 조건 — 켤 것은 켜고, 끌 것은 끈다.
    const facilities = data.facilities || [];
    for (const [id, key, wanted] of [
      ['itemConditions.pet', 'petAllowed', data.petAllowed === '가능'],
      ['itemConditions.loanLease', 'loanAvailable', data.loanAvailable === '가능'],
      ['itemConditions.digitalContract', 'eContract', data.eContract === '가능'],
      ['itemConditions.cctv', 'facilities.CCTV', facilities.includes('CCTV')],
      ['itemConditions.terrace', 'facilities.테라스', facilities.includes('테라스')],
      ['itemConditions.evStation', 'facilities.전기차 충전시설', facilities.includes('전기차 충전시설')],
    ]) await check(key, byId(id), wanted);

    // ⑮ 중개 의뢰를 받은 방법(필수) — 기타면 방법을 적는 칸이 열린다.
    if (await pick('mediationMethod', 'mediationRequest.mediationRequestType', data.mediationMethod) &&
        data.mediationMethod === '기타 방법으로 확인') {
      await waitFor(() => byName('mediationRequest.mediationRequestTypeDescription'), 1500);
      await fillIn('mediationNote', 'mediationRequest.mediationRequestTypeDescription', data.mediationNote);
    }

    // ⑯ 의뢰인 정보 — 전화번호를 넣으면 [확인] 까지 눌러야 등록된다(직방 「실매물 확인」).
    await fillIn('ownerName', 'verification.lessorName', data.ownerName);
    await confirmLessor();

    /* ⑰ 직방 폼에 **갈 곳이 없는** 값들 (실물 확인 2026-09-21, 원룸 등록 폼).
     *
     * 통합 폼은 두 곳 중 한 곳만 받는 것도 필수로 받는다 — 그래야 한 번 채우면 두 폼이
     * 모두 끝난다. 그 대신 **어디로 갔는지**는 말해 주어야 한다. 말하지 않으면 사람은
     * 자기가 적은 난방 방식이 직방 광고에 실렸다고 믿는다. 다방 어댑터도 같은 약속을
     * 지킨다(「다방 등록 폼에 대응 입력란이 없어 직방에만 들어갑니다」). */
    for (const [value, what] of [
      [data.supplyArea, '공급면적'],
      [data.heating, '난방 방식'],
      [data.airconType, '에어컨 종류'],
      [data.roomFeatures, '방 특징'],
      [data.lh, 'LH 전세임대 여부'],
      [data.complexName, '단지명'],
    ]) {
      if (filled(value)) note(what + ': 직방 등록 폼에 대응 입력란이 없어 다방에만 들어갑니다.');
    }

    /* 사진이 먼저다.
     *
     * 직방은 사진을 「이미지 넣기」 창 안에서 받는데, Radix 창이 열려 있는 동안은
     * <body> 의 포인터가 막힌다 — 그 위에 주소 검색 겹을 띄워 두면 사람이 주소를
     * 고를 수 없다. 그래서 여기서 표식을 세워 사진을 부르고, 사진이 끝났다는 말을
     * 들은 뒤에 주소 검색을 띄운다([MirrorSession._transferPhotos] 가 알려 준다).
     *
     * 사진이 없으면 기다리지 않는다. 끝내 말이 없어도 5분이면 주소로 넘어간다 —
     * 주소를 영영 못 고르는 것보다 낫다. */
    if (Number(data.photoCount) > 0) {
      window.__flrFormDone = true;
      const until = Date.now() + 300000;
      while (window.__flrPhotosDone !== true && Date.now() < until) await sleep(250);
    }

    // ⑰ 주소 — 주소 칸을 누르면 카카오 우편번호 창이 뜬다. 브리지가 그 창을 웹뷰 안 전체
    // 화면 겹으로 바꿔 놓았으므로, 여기서 눌러 주면 결과만 고르면 된다(자동 선택기가 고른다).
    if (data.address) {
      if (window.__flrPostcode) window.__flrPostcode.query = data.address;
      const lat = byName('lat');
      if (!lat) mark('address', false, '주소 칸을 찾지 못했습니다.');
      else {
        watchAddressDialogs();
        note('매물 기본 주소: 카카오 주소 검색을 띄웠습니다. 자동으로 고르지 못하면 결과를 직접 눌러 주세요. 고르면 직방 주소 칸이 채워집니다.');
        press(lat);
      }
    }
    for (const message of (window.__flrPostcode ? window.__flrPostcode.notes : [])) note(message);
    for (const violation of (window.__FLR_VIOLATIONS__ || [])) {
      const detail = typeof violation === 'string' ? violation : [violation.kind, violation.target, violation.detail].filter(Boolean).join(': ');
      output.violations.push('깐깐이 위반: ' + detail);
    }
  } catch (error) {
    output.violations.push('자동 입력 오류: ' + String(error && error.stack ? error.stack : error));
  }
  // 표식은 어댑터 셋이 같은 약속을 지킨다 ([MirrorSession._adapterDone]). 직방은 위에서
  // 이미 세웠을 수 있으나, 오류로 빠져나온 길에서도 사진은 붙는 편이 낫다.
  window.__flrFormDone = true;
  // 「광고등록 규정 동의」와 「매물 등록 완료」는 누르지 않는다 — 사람의 몫이다.
  note('광고등록 규정 동의: 직접 읽고 체크해 주세요. 체크해야 등록할 수 있습니다.');
  publish();
  // 카카오 창에서 사람이 주소를 고르는 동안까지는 확인 창을 대신 받는다. 주소가 앉거나
  // 겹이 닫히면 끈다.
  (async () => {
    const until = Date.now() + 180000;
    while (Date.now() < until) {
      const lat = byName('lat');
      if ((lat && lat.value) || !(window.__flrPostcode && window.__flrPostcode.open)) break;
      await sleep(500);
    }
    await sleep(1500);
    auto(false);
  })();

  /* ── 관리비 ─────────────────────────────────────────────────
   * 직방은 부과 방식마다 받는 칸이 통째로 다르다(실물 2026-09-21).
   *  · 정액 관리비 = 부과 기준 + 「세부내역 고지 받았습니까」
   *      고지 받음   → 일반(공용)·전기·수도·가스·난방·인터넷·TV·기타 관리비 비목별 방식과 금액
   *      고지 안 받음 → 월 평균 관리비 + 포함 항목
   *    — 「정액 부과되는 관리비가 월 10만원 이상인 경우에만 해당」이다.
   *  · 기타 = 부과 기준 + 월 평균 관리비 + 포함 항목 + 실비 부과 세부 내역
   *    — 「정액 관리비 10만원 미만이거나 관리 규약 등에 따라 부과되는 경우」다.
   *  · 확인 불가 = 사유 */
  async function fillManageCost() {
    if (data.noManagementFee === true) { await check('noManagementFee', byId('no-manage-cost'), true); return; }
    await check('noManagementFee', byId('no-manage-cost'), false);
    const tier = data.manageMethod === '정액 관리비' ? data.feeTier : null;
    const kind = data.manageMethod === '확인 불가' ? '확인 불가'
      : (tier === '10만원 이상' || tier === '10만원 이상 (세부내역 미고지)') ? '정액 관리비' : '기타';
    const kindButton = [...document.querySelectorAll('main button')].find(b => text(b) === kind);
    if (!kindButton) { mark('manageMethod', false, '관리비 부과 방식 「' + kind + '」 단추를 찾지 못했습니다.'); return; }
    if (!selected(kindButton)) press(kindButton);
    if (!mark('manageMethod', !!await waitFor(() => selected(kindButton), 2000), '「' + kind + '」을 눌렀지만 선택되지 않았습니다.')) return;
    await sleep(300);

    if (kind === '확인 불가') {
      const reason = {
        '단독주택 사유': '건축법 시행령 별표1의 제1호 가목의 단독주택',
        '상가 건물 사유': '오피스텔 제외 상가 건물에 해당하는 경우',
        '미등기·신축 건물 사유': '미등기건물, 신축건물 등 관리비 내역이 확인불가한 경우',
      }[data.unknownFeeReason];
      await waitFor(() => byName('manageCostDetail.reason'), 2000);
      await choose('unknownFeeReason', 'manageCostDetail.reason', reason);
      return;
    }

    const criteria = {
      '직전월 관리비 기준': '직전월 관리비 기준', '3개월 평균 관리비': '최근 3개월 관리비 평균',
      '1년 평균 관리비': '최근 1년 관리비 평균', '기타 직접 입력': '직접 입력',
    }[data.manageBasis];
    await waitFor(() => byName('manageCostDetail.manageCostCriteria.manageCostCriteria'), 2000);
    if (await choose('manageBasis', 'manageCostDetail.manageCostCriteria.manageCostCriteria', criteria) && criteria === '직접 입력') {
      await waitFor(() => { const el = byName('manageCostDetail.manageCostCriteria.manageCostCriteriaEtcDescription'); return el && !el.disabled; }, 1500);
      await fillIn('manageBasisNote', 'manageCostDetail.manageCostCriteria.manageCostCriteriaEtcDescription', data.manageBasisNote);
    }

    const includeNames = {
      '일반(공용) 관리비': '일반(공용) 관리비', '전기': '전기료', '수도': '수도료', '가스': '가스 사용료',
      '난방': '난방비', '인터넷': '인터넷 사용료', 'TV': 'TV 사용료', '기타 관리비': '기타 관리비',
    };
    const includes = async name => {
      await waitFor(() => byName(name), 2000);
      const wanted = (data.manageIncludes || []).map(item => includeNames[item]).filter(Boolean);
      for (const button of buttonGroup(name)) {
        const label = text(button);
        if (!Object.values(includeNames).includes(label)) continue;
        const on = wanted.includes(label);
        if (selected(button) !== on) press(button);
        mark('manageIncludes.' + label, !!await waitFor(() => selected(button) === on, 1500), '포함 항목 선택 상태가 바뀌지 않았습니다.');
      }
    };

    if (kind === '기타') {
      await fillIn('managementFee', 'manageCostDetail.basisDetail.avgManageCost', won(data.managementFee), sameNumber);
      await includes('manageCostDetail.detailIncludes');
      const basis = tier === '10만원 미만' ? '관리비 월 10만원 미만' : {
        '관리규약에 따라 부과': '관리규약에 따라 부과',
        '면적 및 세대별 부과': '공용관리비는 면적/세대별로 부과하고, 사용료는 사용량에 따른 부과',
        '전체 세대 균등 부과': '전체 사용량을 세대수로 나누어 부과',
        '계량기별 실비 부과': '세대별 사용량(별도 계량기)에 따라 부과',
        '기타': '직접 입력',
      }[data.otherFeeReason];
      if (await choose('otherFeeReason', 'manageCostDetail.basisDetail.basis', basis) && basis === '직접 입력') {
        await waitFor(() => { const el = byName('manageCostDetail.basisDetail.basisEtcDescription'); return el && !el.disabled; }, 1500);
        await fillIn('otherFeeNote', 'manageCostDetail.basisDetail.basisEtcDescription', data.otherFeeNote);
      }
      return;
    }

    // 정액 관리비 — 고지 받았는가.
    const informed = tier === '10만원 이상';
    const radio = byId(informed ? 'true' : 'false');
    if (!radio) { mark('feeTier', false, '「의뢰인으로부터 관리비 세부내역에 대해」 선택지를 찾지 못했습니다.'); return; }
    if (radio.getAttribute('aria-checked') !== 'true') press(radio);
    if (!mark('feeTier', !!await waitFor(() => radio.getAttribute('aria-checked') === 'true', 2000), '고지 여부를 고르지 못했습니다.')) return;
    await sleep(300);

    if (!informed) {
      await fillIn('managementFee', 'manageCostDetail.totalAmount', won(data.managementFee), sameNumber);
      await includes('manageCostDetail.detail.normalManageCost.type');
      return;
    }
    const item = key => (data.manageDetail && data.manageDetail[key]) || {};
    const way = {'정액': '정액', '실비': '실비', '해당 없음': '해당없음'};
    const common = item('일반(공용) 관리비');
    await choose('manageDetail.일반(공용) 관리비', 'manageCostDetail.detail.normalManageCost.type', way[common.type]);
    await fillIn('manageDetail.일반(공용) 관리비.amount', 'manageCostDetail.detail.normalManageCost.amount', common.amount, sameNumber);
    for (const [key, field] of [['전기', 'electricity'], ['수도', 'water'], ['가스', 'gas'], ['난방', 'heating'], ['인터넷', 'internet'], ['TV', 'tv']]) {
      const entry = item(key);
      const base = 'manageCostDetail.detail.usageFee.' + field;
      await choose('manageDetail.' + key, base + '.type', way[entry.type]);
      if (entry.type === '정액') {
        await waitFor(() => { const el = byName(base + '.amount'); return el && !el.disabled; }, 1500);
        await fillIn('manageDetail.' + key + '.amount', base + '.amount', entry.amount, sameNumber);
      }
    }
    // 기타 관리비 — 이름 없는 선택란이라 「기타 관리비」 줄에서 찾는다.
    const etc = item('기타 관리비');
    const etcSelect = () => {
      const desc = byName('manageCostDetail.detail.etcManageCost.description');
      let scope = desc ? desc.parentElement : null;
      while (scope && !scope.querySelector('select')) scope = scope.parentElement;
      return scope ? scope.querySelector('select') : null;
    };
    await chooseIn('manageDetail.기타 관리비', etcSelect, etc.type === '있음' ? '직접 입력' : '해당없음');
    if (etc.type === '있음') {
      await waitFor(() => { const el = byName('manageCostDetail.detail.etcManageCost.description'); return el && !el.disabled; }, 1500);
      await fillIn('manageDetail.기타 관리비.note', 'manageCostDetail.detail.etcManageCost.description', etc.note);
      await fillIn('manageDetail.기타 관리비.amount', 'manageCostDetail.detail.etcManageCost.amount', etc.amount, sameNumber);
    }
  }

  /* ── 입주 가능일 달력 ────────────────────────────────────────
   * 칸을 누르면 달력 창이 뜨고, 날짜를 누른 뒤 「2026년 10월 1일로 선택」을 눌러야 폼이
   * 「2026.10.01 이후」를 받는다(실물 번들 MoveInDateField). */
  async function pickMoveInDate(value) {
    const match = String(value).match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (!match) return mark('moveInDate', false, '입주가능일 형식이 YYYY-MM-DD 가 아닙니다.');
    const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
    const input = byName('moveInDate');
    if (!input || input.disabled) return mark('moveInDate', false, '입주 가능일 칸이 잠겨 있습니다.');
    press(input);
    const box = await waitFor(() => dialogWith(['로 선택', '날짜를 선택해 주세요']), 2500);
    if (!box) return mark('moveInDate', false, '달력 창이 열리지 않았습니다.');
    const shown = () => {
      const caption = [...box.querySelectorAll('[role="status"], [aria-live], .rdp-caption_label, [class*="caption"]')]
        .map(text).find(t => /\d{4}/.test(t)) || '';
      const numeric = caption.match(/(\d{4})\D+(\d{1,2})/);
      if (numeric) return [Number(numeric[1]), Number(numeric[2])];
      const names = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
      const english = caption.toLowerCase().match(/([a-z]+)\s+(\d{4})/);
      if (english && names.includes(english[1])) return [Number(english[2]), names.indexOf(english[1]) + 1];
      return null;
    };
    const navButton = next => [...box.querySelectorAll('button')].find(b => {
      const label = (b.getAttribute('aria-label') || b.getAttribute('name') || '').toLowerCase();
      return next ? /next|다음/.test(label) : /previous|prev|이전/.test(label);
    });
    for (let step = 0; step < 72; step++) {
      const now = shown();
      if (!now) break;
      const diff = (year - now[0]) * 12 + (month - now[1]);
      if (diff === 0) break;
      const nav = navButton(diff > 0);
      if (!nav || nav.disabled) break;
      press(nav);
      await sleep(120);
    }
    const now = shown();
    if (!now || now[0] !== year || now[1] !== month) {
      return mark('moveInDate', false, '달력을 ' + year + '년 ' + month + '월로 넘기지 못했습니다.');
    }
    // 앞뒤 달에서 넘어온 날은 제 class 에 day-outside 를 단다(칸의 class 에도 그 글자가
    // 선택자로 들어 있으니 단추 제 것만 본다).
    const days = [...box.querySelectorAll('button[name="day"], button[role="gridcell"]')]
      .filter(b => text(b) === String(day) && !b.classList.contains('day-outside') &&
        b.getAttribute('aria-disabled') !== 'true' && !b.disabled);
    if (!days.length) return mark('moveInDate', false, day + '일을 누를 수 없습니다.');
    press(days[0]);
    const confirm = await waitFor(() => [...box.querySelectorAll('button')].find(b => /로 선택$/.test(text(b)) && !b.disabled), 1500);
    if (!confirm) return mark('moveInDate', false, '날짜를 눌렀지만 「…로 선택」이 켜지지 않았습니다.');
    press(confirm);
    return mark('moveInDate', !!await waitFor(() => {
      const el = byName('moveInDate');
      return el && el.value.includes(year + '년') && el.value.includes(month + '월') && el.value.includes(day + '일');
    }, 2000), '달력에서 골랐지만 입주 가능일 칸이 바뀌지 않았습니다.');
  }

  /* ── 의뢰인 전화번호 [확인] ───────────────────────────────────
   * 직방은 전화번호를 넣고 [확인] 을 누르지 않으면 「‘실매물 확인' 표시 노출을 위해서는,
   * 전화번호를 [확인]해 주셔야 합니다」로 등록을 막는다. [확인] 은 직방이 그 번호가
   * 집주인 번호로 쓸 수 있는지(중개사 번호·중복 여부)만 묻는 것이다. */
  async function confirmLessor() {
    if (!filled(data.ownerPhone)) return;
    const phone = digits(data.ownerPhone);
    if (!await fillIn('ownerPhone', 'verification.lessorPhone', phone, sameDigits)) return;
    const field = byName('verification.lessorPhone');
    // 「의뢰인 정보」 묶음 전체를 본다 — 답(확인되었습니다 · 중복 사유)은 단추 옆이 아니라
    // 그 아래에 새로 그려진다.
    let section = field ? field.parentElement : null;
    while (section && !/의뢰인 정보/.test(section.textContent || '')) section = section.parentElement;
    const button = section ? [...section.querySelectorAll('button')].find(b => text(b) === '확인') : null;
    if (!button) return mark('ownerPhone.confirm', false, '전화번호 옆 [확인] 단추를 찾지 못했습니다.');
    await waitFor(() => !button.disabled, 1500);
    if (button.disabled) return mark('ownerPhone.confirm', false, '[확인] 단추가 잠겨 있습니다.');
    press(button);
    // 답은 셋 중 하나로 보인다 — 「확인되었습니다」, 칸 아래 오류 글, 또는 **숨어 있던**
    // 중복 사유 묶음이 드러난다(그 묶음은 늘 문서에 있고 class 로만 숨는다).
    const visible = el => !!el && !!(el.offsetParent || el.getClientRects().length);
    const duplicateBox = () => {
      const head = document.querySelector('[name="verification.duplicatedLessor.reasonType"]');
      return head && visible(head) ? head : null;
    };
    const said = await waitFor(() => {
      if (duplicateBox()) return 'duplicate';
      const lines = [...section.querySelectorAll('p, span, div')].filter(el => el.childElementCount === 0 && visible(el)).map(text);
      if (lines.some(line => /확인되었습니다/.test(line))) return 'ok';
      const error = lines.find(line => /중개사가 아닌|형식이 올바르지|검증할 수 없습니다|잠시 후 다시/.test(line));
      return error ? 'error:' + error : null;
    }, 8000);
    if (!said) return mark('ownerPhone.confirm', false, '[확인] 을 눌렀지만 직방의 답이 오지 않았습니다. 화면에서 [확인] 을 다시 눌러 주세요.');
    if (said.startsWith('error:')) return mark('ownerPhone', false, '직방이 전화번호를 받지 않았습니다: ' + said.slice(6));
    mark('ownerPhone.confirm', true);
    if (said !== 'duplicate') return;
    // 이미 다른 매물에 쓰인 번호면 사유(필수)를 고르게 한다.
    const reasonId = {
      '의뢰인 다주택 보유': 'MULTIPLE_OWNER', '법인 소유': 'CORPORATE_OWNER',
      '관리인·대리인 위임': 'AGENT_DELEGATION', '기타': 'ETC',
    }[data.ownerPhoneDuplicateReason];
    if (!reasonId) {
      miss('ownerPhoneDuplicateReason', '직방이 이미 다른 매물에 쓰인 번호라며 중복 사유(필수)를 묻습니다. 통합 폼에 사유가 없어 비워 두었으니 화면에서 골라 주세요.');
      return;
    }
    const radio = await waitFor(() => byId(reasonId), 2000);
    if (!radio) return mark('ownerPhoneDuplicateReason', false, '중복 사유 선택지를 찾지 못했습니다.');
    if (radio.getAttribute('aria-checked') !== 'true') press(radio);
    if (!mark('ownerPhoneDuplicateReason', !!await waitFor(() => radio.getAttribute('aria-checked') === 'true', 2000), '중복 사유를 고르지 못했습니다.')) return;
    if (reasonId === 'ETC') {
      await waitFor(() => byName('verification.duplicatedLessor.reason'), 1500);
      await fillIn('ownerPhoneDuplicateNote', 'verification.duplicatedLessor.reason', data.ownerPhoneDuplicateNote);
    }
  }

  /// 주소를 고른 뒤 직방이 띄우는 창 — 오피스텔·아파트 주소면 원룸 폼에서 받지 않는다.
  function watchAddressDialogs() {
    if (window.__flrZigbangAddressWatch) return;
    window.__flrZigbangAddressWatch = new MutationObserver(() => {
      const box = dialogWith(['아파트 주소로 확인', '오피스텔(도시형생활주택)입니다', '광고수량', '등록이 불가능', '상품을 구매']);
      if (!box || box.__flrSeen) return;
      box.__flrSeen = true;
      const said = text(box).slice(0, 200);
      miss('address', '직방이 이 주소를 이 폼으로 받지 않는다고 합니다: ' + said);
      publish();
    });
    window.__flrZigbangAddressWatch.observe(document.body, {subtree: true, childList: true});
  }
})();
''';

/// 다방프로 등록 폼(`/form/room`)을 채운다.
///
/// 실물에서 떠 온 것(2026-09-21): 대분류 셋과 소분류, 단독·다가구의 「건물 유형」,
/// 오피스텔·아파트의 단지 검색(시/도→시/군/구→동, 선택지 value 가 법정동 코드 앞자리)과
/// 평형, 월 관리비 상세입력 창의 세 탭과 정액관리비 세 구간, 단기임대 계약기간,
/// 저/중/고 표기, 시설 체크, 연락처. 「등록 완료」·「임시저장」은 누르지 않는다.
String dabangInjectionScript(String payload) =>
    '(async () => {\n  const data = $payload;\n$_dabangAdapterBody';

const _dabangAdapterBody = r'''
  // 사진은 폼이 다 채워진 뒤에 붙는다. 시작할 때 내려 두지 않으면 앞선 시도가 세워 둔
  // 표식을 보고 사진이 폼 입력과 나란히 달린다.
  window.__flrFormDone = false;
  /* 어댑터가 누르는 동안 다방이 되묻는 확인 창(「매물 유형을 변경할 경우 매물정보가
   * 초기화 됩니다」, 관리비 탭 전환 등)은 한방이 「확인」으로 답한다([MirrorPage.autoAnswering]).
   * 답하지 않으면 WebView 는 늘 「취소」로 답해 다방이 아무것도 바꾸지 않는다. */
  const auto = on => { try { if (window.FlrAutoAnswer) window.FlrAutoAnswer.postMessage(on ? 'on' : 'off'); } catch (_) {} };
  auto(true);
  const output = {applied: 0, missing: [], unsupported: [], verified: 0, violations: []};
  const publish = () => { try { window.ListingResult.postMessage(JSON.stringify(output)); } catch (_) {} };
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  // 깐깐이(mirror 의 엄격 층)는 click/input/change 를 삼켰다가 0.3초 뒤에 다시 쏜다.
  // 그래서 조작 하나하나의 반응을 기다려야 한다.
  const REACT = 420;
  const text = el => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
  const norm = value => String(value === undefined || value === null ? '' : value).replace(/\s+/g, '');
  const filled = value => value !== undefined && value !== null && value !== '' &&
    !(Array.isArray(value) && value.length === 0);
  const note = message => { if (!output.unsupported.includes(message)) output.unsupported.push(message); };
  const miss = (key, why) => output.missing.push(key + ': ' + why);
  const ok = () => { output.applied++; output.verified++; };
  const waitUntil = async (predicate, timeout = 2600) => {
    const until = Date.now() + timeout;
    for (;;) {
      const value = predicate();
      if (value) return value;
      if (Date.now() >= until) return null;
      await sleep(60);
    }
  };

  /* ── 자리 찾기 ──────────────────────────────────────────────
   * 다방 표는 한 <tr> 안에 (th, td) 쌍이 여럿 들어간다 — 「욕실 수」 옆에 「엘리베이터」,
   * 「복층 여부」 옆에 「현관 유형」이 같은 줄에 있다. 줄 전체를 훑으면 옆 항목의 컨트롤을
   * 잘못 건드리므로, th 바로 뒤의 td 만 본다. td 안의 하위 묶음은 <header><h1>로 갈린다. */
  const cellOf = (section, label) => {
    const root = document.getElementById(section);
    if (!root) return null;
    for (const th of root.querySelectorAll('th')) {
      if (!norm(text(th)).includes(norm(label))) continue;
      let node = th.nextElementSibling;
      while (node && node.tagName !== 'TD') node = node.nextElementSibling;
      return node;
    }
    return null;
  };
  const rowOf = (section, label) => {
    const root = document.getElementById(section);
    if (!root) return null;
    for (const tr of root.querySelectorAll('tr')) {
      const head = tr.querySelector('th h1');
      if (head && norm(text(head)).replace('*', '') === norm(label)) return tr;
    }
    return null;
  };
  const groupOf = (cell, heading) => {
    if (!cell) return null;
    for (const header of cell.querySelectorAll('header')) {
      if (norm(text(header)) === norm(heading)) return header.parentElement;
    }
    return null;
  };
  const labelInput = (scope, wanted) => {
    if (!scope) return null;
    for (const label of scope.querySelectorAll('label')) {
      if (norm(text(label)) === norm(wanted)) return label.querySelector('input');
    }
    for (const label of scope.querySelectorAll('label')) {
      if (norm(text(label)).includes(norm(wanted))) return label.querySelector('input');
    }
    return null;
  };

  /* ── 조작 ───────────────────────────────────────────────────
   * 깐깐이는 ① el.value = v 로 넣은 값을 「폼이 모르는 대입」으로 되돌리고
   * ② 앞에 pointerdown 이 없는 로봇 click 을 버린다. 둘 다 피해서 넣는다. */
  const valueSetter = el => Object.getOwnPropertyDescriptor(
    el.tagName === 'SELECT' ? HTMLSelectElement.prototype :
    el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype,
    'value').set;
  /* 초점 사건은 **직접** 보낸다. 다방의 날짜 칸(사용승인일·입주 가능 일자)은 칸을 떠날 때
   * (focusout) 비로소 폼에 값을 넘기는데, 화면 뒤에 있는 웹뷰에서는 el.focus()·el.blur()
   * 가 아무 일도 하지 않는다 — 문서가 초점을 갖고 있지 않아서다(실물 2026-09-21: 칸에는
   * 「20180301」이 보이는데 폼은 빈 날짜로 알았다). */
  const setNative = (el, value) => {
    if (!el) return false;
    el.dispatchEvent(new FocusEvent('focusin', {bubbles: true}));
    valueSetter(el).call(el, String(value));
    ['input', 'change'].forEach(type => el.dispatchEvent(new Event(type, {bubbles: true})));
    el.dispatchEvent(new FocusEvent('focusout', {bubbles: true}));
    return true;
  };
  const press = el => {
    if (!el) return false;
    const init = {bubbles: true, cancelable: true, composed: true, view: window};
    el.dispatchEvent(new PointerEvent('pointerdown', init));
    el.dispatchEvent(new MouseEvent('mousedown', init));
    el.dispatchEvent(new MouseEvent('mouseup', init));
    el.dispatchEvent(new MouseEvent('click', init));
    return true;
  };

  // 미러는 반응할 때마다 <tr> 을 틀에서 새로 만들어 통째로 갈아 끼운다(setRow).
  // 그래서 붙잡아 둔 노드는 곧 화면 밖의 유령이 된다 — 자리는 늘 함수로 다시 찾는다.
  const at = target => { try { return typeof target === 'function' ? target() : target; } catch (_) { return null; } };
  const ready = (locate, timeout) => waitUntil(() => {
    const el = at(locate);
    return el && !el.disabled ? el : null;
  }, timeout);

  /* ── 되돌림 대비 ─────────────────────────────────────────────
   * **주소를 고르면 다방은 폼을 처음 상태로 되돌린다** (실물 실측 2026-09-20: 제목에
   * 손으로 친 글자까지 사라졌다 — 주소와 섹션이 다른데도). 넣은 값은 넣는 그 순간에만
   * 맞고 나중에 통째로 없어지므로, 그 자리에서 되읽어 본 「검증」은 오래가는 약속이 아니다.
   *
   * 그래서 성공한 조작마다 **다시 재는 법과 다시 넣는 법**을 함께 적어 두고, 끝에서
   * ([reconcile]) 한 번 더 맞춘다. 주소를 앞으로 당겨도 이 그물은 걷지 않는다 — 폼을
   * 되돌리는 것이 주소뿐이라는 보장이 없고, 숫자가 진실이려면 마지막에 본 것이어야 한다. */
  const replay = [];
  let replaying = false;
  /// [reconcile] 이 지금까지 「검증」에서 빼 둔 개수. 여러 번 불려도 같은 항목을 거듭
  /// 빼지 않기 위해 기억한다.
  let deducted = 0;
  /// 본 차례가 끝났는가. 끝난 뒤에 도착하는 되돌림은 [watchAddress] 가 맞춘다.
  let settled = false;
  /// 창(모달) 안의 칸은 **적어 두지 않는다.** 「월 관리비 상세입력」처럼 값을 받고
  /// 닫히는 창은 닫히는 순간 칸이 사라지므로, 다시 재면 늘 「없어졌다」로 읽힌다 —
  /// 저장된 것을 잃었다고 말하고, 있지도 않은 칸에 다시 넣으려 든다.
  const inModal = el => !!(el && el.closest && el.closest('#modal-container'));
  const remember = (key, el, check, redo) => {
    if (replaying || inModal(el)) return;
    replay.push({key, check, redo});
  };
  const holds = item => { try { return !!item.check(); } catch (_) { return false; } };

  /// 폼이 스스로 모양을 다듬는 칸은 **숫자만 같으면 같은 값이다.** 실물 다방의
  /// 사용승인일 칸은 넣은 `20250301` 을 제 형식으로 고쳐 되돌려 주어, 글자 그대로
  /// 견주면 넣고도 실패로 읽혔다(2026-09-20 실측).
  const digits = value => String(value).replace(/[^0-9]/g, '');
  const sameDigits = (got, wanted) => !!digits(wanted) && digits(got) === digits(wanted);
  const sameText = (got, wanted) => got === wanted;

  const fill = (key, locate, value, transform = v => v, same = sameText) => {
    if (!filled(value)) return false;
    const el = at(locate);
    if (!el) { miss(key, '다방 폼에서 입력란을 찾지 못했습니다.'); return false; }
    if (el.disabled) { miss(key, '입력란이 잠겨 있어 값을 넣지 못했습니다.'); return false; }
    const wanted = String(transform(value));
    setNative(el, wanted);
    const again = at(locate) || el;
    if (same(String(again.value), wanted)) {
      ok();
      remember(key, again,
        () => { const now = at(locate); return !!now && same(String(now.value), wanted); },
        () => { const now = at(locate); if (now && !now.disabled) setNative(now, wanted); });
      return true;
    }
    output.applied++;
    // 무엇으로 읽혔는지 함께 적는다. 「같은 값을 못 읽었다」만으로는 폼이 형식을 고친
    // 것인지 값을 버린 것인지 알 수 없어, 실물에서 한 번 더 재 봐야만 했다.
    miss(key, '넣은 값은 「' + wanted + '」인데 폼은 「' + String(again.value).slice(0, 40) + '」로 읽습니다.');
    return false;
  };

  const pickOption = (el, wanted) => {
    const target = norm(wanted);
    if (!target) return null;
    const options = [...el.options].filter(option => option.value !== '');
    return options.find(option => norm(text(option)) === target)
      || options.find(option => norm(option.value) === target)
      || options.find(option => norm(text(option)).includes(target))
      || options.find(option => target.includes(norm(text(option))));
  };
  const select = async (key, locate, wanted, timeout = 2600) => {
    if (!filled(wanted)) return false;
    if (!at(locate)) { miss(key, '다방 폼에서 선택란을 찾지 못했습니다.'); return false; }
    const el = await ready(locate, timeout);
    if (!el) { miss(key, '선택란이 아직 잠겨 있어 고르지 못했습니다.'); return false; }
    const option = pickOption(el, wanted);
    if (!option) { note(key + ' ' + wanted + ': 다방 폼의 선택지에 대응하는 항목이 없습니다.'); return false; }
    const value = option.value;
    setNative(el, value);
    if (await waitUntil(() => { const now = at(locate); return now && now.value === value; }, 1200)) {
      ok();
      remember(key, el,
        () => { const now = at(locate); return !!now && now.value === value; },
        () => { const now = at(locate); if (now && !now.disabled) setNative(now, value); });
      await sleep(REACT); return true;
    }
    output.applied++;
    miss(key, '고른 뒤 폼에서 같은 값을 다시 읽지 못했습니다.');
    return false;
  };

  // 라디오·체크박스는 label 이 아니라 그 안의 input 을 눌러야 미러의 그룹 처리가
  // 어느 것을 눌렀는지 알아본다(미러는 window 캡처에서 e.target 을 본다).
  const toggle = async (key, locate, wanted, label) => {
    const el = await ready(locate, 3000);
    if (!el) {
      miss(key, at(locate) ? (label || '선택지') + '이(가) 아직 잠겨 있어 고르지 못했습니다.'
        : '다방 폼에서 ' + (label || '선택지') + '을(를) 찾지 못했습니다.');
      return false;
    }
    const keep = () => {
      remember(key, el,
        () => { const now = at(locate); return !!now && now.checked === wanted; },
        () => { const now = at(locate); if (now && !now.disabled && now.checked !== wanted) press(now); });
    };
    if (el.checked === wanted) { ok(); keep(); return true; }
    press(el);
    if (await waitUntil(() => { const now = at(locate); return now && now.checked === wanted; }, 2000)) {
      ok(); keep(); await sleep(REACT); return true;
    }
    output.applied++;
    miss(key, (label || '선택지') + '을(를) 눌렀지만 선택 상태가 바뀌지 않았습니다.');
    return false;
  };
  const choose = async (key, scope, wanted, mapped) => {
    if (!filled(wanted)) return false;
    const target = mapped === undefined ? wanted : mapped;
    if (target === null) return false;
    return toggle(key, () => labelInput(at(scope), target), true, target);
  };

  /* 넣어 둔 것을 전부 다시 재고, 없어진 것은 다시 넣는다.
   *
   * 다시 넣는 일이 또 다른 행을 되돌릴 수 있어(매물유형을 다시 고르면 7행이 다시
   * 그려진다) 잠잠해질 때까지 몇 번 돈다. 끝내 붙지 않는 것만 「확인할 항목」에 남긴다.
   * [output.verified] 는 **마지막에 본 것**으로 고쳐 적는다 — 넣던 순간의 숫자는
   * 사람에게 거짓말이 된다. */
  const reconcile = async () => {
    if (!replay.length) return;
    replaying = true;
    for (let round = 0; round < 3; round++) {
      const lost = replay.filter(item => !holds(item));
      if (!lost.length) break;
      for (const item of lost) {
        try { await item.redo(); } catch (_) { /* 다음 바퀴에서 다시 만난다 */ }
      }
      await sleep(REACT);
    }
    replaying = false;
    const stuck = replay.filter(item => !holds(item));
    // 「검증」에서 **끝내 안 남은 것만** 뺀다. 처음부터 다시 세면 창 안에서 받고 닫힌
    // 관리비처럼 [replay] 에 없는 성공까지 사라져, 숫자가 정직해지는 게 아니라 인색해진다.
    //
    // [watchAddress] 가 이것을 여러 번 부르므로 **뺀 만큼을 기억했다가 되돌린 뒤** 다시
    // 뺀다. 그러지 않으면 부를 때마다 같은 항목을 또 빼서 검증 숫자가 0까지 내려간다.
    output.verified = Math.max(0, output.verified + deducted - stuck.length);
    deducted = stuck.length;
    // 되돌림이 또 오면 이 자리도 다시 지나간다 — 같은 말을 두 번 적지 않는다.
    for (let i = output.missing.length - 1; i >= 0; i--) {
      if (/: 넣은 값이 폼에서 사라져/.test(output.missing[i])) output.missing.splice(i, 1);
    }
    for (const item of stuck) {
      miss(item.key, '넣은 값이 폼에서 사라져 다시 넣었지만 남지 않았습니다.');
    }
    publish();
  };

  const modal = title => {
    const box = document.getElementById('modal-container');
    return box && norm(text(box)).includes(norm(title)) ? box : null;
  };
  const modalButton = (box, wanted) =>
    box ? [...box.querySelectorAll('button')].find(button => norm(text(button)) === norm(wanted)) : null;
  const bare = (value, suffix) => { let s = String(value === undefined || value === null ? '' : value).trim(); if (s.endsWith(suffix)) s = s.slice(0, -1).trim(); return s; };
  /// value 로 고른다 — 다방 선택란은 value 가 코드(THIRTY_UNDER · LAST_MONTH …)라 글자보다 확실하다.
  const selectValue = async (key, locate, value, timeout = 2600) => {
    if (!filled(value)) return false;
    if (!at(locate)) { miss(key, '다방 폼에서 선택란을 찾지 못했습니다.'); return false; }
    const el = await ready(locate, timeout);
    if (!el) { miss(key, '선택란이 아직 잠겨 있어 고르지 못했습니다.'); return false; }
    if (![...el.options].some(option => option.value === String(value))) {
      note(key + ': 다방 선택지에 「' + value + '」이(가) 없습니다.');
      return false;
    }
    if (el.value === String(value)) { ok(); remember(key, el, () => { const now = at(locate); return !!now && now.value === String(value); }, () => { const now = at(locate); if (now && !now.disabled) setNative(now, value); }); return true; }
    setNative(el, value);
    if (await waitUntil(() => { const now = at(locate); return now && now.value === String(value); }, 1500)) {
      ok();
      remember(key, el,
        () => { const now = at(locate); return !!now && now.value === String(value); },
        () => { const now = at(locate); if (now && !now.disabled) setNative(now, value); });
      await sleep(REACT);
      return true;
    }
    output.applied++;
    miss(key, '고른 뒤 폼에서 같은 값을 다시 읽지 못했습니다.');
    return false;
  };

  /* ── 주소 ───────────────────────────────────────────────────
   * 주택/빌라 — 「검색」은 카카오 우편번호 화면을 띄운다(브리지가 웹뷰 안 전체 화면 겹으로
   * 그린다). 결과를 고르면 다방이 폼을 처음 상태로 되돌리고(매물유형·방 수·거래 종류만
   * 남긴다) 동/호 칸을 켜고 건축물대장 창을 띄운다. 대장 창은 「직접 입력」으로 닫는다 —
   * 대장 조회는 이미 넣은 면적·용도·승인일을 공공데이터 값으로 덮어쓰기 때문이다.
   * 오피스텔·아파트 — 주소 대신 시/도→시/군/구→동→단지를 고른다([enterComplexAddress]). */
  const addressCell = () => cellOf('room_info', '매물 주소');
  const addressInput = name => () => {
    const now = addressCell();
    return now ? now.querySelector('input[name="' + name + '"]') : null;
  };
  /// 「등기부등본 상에 ‘동’ 정보가 없을 경우 체크」
  const noDongBox = () => {
    const cell = addressCell();
    if (!cell) return null;
    const label = [...cell.querySelectorAll('label')].find(l => /동.{0,3}정보가 없을 경우/.test(text(l)));
    return label ? label.querySelector('input[type="checkbox"]') : null;
  };
  const fillUnit = async () => {
    if (data.singleBuilding === true) {
      if (noDongBox()) await toggle('singleBuilding', noDongBox, true, '동 정보 없음');
    } else {
      if (noDongBox() && noDongBox().checked) await toggle('singleBuilding', noDongBox, false, '동 정보 없음');
      fill('building', addressInput('dong'), bare(data.building, '동'));
    }
    fill('unit', addressInput('ho'), bare(data.unit, '호'));
  };
  const afterAddressPicked = () => {
    const cell = addressCell();
    if (!cell) return;
    const ledger = modal('건축물대장');
    if (ledger) {
      const keep = modalButton(ledger, '아니요, 직접 입력할게요') || modalButton(ledger, '닫기');
      if (keep) {
        press(keep);
        note('건축물대장 자동 조회: 면적·용도·승인일이 공공데이터 값으로 덮어써지지 않도록 「직접 입력」으로 닫았습니다. 세 항목은 통합 폼의 값으로 채웁니다.');
      }
    }
    const dong = cell.querySelector('input[name="dong"]');
    const ho = cell.querySelector('input[name="ho"]');
    if (!dong || !ho || dong.disabled || ho.disabled) return;
    const picked = [...cell.querySelectorAll('[class*=AddressList] li')].map(li => norm(text(li))).join('|');
    if (!picked) return;
    if (window.__flrDabangAddress === picked) return;
    window.__flrDabangAddress = picked;
    for (const bucket of [output.missing, output.unsupported]) {
      for (let i = bucket.length - 1; i >= 0; i--) {
        if (/^(매물 기본 주소|address|building|unit|동 정보|호수 정보):/.test(bucket[i])) bucket.splice(i, 1);
      }
    }
    fillUnit();
    output.applied++;
    output.verified++;
    publish();
  };
  /* 사진을 붙이는 동안에는 폼을 건드리지 않는다.
   *
   * [reconcile] 은 없어진 값을 다시 넣는데, 매물유형을 다시 누르면 매물 정보·추가 정보
   * 7행이 통째로 다시 그려진다. 그 다시 그리기가 **방금 올라간 사진 카드를 쓸어 간다.**
   * 사진 카드가 생기고 사라지는 것 자체도 body 의 변화라, 막지 않으면 사진이 제가
   * 저를 지우게 만드는 셈이 된다. `until` 은 사진 다리(lib/photo_transfer.dart)가
   * 부를 때마다 앞으로 밀리고 끝나면 0 이 되므로, 전송이 죽어도 여기서 영원히 멈추지
   * 않는다. */
  const photoBusy = () => !!window.__flrPhotos && Date.now() < (window.__flrPhotos.until || 0);
  const photoArea = () => document.getElementById('visual_info');
  const watchAddress = () => {
    if (window.__flrDabangAddressWatch) return;
    window.__flrDabangAddressWatch = new MutationObserver(records => {
      if (photoBusy()) return;
      const spot = photoArea();
      if (spot && records.every(record => spot.contains(record.target))) return;
      afterAddressPicked();
      // 본 차례가 이미 끝난 뒤에 주소가 도착했다면, 그 되돌림을 맞출 사람이 없다.
      if (settled && !replaying) {
        settled = false;
        auto(true);
        reconcile().then(() => { settled = true; setTimeout(() => auto(false), 1500); });
      }
    });
    window.__flrDabangAddressWatch.observe(document.body, {
      subtree: true, childList: true, attributes: true, attributeFilter: ['disabled'],
    });
  };

  /// 카카오 주소 화면을 띄우고 주소가 앉을 때까지 기다린다. 앉았는지는 동·호 칸이
  /// 열렸는지로 안다 — 다방이 주소를 받아들였을 때만 풀리는 자물쇠다.
  const pickAddress = async () => {
    const cell = addressCell();
    const search = cell && [...cell.querySelectorAll('button')].find(button => norm(text(button)) === '검색');
    if (!search) { miss('address', '매물 주소의 「검색」 버튼을 찾지 못했습니다.'); return false; }
    press(search);
    const landed = await waitUntil(() => {
      const now = addressCell();
      const dong = now && now.querySelector('input[name="dong"]');
      return dong && !dong.disabled ? dong : null;
    }, 60000);
    afterAddressPicked();
    if (!landed) {
      note('매물 기본 주소: 카카오 주소 검색을 띄웠지만 주소가 확정되지 않아 나머지를 먼저 채웠습니다. '
        + '결과를 직접 눌러 주시면 주소·동·호가 채워지고, 주소 때문에 지워진 값은 한방이 다시 넣습니다.');
      return false;
    }
    await sleep(REACT);
    return true;
  };

  /* ── 오피스텔·아파트 단지 ─────────────────────────────────────
   * 시/도 → 시/군/구 → 동/읍/면 을 고르면 그 동의 단지 목록이 뜬다. 선택지의 value 가
   * **법정동 코드의 앞자리**다(시/도 2자리 · 시/군/구 5자리 · 동 8자리, 실물 2026-09-21) —
   * 카카오가 준 법정동 코드로 고르면 이름을 견줄 필요가 없다. 목록에는 단지 이름만
   * 있어서(주소가 없다) 단지는 통합 폼의 단지명으로 고른다. */
  const SIDO = {
    '서울': '서울특별시', '부산': '부산광역시', '대구': '대구광역시', '인천': '인천광역시',
    '광주': '광주광역시', '대전': '대전광역시', '울산': '울산광역시', '세종': '세종특별자치시',
    '경기': '경기도', '강원': '강원특별자치도', '충북': '충청북도', '충남': '충청남도',
    '전북': '전북특별자치도', '전남': '전라남도', '경북': '경상북도', '경남': '경상남도',
    '제주': '제주특별자치도',
  };
  const complexKey = value => norm(String(value || '').replace(/\([^)]*\)/g, '')).toLowerCase();
  const enterComplexAddress = async () => {
    const code = digits(data.legalDongCode);
    const regionSelect = name => () => { const cell = addressCell(); return cell ? cell.querySelector('select[name="' + name + '"]') : null; };
    const levels = [
      ['city', 2, [SIDO[data.sido] || data.sido]],
      ['gu', 5, [data.sigungu]],
      ['dong', 8, [data.bname]],
    ];
    for (const [name, width, names] of levels) {
      const el = await waitUntil(() => { const s = regionSelect(name)(); return s && !s.disabled && s.options.length > 1 ? s : null; }, 6000);
      if (!el) { miss('address', '단지 검색의 ' + name + ' 선택란이 준비되지 않았습니다.'); return false; }
      const options = [...el.options].filter(o => o.value !== '');
      const option = (code.length >= width && options.find(o => o.value === code.slice(0, width))) ||
        options.find(o => names.some(n => filled(n) && norm(text(o)) === norm(n))) ||
        options.find(o => names.some(n => filled(n) && (norm(n).includes(norm(text(o))) || norm(text(o)).includes(norm(n)))));
      if (!option) { miss('address', '주소 「' + data.address + '」에 맞는 ' + name + ' 선택지를 찾지 못했습니다.'); return false; }
      if (!await selectValue('address.' + name, regionSelect(name), option.value, 6000)) return false;
    }
    const search = () => { const cell = addressCell(); return cell ? cell.querySelector('input[placeholder="단지검색"]') : null; };
    const input = await waitUntil(() => { const s = search(); return s && !s.disabled ? s : null; }, 6000);
    if (!input) { miss('address', '단지검색 칸이 열리지 않았습니다.'); return false; }
    // 목록은 칸에 초점이 가야 뜨고, 글자를 넣으면 그 글자로 좁혀진다.
    input.focus();
    input.dispatchEvent(new FocusEvent('focus', {bubbles: false}));
    input.dispatchEvent(new FocusEvent('focusin', {bubbles: true}));
    const wanted = complexKey(data.complexName || data.buildingName);
    if (!wanted) { miss('address', '단지명이 없어 다방 단지 목록에서 고를 수 없습니다.'); return false; }
    setNative(input, String(data.complexName || data.buildingName).replace(/\([^)]*\)/g, '').trim());
    input.dispatchEvent(new FocusEvent('focusin', {bubbles: true}));
    const list = await waitUntil(() => {
      const cell = addressCell();
      const items = cell ? [...cell.querySelectorAll('ul[class*=SearchList] > li')] : [];
      return items.length ? items : null;
    }, 8000);
    if (!list) { miss('address', '단지 목록이 나타나지 않았습니다. 단지명 「' + (data.complexName || '') + '」을 확인해 주세요.'); return false; }
    const exact = list.filter(li => complexKey(text(li)) === wanted);
    const partial = list.filter(li => complexKey(text(li)).includes(wanted) || wanted.includes(complexKey(text(li))));
    const item = exact.length === 1 ? exact[0] : exact.length === 0 && partial.length === 1 ? partial[0] : null;
    if (!item) {
      miss('address', '단지 후보 ' + (exact.length || partial.length || list.length) + '개 중 「' + (data.complexName || '') +
        '」 하나를 확정하지 못했습니다(' + (exact.length ? exact : partial.length ? partial : list).slice(0, 5).map(text).join(', ') + '). 화면에서 직접 골라 주세요.');
      return false;
    }
    press(item);
    const picked = await waitUntil(() => {
      const cell = addressCell();
      const summary = cell && cell.querySelector('[class*=AddressList]');
      return summary && complexKey(text(summary)).includes(complexKey(text(item))) ? summary : null;
    }, 6000);
    if (!picked) { miss('address', '「' + text(item) + '」 단지를 눌렀지만 주소가 확정되지 않았습니다.'); return false; }
    ok();
    await sleep(REACT);
    await fillUnit();
    await pickComplexSpace();
    return true;
  };
  /// 평형 — 선택지는 「79B (79.93㎡ / 59.94㎡)」처럼 공급/전용이다. 통합 폼의 전용·공급면적과
  /// 가장 가까운 것을 고르되, 전용이 1㎡ 넘게 어긋나면 고르지 않는다.
  const pickComplexSpace = async () => {
    const locate = () => { const cell = cellOf('room_info', '매물 크기'); return cell ? cell.querySelector('select[name="complexSpaceSeq"]') : null; };
    const el = await waitUntil(() => { const s = locate(); return s && !s.disabled && s.options.length > 1 ? s : null; }, 6000);
    if (!el) { miss('exclusiveArea', '평형 선택란이 준비되지 않았습니다.'); return false; }
    const exclusive = Number(data.exclusiveArea), supply = Number(data.supplyArea);
    let best = null;
    for (const option of [...el.options].filter(o => o.value !== '')) {
      const m = text(option).match(/\(([\d.]+)㎡\s*\/\s*([\d.]+)㎡\)/);
      if (!m) continue;
      const [s, e] = [Number(m[1]), Number(m[2])];
      const score = Math.abs(e - exclusive) + (Number.isNaN(supply) ? 0 : Math.abs(s - supply) / 2);
      if (Math.abs(e - exclusive) <= 1 && (!best || score < best.score)) best = {option, score};
    }
    if (!best) {
      miss('exclusiveArea', '전용 ' + data.exclusiveArea + '㎡ 에 맞는 평형이 없습니다(' +
        [...el.options].filter(o => o.value !== '').map(text).slice(0, 6).join(', ') + '). 화면에서 평형을 골라 주세요.');
      return false;
    }
    return selectValue('exclusiveArea', locate, best.option.value);
  };

  /* ── 월 관리비 상세입력 창 ─────────────────────────────────────
   * 부과방식 세 탭 — 정액관리비(10만원 미만 · 10만원 이상 · 10만원 이상 세부내역 미고지),
   * 기타부과(E01~E04 · E99), 확인불가(U01~U03). 탭·구간을 바꾸면 다방이 confirm 으로
   * 되묻는다(한방이 「확인」으로 답한다). 「확인」 단추는 창이 값을 다 받아야 켜진다. */
  const INCLUDE_CODES = {
    '일반(공용) 관리비': 'PUBLIC_USE_RATES', '전기': 'ELECTRIC_RATES', '수도': 'WATER_RATES', '가스': 'GAS_RATES',
    '난방': 'HEATING_RATES', '인터넷': 'INTERNET_RATES', 'TV': 'TV_RATES', '기타 관리비': 'ETC_USE_RATES',
  };
  const BASIS = {
    '직전월 관리비 기준': 'LAST_MONTH', '3개월 평균 관리비': 'LAST_THREE_MONTH_AVG',
    '1년 평균 관리비': 'LAST_ONE_YEAR_AVG', '기타 직접 입력': 'ETC',
  };
  const completeFeeModal = async () => {
    const box = () => modal('월 관리비 상세입력');
    if (!await waitUntil(box)) { miss('managementFee', '「관리비 있음」 뒤에 상세입력 창이 열리지 않았습니다.'); return; }
    const inBox = selector => () => { const b = box(); return b ? b.querySelector(selector) : null; };
    const radio = value => inBox('input[type="radio"][value="' + value + '"]');
    // 창 안의 줄(li)은 제목 칸(.th)의 글자로 찾는다.
    const row = title => () => {
      const b = box();
      // 필수 줄은 제목 뒤에 「*」가 붙는다(「관리비*」·「구분*」).
      return b ? [...b.querySelectorAll('li')].find(li => { const th = li.querySelector('.th'); return th && norm(text(th)).replace(/\*/g, '') === norm(title); }) || null : null;
    };
    const inRow = (title, selector, index = 0) => () => { const r = row(title)(); return r ? r.querySelectorAll(selector)[index] || null : null; };
    const method = data.manageMethod === '기타 부과' ? '기타부과' : data.manageMethod === '확인 불가' ? '확인불가' : '정액관리비';
    const tab = modalButton(box(), method);
    if (!tab) { miss('manageMethod', '상세입력 창에서 「' + method + '」 탭을 찾지 못했습니다.'); return; }
    press(tab);
    await sleep(REACT);
    const tier = data.feeTier === '10만원 이상' ? 'ABOVE_FIXED_FEE_THRESHOLD'
      : data.feeTier === '10만원 이상 (세부내역 미고지)' ? 'ABOVE_FIXED_FEE_THRESHOLD_NO_DETAILS' : 'BELOW_FIXED_FEE_THRESHOLD';
    if (method === '정액관리비') {
      await toggle('feeTier', radio(tier), true, '정액관리비 ' + data.feeTier);
      await sleep(REACT);
    } else if (method === '기타부과') {
      await waitUntil(() => { const b = box(); return b && [...b.querySelectorAll('select option')].some(o => o.value === 'E01'); });
    } else {
      await waitUntil(inBox('select[name="detailCode"]'));
    }

    if (method !== '확인불가') {
      const basis = BASIS[data.manageBasis];
      if (basis) {
        await toggle('manageBasis', radio(basis), true, '관리비 기준');
        if (basis === 'ETC') {
          await sleep(REACT);
          const basisRow = () => { const r = radio('ETC')(); let li = r ? r.closest('li') : null; return li; };
          fill('manageBasisNote', () => { const li = basisRow(); return li ? li.querySelector('input[type="text"]') : null; }, data.manageBasisNote);
        }
      }
    }
    const includes = async () => {
      for (const [item, code] of Object.entries(INCLUDE_CODES)) {
        const wanted = (data.manageIncludes || []).includes(item);
        const box = inBox('input[type="checkbox"][value="' + code + '"]');
        if (!box()) { if (wanted) miss('manageIncludes.' + item, '포함 항목 「' + item + '」 칸을 찾지 못했습니다.'); continue; }
        if (box().checked !== wanted) await toggle('manageIncludes.' + item, box, wanted, '포함 항목 ' + item);
        else if (wanted) ok();
      }
    };
    const won = man => String(Math.round(Number(man) * 10000));

    if (method === '정액관리비' && tier === 'BELOW_FIXED_FEE_THRESHOLD') {
      fill('managementFee', inBox('input[name="detailCost"]'), won(data.managementFee));
      await includes();
    } else if (method === '정액관리비' && tier === 'ABOVE_FIXED_FEE_THRESHOLD') {
      const item = key => (data.manageDetail && data.manageDetail[key]) || {};
      const common = item('일반(공용) 관리비');
      await toggle('manageDetail.일반(공용) 관리비', inRow('공용 관리비', 'input[type="radio"][value="' + (common.type === '실비' ? 'ACTUAL_EXPENSE' : 'FIXED_FEE') + '"]'), true, '공용 관리비 부과 방식');
      await sleep(REACT);
      fill('manageDetail.일반(공용) 관리비.amount', inRow('공용 관리비', 'input[name="detailCost"]'), digits(common.amount));
      for (const [key, title] of [['전기', '전기'], ['수도', '수도'], ['가스', '가스'], ['난방', '난방비'], ['인터넷', '인터넷'], ['TV', 'TV']]) {
        const entry = item(key);
        const fixed = entry.type === '정액';
        await toggle('manageDetail.' + key, inRow(title, 'input[type="radio"][value="' + (fixed ? 'FIXED_FEE' : 'ACTUAL_EXPENSE') + '"]'), true, key + ' 부과 방식');
        if (fixed) { await sleep(REACT); fill('manageDetail.' + key + '.amount', inRow(title, 'input[name="detailCost"]'), digits(entry.amount)); }
        if (entry.type === '해당 없음') note('관리비 ' + key + ' 해당 없음: 다방은 비목마다 정액·실비만 받아 「실비」로 넣었습니다.');
      }
      const etc = item('기타 관리비');
      await toggle('manageDetail.기타 관리비', inRow('기타 관리비', 'input[type="radio"][value="' + (etc.type === '있음' ? 'has' : 'none') + '"]'), true, '기타 관리비 여부');
      if (etc.type === '있음') {
        await sleep(REACT);
        await toggle('manageDetail.기타 관리비.way', inRow('기타 관리비', 'input[type="radio"][value="FIXED_FEE"]'), true, '기타 관리비 부과 방식');
        await sleep(REACT);
        fill('manageDetail.기타 관리비.amount', inRow('기타 관리비', 'input[name="detailCost"]'), digits(etc.amount));
        fill('manageDetail.기타 관리비.note', () => {
          const r = row('기타 관리비')();
          return r ? [...r.querySelectorAll('input[type="text"]')].find(i => i.name !== 'detailCost') || null : null;
        }, etc.note);
      }
    } else if (method === '정액관리비') {
      await selectValue('manageMethod.noDetails', () => { const b = box(); return b ? [...b.querySelectorAll('select')].find(s => [...s.options].some(o => o.value === 'E98')) || null : null; }, 'E98');
      fill('managementFee', inRow('관리비', 'input[type="text"]'), won(data.managementFee));
      await includes();
    } else if (method === '기타부과') {
      const code = {
        '관리규약에 따라 부과': 'E01', '면적 및 세대별 부과': 'E02', '전체 세대 균등 부과': 'E03',
        '계량기별 실비 부과': 'E04', '기타': 'E99',
      }[data.otherFeeReason];
      const codeSelect = () => { const b = box(); return b ? [...b.querySelectorAll('select')].find(s => [...s.options].some(o => o.value === 'E01')) || null : null; };
      await selectValue('otherFeeReason', codeSelect, code);
      if (code === 'E99') {
        await sleep(REACT);
        fill('otherFeeNote', () => { const s = codeSelect(); const cell = s ? s.closest('.td') : null; return cell ? cell.querySelector('input[type="text"]') : null; }, data.otherFeeNote);
      }
      fill('managementFee', inRow('관리비', 'input[type="text"]'), won(data.managementFee));
      await includes();
    } else {
      const code = {'단독주택 사유': 'U01', '상가 건물 사유': 'U02', '미등기·신축 건물 사유': 'U03'}[data.unknownFeeReason];
      await selectValue('unknownFeeReason', inBox('select[name="detailCode"]'), code);
    }

    const confirm = await waitUntil(() => {
      const button = modalButton(box(), '확인');
      return button && !button.disabled ? button : null;
    }, 3000);
    if (!confirm) {
      miss('managementFee', '상세입력 값을 넣었지만 「확인」이 켜지지 않았습니다. 창을 열어 둔 채 두었으니 직접 확인해 주세요.');
      return;
    }
    press(confirm);
    if (await waitUntil(() => !box(), 3000)) ok();
    else miss('managementFee', '「확인」을 눌렀지만 상세입력 창이 닫히지 않았습니다.');
  };

  /* ── 매물유형 ──────────────────────────────────────────────── */
  const PROPERTY = {
    '빌라/연립/다세대': ['주택', '빌라/연립/다세대'], '단독주택': ['주택', '단독주택'],
    '다가구주택': ['주택', '다가구주택'], '상가주택': ['주택', '상가주택'],
    '오피스텔': ['오피스텔', null], '아파트': ['아파트', null],
  };
  let complexProperty = false;
  /// 지금 골라져 있는 대분류 — 소분류 줄의 글자로 안다(주택/빌라는 네다섯 칸, 오피스텔·
  /// 아파트는 한 칸이다). 대분류 단추 자체에는 골라졌다는 표식이 없다.
  const currentMajor = () => {
    const labels = [...(rowOf('room_info', '매물유형') || document).querySelectorAll('label')].map(text);
    if (labels.some(l => l.startsWith('빌라/연립/다세대'))) return '주택';
    if (labels.some(l => l.startsWith('오피스텔'))) return '오피스텔';
    if (labels.some(l => l.startsWith('아파트'))) return '아파트';
    return null;
  };
  const applyPropertyType = async () => {
    const mapping = PROPERTY[data.propertyType];
    if (!mapping) {
      miss('propertyType', '매물 종류 「' + data.propertyType + '」는 다방 주거용 매물 등록 폼에 대응하는 유형이 없습니다.');
      return false;
    }
    const [major, minor] = mapping;
    const majorButton = () => [...(rowOf('room_info', '매물유형') || document).querySelectorAll('button')]
      .find(item => norm(text(item)).startsWith(norm(major)));
    if (currentMajor() !== major) {
      const button = majorButton();
      if (!button) { miss('propertyType', '대분류 「' + major + '」 버튼을 찾지 못했습니다.'); return false; }
      press(button);
      // 대분류를 바꾸면 다방이 「매물정보가 초기화 됩니다」로 되묻고, 7개 행이 다시 그려진다.
      if (!await waitUntil(() => currentMajor() === major, 4000)) {
        miss('propertyType', '대분류 「' + major + '」를 눌렀지만 바뀌지 않았습니다.');
        return false;
      }
      await sleep(REACT);
    }
    // 주소가 폼을 되돌리면 대분류부터 풀린다. 그러면 뒤의 값들은 있을 자리가 없으므로
    // 이것을 가장 먼저 적어 둔다 — [reconcile] 은 적어 둔 순서대로 되돌린다.
    remember('propertyType', majorButton(),
      () => currentMajor() === major,
      async () => {
        const again = majorButton();
        if (!again) return;
        press(again);
        await waitUntil(() => currentMajor() === major, 4000);
      });
    if (!minor) {
      complexProperty = true;
      ok();
      return true;
    }
    // 소분류 라디오는 매물유형 행의 두 번째 칸에 있다.
    const done = await choose('propertyType', () => rowOf('room_info', '매물유형'), minor);
    // 단독·다가구는 「건물 유형」을 묻는다 — 방 하나(건물 일부)를 내놓는 것이다.
    if (done && (minor === '단독주택' || minor === '다가구주택')) {
      await sleep(REACT);
      await choose('propertyType.unit', () => cellOf('room_info', '건물 유형'), '건물 일부');
    }
    return done;
  };

  try {
    if (window.__flrPostcode) window.__flrPostcode.query = data.address || '';
    watchAddress();

    // ① 매물유형 — 대분류를 바꾸면 매물 정보 7행이 통째로 다시 그려지므로 가장 먼저.
    await applyPropertyType();

    /* ② 주소 — **여기서 끝까지 받는다.**
     *
     * 주소를 고르는 순간 다방이 폼을 처음 상태로 되돌려 그때까지 채운 것이 사라진다
     * (실물 실측 2026-09-20). 되돌리는 쪽을 먼저 지나가면 뒤의 값들이 살아남는다.
     * 끝내 안 오면 멈추지 않고 나머지를 채운다 — 늦게 도착하는 주소는 [watchAddress] 가
     * 듣고, 그때 [reconcile] 이 다시 맞춘다. */
    if (complexProperty) {
      await enterComplexAddress();
      afterAddressPicked();
    } else if (filled(data.address)) {
      const keyword = addressCell() && addressCell().querySelector('input[name="keyword"]');
      if (keyword) {
        setNative(keyword, data.address);
        if (keyword.value === String(data.address)) output.applied++;
      }
      await pickAddress();
    }

    // ③ 면적 — 평/㎡ 두 칸이 짝이다. ㎡ 칸에 넣으면 다방이 평을 계산한다. 단지는 평형으로 받았다.
    if (!complexProperty) {
      const sizeCell = () => cellOf('room_info', '매물 크기');
      const areaInput = (heading, name) => () => {
        const group = groupOf(sizeCell(), heading);
        return group ? group.querySelectorAll('input[name="' + name + '"]')[1] : null;
      };
      fill('exclusiveArea', areaInput('전용면적', 'room'), data.exclusiveArea);
      fill('supplyArea', areaInput('공급면적(선택)', 'supply'), data.supplyArea);
    }

    // ④ 건축물 용도·승인
    const pick = (section, label, selector, index = 0) => () => {
      const cell = cellOf(section, label);
      return cell ? cell.querySelectorAll(selector)[index] : null;
    };
    await select('buildingUse', pick('room_info', '건축물용도', 'select'), data.buildingUse);
    await select('approvalDateType', pick('room_info', '건축물승인', 'select'), '사용승인일');
    // 실물은 넣은 날짜를 제 형식으로 고쳐 되돌려 준다 — 숫자만 같으면 들어간 것이다.
    fill('approvalDate', pick('room_info', '건축물승인', 'input[type="text"]'),
      data.approvalDate, v => String(v).replace(/-/g, ''), sameDigits);

    // ⑤ 방 정보 — 방 수를 넣어야 방 거실 형태·방 특징이 켜진다. 방 거실 형태는 방이 하나일 때만 묻는다.
    const roomGroup = heading => () => groupOf(cellOf('room_info', '방 정보'), heading);
    const rooms = Math.max(1, parseInt(String(data.rooms || '1'), 10) || 1);
    fill('rooms', () => {
      const group = roomGroup('방 수')();
      return group ? group.querySelector('input') : null;
    }, String(rooms));
    await sleep(REACT);
    if (rooms === 1) {
      const living = data.structure === '분리형' ? '분리형' : data.structure === '오픈형' ? '오픈형'
        : ({'오픈형 원룸': '오픈형', '분리형 원룸': '분리형'})[data.roomLayout] || null;
      if (living) await choose('roomLayout', roomGroup('방 거실 형태'), living);
      else miss('roomLayout', '방이 하나면 다방은 오픈형·분리형을 꼭 고르게 합니다. 통합 폼의 구조를 확인해 주세요.');
    }
    const features = roomGroup('방 특징(선택)');
    for (const [label, wanted] of [
      ['신축', (data.roomFeatures || []).includes('신축')],
      ['큰길가', (data.roomFeatures || []).includes('큰길가')],
      ['반려동물', data.petAllowed === '가능'],
    ]) {
      const box = () => labelInput(features(), label);
      if (!box()) continue;
      if (box().checked !== wanted) await toggle('roomFeatures.' + label, box, wanted, label);
    }

    // ⑥ 거래 종류 — 고르면 가격 정보 행과 LH 행이 다시 그려진다. 다 그려진 뒤에 넣는다.
    const tradeCell = () => cellOf('trade_info', '거래 종류');
    await choose('trade', tradeCell, data.trade);
    const price = name => () => {
      const cell = cellOf('trade_info', '가격 정보');
      return cell ? cell.querySelector('input[name="' + name + '"]') : null;
    };
    if (filled(data.trade)) {
      await waitUntil(() => data.trade === '월세' ? price('price')() : price('deposit')(), 3000);
    }
    if (data.trade === '매매') fill('salePrice', price('deposit'), data.salePrice);
    else {
      fill('deposit', price('deposit'), data.deposit);
      if (data.trade === '월세') fill('monthlyRent', price('price'), data.monthlyRent);
    }
    // 단기임대 — 월세에서만 켜지고, 켜면 계약기간(개월)과 협의 가능 여부를 꼭 고르게 한다.
    if (data.trade === '월세') {
      const shortBox = () => labelInput(tradeCell(), '단기임대');
      if (shortBox() && shortBox().checked !== (data.shortTerm === true)) {
        await toggle('shortTerm', shortBox, data.shortTerm === true, '단기임대');
      }
      if (data.shortTerm === true) {
        await waitUntil(() => document.querySelector('#trade_info select[name="shortLeaseMonth"]'), 2500);
        await selectValue('shortTermMonths', () => document.querySelector('#trade_info select[name="shortLeaseMonth"]'), String(parseInt(data.shortTermMonths, 10)));
        await selectValue('shortTermNegotiation', () => document.querySelector('#trade_info select[name="shortLeaseMonthNegotiationType"]'),
          data.shortTermNegotiation === '이상 협의가능' ? 'OVER' : 'UNDER');
      }
    }

    // ⑦ 융자금
    const loanSelect = pick('trade_info', '융자금 여부', 'select');
    const loanCode = {'없음': 'NOT_EXIST', '시세 30% 미만': 'THIRTY_UNDER', '시세 30% 이상': 'THIRTY_OVER'}[data.loan];
    if (await selectValue('loan', loanSelect, loanCode) && loanCode !== 'NOT_EXIST' && filled(data.loanAmount)) {
      const amount = pick('trade_info', '융자금 여부', 'input[type="text"]');
      if (await ready(amount, 1500)) fill('loanAmount', amount, digits(data.loanAmount));
    }

    // ⑧ LH — 전세·월세에서만 나온다. 「가능」이면 임대인 동의 체크(필수)가 붙는데, 그것은 동의라 사람이 한다.
    if (filled(data.lh) && data.trade !== '매매') {
      const lhCell = () => cellOf('trade_info', 'LH');
      if (await waitUntil(lhCell, 2000)) {
        await choose('lh', lhCell, data.lh);
        if (data.lh === '가능') note('LH 전세임대 가능: 다방은 「임대인의 동의를 받은 매물」 확인 체크(필수)를 요구합니다. 동의 항목이라 직접 확인하고 체크해 주세요.');
      } else note('LH 전세임대 여부: 이 거래 종류에서는 다방 폼에 LH 항목이 나타나지 않습니다.');
    }

    // ⑨ 관리비
    const feeSelect = pick('trade_info', '관리비', 'select');
    await selectValue('noManagementFee', feeSelect, data.noManagementFee === true ? 'false' : 'true');
    if (data.noManagementFee !== true) await completeFeeModal();

    // ⑩ 입주
    const moveIn = () => cellOf('trade_info', '입주 가능 일자');
    if (data.moveInType === '날짜 지정' && filled(data.moveInDate)) {
      await choose('moveInType', moveIn, '일자 선택');
      await sleep(REACT);
      fill('moveInDate', pick('trade_info', '입주 가능 일자', 'input[type="text"]'), data.moveInDate, v => String(v).replace(/-/g, ''), sameDigits);
    } else {
      await choose('moveInType', moveIn, '즉시 입주');
    }
    const negotiable = () => labelInput(moveIn(), '협의 가능할 경우');
    if (negotiable() && negotiable().checked !== (data.moveInNegotiable === true)) {
      await toggle('moveInNegotiable', negotiable, data.moveInNegotiable === true, '협의 가능할 경우');
    }

    // ⑪ 층 수 — 전체 층을 고르면 해당 층 목록이 다시 만들어진다. 반지층 -1 · 옥탑 0.
    await selectValue('floorAll', pick('additional_info', '층 수', 'select', 0), String(parseInt(data.floorAll, 10)));
    const floorCode = data.floor === '반지하' ? '-1' : data.floor === '옥탑' ? '0' : String(parseInt(data.floor, 10));
    await waitUntil(() => { const s = pick('additional_info', '층 수', 'select', 1)(); return s && [...s.options].some(o => o.value === floorCode); }, 2500);
    await selectValue('floor', pick('additional_info', '층 수', 'select', 1), floorCode);
    const bandBox = pick('additional_info', '층 수', 'input[type="checkbox"]');
    if (bandBox()) {
      if (bandBox().checked !== (data.floorPrivate === true)) {
        await toggle('floorPrivate', bandBox, data.floorPrivate === true, '저/중/고 표기');
      }
      if (data.floorPrivate === true) {
        const band = {'저층': 'LOW', '중층': 'MIDDLE', '고층': 'HIGH'}[data.floorBand];
        await waitUntil(() => { const s = pick('additional_info', '층 수', 'select', 2)(); return s && !s.disabled; }, 2000);
        await selectValue('floorBand', pick('additional_info', '층 수', 'select', 2), band);
      }
    }

    // ⑫ 방향
    const base = {'거실 기준': 'LIVING_ROOM', '안방 기준': 'MAIN_ROOM'}[data.directionBase];
    await selectValue('directionBase', pick('additional_info', '방향 기준', 'select', 0), base);
    await select('direction', pick('additional_info', '방향 기준', 'select', 1), data.direction);

    // ⑬ 욕실·엘리베이터 — 같은 줄의 다른 칸이다.
    fill('bathrooms', pick('additional_info', '욕실 수', 'input'), String(parseInt(data.bathrooms, 10)));
    await choose('elevator', () => cellOf('additional_info', '엘리베이터'), data.elevator);

    // ⑭ 주차 — 오피스텔·아파트는 세대당 주차 수도 필수다.
    const parkingOk = await selectValue('parking', pick('additional_info', '주차 가능 여부', 'select'), data.parking === '주차 가능' ? 'true' : 'false');
    if (parkingOk && data.parking === '주차 가능') {
      const count = () => { const cell = cellOf('additional_info', '주차 가능 여부'); return cell ? cell.querySelector('input[placeholder*="총 가능 주차수"]') || cell.querySelector('input[type="text"]') : null; };
      if (await ready(count)) fill('parkingCount', count, data.parkingCount);
      else miss('parkingCount', '주차 대수 입력란이 켜지지 않았습니다.');
      const average = () => { const cell = cellOf('additional_info', '주차 가능 여부'); return cell ? cell.querySelector('input[placeholder*="세대당"]') : null; };
      if (average()) {
        if (filled(data.parkingPerHousehold)) fill('parkingPerHousehold', average, data.parkingPerHousehold);
        else miss('parkingPerHousehold', '다방은 오피스텔·아파트의 세대당 주차 수를 필수로 받습니다.');
      } else if (filled(data.parkingPerHousehold)) note('세대당 주차 대수: 다방은 주택/빌라에서 총 주차 대수만 받습니다.');
    }

    // ⑮ 복층 · 현관 · 세대
    await choose('roomLayout.duplex', () => cellOf('additional_info', '복층 여부'), data.duplex === '복층' || data.roomLayout === '복층형 원룸' ? '복층' : '단층');
    if (filled(data.entranceType)) await select('entranceType', pick('additional_info', '현관 유형', 'select'), data.entranceType);
    if (filled(data.householdCount)) {
      const household = pick('additional_info', '세대(가구수)', 'input');
      if (household()) fill('householdCount', household, digits(data.householdCount));
    }

    // ⑯ 시설 — 켤 것은 켜고, 끌 것은 끈다.
    if (filled(data.heating)) await choose('heating', () => cellOf('facility_info', '난방 시설'), data.heating);
    const setChecks = async (section, wantedLabels, known) => {
      const cell = () => cellOf('facility_info', section);
      if (!cell()) return;
      for (const label of known) {
        const box = () => labelInput(cell(), label);
        if (!box()) continue;
        const wanted = wantedLabels.includes(label);
        if (box().checked !== wanted) await toggle('facility.' + label, box, wanted, label);
        else if (wanted) ok();
      }
    };
    await setChecks('냉방 시설', (data.appliances || []).includes('에어컨') ? (data.airconType || []) : [], ['벽걸이형', '스탠드형', '천장형']);
    const LIVING = ['침대', '책상', '옷장', '식탁', '쇼파', '신발장', '냉장고', '세탁기', '건조기', '샤워부스', '욕조', '비데', '싱크대', '식기세척기', '가스레인지', '인덕션', '전자레인지', '가스오븐', 'TV', '붙박이장'];
    await setChecks('생활 시설', data.appliances || [], LIVING);
    const skipped = (data.appliances || []).filter(item => item !== '에어컨' && !LIVING.includes(item));
    if (skipped.length) note('가전·가구 ' + skipped.join(', ') + ': 다방 생활 시설에 없어 직방에만 들어갑니다.');
    const facilities = (data.facilities || []).map(item => ({'공동현관보안': '현관보안', '베란다/발코니': '베란다'})[item] || item);
    await setChecks('보안 시설', facilities, ['경비원', '비디오폰', '인터폰', '카드키', 'CCTV', '사설경비', '현관보안', '방범창']);
    await setChecks('기타 시설', facilities, ['화재경보기', '베란다', '테라스', '마당', '무인택배함']);
    if ((data.facilities || []).includes('전기차 충전시설')) note('전기차 충전시설: 다방 시설 정보에 없어 직방에만 들어갑니다.');

    // ⑰ 글 — 제목 칸은 다방이 허락하지 않은 글자가 섞이면 값을 통째로 받지 않는다.
    fill('title', pick('detail_info', '제목', 'input,textarea'), data.title);
    fill('description', pick('detail_info', '상세설명', 'textarea,input'), data.description);
    if (filled(data.privateMemo)) fill('privateMemo', pick('detail_info', '비공개 메모', 'textarea,input'), data.privateMemo);

    // ⑱ 연락처 — 비워 두면 대표 연락처로 들어간다. 첫 연락처를 그대로 고른다.
    const contact = () => { const cell = cellOf('agent_contact_info', '연락처'); return cell ? cell.querySelector('select') : null; };
    if (contact() && !contact().value) {
      const first = [...contact().options].find(o => o.value !== '');
      if (first) await selectValue('agentContact', contact, first.value);
    }

    if (filled(data.loanAvailable)) note('전세자금대출 가능 여부: 다방 등록 폼에 대응 입력란이 없어 직방에만 들어갑니다.');
    if (filled(data.eContract)) note('전자계약 가능 여부: 다방 등록 폼에 대응 입력란이 없어 직방에만 들어갑니다.');
    if (filled(data.ownerPhone)) note('집주인 연락처: 다방 등록 폼에 집주인 연락처 입력란이 없어 직방에만 들어갑니다.');
    // 실물 확인 2026-09-21: 다방 폼의 일곱 섹션 어디에도 위반건축물·중개 의뢰 방법 줄이 없다.
    if (filled(data.violation) && data.violation !== '해당 없음') {
      note('위반건축물 여부: 다방 등록 폼에 대응 입력란이 없어 직방에만 들어갑니다. '
        + '다방 광고에도 알려야 한다면 상세 설명에 적어 주세요.');
    }
    if (filled(data.mediationMethod)) note('중개 의뢰를 받은 방법: 다방 등록 폼에 대응 입력란이 없어 직방에만 들어갑니다.');
    for (const message of (window.__flrPostcode ? window.__flrPostcode.notes : [])) note(message);

    // ⑲ 마지막 대조 — 주소(②)나 그 밖의 무엇이 폼을 되돌렸다면 여기서 드러나고,
    // 여기서 다시 채워진다. 「검증」 숫자도 여기서 본 것으로 고쳐 적는다.
    await reconcile();
    settled = true;
  } catch (error) {
    output.violations.push('다방 자동 입력 오류: ' + String(error && error.stack ? error.stack : error));
  }
  /* 여기서부터 폼은 조용하다 — **사진은 이제 붙여도 된다.**
   *
   * 오류로 빠져나온 길에도 세운다. 반쯤 채워진 폼이라도 사진은 붙는 편이 낫고,
   * 세우지 않으면 [MirrorSession._adapterDone] 이 3분을 기다린 뒤에야 움직인다. */
  window.__flrFormDone = true;
  for (const violation of (window.__FLR_VIOLATIONS__ || [])) {
    const detail = typeof violation === 'string' ? violation
      : [violation.kind, violation.target, violation.detail].filter(Boolean).join(' · ');
    output.violations.push('깐깐이 위반: ' + detail);
  }
  // 「임시저장」·「등록 완료」·#submit 은 어떤 경우에도 누르지 않는다. 이 어댑터는 채우기만 한다.
  publish();
  setTimeout(() => auto(false), 1500);
})();
''';

String daangnInjectionScript(String payload) =>
    '''
(async () => {
  const data = $payload;
  window.__flrFormDone = false;
$_daangnAdapterBody''';

const _daangnAdapterBody = r'''
  const output = {applied: 0, missing: [], unsupported: [], verified: 0, violations: []};
  const publish = () => window.ListingResult.postMessage(JSON.stringify(output));
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  // 깐깐이(mirror 의 엄격 층)는 click/input/change 를 삼켰다가 0.3초 뒤에 다시 쏜다.
  // 그래서 조작 하나하나의 반응을 기다려야 한다.
  const REACT = 420;
  const text = el => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
  const norm = value => String(value === undefined || value === null ? '' : value).replace(/\s+/g, '');
  const filled = value => value !== undefined && value !== null && value !== '' &&
    !(Array.isArray(value) && value.length === 0);
  const note = message => { if (!output.unsupported.includes(message)) output.unsupported.push(message); };
  const miss = (key, why) => output.missing.push(key + ': ' + why);
  const ok = () => { output.applied++; output.verified++; };
  const waitUntil = async (predicate, timeout = 2600) => {
    const until = Date.now() + timeout;
    for (;;) {
      const value = predicate();
      if (value) return value;
      if (Date.now() >= until) return null;
      await sleep(60);
    }
  };

  /* ── 자리 찾기 ──────────────────────────────────────────────
   * 당근은 SEED 디자인 시스템이다. 줄 이름은 줄 첫 칸의 굵은 글씨(span.t4-bold)이고, 줄은
   * div.flex.items-start.gap-x3 이다. 미러는 반응할 때마다 묶음을 틀에서 새로 만들어 갈아 끼우므로
   * 붙잡아 둔 노드는 곧 유령이 된다 — 자리는 늘 함수로 다시 찾는다. */
  const root = () => document.getElementById('style-root') || document.body;
  const rowOf = label => {
    const span = [...root().querySelectorAll('span.t4-bold')].find(s => text(s) === label);
    return span ? span.closest('div.flex.items-start.gap-x3') : null;
  };
  const inRow = (label, selector) => () => {
    const row = rowOf(label);
    return row ? row.querySelector(selector) : null;
  };
  const labelIn = (scope, word) => scope
    ? [...scope.querySelectorAll('label')].find(label => norm(text(label)) === norm(word)) || null
    : null;
  const at = target => { try { return typeof target === 'function' ? target() : target; } catch (_) { return null; } };
  const ready = (locate, timeout) => waitUntil(() => {
    const el = at(locate);
    return el && !el.disabled ? el : null;
  }, timeout);
  // SEED 는 켜진 체크박스·라디오의 라벨에 data-checked 를 붙인다.
  const isOn = label => !!label && label.hasAttribute('data-checked');

  /* ── 조작 ───────────────────────────────────────────────────
   * 깐깐이는 ① el.value = v 로 넣은 값을 「폼이 모르는 대입」으로 되돌리고
   * ② 앞에 pointerdown 이 없는 로봇 click 을 버린다. 둘 다 피해서 넣는다. */
  const valueSetter = el => Object.getOwnPropertyDescriptor(
    el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype,
    'value').set;
  const setNative = (el, value) => {
    if (!el) return false;
    el.focus && el.focus();
    valueSetter(el).call(el, String(value));
    ['input', 'change'].forEach(type => el.dispatchEvent(new Event(type, {bubbles: true})));
    el.blur && el.blur();
    return true;
  };
  const press = el => {
    if (!el) return false;
    const init = {bubbles: true, cancelable: true, composed: true, view: window};
    el.dispatchEvent(new PointerEvent('pointerdown', init));
    el.dispatchEvent(new MouseEvent('mousedown', init));
    el.dispatchEvent(new MouseEvent('mouseup', init));
    el.dispatchEvent(new MouseEvent('click', init));
    return true;
  };

  const fill = (key, locate, value, transform = v => v) => {
    if (!filled(value)) return false;
    const el = at(locate);
    if (!el) { miss(key, '당근 폼에서 입력란을 찾지 못했습니다.'); return false; }
    if (el.disabled) { miss(key, '입력란이 잠겨 있어 값을 넣지 못했습니다.'); return false; }
    const wanted = String(transform(value));
    setNative(el, wanted);
    const again = at(locate) || el;
    if (String(again.value) === wanted) { ok(); return true; }
    output.applied++;
    miss(key, '값을 넣었지만 폼에서 같은 값을 다시 읽지 못했습니다.');
    return false;
  };

  // 체크박스·라디오는 라벨 안의 숨은 input 을 누른다. 확인은 input.checked 가 아니라 라벨의
  // data-checked 로 한다 — 대출·반려동물·주차 라디오는 셋 다 name=requiredOptions 라서
  // 브라우저 눈에는 한 묶음이고, input.checked 는 셋 중 하나만 참이 된다.
  const setToggle = async (key, locateLabel, wanted, what) => {
    const label = await waitUntil(() => {
      const found = at(locateLabel);
      const input = found && found.querySelector('input');
      return input && !input.disabled ? found : null;
    }, 1500);
    if (!label) {
      miss(key, at(locateLabel) ? '「' + what + '」이(가) 잠겨 있어 고르지 못했습니다.'
        : '당근 폼에서 「' + what + '」을(를) 찾지 못했습니다.');
      return false;
    }
    if (isOn(label) === wanted) { ok(); return true; }
    press(label.querySelector('input'));
    if (await waitUntil(() => { const now = at(locateLabel); return now && isOn(now) === wanted; }, 2000)) {
      ok(); await sleep(150); return true;
    }
    output.applied++;
    miss(key, '「' + what + '」을(를) 눌렀지만 선택 상태가 바뀌지 않았습니다.');
    return false;
  };
  const checkbox = (key, rowLabel, word, wanted = true) =>
    setToggle(key, () => labelIn(rowOf(rowLabel), word), wanted, word);
  const radio = (key, rowLabel, value, what) => setToggle(key, () => {
    const row = rowOf(rowLabel);
    const input = row && row.querySelector('input[type="radio"][value="' + value + '"]');
    return input ? input.closest('label') : null;
  }, true, what || value);

  // 선택 상자(매물 종류·건축물 용도·방향)는 button[name] 과, 누르면 바로 아래 붙는 목록이다.
  // native select 가 없어 표시된 값(.seed-input-button__value)으로 확인한다.
  const selectButton = name => document.querySelector('button[name="' + name + '"]');
  const shownValue = name => {
    const button = selectButton(name);
    const value = button && button.parentElement.querySelector('.seed-input-button__value');
    return value ? text(value) : '';
  };
  const choose = async (key, name, word) => {
    if (!filled(word)) return false;
    if (!selectButton(name)) { miss(key, '당근 폼에서 선택 상자를 찾지 못했습니다.'); return false; }
    if (norm(shownValue(name)) === norm(word)) { ok(); return true; }
    const options = () => {
      const holder = selectButton(name) && selectButton(name).closest('.relative');
      return holder ? [...holder.querySelectorAll('div.absolute button')] : [];
    };
    press(selectButton(name));
    const list = await waitUntil(() => options().length ? options() : null, 2000);
    if (!list) { miss(key, '선택 목록이 열리지 않았습니다.'); return false; }
    const option = list.find(item => norm(text(item)) === norm(word));
    if (!option) {
      press(selectButton(name));
      await sleep(REACT);
      note(key + ' ' + word + ': 당근 선택 목록에 대응하는 항목이 없습니다.');
      return false;
    }
    const label = text(option);
    press(option);
    if (await waitUntil(() => shownValue(name) === label && !options().length, 2000)) {
      ok(); await sleep(150); return true;
    }
    output.applied++;
    miss(key, '고른 뒤 선택 상자에서 같은 값을 다시 읽지 못했습니다.');
    return false;
  };

  /* ── 주소 ───────────────────────────────────────────────────
   * 당근 미러의 주소 검색은 카카오가 아니라 같은 출처의 /api/juso 다. 주소 칸 → 「매물 주소」 창 →
   * 치는 동안 검색(0.5초 뒤) → 결과 줄(우편번호 · 도로명 · 지번 · 「선택」) → 상세 주소 → 「입력하기」.
   * 「입력하기」 뒤에는 건축물대장이 용도·엘리베이터·사용승인일·최고층을 공공데이터로 덮어쓰고
   * 집주인 전화번호 칸이 켜진다. 그래서 주소를 가장 먼저 넣고, 나머지 값은 그 뒤에 넣는다. */
  const SIDO = [
    ['서울특별시', '서울'], ['부산광역시', '부산'], ['대구광역시', '대구'], ['인천광역시', '인천'],
    ['광주광역시', '광주'], ['대전광역시', '대전'], ['울산광역시', '울산'], ['세종특별자치시', '세종'],
    ['경기도', '경기'], ['강원특별자치도', '강원'], ['강원도', '강원'], ['충청북도', '충북'],
    ['충청남도', '충남'], ['전북특별자치도', '전북'], ['전라북도', '전북'], ['전라남도', '전남'],
    ['경상북도', '경북'], ['경상남도', '경남'], ['제주특별자치도', '제주'], ['제주도', '제주'],
  ];
  const simplify = value => {
    let words = norm(value);
    for (const [full, short] of SIDO) {
      if (words.startsWith(full)) { words = short + words.slice(full.length); break; }
      if (words.startsWith(short)) break;
    }
    return words.replace(/\(.*?\)/g, '');
  };
  const wantedAddress = simplify(data.address);
  const numbersOf = words => (words.match(/\d+(-\d+)?/g) || []);
  const wantedNumbers = numbersOf(wantedAddress);
  const score = candidate => {
    const value = simplify(candidate);
    if (!value) return -1;
    if (value === wantedAddress) return 1000;
    let prefix = 0;
    while (prefix < value.length && prefix < wantedAddress.length && value[prefix] === wantedAddress[prefix]) prefix++;
    let points = prefix * 4;
    const values = numbersOf(value);
    for (const number of wantedNumbers) {
      if (values.includes(number)) points += 60;
      else if (values.some(other => other.split('-')[0] === number.split('-')[0])) points += 20;
    }
    points -= Math.max(0, values.length - wantedNumbers.length) * 15;
    if (value.includes(wantedAddress) || wantedAddress.includes(value)) points += 40;
    return points;
  };

  const dialog = () => document.querySelector('[role="dialog"][aria-modal="true"]');
  const dialogInput = () => { const box = dialog(); return box ? box.querySelector('.seed-field__root input') : null; };
  const dialogButton = word => {
    const box = dialog();
    return box ? [...box.querySelectorAll('button')].find(button => text(button) === word) || null : null;
  };
  const closeDialog = async () => {
    const close = dialog() && dialog().querySelector('button[aria-label="닫기"]');
    if (close) { press(close); await waitUntil(() => !dialog(), 2000); }
  };
  // 당근은 동 입력란이 없다 — 「101동 202호」처럼 합쳐 상세 주소에 넣는다. 단일동이면 호수만.
  const detailAddress = () => {
    const suffix = (value, tail) => { const words = String(value).trim(); return words.endsWith(tail) ? words : words + tail; };
    const dong = data.singleBuilding !== true && filled(data.building) ? suffix(data.building, '동') : '';
    const ho = filled(data.unit) ? suffix(data.unit, '호') : '';
    return [dong, ho].filter(Boolean).join(' ');
  };
  let addressEntered = false;
  let ledgerFilled = false;
  const enterAddress = async () => {
    const opener = selectButton('address');
    if (!opener) {
      miss('address', '주소 칸을 찾지 못했습니다. 이미 입력된 주소가 있으면 「수정하기」로 직접 바꿔 주세요.');
      return;
    }
    press(opener);
    const search = await waitUntil(dialogInput, 3000);
    if (!search) { miss('address', '「매물 주소」 창이 열리지 않았습니다.'); return; }
    setNative(search, data.address);
    const picks = await waitUntil(() => {
      const box = dialog();
      if (!box) return null;
      // 중계에 못 가면 미러는 예시 주소를 보여 준다 — 그것은 고르지 않는다.
      const notice = box.querySelector('[data-mirror-note]');
      if (notice) return {failure: text(notice)};
      const buttons = [...box.querySelectorAll('button')].filter(button => text(button) === '선택');
      if (buttons.length) return {buttons};
      return /검색 결과가 없어요/.test(text(box)) ? {failure: '「' + data.address + '」 검색 결과가 없습니다.'} : null;
    }, 10000);
    if (!picks || picks.failure) {
      miss('address', (picks ? picks.failure : '당근 주소 검색 결과가 10초 안에 오지 않았습니다.') + ' 주소를 직접 검색해 주세요.');
      await closeDialog();
      return;
    }
    // 결과 줄마다 도로명·지번 두 주소 중 더 잘 맞는 쪽으로 점수를 매긴다. 같으면 먼저 나온 줄.
    let best = null;
    for (const button of picks.buttons) {
      const lines = [...button.parentElement.querySelectorAll('.t4-regular')].map(text);
      const points = Math.max(-1, ...lines.map(score));
      if (!best || points > best.points) best = {button, points, road: lines[0] || ''};
    }
    press(best.button);
    const detail = await waitUntil(() => dialogButton('입력하기') && dialogInput(), 4000);
    if (!detail) { miss('address', '주소를 고른 뒤 상세 주소 단계가 열리지 않았습니다.'); await closeDialog(); return; }
    const words = detailAddress();
    if (words) {
      setNative(detail, words);
      if (!(await waitUntil(() => dialogInput() && dialogInput().value === words, 1000))) {
        miss('building', '상세 주소를 넣었지만 다시 읽지 못했습니다.');
      }
      await sleep(REACT);
    }
    const entered = Date.now();
    press(dialogButton('입력하기'));
    const shown = await waitUntil(() => {
      const row = rowOf('주소');
      return row && !row.querySelector('button[name="address"]') && /수정하기/.test(text(row)) ? row : null;
    }, 4000);
    if (!shown) { miss('address', '「입력하기」를 눌렀지만 주소 칸이 바뀌지 않았습니다.'); return; }
    addressEntered = true;
    ok();
    if (words) { output.applied++; output.verified++; }
    note('매물 기본 주소: 당근 주소 검색에서 「' + best.road + '」를 골랐고 상세 주소는 「' + (words || '없음') + '」로 넣었습니다.');
    await waitUntil(() => !dialog(), 3000);
    // 건축물대장은 누른 뒤 0.64~0.94초(+조회 시간)에 채워지고 알림을 띄운다. 없으면 아무것도 안 채운다.
    ledgerFilled = !!(await waitUntil(() => document.querySelector('[data-mirror-note="ledger"]'),
      Math.max(0, 4000 - (Date.now() - entered))));
    if (ledgerFilled) await sleep(REACT);
  };

  /* ── 변환표 ─────────────────────────────────────────────── */
  const SALES_TYPE = {
    '오픈형 원룸': '오픈형 원룸', '분리형 원룸': '분리형 원룸', '복층형 원룸': '오픈형 원룸',
    '투룸 빌라': '빌라(투룸 이상)', '쓰리룸 이상 빌라': '빌라(투룸 이상)',
    '오피스텔 원룸형': '오피스텔', '오피스텔 분리/투룸형': '오피스텔', '아파트': '아파트',
    '단독주택': '단독/전원주택', '다가구주택': '단독/전원주택', '상가주택': '단독/전원주택',
    '상가 점포': '상가', '사무실': '사무실', '일반 건물': '건물', '공장/창고': '공장/창고', '토지': '토지',
  };
  // 띄어쓰기만 다른 것은 norm 으로 맞는다. 이름이 다른 둘만 적는다.
  const USAGE_ALIAS = {'교정 및 군사시설': '교정시설', '장례시설': '장례식장'};
  const usageWord = USAGE_ALIAS[data.buildingUse] || data.buildingUse;
  const TRISTATE = {'가능': 'YES', '불가능': 'NO', '확인 필요': 'DONT_KNOW'};
  const APPLIANCES = {
    '에어컨': '에어컨', '세탁기': '세탁기', '냉장고': '냉장고', '전자레인지': '전자렌지',
    '가스레인지': '가스렌지', '인덕션': '인덕션', '침대': '침대',
  };
  const PERIOD = {
    '직전월 관리비 기준': 'LAST_MONTH', '3개월 평균 관리비': 'AVG_3_MONTHS',
    '1년 평균 관리비': 'AVG_1_YEAR', '기타 직접 입력': 'ETC',
  };
  const INCLUDES = {
    '청소비': '공용', '승강기유지비': '공용', '주차비': '공용', '경비비': '공용',
    '전기료': '전기료', '수도료': '수도료', '가스사용료': '가스비', '난방비': '난방비',
    '인터넷': '인터넷비', '유선TV': 'TV', '기타': '기타',
  };
  // 정액 관리비(10만원 이상)의 항목별 줄 이름
  const ITEM_ROWS = {
    '전기료': '전기료', '수도료': '수도료', '가스사용료': '가스비', '난방비': '난방비',
    '인터넷': '인터넷비', '유선TV': 'TV', '기타': '기타',
  };
  const ETC_BASIS = {
    '관리규약에 따라 부과': 'BY_REGULATIONS',
    '면적 및 세대별 부과': 'COMMON_BY_AREA_OR_UNITS_AND_USAGE_BY_METER',
    '전체 세대 균등 부과': 'SHARED_BY_UNITS',
    '계량기별 실비 부과': 'BY_INDIVIDUAL_METER',
    '의뢰인 미고지': 'ESTIMATED_BY_AGENT_DUE_TO_NO_OWNER_INFO',
    '기타': 'ETC',
  };
  const UNAVAILABLE_REASON = {
    '단독주택 사유': 'SINGLE_HOUSE', '상가 및 상가주택 사유': 'STORE_NOT_OFFICETEL', '미등기 건물 사유': 'UNREGISTERED_OR_NEW',
  };
  const UNDER_10 = '10만원 미만 혹은 의뢰인이 세부 내역 미제공';

  /* ── 관리비 ─────────────────────────────────────────────────
   * 부과 방식(정액 관리비 · 기타 부과 · 확인 불가)을 고를 때마다 아래 묶음이 통째로 바뀐다.
   * 정액 관리비 = 부과 기준 + 항목별(공용·전기료…기타) · 「10만원 미만」 = 부과 기준 + 총 관리비 + 관리비에 포함
   * 기타 부과 = 그것 + 관리비 세부 타입 · 확인 불가 = 확인 불가 사유 */
  const feeMode = async (key, value, what, shows) => {
    if (!(await radio(key, '부과 방식', value, what))) return false;
    if (await waitUntil(() => rowOf(shows), 2500)) return true;
    miss(key, '「' + what + '」을(를) 골랐지만 아래 칸(' + shows + ')이 나타나지 않았습니다.');
    return false;
  };
  const feePeriod = async () => {
    const value = PERIOD[data.manageBasis];
    if (!value) {
      note('관리비 부과 기준: 통합 폼 값이 없어 당근 「부과 기준」(필수)을 비워 두었습니다. 화면에서 골라 주세요.');
      return;
    }
    await radio('manageBasis', '부과 기준', value, data.manageBasis);
    if (value === 'ETC') note('관리비 부과 기준 기타: 당근은 기준 내용을 따로 받지만 통합 폼에는 내용이 없어 화면에서 적어 주세요.');
  };
  const feeTotal = () => {
    if (filled(data.managementFee)) fill('managementFee', inRow('총 관리비', 'input[name="totalManageCost"]'), data.managementFee);
    else note('총 관리비: 통합 폼에 금액이 없어 당근 「총 관리비」(필수)를 비워 두었습니다.');
  };
  const feeIncludes = async () => {
    const seen = new Set();
    for (const item of (data.manageIncludes || [])) {
      const target = INCLUDES[item];
      if (!target) { note('관리비 포함 항목 ' + item + ': 당근 「관리비에 포함」에 대응 항목이 없습니다.'); continue; }
      if (seen.has(target)) continue;
      seen.add(target);
      await checkbox('manageIncludes.' + item, '관리비에 포함', target);
    }
    if (seen.has('기타')) note('관리비에 포함 기타: 당근은 기타 항목 이름을 따로 받아 화면에서 적어 주세요.');
    if (!seen.size) note('관리비에 포함: 통합 폼에 포함 항목이 없어 당근 「관리비에 포함」(필수)을 비워 두었습니다.');
  };
  const applyFee = async () => {
    if (data.noManagementFee === true) {
      if (await feeMode('noManagementFee', 'FIXED', '정액 관리비', '부과 기준') &&
          await checkbox('noManagementFee', '부과 방식', UNDER_10) &&
          await waitUntil(() => rowOf('총 관리비'), 2500)) {
        fill('noManagementFee', inRow('총 관리비', 'input[name="totalManageCost"]'), '0');
        note('관리비 없음: 당근에는 「관리비 없음」이 없어 정액 관리비 · 10만원 미만 · 총 관리비 0만원으로 넣었습니다. 「부과 기준」과 「관리비에 포함」(필수)은 화면에서 골라 주세요.');
      }
      return;
    }
    if (data.manageMethod === '정액 관리비') {
      if (!(await feeMode('manageMethod', 'FIXED', '정액 관리비', '부과 기준'))) return;
      const amount = Number(data.managementFee);
      if (filled(data.managementFee) && !Number.isNaN(amount) && amount < 10) {
        if (!(await checkbox('managementFee.under10', '부과 방식', UNDER_10))) return;
        if (!(await waitUntil(() => rowOf('총 관리비'), 2500))) {
          miss('managementFee', '「10만원 미만」을 켰지만 총 관리비 칸이 나타나지 않았습니다.');
          return;
        }
        await feePeriod();
        feeTotal();
        await feeIncludes();
        return;
      }
      // 10만원 이상 — 당근은 공용 금액과 항목별 부과 방식(쓴 만큼·정액)을 받는다.
      await feePeriod();
      const details = data.manageDetail || {};
      for (const [fee, row] of Object.entries(ITEM_ROWS)) {
        const way = details[fee];
        const value = way === '정액 부과' ? 'FIXED' : way === '실비 부과' ? 'USED'
          : way === '해당 없음' && fee === '기타' ? 'NONE' : null;
        if (value) {
          await radio('manageDetail.' + fee, row, value, row + ' ' + (value === 'FIXED' ? '정액' : value === 'USED' ? '쓴 만큼' : '없음'));
          if (fee === '기타' && value !== 'NONE') note('관리비 기타 항목: 당근은 기타 항목 이름을 따로 받아 화면에서 적어 주세요.');
        } else if (way === '해당 없음') {
          note('관리비 ' + row + ' 해당 없음: 당근의 이 항목에는 「쓴 만큼」·「정액」만 있어 기본값 「쓴 만큼」을 그대로 두었습니다.');
        } else {
          note('관리비 ' + row + ': 통합 폼에 비목별 부과 방식이 없어 당근 기본값을 그대로 두었습니다.');
        }
      }
      note('공용 관리비 금액: 당근 정액 관리비(10만원 이상)는 공용 관리비 금액(필수)을 따로 받지만 통합 폼에는 총액' +
        (filled(data.managementFee) ? '(' + data.managementFee + '만원)' : '') + '만 있어 비워 두었습니다. 화면에서 직접 넣어 주세요.');
      const fixed = Object.keys(ITEM_ROWS).filter(fee => details[fee] === '정액 부과').map(fee => ITEM_ROWS[fee]);
      if (fixed.length) note('정액 항목 금액(' + fixed.join('·') + '): 당근은 「정액」 항목마다 금액을 받지만 통합 폼에는 항목별 금액이 없어 비워 두었습니다.');
      if (filled(data.manageIncludes)) note('관리비 포함 항목: 당근 정액 관리비(10만원 이상)는 포함 항목 대신 항목별 부과 방식을 받아 체크하지 않았습니다.');
      return;
    }
    if (data.manageMethod === '기타 부과') {
      if (!(await feeMode('manageMethod', 'ETC', '기타 부과', '관리비 세부 타입(실비 근거)'))) return;
      await feePeriod();
      feeTotal();
      await feeIncludes();
      const basis = ETC_BASIS[data.otherFeeReason];
      if (!basis) { note('관리비 세부 타입: 통합 폼에 기타 부과 사유가 없어 당근 「관리비 세부 타입」(필수)을 비워 두었습니다.'); return; }
      await radio('otherFeeReason', '관리비 세부 타입(실비 근거)', basis, data.otherFeeReason);
      if (basis === 'ETC') note('관리비 세부 타입 기타: 당근은 직접 입력 내용을 받지만 통합 폼에는 내용이 없어 화면에서 적어 주세요.');
      return;
    }
    if (data.manageMethod === '확인 불가') {
      if (!(await feeMode('manageMethod', 'UNAVAILABLE', '확인 불가', '확인 불가 사유'))) return;
      const reason = UNAVAILABLE_REASON[data.unknownFeeReason];
      if (reason) await radio('unknownFeeReason', '확인 불가 사유', reason, data.unknownFeeReason);
      else note('확인 불가 사유: 통합 폼 값이 없어 당근 「확인 불가 사유」(필수)를 비워 두었습니다.');
    }
  };

  // 건축물대장이 늦게 도착하면 넣은 값을 다시 덮어쓸 수 있다. 끝에서 한 번 더 대조한다.
  const reconcileLedger = async () => {
    const counts = {applied: output.applied, verified: output.verified};
    const fixed = [];
    if (filled(usageWord) && norm(shownValue('buildingUsage')) !== norm(usageWord)) {
      await choose('buildingUse', 'buildingUsage', usageWord);
      fixed.push('건축물 용도');
    }
    const date = inRow('사용승인일', 'input[name="buildingApprovalDate"]');
    if (filled(data.approvalDate) && at(date) && at(date).value !== String(data.approvalDate)) {
      fill('approvalDate', date, data.approvalDate);
      fixed.push('사용승인일');
    }
    const top = inRow('층 정보', 'input[name="topFloor"]');
    if (filled(data.floorAll) && at(top) && at(top).value !== String(data.floorAll)) {
      fill('floorAll', top, data.floorAll);
      fixed.push('전체 층');
    }
    const elevator = labelIn(rowOf('매물 특징'), '엘리베이터');
    if ((data.elevator === '있음' || data.elevator === '없음') && elevator && isOn(elevator) !== (data.elevator === '있음')) {
      await checkbox('elevator', '매물 특징', '엘리베이터', data.elevator === '있음');
      fixed.push('엘리베이터');
    }
    Object.assign(output, counts);
    if (fixed.length) note('건축물대장: 늦게 들어온 공공데이터가 ' + fixed.join('·') + '을(를) 바꿔 통합 폼 값으로 다시 맞췄습니다.');
  };

  try {
    // ① 주소 — 건축물대장이 덮어쓰는 칸보다 먼저, 집주인 전화번호 칸보다 먼저.
    if (filled(data.address)) await enterAddress();
    if (ledgerFilled) {
      note('건축물대장: 당근이 주소 입력 뒤 공공데이터로 채운 건축물 용도·사용승인일·전체 층·엘리베이터를 통합 폼 값으로 다시 맞췄습니다.');
    }

    // ② 매물 종류 — 아파트면 층 정보 줄이 「저/중/고로 표시」가 있는 틀로 바뀐다. 층보다 먼저.
    const salesType = SALES_TYPE[data.propertyType];
    if (salesType) await choose('propertyType', 'salesType', salesType);
    else if (filled(data.propertyType)) note('매물 대분류 ' + data.propertyType + ': 당근 매물 종류에 대응하는 항목이 없습니다.');
    if (data.propertyType === '복층형 원룸') note('매물 대분류 복층형 원룸: 당근에는 복층 매물 종류가 없어 「오픈형 원룸」과 매물 특징 「복층」으로 넣었습니다.');
    if (data.propertyType === '다가구주택' || data.propertyType === '상가주택') {
      note('매물 대분류 ' + data.propertyType + ': 당근은 「단독/전원주택」으로만 받습니다.');
    }

    // ③ 건축물 용도·면적
    if (await choose('buildingUse', 'buildingUsage', usageWord) && usageWord !== data.buildingUse) {
      note('건축물 용도 ' + data.buildingUse + ': 당근 목록의 「' + usageWord + '」로 골랐습니다.');
    }
    fill('exclusiveArea', inRow('전용면적', 'input[name="area"]'), data.exclusiveArea);
    fill('supplyArea', inRow('공급면적', 'input[name="supplyArea"]'), data.supplyArea);

    // ④ 거래 유형 — 고른 유형마다 가격 묶음이 붙고 칸 이름은 trades.<고른 순번>.price 처럼 붙는다.
    // 단기 매물이면 당근 안내(「거래 유형이 2개 이상이면 모두 선택」)대로 단기도 함께 고른다.
    const trades = ['월세', '전세', '매매', '단기'].includes(data.trade) ? [data.trade] : [];
    if (data.shortTerm === true && (data.trade === '월세' || data.trade === '전세')) trades.push('단기');
    else if (data.shortTerm === true && data.trade === '매매') {
      note('단기 매물: 당근의 단기는 보증금·월세로 받는 거래라 매매와 함께 고르지 않았습니다.');
    }
    for (const kind of trades) await checkbox('trade.' + kind, '거래 유형', kind);
    const tradeInput = (kind, field) => inRow(kind, '[name$=".' + field + '"]');
    await waitUntil(() => trades.every(kind => at(tradeInput(kind, 'price'))), 3000);
    if (data.trade === '월세') {
      fill('deposit', tradeInput('월세', 'price'), data.deposit);
      fill('monthlyRent', tradeInput('월세', 'monthlyPay'), data.monthlyRent);
    } else if (data.trade === '전세') {
      fill('deposit', tradeInput('전세', 'price'), data.deposit);
    } else if (data.trade === '매매') {
      fill('salePrice', tradeInput('매매', 'price'), data.salePrice);
    } else if (data.trade === '단기') {
      note('단기 보증금·월세: 통합 폼은 단기 거래에서 금액을 받지 않아 당근 단기 금액 칸(필수)을 비워 두었습니다. 화면에서 직접 넣어 주세요.');
    }
    if (trades.includes('단기') && data.trade !== '단기') {
      fill('shortTerm.deposit', tradeInput('단기', 'price'), data.deposit);
      if (data.trade === '월세') fill('shortTerm.monthlyRent', tradeInput('단기', 'monthlyPay'), data.monthlyRent);
      else note('단기 월세: 전세 매물이라 통합 폼에 월세가 없어 당근 단기 월세 칸을 비워 두었습니다.');
      note('단기 매물: 「' + data.trade + '」와 「단기」를 함께 골랐고 단기 금액에는 ' + data.trade + ' 금액을 그대로 넣었습니다.');
    }
    if (trades.includes('단기')) {
      note('단기 조건: 당근은 단기임대 기간·조건 설명을 받지만 통합 폼에 기간 정보가 없어 비워 두었습니다. 화면에서 직접 적어 주세요.');
    }

    // ⑤ 매물 정보
    fill('approvalDate', inRow('사용승인일', 'input[name="buildingApprovalDate"]'), data.approvalDate);
    const count = value => String(value).replace(/\s*이상$/, '');
    fill('rooms', inRow('방/욕실', 'input[name="roomCnt"]'), data.rooms, count);
    fill('bathrooms', inRow('방/욕실', 'input[name="bathroomCnt"]'), data.bathrooms, count);
    for (const [key, label] of [['rooms', '방 개수'], ['bathrooms', '욕실 수']]) {
      if (/이상$/.test(String(data[key] || ''))) note(label + ' ' + data[key] + ': 당근은 숫자만 받아 ' + count(data[key]) + '(으)로 넣었습니다.');
    }

    // 층 — 지하·반지하는 체크, 옥탑은 매물 특징으로 받는다.
    fill('floorAll', inRow('층 정보', 'input[name="topFloor"]'), data.floorAll);
    const floorWord = String(data.floor === undefined || data.floor === null ? '' : data.floor);
    const basement = /^지하\s*(\d+)\s*층?$/.exec(floorWord);
    if (floorWord === '반지하') await checkbox('floor', '층 정보', '반지하');
    else if (basement) {
      await checkbox('floor.basement', '층 정보', '지하');
      fill('floor', inRow('층 정보', 'input[name="floor"]'), basement[1]);
    } else if (floorWord === '옥탑') {
      note('해당 층 옥탑: 당근은 옥탑을 층수가 아니라 매물 특징 「옥탑」으로 받아 해당 층 칸은 비워 두었습니다.');
    } else fill('floor', inRow('층 정보', 'input[name="floor"]'), floorWord);
    if (data.floorPrivate === true) {
      const top = Number(data.floorAll), level = Number(floorWord);
      if (salesType !== '아파트') {
        note('층수 비공개: 당근은 매물 종류가 아파트일 때만 「저/중/고로 표시」를 제공합니다.');
      } else if (!(level > 0 && top > 0)) {
        note('층수 비공개: 지하·반지하·옥탑은 당근에서 저/중/고로 표시할 수 없습니다.');
      } else if (await checkbox('floorPrivate', '층 정보', '저/중/고로 표시')) {
        const band = level / top <= 1 / 3 ? '저층' : level / top <= 2 / 3 ? '중층' : '고층';
        const chip = () => {
          const row = rowOf('층 정보');
          return row ? [...row.querySelectorAll('label.seed-control-chip')].find(label => text(label) === band) : null;
        };
        if (await waitUntil(chip, 2000) && await setToggle('floorPrivate.band', chip, true, band)) {
          note('층수 비공개: 전체 ' + top + '층 중 ' + level + '층이라 「' + band + '」으로 표시했습니다.');
        }
      }
    }

    await choose('direction', 'buildingOrientation', data.direction);
    if (filled(data.directionBase)) note('방향 기준 ' + data.directionBase + ': 당근은 방향 기준을 따로 받지 않아 방향만 넣었습니다.');

    // 대출·반려동물·주차 — 셋 다 name=requiredOptions. 줄 안에서 value 로 찾는다.
    if (TRISTATE[data.loanAvailable]) await radio('loanAvailable', '대출', TRISTATE[data.loanAvailable], '대출 ' + data.loanAvailable);
    if (TRISTATE[data.petAllowed]) await radio('petAllowed', '반려동물', TRISTATE[data.petAllowed], '반려동물 ' + data.petAllowed);
    if (data.parking === '주차 가능' || data.parking === '주차 불가능') {
      const yes = data.parking === '주차 가능';
      if (await radio('parking', '주차', yes ? 'YES' : 'NO', data.parking) && yes) {
        // 「가능」이면 총·세대당 대수 묶음이 주차 줄 바로 뒤에 붙는다.
        const total = () => root().querySelector('input[name="availableTotalParkingSpots"]');
        if (await waitUntil(total, 2000)) {
          fill('parkingCount', total, data.parkingCount);
          fill('parkingPerHousehold', () => root().querySelector('input[name="availableParkingSpotsV2"]'), data.parkingPerHousehold);
        } else miss('parkingCount', '「주차 가능」 뒤에 주차 대수 칸이 나타나지 않았습니다.');
      }
    }

    // ⑥ 위반건축물·매물 특징·가전
    if (data.violation === '위반건축물 해당') await checkbox('violation', '위반건축물', '해당');
    if (data.propertyType === '복층형 원룸' || data.roomLayout === '복층형 원룸') await checkbox('roomLayout.duplex', '매물 특징', '복층');
    if (floorWord === '옥탑') await checkbox('floor.rooftop', '매물 특징', '옥탑');
    // 엘리베이터는 건축물대장이 켤 수 있어 「없음」도 분명히 맞춘다.
    if (data.elevator === '있음' || data.elevator === '없음') {
      await checkbox('elevator', '매물 특징', '엘리베이터', data.elevator === '있음');
    }
    for (const item of (data.appliances || [])) {
      if (APPLIANCES[item]) await checkbox('appliances.' + item, '가전/가구', APPLIANCES[item]);
      else note('가전·가구 옵션 ' + item + ': 당근 가전/가구에 대응 항목이 없습니다.');
    }
    for (const item of (data.facilities || [])) {
      note('보안 및 시설 옵션 ' + item + ': 당근 매물 특징에는 복층·옥탑·엘리베이터만 있어 대응 항목이 없습니다.');
    }

    // ⑦ 관리비
    await applyFee();

    // ⑧ 입주가능일 — 날짜가 들어가야 「입주일 협의 가능」이 붙는다.
    if (data.moveInType === '즉시 입주') {
      await checkbox('moveInType', '입주가능일', '즉시 입주 가능');
      if (data.moveInNegotiable === true) note('입주일 협의 가능: 당근은 「즉시 입주 가능」을 켜면 협의 체크를 받지 않습니다.');
    } else if (data.moveInType === '날짜 지정') {
      if (fill('moveInDate', inRow('입주가능일', 'input[name="moveInDate"]'), data.moveInDate) && data.moveInNegotiable === true) {
        if (await waitUntil(() => labelIn(rowOf('입주가능일'), '입주일 협의 가능'), 2000)) {
          await checkbox('moveInNegotiable', '입주가능일', '입주일 협의 가능');
        } else miss('moveInNegotiable', '날짜를 넣었지만 「입주일 협의 가능」이 나타나지 않았습니다.');
      }
    } else if (data.moveInType === '협의 가능') {
      note('입주 방식 협의 가능: 당근은 날짜를 넣은 뒤에만 「입주일 협의 가능」을 켤 수 있어 입주가능일(필수)을 비워 두었습니다. 화면에서 날짜를 정하거나 「즉시 입주 가능」을 골라 주세요.');
    }

    // ⑨ 글 — 제목은 「매물 한줄 설명」(40자)으로 보낸다.
    fill('description', inRow('상세 설명', 'textarea[name="content"]'), data.description);
    fill('title', inRow('매물 한줄 설명', 'input[name="addressInfo"]'), data.title);
    if (filled(data.privateMemo)) {
      const memo = String(data.privateMemo);
      if (memo.length > 800) note('중개소 비밀메모: 당근은 800자까지 받아 앞 800자만 넣었습니다.');
      fill('privateMemo', inRow('중개소 비밀메모', 'textarea[name="memoContent"]'), memo.slice(0, 800));
    }
    if (filled(data.ownerPhone)) {
      const phone = inRow('집주인 전화번호', 'input[name="lessorPhoneNumber"]');
      if (await ready(phone, 1500)) fill('ownerPhone', phone, data.ownerPhone);
      else miss('ownerPhone', '당근은 주소를 입력한 뒤에만 집주인 전화번호 칸을 켭니다. 주소를 고른 뒤 직접 넣어 주세요.');
    }

    if (filled(data.heating)) note('난방 방식: 당근 등록 폼에 입력란이 없습니다.');
    if (filled(data.lh)) note('LH 전세임대 여부: 당근 등록 폼에 입력란이 없습니다.');
    if (filled(data.loan)) {
      note('융자금 ' + data.loan + (filled(data.loanAmount) ? ' (' + data.loanAmount + '만원)' : '') +
        ': 당근 등록 폼에는 융자금 입력란이 없습니다. 「대출」 줄은 대출 가능 여부입니다.');
    }

    if (addressEntered) await reconcileLedger();
  } catch (error) {
    output.violations.push('당근 자동 입력 오류: ' + String(error && error.stack ? error.stack : error));
  }
  // 폼은 여기서 조용해진다 — 사진은 이제 붙여도 된다 ([MirrorSession._adapterDone]).
  window.__flrFormDone = true;
  for (const violation of (window.__FLR_VIOLATIONS__ || [])) {
    const detail = typeof violation === 'string' ? violation
      : [violation.kind, violation.target, violation.detail].filter(Boolean).join(' · ');
    output.violations.push('깐깐이 위반: ' + detail);
  }
  // 「임시저장」·「매물 등록하기」는 어떤 경우에도 누르지 않는다. 이 어댑터는 채우기만 한다.
  publish();
})();
''';

/// The frames [addressPickerFrameScript] works in. Android only lets the script
/// into these origins; iOS runs it in every frame and the script checks the
/// host itself.
const kakaoPostcodeOrigins = [
  'https://postcode.map.kakao.com',
  'https://postcode.map.daum.net',
];

String addressPickerFrameScript(String target) =>
    '''
(function pick() {
  // Runs in EVERY frame, so leave the mirror page alone.
  if (!/^postcode\\.map\\.(kakao\\.com|daum\\.net)\$/.test(location.hostname)) return;
  // Android puts this in as the document starts, before the result list exists.
  // Kakao binds the result buttons in its own jQuery ready handler, so wait
  // until every DOMContentLoaded listener has run — where iOS injects it.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => setTimeout(pick), {once: true});
    return;
  }
  const targetInput = $target;
  const targets = (Array.isArray(targetInput) ? targetInput : [targetInput])
    .map(value => String(value || '').trim()).filter(Boolean);
  if (!targets.length) return;
  if (window.__flrPickerRan || window.__flrPickerRunning) return;
  window.__flrPickerRunning = true;
  // Only the search this app started gets picked for the user. If they clear the
  // box and look for somewhere else, that is their choice to make.
  const clean = value => String(value === undefined || value === null ? '' : value)
    .replace(/\\(.*?\\)/g, ' ').replace(/\\s+/g, ' ').trim();
  const squash = value => clean(value).replace(/\\s+/g, '');
  const query = () => (document.getElementById('cQuery') || {}).value ||
    new URLSearchParams(location.search).get('cq') || '';

  // 시·도 이름은 카카오가 「서울」로 줄여 쓰기도 하고 「서울특별시」로 다 쓰기도 한다.
  const SIDO = [
    ['서울특별시', '서울'], ['부산광역시', '부산'], ['대구광역시', '대구'], ['인천광역시', '인천'],
    ['광주광역시', '광주'], ['대전광역시', '대전'], ['울산광역시', '울산'], ['세종특별자치시', '세종'],
    ['경기도', '경기'], ['강원특별자치도', '강원'], ['강원도', '강원'], ['충청북도', '충북'],
    ['충청남도', '충남'], ['전북특별자치도', '전북'], ['전라북도', '전북'], ['전라남도', '전남'],
    ['경상북도', '경북'], ['경상남도', '경남'], ['제주특별자치도', '제주'], ['제주도', '제주'],
  ];
  const normalize = value => {
    let text = clean(value);
    for (const [full, short] of SIDO) {
      if (text.startsWith(full)) { text = short + text.slice(full.length); break; }
      if (text.startsWith(short)) break;
    }
    return text.replace(/\\s+/g, ' ').trim();
  };

  const wanted = targets.map(normalize);
  // 번지·건물번호는 「123」과 「123-4」를 가르는 결정적인 부분이라 따로 본다.
  const numbersOf = text => (text.match(/\\d+(-\\d+)?/g) || []);
  const tokensOf = text => normalize(text).split(/\\s+/).filter(Boolean);
  const houseNumber = text => numbersOf(normalize(text)).slice(-1)[0] || '';
  const localityTokens = text => tokensOf(text).filter(token =>
    /(?:시|도|군|구)\$/.test(token));
  const placeTokens = text => tokensOf(text).filter(token =>
    /(?:읍|면|동|리|가|로|길)\$/.test(token));
  const intersects = (left, right) => left.some(token => right.includes(token));

  const matchesAddress = (candidate, expected) => {
    const value = normalize(candidate);
    if (!value || !expected) return false;
    if (squash(value) === squash(expected)) return true;
    const expectedHouse = houseNumber(expected);
    if (!expectedHouse || houseNumber(value) !== expectedHouse) return false;
    const expectedPlaces = placeTokens(expected);
    const candidatePlaces = placeTokens(value);
    // 같은 구와 번지만으로는 부족하다. 이전 검색의 다른 도로도 그 조건을
    // 만족할 수 있으므로 도로명 또는 법정동이 반드시 겹쳐야 한다.
    if (!expectedPlaces.length || !intersects(expectedPlaces, candidatePlaces)) return false;
    const expectedLocalities = localityTokens(expected);
    return !expectedLocalities.length || intersects(expectedLocalities, localityTokens(value));
  };

  const score = candidate => {
    const value = normalize(candidate);
    if (!value) return -1;
    let winner = -1;
    for (const expected of wanted) {
      if (squash(value) === squash(expected)) return 1000;
      if (!matchesAddress(value, expected)) continue;
      const sharedPlaces = placeTokens(expected).filter(token => placeTokens(value).includes(token)).length;
      const sharedLocalities = localityTokens(expected).filter(token => localityTokens(value).includes(token)).length;
      winner = Math.max(winner, 100 + sharedPlaces * 40 + sharedLocalities * 10);
    }
    return winner;
  };

  const press = el => {
    el.scrollIntoView({block: 'center'});
    el.click();
  };

  const candidates = () => [...document.querySelectorAll('span.txt_address[data-addr]')]
    .map(span => ({
      span,
      button: span.querySelector('button.link_post'),
      address: span.getAttribute('data-addr') || '',
      road: span.getAttribute('data-addr_type') === 'R',
    }))
    .filter(item => item.button && item.address);

  const best = items => {
    let winner = null;
    for (const item of items) {
      const value = score(item.address);
      // 같은 점수면 먼저 나온 것 — 카카오가 이미 관련도 순으로 준다.
      // 도로명은 두 미러가 모두 주소 칸에 쓰는 형식이라 동점에서 한 표 더 준다.
      const weighted = value + (item.road ? 1 : 0);
      if (!winner || weighted > winner.weighted) winner = {item, weighted};
    }
    return winner && winner.item;
  };

  const stronglyMatches = item => {
    return !!item && wanted.some(expected => matchesAddress(item.address, expected));
  };

  const waitFor = (predicate, timeout) => new Promise(resolve => {
    const until = Date.now() + timeout;
    const tick = () => {
      const value = predicate();
      if (value) return resolve(value);
      if (Date.now() >= until) return resolve(null);
      setTimeout(tick, 80);
    };
    tick();
  });

  (async () => {
    // 다방에서는 iframe 의 documentEnd 뒤에 검색어를 채우고, 그보다 더 늦게
    // 결과 목록을 그리기도 한다. 둘 다 한 deadline 안에서 기다려야 한다.
    const deadline = Date.now() + 12000;
    const ours = await waitFor(() => {
      const value = query();
      if (!value) return null;
      return targets.some(expected => squash(value) === squash(expected)) ? value : null;
    }, Math.max(0, deadline - Date.now()));
    if (!ours) return;
    try {
      if (sessionStorage.getItem('flrPicked') === '1') return;
    } catch (_) { /* private mode: the in-memory flags still prevent duplicates */ }

    // 첫 화면: 우편번호 묶음마다 도로명·지번 후보가 붙어 있다.
    const first = await waitFor(() => {
      const items = candidates();
      const pick = best(items);
      return stronglyMatches(pick) ? {items, pick} : null;
    }, Math.max(0, deadline - Date.now()));
    if (!first) return;
    const pick = first.pick;
    if (!pick) return;
    // 완료 표시는 실제 후보를 찾은 뒤, 클릭 직전에만 세운다. 늦은 검색어/후보로
    // 빈 실행이 끝난 경우에는 다음 주입이 다시 시도할 수 있어야 한다.
    press(pick.button);

    // 도로명 하나에 지번이 여럿이면 카카오가 지번 고르는 화면을 한 번 더 띄운다.
    const second = await waitFor(() => {
      const list = document.querySelector('.main_jibun, .list_jibun, [class*=mapping_jibun]');
      if (!list) return null;
      const items = candidates().filter(item => list.contains(item.span));
      return items.length ? items : null;
    }, 2500);
    if (!second) {
      window.__flrPickerRan = true;
      return;
    }
    const follow = best(second);
    // 어느 지번인지 가릴 근거가 없으면 카카오가 준 첫 줄을 쓴다.
    // 첫 클릭 전에 완료를 저장하면 2단계 화면이 새 문서로 열릴 때 그 문서가
    // 즉시 종료된다. 실제 마지막 선택 직전에만 완료 상태를 남긴다.
    window.__flrPickerRan = true;
    try { sessionStorage.setItem('flrPicked', '1'); } catch (_) { /* ignore */ }
    press((follow || second[0]).button);
  })().finally(() => { window.__flrPickerRunning = false; });
})();
''';
