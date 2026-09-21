/// 광고 목록 위에서 도는 두 스크립트 — **번호를 알아내는 것**과 **그 번호의 카드를
/// 사람 앞에 올려 놓는 것**.
///
/// 한방은 매물을 내리지 않는다. 내리는 누름은 되돌릴 수 없으므로 끝까지 사람 몫이고,
/// 한방이 하는 일은 그 사람이 **엉뚱한 매물을 내리지 않게** 하는 것뿐이다. 그래서
/// 여기 있는 것은 전부 읽기와 표시뿐이고, 「광고 종료」·「매물 종료하기」를 누르는
/// 코드는 한 줄도 없다.
///
/// ## 왜 번호로 찾는가
///
/// 광고 목록에는 이 중개사의 매물이 통째로 걸려 있다 (미러 실측 2026-09-21:
/// 직방 광고 중 45건, 다방 광고 진행 119건). 제목도 주소도 닮은 매물이 줄줄이 있는
/// 목록에서 「이것이 그 매물이다」라고 말할 수 있는 것은 플랫폼이 붙여 준 번호뿐이다.
///
/// ## 카드를 어떻게 알아보는가
///
/// 클래스 이름으로 찾지 않는다. 다방은 styled-components 의 해시 클래스
/// (`styled__RoomContent-sc-114y74r-5`)를 쓰고 직방은 Tailwind 를 쓰는데, 둘 다
/// 빌드마다 바뀔 수 있는 이름이다. 대신 **페이지가 사람에게 보여 주는 것**으로 찾는다:
/// 번호가 적힌 글자를 찾아 그 조상으로 올라가다가, 플랫폼 자신의 종료 버튼을 품은
/// 첫 번째 상자를 카드로 본다. 미러에서 직방은 `AdItemCard` div, 다방은 `<li>` 가
/// 그렇게 잡힌다 — 이름을 하나도 적지 않고서.
library;

import 'dart:convert';

import 'fields.dart';

/// 카드에 마름질된 테를 두를 때 쓰는 표. 눌림 감시([pressWatcherScript])도 이
/// 선택자로 범위를 좁힌다 — 표가 붙은 카드 **안에서 누른 것만** 이 매물을 내린
/// 것으로 친다.
const takedownCardMark = 'data-flr-takedown-card';

/// [takedownCardMark] 가 붙은 카드를 가리키는 CSS 선택자.
const takedownCardSelector = '[$takedownCardMark]';

/// 광고 목록에서 매물 번호를 읽어 `ListingNumber` 로 답하는 스크립트.
///
/// [hints] 는 한방이 그 매물에 대해 아는 것 — 제목·주소·동호·금액이다. 카드 한 장
/// 한 장을 이 넷과 견주어 점수를 매기고, **가장 높은 한 장이 홀로 앞설 때만** 번호를
/// 말한다. 비슷한 점수가 둘이면 답하지 않는다: 틀린 번호는 없는 번호보다 나쁘다.
String listingNumberScript(ListingPlatform platform, Map<String, dynamic> hints) =>
    '''
(() => {
  const config = ${jsonEncode({
      'labels': platform.takedownLabels,
      'hints': _hintsOf(hints),
      'lazy': platform.listingsLoadLazily,
    })};
$_cardsChunk
$_scoreChunk
$_scrollChunk
  const answer = () => {
    const cards = readCards();
    const scored = score(cards);
    const best = scored[0] || null;
    const next = scored[1] || null;
    // 이긴 카드가 **혼자** 이겨야 한다. 동점이면 둘 중 어느 쪽인지 알 수 없다.
    const decided = best && best.score >= 3 && (!next || next.score < best.score)
      ? best.number : null;
    return {
      number: decided,
      cards: cards.length,
      score: best ? best.score : 0,
      why: best ? best.why : [],
      runnerUp: next ? next.score : 0,
    };
  };
  // 실물 목록은 페이지가 끝난 뒤에 그려진다(직방 Next.js, 다방 SPA). 카드가 한 장도
  // 없으면 아직 안 그려진 것이지 없는 것이 아니다 — 잠깐씩 다시 본다.
  //
  // 그리고 **보이는 것이 전부가 아니다.** 직방은 스무 장만 그려 두므로, 고르지
  // 못했으면 더 실어 놓고 다시 본다. 방금 올린 매물이 스무 번째 뒤에 있으면 한 번
  // 훑고 마는 눈에는 영영 안 보인다 — 그것이 번호를 못 읽던 까닭이다.
  let tries = 0;
  let mostCards = 0;
  let quiet = 0;
  const tick = () => {
    const result = answer();
    const grew = result.cards > mostCards;
    mostCards = Math.max(mostCards, result.cards);
    quiet = grew ? 0 : quiet + 1;
    if (!result.number) loadMore();
    // **카드가 더 늘지 않는 것**만이 다 실렸다는 신호다. 스크롤이 움직였는지로
    // 재면, 이미 바닥에 붙어 있던 순간을 「끝」으로 잘못 읽는다.
    const done = result.number || (result.cards > 0 && quiet >= 5) || ++tries >= 60;
    if (done) {
      try {
        window.ListingNumber.postMessage(
          JSON.stringify({...result, tries, scanned: mostCards}));
      } catch (_) {}
      return;
    }
    setTimeout(tick, 500);
  };
  tick();
})();
''';

