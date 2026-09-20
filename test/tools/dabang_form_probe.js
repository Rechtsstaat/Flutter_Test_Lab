/*
 * 다방프로 등록 폼(로그인 뒤)의 **구조**를 떠 오는 읽기 전용 탐침.
 *
 * 다방 어댑터(`lib/remote_form.dart` 의 `dabangInjectionScript`)는 칸을 찾을 때
 * `#room_info` · `#trade_info` 섹션 id, `th` 줄 제목, `th h1`, `td` 안의 `header`
 * 소제목, `label` 글자에 기댄다. 이 기준은 전부 **미러를 떠서** 쓴 것이라, 실물
 * 로그인 뒤 화면이 다르면 입력이 통째로 빗나간다. 이 탐침은 그 기준이 실물에서도
 * 성립하는지를 한 번에 재 온다.
 *
 * 쓰는 법 — 계정 주인이 직접 돌린다:
 *   1. 크롬에서 https://pro.dabangapp.com 로그인
 *   2. https://pro.dabangapp.com/form/room 을 연다 (폼이 다 그려질 때까지 기다린다)
 *   3. DevTools 콘솔(⌥⌘I → Console)에 이 파일을 통째로 붙여넣고 Enter
 *   4. 이어서 `copy(__dabangProbe)` 를 치면 결과가 클립보드에 담긴다
 *
 * **넣지 않는 것**: 입력란에 들어 있는 값(`value`), 체크 상태, 쿠키. 담는 것은 칸의
 * **이름과 생김새**뿐이다 — 줄 제목, `name`, `type`, `id`, 안내 문구(placeholder),
 * 선택지 글자, 버튼 글자.
 *
 * 그것만으로도 새는 곳이 하나 있다: 「연락처」 줄의 `<select>` 는 **선택지 자체가**
 * 중개사 이름과 번호다(미러에서도 `김미러 (대표)` 로 나온다). 그래서 사람을 가리키는
 * 줄의 선택지 글자는 길이만 남기고 지우고, 어디서 온 글자든 전화번호 꼴은 한 번 더
 * 지운다 — 어댑터가 알아야 하는 것은 「거기 select 가 있고 선택지가 2개」라는 사실뿐이다.
 *
 * **쓰지 않는 것**: 이 스크립트는 클릭도 입력도 제출도 하지 않는다. `querySelector`
 * 와 속성 읽기만 한다.
 */
