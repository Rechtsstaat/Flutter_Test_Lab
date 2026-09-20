/*
 * 앱이 사진을 넣는 **방식 그대로** 크롬에서 재현해 보는 탐침.
 *
 * 왜 필요한가 — 실물에서 첨부가 「현재 0장입니다」로 끝났는데, 사람이 손으로 올리면
 * 카드가 정상으로 생기고 그 카드는 미러와 구조까지 같다(2026-09-20 실측). 즉 카드를
 * 세는 규칙은 맞다. 그렇다면 남은 갈림길은 둘이고, 이 탐침이 그것을 가른다:
 *
 *   ① 앱이 **엉뚱한 입력란**에 넣는다. 실물 폼에는 file 입력이 둘이고
 *      (`image/*` multiple, `image/jpg, image/jpeg, image/png` 단일) 둘 다 body 밑에
 *      떠 있어 생김새만으로는 어느 쪽이 「일반 사진」인지 알 수 없다.
 *      `lib/photo_transfer.dart` 의 `input()` 은 앞쪽(`image/*` multiple)을 고른다.
 *   ② 입력란은 맞는데 WKWebView 에서 `DataTransfer` 로 넣은 파일을 다방 핸들러가
 *      받지 않는다. 그렇다면 크롬에서는 **성공**해야 한다.
 *
 * 결과가 「카드 생김」이면 ②(기기 문제), 「안 생김」이면 ①(입력란 문제)다.
 *
 * 쓰는 법 — 계정 주인이 직접 돌린다:
 *   1. 크롬에서 pro.dabangapp.com/form/room 을 **새로** 연다 (사진이 없는 상태로)
 *   2. DevTools 콘솔에 이 파일을 통째로 붙여넣고 Enter
 *   3. 최대 30초 기다린다. 콘솔에 `판정: ...` 줄이 찍히면 끝난 것이다
 *   4. 그 **뒤에** 콘솔에 아래 한 줄을 쳐서 파일로 받는다
 *      (`copy(__dabangAttachProbe)` 도 되지만, 클립보드보다 파일이 다루기 쉽다)
 *
 *      (() => { const a = document.createElement('a');
 *        a.href = URL.createObjectURL(new Blob([__dabangAttachProbe], {type:'application/json'}));
 *        a.download = 'dabang-attach-probe.json'; a.click(); })()
 *
 *   5. **끝나면 페이지를 새로고침한다** — 올라간 시험용 사진은 그걸로 사라진다
 *
 * 급하면 `판정:` 줄만 봐도 된다. ①인지 ②인지가 핵심이고 나머지는 세부 확인용이다.
 *
 * 이 탐침은 스스로 만든 파란 사각형 PNG 한 장만 쓴다. 사진첩을 읽지 않고, 「임시저장」·
 * 「등록 완료」는 누르지 않는다. 폼에 사진 한 장이 붙을 뿐이고 새로고침하면 없던 일이 된다.
 */
(async () => {
  const SELECTOR = 'section#visual_info [class*="SortableContainer"] [data-index]';
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const cards = () => [...document.querySelectorAll(SELECTOR)];
  const settled = (card) => !!card.dataset.id && card.getAttribute('aria-disabled') === 'false';

  const log = [];
  const say = (line) => { log.push(line); console.log('[탐침] ' + line); };

  const inputs = [...document.querySelectorAll('input[type="file"]')];
  say('file 입력 ' + inputs.length + '개: ' + inputs.map((el, i) =>
    '#' + i + '(' + (el.accept || '없음') + (el.multiple ? ', multiple' : '') + ')').join(' / '));

  // 페이지가 어느 입력란을 실제로 쓰는지도 함께 듣는다. 앱이 넣은 뒤 다방 핸들러가
  // 반응하는지, 반응한다면 어느 쪽인지가 그대로 보인다.
  const heard = [];
  inputs.forEach((el, i) => {
    for (const type of ['change', 'input']) {
      el.addEventListener(type, () => heard.push(
        type + '@#' + i + ' files=' + (el.files ? el.files.length : '?')), true);
    }
  });

  // lib/photo_transfer.dart 의 PhotoTarget.dabang.input() 과 같은 규칙.
  const chosen = inputs.find((el) => el.multiple && el.accept === 'image/*');
  if (!chosen) {
    say('앱이 고르는 규칙(multiple && accept === "image/*")에 맞는 입력란이 없다. 여기서 끝.');
    window.__dabangAttachProbe = JSON.stringify({log, heard}, null, 2);
    return {log, heard};
  }
  say('앱이 고를 입력란: #' + inputs.indexOf(chosen));

  const before = cards().length;
  say('넣기 전 카드 ' + before + '장');

  // 파란 사각형 PNG 를 손으로 짓는다 — 사진첩을 읽지 않기 위해서다.
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 800;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#2d6cdf';
  ctx.fillRect(0, 0, 800, 800);
  ctx.fillStyle = '#ffffff';
  ctx.font = 'bold 64px sans-serif';
  ctx.fillText('TEST', 300, 420);
  const blob = await new Promise((r) => canvas.toBlob(r, 'image/jpeg', 0.9));
  const file = new File([blob], 'hanbang-probe.jpg',
    {type: 'image/jpeg', lastModified: Date.now()});
  say('시험용 사진 ' + file.size + '바이트 (image/jpeg)');

  // lib/photo_transfer.dart 의 commit() 과 같은 방식.
  const transfer = new DataTransfer();
  transfer.items.add(file);
  chosen.files = transfer.files;
  if (chosen.files.length !== 1) {
    say('DataTransfer 로 파일을 넣지 못했다. 여기서 끝.');
    window.__dabangAttachProbe = JSON.stringify({log, heard}, null, 2);
    return {log, heard};
  }
  say('입력란에 파일이 들어갔다 (files=' + chosen.files.length + ')');
  chosen.dispatchEvent(new Event('input', {bubbles: true}));
  chosen.dispatchEvent(new Event('change', {bubbles: true}));
  say('input·change 를 쏘았다');

  // 앱과 같은 방식으로 카드가 앉기를 기다린다.
  let grew = false;
  for (let waited = 0; waited < 30000; waited += 1000) {
    await sleep(1000);
    const now = cards();
    if (now.length > before) {
      grew = true;
      say((waited / 1000 + 1) + '초 만에 카드 ' + now.length + '장 — 처리 완료 '
        + (now.every(settled) ? '확인됨' : '아직'));
      if (now.every(settled)) break;
    }
  }
  const after = cards();
  if (!grew) say('30초를 기다려도 카드가 늘지 않았다 (' + after.length + '장). → 입력란이 잘못됐을 가능성');
  say('페이지가 들은 것: ' + (heard.length ? heard.join(', ') : '(없음 — 다방 핸들러가 반응하지 않았다)'));

  const result = {
    url: location.href,
    inputs: inputs.map((el) => ({accept: el.accept || null, multiple: !!el.multiple})),
    chosenIndex: inputs.indexOf(chosen),
    cardsBefore: before,
    cardsAfter: after.length,
    grew,
    allSettled: after.length > 0 && after.every(settled),
    heard,
    log,
    verdict: grew
      ? '② 기기 쪽 문제 — 크롬에서는 앱과 같은 방식으로 카드가 생긴다'
      : '① 입력란 문제 — 앱이 고르는 입력란으로는 크롬에서도 카드가 안 생긴다',
  };
  window.__dabangAttachProbe = JSON.stringify(result, null, 2);
  console.log('판정: ' + result.verdict + '\ncopy(__dabangAttachProbe) 로 담으세요. 끝나면 페이지를 새로고침하세요.');
  return result;
})();