/// 광고 목록에서 [number] 카드를 찾아 화면 가운데로 올리고 테를 두르는 스크립트.
/// 결과는 `TakedownCard` 로 온다.
///
/// 찾지 못하면 플랫폼 자신의 검색창에 번호를 한 번 넣어 본다. 직방은 「등록번호 /
/// 주소 / 제목 / 비밀메모로 검색」, 다방은 「매물번호/주소/메모/제목 검색」이라고
/// 적어 둔 칸이 있다 (미러 실측 2026-09-21). 미러의 검색창은 장식이라 아무 일도
/// 일어나지 않지만, 실물에서는 이 한 번이 목록을 한 장으로 줄여 준다.
String takedownCardScript(ListingPlatform platform, String number) =>
    '''
(() => {
  const config = ${jsonEncode({
      'number': number,
      'labels': platform.takedownLabels,
      'searchHints': _searchHints,
      'mark': takedownCardMark,
      'lazy': platform.listingsLoadLazily,
    })};
  const norm = value => String(value || '').replace(/\\s+/g, ' ').trim();
  // 50144198 이 501441980 이나 금액의 일부와 같은 것으로 읽히면 안 된다.
  const holds = text => {
    let at = text.indexOf(config.number);
    while (at >= 0) {
      const before = text[at - 1];
      const after = text[at + config.number.length];
      const digit = ch => ch >= '0' && ch <= '9';
      if (!digit(before) && !digit(after)) return true;
      at = text.indexOf(config.number, at + 1);
    }
    return false;
  };
  const isTakedown = el => config.labels.includes(norm(el.textContent));
  const locate = () => {
    for (const leaf of document.querySelectorAll('body *')) {
      if (leaf.children.length !== 0) continue;
      if (!holds(norm(leaf.textContent))) continue;
      for (let node = leaf.parentElement; node && node !== document.body;
           node = node.parentElement) {
        if ([...node.querySelectorAll('button, a, [role="button"]')].some(isTakedown)) {
          return node;
        }
      }
    }
    return null;
  };

$_scrollChunk
  const styleId = 'flr-takedown-card-style';
  const ensureStyle = () => {
    if (document.getElementById(styleId)) return;
    const style = document.createElement('style');
    style.id = styleId;
    // 카드를 **더해서** 눈에 띄게 한다. 다른 카드를 가리거나 흐리지 않는다 —
    // 사람이 「내가 보고 있는 것이 정말 이 매물인가」를 제 눈으로 확인할 수 있어야
    // 하고, 그러려면 옆 카드도 그대로 보여야 한다.
    style.textContent = `
      [\${config.mark}] {
        position: relative !important;
        outline: 3px solid #2F6BFF !important;
        outline-offset: -2px !important;
        border-radius: 12px !important;
        background: #F2F6FF !important;
        scroll-margin-top: 96px !important;
        scroll-margin-bottom: 96px !important;
      }
      [\${config.mark}]::after {
        content: '한방에서 내릴 매물';
        position: absolute; top: -11px; left: 12px; z-index: 5;
        padding: 2px 8px; border-radius: 999px;
        background: #2F6BFF; color: #FFFFFF;
        font-size: 11px; font-weight: 700; line-height: 18px;
        white-space: nowrap; pointer-events: none;
      }`;
    document.head.appendChild(style);
  };

  const state = window.__flrTakedownCard || (window.__flrTakedownCard = {});
  // 번호가 바뀌면(플랫폼이 넘어가면) 앞의 표는 남의 것이다.
  if (state.number !== config.number) {
    state.card && state.card.removeAttribute(config.mark);
    Object.assign(state, {number: config.number, card: null, scrolled: false,
                          searched: false, told: null, gaveUp: false,
                          since: Date.now()});
  }

  /// 여기까지 못 찾았으면 사람에게 맡긴다. 목록이 여러 장이거나(다방은 24장씩
  /// 끊어 싣는다) 그새 이미 내려간 매물이면 이 페이지에는 영영 없다. 그때까지
  /// 한방이 눌림을 「표가 붙은 카드 안」으로 가둬 두면, 사람이 제 손으로 찾아
  /// 눌러도 한방은 못 듣는다 — 그래서 포기했다는 말을 반드시 한다.
  const giveUpAfter = 20000;

  const search = () => {
    if (state.searched) return;
    const box = [...document.querySelectorAll('input[type="search"], input[type="text"]')]
      .find(el => config.searchHints.some(hint =>
        String(el.getAttribute('placeholder') || '').includes(hint)));
    if (!box) return;
    state.searched = true;
    // 깐깐이(미러)와 React 둘 다 el.value = … 를 못 본 척한다. 원래의 setter 를
    // 불러 넣고 input·change 를 직접 울려야 페이지가 알아듣는다.
    const setter = Object.getOwnPropertyDescriptor(
      HTMLInputElement.prototype, 'value').set;
    box.focus();
    setter.call(box, config.number);
    ['input', 'change'].forEach(type =>
      box.dispatchEvent(new Event(type, {bubbles: true})));
    for (const type of ['keydown', 'keypress', 'keyup']) {
      box.dispatchEvent(new KeyboardEvent(type, {
        key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true,
      }));
    }
    box.blur && box.blur();
  };

  const tell = found => {
    const said = found + '|' + state.gaveUp;
    if (state.told === said) return;
    state.told = said;
    try {
      window.TakedownCard.postMessage(JSON.stringify({
        found, gaveUp: state.gaveUp, number: config.number,
        searched: state.searched,
      }));
    } catch (_) {}
  };

  const apply = () => {
    const card = locate();
    if (!card) {
      // 번호를 아는 자리다. 검색창이 목록을 한 장으로 줄여 주는 것이 가장 빠르고
      // (실물 2026-09-22: 직방은 정말 한 장으로 줄어든다), 그것이 듣지 않는
      // 목록에서는 더 실어 가며 찾는다. 포기한 뒤에는 밀지 않는다 — 그때부터는
      // 사람이 제 손으로 목록을 보는 중이다.
      search();
      if (!state.gaveUp) loadMore();
      if (!state.gaveUp && Date.now() - state.since > giveUpAfter) {
        state.gaveUp = true;
      }
      tell(false);
      return false;
    }
    state.gaveUp = false;
    if (card !== state.card) {
      state.card && state.card.removeAttribute(config.mark);
      state.card = card;
      ensureStyle();
      card.setAttribute(config.mark, '');
    }
    if (!state.scrolled) {
      state.scrolled = true;
      card.scrollIntoView({block: 'center'});
      // 옆으로는 옮기지 않는다: scrollIntoView 는 화면 밖으로 밀려난 것을 가지러
      // 오른쪽으로 따라가는데, 그러면 사람이 보는 화면이 통째로 어긋난다.
      window.scrollTo(0, window.scrollY);
    }
    tell(true);
    return true;
  };

  // 목록은 늦게 그려지고(직방 Next.js, 다방 SPA), 그려진 뒤에도 React 가 카드를
  // 통째로 갈아 끼운다. 한 번 찾고 끝내면 표는 곧 유령이 된다.
  if (state.observer) state.observer.disconnect();
  if (state.timer) clearInterval(state.timer);
  const schedule = () => {
    if (state.pending) return;
    state.pending = setTimeout(() => { state.pending = 0; apply(); }, 150);
  };
  state.observer = new MutationObserver(schedule);
  state.observer.observe(document.documentElement, {childList: true, subtree: true});
  // MutationObserver 는 「아직 아무것도 안 그려진」 정적인 순간에는 울리지 않는다.
  state.timer = setInterval(apply, 700);
  return apply();
})();
''';

