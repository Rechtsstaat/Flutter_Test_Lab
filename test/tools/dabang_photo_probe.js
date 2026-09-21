/*
 * 다방 사진 첨부 자리의 **구조**를 떠 오는 읽기 전용 탐침.
 *
 * `lib/photo_transfer.dart` 의 `PhotoTarget.dabang` 은 올린 사진을 이렇게 찾는다:
 *
 *   input()  document 전체에서 multiple 이고 accept === 'image/*' 인 file 입력
 *   cards()  section#visual_info [class*="SortableContainer"] [data-index]
 *   cardId   card.dataset.id
 *   settled  dataset.id 가 있고 aria-disabled === 'false'
 *
 * 실물에서 첨부가 「현재 0장입니다」로 끝났다(2026-09-20). 파일은 입력란에 들어갔으니
 * `cards()` 가 못 찾는 것이고, 그 셀렉터는 styled-components 가 지어낸 클래스 이름과
 * `#visual_info` 안에 있다는 가정에 기대고 있다 — 둘 다 실물에서 다를 수 있다.
 *
 * 쓰는 법 — 계정 주인이 직접 돌린다:
 *   1. 크롬에서 pro.dabangapp.com 로그인 → /form/room
 *   2. 「일반 사진」에 **아무 사진이나 한 장** 손으로 올린다 (등록은 누르지 않는다)
 *   3. 사진이 화면에 뜬 뒤 DevTools 콘솔에 이 파일을 붙여넣고 Enter
 *   4. `copy(__dabangPhotoProbe)` 또는 아래 한 줄로 파일로 받는다
 *
 *      (() => { const a = document.createElement('a');
 *        a.href = URL.createObjectURL(new Blob([__dabangPhotoProbe], {type:'application/json'}));
 *        a.download = 'dabang-photo-probe.json'; a.click(); })()
 *
 * **넣지 않는 것**: 사진 자체, `src`·`href`(blob/데이터 URL), 파일 이름, `alt`·`title`
 * 같은 사람이 쓴 글. 담는 것은 태그·클래스 이름·`data-*`·`aria-*` 뿐이다.
 */
(() => {
  const SELECTOR = 'section#visual_info [class*="SortableContainer"] [data-index]';

  const attrs = (el) => {
    const out = {};
    for (const a of el.attributes) {
      if (/^(data-|aria-)/.test(a.name)) out[a.name] = a.value.slice(0, 40);
    }
    return out;
  };
  const idPath = (el) => {
    const out = [];
    for (let n = el; n; n = n.parentElement) if (n.id) out.unshift(n.id);
    return out.join(' > ');
  };
  // 사람이 쓴 글과 사진 자체는 담지 않는다. 뼈대만 남긴다.
  const skeleton = (el, depth) => {
    if (!el || depth < 0) return null;
    const node = {
      tag: el.tagName.toLowerCase(),
      cls: String(el.className || '').slice(0, 120) || undefined,
      id: el.id || undefined,
      ...attrs(el),
    };
    if (el.children.length && depth > 0) {
      node.kids = [...el.children].slice(0, 12).map((k) => skeleton(k, depth - 1));
      if (el.children.length > 12) node.more = el.children.length - 12;
    }
    return node;
  };

  const files = [...document.querySelectorAll('input[type="file"]')].map((el) => ({
    accept: el.accept || null,
    multiple: !!el.multiple,
    path: idPath(el),
    parent: el.parentElement
      ? el.parentElement.tagName.toLowerCase() + '.' + String(el.parentElement.className || '').slice(0, 60)
      : null,
  }));

  // ① 지금 쓰는 셀렉터가 맞나
  const matched = [...document.querySelectorAll(SELECTOR)];
  const visual = document.getElementById('visual_info');

  // ② 안 맞는다면 어디에 있나 — 올린 사진 카드로 보이는 후보를 넓게 훑는다.
  const candidates = [...document.querySelectorAll('[data-index], [data-id], [aria-roledescription], [class*="Sortable"]')]
    .filter((el) => el.querySelector('img, canvas, [style*="background-image"]') || /image|photo|thumb|사진/i.test(el.className || ''))
    .slice(0, 24)
    .map((el) => ({
      tag: el.tagName.toLowerCase(),
      cls: String(el.className || '').slice(0, 120),
      path: idPath(el),
      inVisualInfo: !!(visual && visual.contains(el)),
      ...attrs(el),
    }));

  const probe = {
    url: location.href,
    redaction: '사진·src·파일이름·사람이 쓴 글 미수집 / 태그·클래스·data-*·aria-* 만',
    fileInputs: files,
    bridgeExpects: {
      selector: SELECTOR,
      matchedCount: matched.length,
      matched: matched.slice(0, 8).map((el) => ({
        cls: String(el.className || '').slice(0, 120),
        settledByCurrentRule: !!el.dataset.id && el.getAttribute('aria-disabled') === 'false',
        ...attrs(el),
      })),
      visualInfoPresent: !!visual,
      sortableInsideVisualInfo: visual
        ? visual.querySelectorAll('[class*="SortableContainer"]').length
        : 0,
      sortableAnywhere: document.querySelectorAll('[class*="SortableContainer"]').length,
    },
    cardCandidates: candidates,
    // 사진 자리의 실제 뼈대. 셀렉터를 새로 짜려면 이게 있어야 한다.
    visualInfoSkeleton: skeleton(visual, 6),
  };

  window.__dabangPhotoProbe = JSON.stringify(probe, null, 2);
  console.log(
    '다방 사진 탐침 — 현재 셀렉터로 %d장, #visual_info 안 Sortable %d개, 문서 전체 %d개, 후보 %d개\n' +
      'copy(__dabangPhotoProbe) 로 클립보드에 담으세요.',
    probe.bridgeExpects.matchedCount,
    probe.bridgeExpects.sortableInsideVisualInfo,
    probe.bridgeExpects.sortableAnywhere,
    candidates.length,
  );
  return probe;
})();