(() => {
  /** 사람을 가리키는 줄 — 여기 선택지 글자는 길이만 남긴다. */
  const PERSONAL = /연락처|담당자|중개사|사무소|대표|휴대폰|전화/;
  /** 어디서 왔든 전화번호 꼴은 지운다. */
  const scrub = (s) =>
    String(s || '').replace(/0\d{1,2}[-.\s]?\d{3,4}[-.\s]?\d{4}/g, '<전화번호>');
  const redact = (s) => (s ? '<가려짐 ' + [...s].length + '자>' : s);

  const norm = (s) => scrub(String(s || '').replace(/\s+/g, ' ').trim());
  const text = (el) => norm(el && el.textContent);
  const cap = (list, n) => (list.length > n ? list.slice(0, n) : list);

  /** 한 노드까지 내려오는 동안 만난 id 들 — `room_info > ...` 처럼 자리를 말해 준다. */
  const idPath = (el) => {
    const out = [];
    for (let n = el; n; n = n.parentElement) if (n.id) out.unshift(n.id);
    return out.join(' > ');
  };

  /** 컨트롤 하나의 **생김새**. 값은 담지 않는다. */
  const control = (el, personal) => {
    const out = { tag: el.tagName.toLowerCase() };
    if (el.type) out.type = el.type;
    if (el.name) out.name = el.name;
    if (el.id) out.id = el.id;
    const role = el.getAttribute('role');
    if (role) out.role = role;
    if (el.placeholder) out.placeholder = norm(el.placeholder);
    if (el.disabled) out.disabled = true;
    if (el.tagName === 'SELECT') {
      const options = [...el.options].map((o) => text(o));
      out.options = cap(personal ? options.map(redact) : options, 80);
    }
    if (el.tagName === 'BUTTON') out.text = text(el);
    if (el.type === 'file') {
      out.accept = el.accept || null;
      out.multiple = !!el.multiple;
    }
    return out;
  };

  // ── ① 어댑터가 기대는 것들이 실물에도 있는가 ──────────────────────────
  const files = [...document.querySelectorAll('input[type="file"]')];
  const buttons = [...document.querySelectorAll('button, a, [role="button"]')];
  const hasLabel = (label) => buttons.some((el) => text(el).includes(label));

  const expectations = {
    // lib/remote_form.dart formReadyScript(dabang)
    formReady: !!document.querySelector('#room_info th, #trade_info th'),
    // dabangInjectionScript 의 cellOf/rowOf 가 딛는 섹션
    sections: ['room_info', 'trade_info', 'visual_info'].map((id) => {
      const el = document.getElementById(id);
      return {
        id,
        present: !!el,
        thCount: el ? el.querySelectorAll('th').length : 0,
        thH1Count: el ? el.querySelectorAll('th h1').length : 0,
      };
    }),
    // lib/photo_transfer.dart PhotoTarget.dabang
    photoInput: {
      fileInputs: files.length,
      matches: files.some((el) => el.multiple && el.accept === 'image/*'),
      seen: files.map((el) => ({
        accept: el.accept || null,
        multiple: !!el.multiple,
        name: el.name || null,
        id: el.id || null,
        path: idPath(el),
      })),
    },
    photoCards: document.querySelectorAll(
      'section#visual_info [class*="SortableContainer"] [data-index]',
    ).length,
    // lib/fields.dart submitLabels / takedownLabels
    submitLabel: { '등록 완료': hasLabel('등록 완료') },
  };

  // ── ② 줄 하나하나의 실제 생김새 ───────────────────────────────────────
  const rows = [...document.querySelectorAll('th')].map((th) => {
    let td = th.nextElementSibling;
    while (td && td.tagName !== 'TD') td = td.nextElementSibling;
    const h1 = th.querySelector('h1');
    const heading = text(th);
    const personal = PERSONAL.test(heading);
    return {
      path: idPath(th),
      th: heading,
      h1: h1 ? text(h1) : null,
      personal: personal || undefined,
      tdFollows: !!td,
      headers: td ? [...td.querySelectorAll('header')].map(text) : [],
      labels: td
        ? cap([...td.querySelectorAll('label')].map((el) => {
            const label = text(el);
            return personal ? redact(label) : label;
          }), 60)
        : [],
      controls: td
        ? cap(
            [...td.querySelectorAll('input, select, textarea, button')].map((el) =>
              control(el, personal),
            ),
            60,
          )
        : [],
    };
  });

  // ── ③ 표 밖에 있는 칸들 (실물이 표를 안 쓸 수도 있다) ──────────────────
  const inTable = new Set();
  for (const row of document.querySelectorAll('tr')) {
    for (const el of row.querySelectorAll('input, select, textarea')) inTable.add(el);
  }
  const loose = [...document.querySelectorAll('input, select, textarea')]
    .filter((el) => !inTable.has(el) && el.type !== 'hidden')
    .map((el) => ({ ...control(el, true), path: idPath(el) }));

  const probe = {
    capturedAt: new Date().toISOString(),
    redaction: '값·체크상태 미수집 / 사람 줄의 선택지는 길이만 / 전화번호 꼴 제거',
    url: location.href,
    title: document.title,
    viewport: { width: innerWidth, height: innerHeight },
    userAgent: navigator.userAgent,
    expectations,
    rowCount: rows.length,
    rows,
    looseControls: cap(loose, 120),
    sectionIds: [...document.querySelectorAll('section[id], div[id]')]
      .filter((el) => el.querySelector('input, select, textarea, th'))
      .map((el) => el.id)
      .filter((id, i, all) => all.indexOf(id) === i),
  };

  window.__dabangProbe = JSON.stringify(probe, null, 2);
  console.log(
    '다방 폼 탐침 — 줄 %d개, formReady=%s, 사진칸=%s, 「등록 완료」=%s\n' +
      'copy(__dabangProbe) 로 클립보드에 담으세요.',
    probe.rowCount,
    expectations.formReady,
    expectations.photoInput.matches,
    expectations.submitLabel['등록 완료'],
  );
  return probe;
})();