/// 목록을 더 싣는 토막 — 두 스크립트가 같은 손으로 목록을 민다.
///
/// 직방은 광고 중 44건 가운데 **스무 장만** 그려 둔다. 그런데 스크롤되는 것은 문서가
/// 아니라 목록 제 안쪽 상자라(`div.overflow-y-auto`, 실물 2026-09-22) `window.scrollTo`
/// 로는 한 장도 더 실리지 않는다. 카드에서 위로 올라가며 **정말 스크롤되는 상자**를
/// 찾아 그것을 내린다. 못 찾으면 문서를 내린다 — 그것으로 되는 목록도 있다.
const _scrollChunk = r'''
  const scrollerOf = node => {
    for (let el = node; el && el !== document.body; el = el.parentElement) {
      const how = getComputedStyle(el).overflowY;
      if ((how === 'auto' || how === 'scroll') && el.scrollHeight > el.clientHeight + 40) {
        return el;
      }
    }
    return document.scrollingElement || document.documentElement;
  };
  /// 한 번 더 싣기를 청한다.
  ///
  /// 무한 스크롤은 **바닥에 닿는 순간**에 다음 장을 싣는다. 이미 바닥에 붙어 있으면
  /// 그 순간이 다시 오지 않으므로, 살짝 떼었다 다시 붙인다. 이것 없이는 스무 장에서
  /// 마흔 장까지만 가고 나머지를 못 싣는다(실물 2026-09-22: 광고 중 44건).
  const loadMore = () => {
    if (!config.lazy) return false;
    const button = [...document.querySelectorAll('button, a, [role="button"]')]
      .find(isTakedown);
    if (!button) return false;
    const box = scrollerOf(button);
    if (!box) return false;
    const was = box.scrollTop;
    box.scrollTop = box.scrollHeight;
    if (box.scrollTop === was) {
      box.scrollTop = Math.max(0, was - 240);
      box.scrollTop = box.scrollHeight;
    }
    return true;
  };
''';

/// 카드를 읽어 오는 토막 — 두 스크립트가 같은 눈으로 목록을 본다.
const _cardsChunk = r'''
  const norm = value => String(value || '').replace(/\s+/g, ' ').trim();
  const squash = value => String(value || '').replace(/\s+/g, '');
  const isTakedown = el => config.labels.includes(norm(el.textContent));
  // 카드에서 번호를 뽑는다. 「등록번호 : 50144198」(직방)처럼 이름이 붙어 있으면 그
  // 이름을 믿고, 이름 없이 놓인 「58948955」(다방)는 자릿수로 가린다 — 조회수·찜·층은
  // 그만큼 길지 않고, 날짜는 점으로 끊어져 있다.
  const numberIn = text => {
    const labelled = text.match(/(?:등록번호|매물번호)\s*[:：]?\s*(\d{4,})/);
    if (labelled) return labelled[1];
    const bare = text.match(/(?:^|[^0-9])(\d{7,})(?![0-9])/);
    return bare ? bare[1] : null;
  };
  // 종료 버튼 하나가 카드 한 장이다. 버튼에서 위로 올라가다가 번호를 품은 첫 상자가
  // 그 버튼의 카드다 — 더 올라가면 목록 전체를 한 장으로 세게 된다.
  const readCards = () => {
    const cards = [];
    const seen = new Set();
    for (const button of document.querySelectorAll('button, a, [role="button"]')) {
      if (!isTakedown(button)) continue;
      for (let node = button.parentElement; node && node !== document.body;
           node = node.parentElement) {
        const text = norm(node.innerText);
        const number = numberIn(text);
        if (!number) continue;
        if (!seen.has(node)) {
          seen.add(node);
          cards.push({number, text});
        }
        break;
      }
    }
    return cards;
  };
''';

/// 카드 한 장을 한방이 아는 것과 견주는 토막.
///
/// 점수는 「얼마나 드문 일치인가」다. 제목이 같은 매물은 거의 없고(3), 주소가 같아도
/// 호수가 다른 매물은 한 건물에 여럿 있으며(2), 금액이 같은 매물은 목록에 수두룩하다
/// — 그래도 금액 둘이 겹치면 우연이 아니라고 볼 만하다(2). 호수 하나는 혼자서는
/// 아무 말도 하지 못한다(1). 통과선 3 은 **한 가지만으로는 모자란다**는 뜻이다.
const _scoreChunk = r'''
  const has = (haystack, needle) => {
    const wanted = squash(needle);
    return wanted.length > 1 && haystack.includes(wanted);
  };
  const score = cards => cards.map(card => {
    const text = squash(card.text);
    const hints = config.hints;
    let score = 0;
    const why = [];
    if (has(text, hints.title)) { score += 3; why.push('제목'); }
    if (has(text, hints.address)) { score += 2; why.push('주소'); }
    else if (hints.address) {
      // 목록은 주소를 저마다 다르게 줄여 적는다. 시·도를 떼고 「동 번지」만 본다.
      const tail = String(hints.address).split(/\s+/).slice(-2).join('');
      if (has(text, tail)) { score += 2; why.push('주소'); }
    }
    if (hints.unit && has(text, hints.unit + '호')) { score += 1; why.push('호'); }
    if (has(text, hints.price)) { score += 2; why.push('금액'); }
    return {number: card.number, score, why};
  }).sort((a, b) => b.score - a.score);
''';

/// 두 플랫폼이 검색창에 적어 둔 말 (미러 실측 2026-09-21).
const _searchHints = ['등록번호', '매물번호'];

/// 통합 폼의 값에서 목록과 견줄 것만 고른다.
Map<String, String> _hintsOf(Map<String, dynamic> values) {
  String at(String key) => '${values[key] ?? ''}'.trim();
  return {
    'title': at('title'),
    'address': at('address'),
    'unit': at('unit'),
    'price': listingPriceLine(values),
  };
}

/// 목록의 카드가 금액을 적는 방식 — 「월세 200/25」·「전세 1000」·「매매 12500」.
///
/// [Listing.priceLine] 과 달리 억 단위로 접지 않는다. 직방과 다방 모두 카드에는
/// 만원 단위를 그대로 적는다 (미러 실측 2026-09-21: 「월세 200/25」·「매매 1억2500」).
/// 접는 쪽은 한방의 화면 사정이지 플랫폼의 표기가 아니다.
String listingPriceLine(Map<String, dynamic> values) {
  String number(String key) =>
      '${values[key] ?? ''}'.replaceAll(',', '').trim();
  final trade = '${values['trade'] ?? ''}'.trim();
  return switch (trade) {
    '월세' => '월세 ${number('deposit')}/${number('monthlyRent')}',
    '전세' => '전세 ${number('deposit')}',
    '매매' => '매매 ${number('salePrice')}',
    _ => '',
  };
}
