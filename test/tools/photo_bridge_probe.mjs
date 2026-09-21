// 사진 다리(lib/photo_transfer.dart)의 **판단 규칙을 실제로 돌려 보는** 하네스.
//
// 왜 필요한가 — 다리의 어려운 부분은 전부 JavaScript 문자열 안에 있고, Dart 테스트는
// 그 문자열에 어떤 글자가 들어 있는지밖에 못 본다. 「카드가 앉았는가 / 폼이 다시
// 그려졌는가 / 카드가 떴다 사라졌는가」는 글자가 아니라 **돌려 봐야** 알 수 있는
// 것이고, 실기기에서 47초를 헛기다리게 만든 것이 바로 이 판단이었다(2026-09-20).
//
// 브라우저를 띄우지 않는다. 다리가 실제로 만지는 것만 가짜로 세운 뒤(파일 입력 한 개,
// 사진 자리 한 개, 카드 목록) node:vm 안에서 다리를 그대로 돌린다. 시계도 우리가 쥐고
// 있어 「얼마나 버텼는가」를 기다리지 않고 잰다.
//
//   node test/tools/photo_bridge_probe.mjs --script=<다리 JS 파일> [--target=zigbang]
//
// 직방은 사진을 창 안에서 받으므로 가짜 세상도 다르다 — `--target=zigbang` 이 그쪽
// 세상과 그쪽 물음들을 고른다.
//
// stdout 에 JSON 한 덩이를 찍는다: {cases: [{name, pass, got, want}], pass}.
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const scriptPath = (process.argv.find((a) => a.startsWith('--script=')) || '').slice(9);
if (!scriptPath) {
  console.log(JSON.stringify({skip: '--script=<path> 가 필요합니다.'}));
  process.exit(0);
}
const bridgeSource = readFileSync(scriptPath, 'utf8');
const target = (process.argv.find((a) => a.startsWith('--target=')) || '--target=dabang').slice(9);

/* ── 가짜 DOM ────────────────────────────────────────────────
 * 다리가 만지는 것만 있다. 없는 것을 흉내 내면 하네스가 진실의 자리를 빼앗는다. */
const CARDS = 'section#visual_info [class*="SortableContainer"] [data-index]';

const element = (tag, cls, attrs) => {
  const node = {
    tagName: tag.toUpperCase(),
    className: cls || '',
    _attrs: {...(attrs || {})},
    dataset: {},
    children: [],
    textContent: '',
    getAttribute(name) {
      return Object.prototype.hasOwnProperty.call(this._attrs, name) ? this._attrs[name] : null;
    },
    setAttribute(name, value) {
      this._attrs[name] = String(value);
      if (name.startsWith('data-')) this.dataset[name.slice(5)] = String(value);
    },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    contains(other) { return other === this; },
    dispatchEvent() { return true; },
    click() {},
    parentElement: null,
  };
  Object.defineProperty(node, 'attributes', {
    get() { return Object.entries(this._attrs).map(([name, value]) => ({name, value})); },
  });
  for (const [name, value] of Object.entries(node._attrs)) {
    if (name.startsWith('data-')) node.dataset[name.slice(5)] = String(value);
  }
  return node;
};

const card = (id, disabled) => element('div', 'styled__Card-sc-1wpie1-3 gprsbc', {
  'data-index': '0',
  'data-id': id,
  'aria-disabled': disabled ? 'true' : 'false',
  'aria-roledescription': 'sortable',
});

class World {
  constructor() {
    this.input = element('input', '', {});
    this.input.type = 'file';
    this.input.multiple = true;
    this.input.accept = 'image/*';
    this.input.files = {length: 0};
    this.spot = element('section', 'scroll-element', {});
    this.spot.id = 'visual_info';
    this.cards = [];
  }

  /// 폼이 통째로 다시 그려졌다 — 다방이 주소를 고를 때 하는 일이다. 노드가 갈리고
  /// 올라가 있던 카드도 함께 사라진다.
  rebuild() {
    const fresh = element('section', 'scroll-element', {});
    fresh.id = 'visual_info';
    this.spot = fresh;
    this.cards = [];
  }

  document() {
    const world = this;
    return {
      getElementById: (id) => (id === 'visual_info' ? world.spot : null),
      querySelectorAll(selector) {
        if (selector === 'input[type="file"]') return [world.input];
        if (selector === CARDS) return world.cards;
        return [];
      },
      createElement: (tag) => element(tag, '', {}),
      head: {appendChild() {}},
      body: element('body', '', {}),
      documentElement: {style: {}},
      addEventListener() {},
    };
  }
}

const run = (world, clock) => {
  const sandbox = {
    console,
    atob: (value) => Buffer.from(value, 'base64').toString('binary'),
    location: {hostname: 'pro.dabangapp.com', pathname: '/form/room'},
    Date: new Proxy(Date, {get: (target, key) => (key === 'now' ? () => clock.now : target[key])}),
    MutationObserver: class {
      constructor(callback) { this.callback = callback; }
      observe() {}
      disconnect() {}
    },
    File: class {
      constructor(parts, name, options) {
        this.size = parts.reduce((total, part) => total + (part.length || part.byteLength || 0), 0);
        this.name = name;
        this.type = (options || {}).type;
      }
    },
    DataTransfer: class {
      constructor() { this._files = []; this.items = {add: (file) => this._files.push(file)}; }
      get files() { const list = this._files.slice(); list.length = this._files.length; return list; }
    },
    FileReader: class {
      readAsArrayBuffer() { if (this.onload) this.onload(); }
    },
    Event: class { constructor(type) { this.type = type; } },
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.document = world.document();
  sandbox.window.addEventListener = () => {};
  vm.createContext(sandbox);
  const opened = JSON.parse(vm.runInContext(bridgeSource, sandbox));
  if (opened.error) throw new Error('다리가 열리지 않았다: ' + opened.error);
  return sandbox;
};

/// 한 장을 넣고 commit 까지 간다. 이후의 카드 모양은 부르는 쪽이 정한다.
const commitOne = (world, clock) => {
  const sandbox = run(world, clock);
  const call = (method, ...args) =>
    JSON.parse(vm.runInContext(
      `JSON.stringify(window.__flrPhotos.${method}(...${JSON.stringify(args)}))`,
      sandbox,
    ));
  call('begin', {name: 'photo-1.png', type: 'image/png', size: 4, lastModified: 0}, 1);
  call('append', Buffer.from([1, 2, 3, 4]).toString('base64'));
  call('commit');
  return {call, sandbox};
};

const cases = [];
const check = (name, got, want) => {
  const pass = JSON.stringify(got) === JSON.stringify(want);
  cases.push({name, pass, got, want});
};

if (target === 'zigbang') {
/* ── 직방의 가짜 세상 ─────────────────────────────────────────
 * 직방은 사진을 창 안에서 받는다(2026-09-08 현장조사 §3-6). 폼에는 값을 받아 적기만
 * 하는 readonly `input[name=images]` 와 빈 카드 목록(ul)뿐이고, 그 칸을 누르면
 * 「이미지 넣기」 창이 열린다. 진짜 파일 입력은 그 창 안에 있다.
 *
 * 그래서 여기서 흉내 내는 것은 **세 가지**다: 눌러야 열리는 창, 사진을 다 받고 나서야
 * 풀리는 [확인], 그리고 [확인] 뒤에야 생기는 폼의 카드들. */
class ZigbangWorld {
  constructor(clock) {
    // 창은 **곧바로** 뜨지 않는다 — Radix 가 애니메이션을 마쳐야 문서에 앉는다.
    // 다리는 그동안 「아직」이라고 답해야 하고, 답답하다고 트리거를 다시 누르면
    // 방금 연 창을 도로 닫는다.
    this.clock = clock;
    this.openAt = null;
    this.taps = 0;
    this.confirmEnabled = false;
    this.cards = [];
    this.ul = element('ul', 'mt-2 flex flex-wrap', {});
    const world = this;
    this.ul.querySelectorAll = () => world.cards;
    Object.defineProperty(this.ul, 'children', {get: () => world.cards});

    this.field = element('div', 'relative space-y-1.5', {});
    this.field.querySelector = (selector) => (selector === 'ul' ? world.ul : null);
    this.field.querySelectorAll = (selector) =>
      selector === 'ul > *' ? world.cards : [];

    this.wrap = element('div', 'relative md:w-1/2', {});
    this.wrap.parentElement = this.field;
    this.trigger = element('input', 'cursor-pointer', {name: 'images'});
    this.trigger.readOnly = true;
    this.trigger.parentElement = this.wrap;
    // 누르면 창이 열린다 — 실물의 React onClick 자리다.
    this.trigger.click = () => { world.taps++; world.openAt = world.clock.now + 500; };
    this.trigger.dispatchEvent = () => true;

    this.input = element('input', '', {});
    this.input.type = 'file';
    this.input.multiple = true;
    this.input.accept = 'image/*,.png,.jpg,.jpeg';
    this.input.files = {length: 0};

    this.confirm = element('button', '', {});
    this.confirm.textContent = '확인';
    Object.defineProperty(this.confirm, 'disabled', {
      get: () => !world.confirmEnabled,
    });
    // [확인] 을 누르면 창이 닫히고, 그제야 폼에 카드가 앉는다.
    this.confirm.click = () => {
      if (!world.confirmEnabled) return;
      world.openAt = null;
      world.cards = world.delivered.map((_, index) =>
        element('li', 'aspect-square', {'data-id': 'zb-' + index, 'aria-disabled': 'false'}));
    };
    this.confirm.dispatchEvent = () => true;

    this.dialog = element('div', '', {role: 'dialog', 'data-state': 'open'});
    this.dialog.textContent = '이미지 넣기 클릭하여 파일 첨부 또는 파일을 여기로 끌어 놓으세요.';
    this.dialog.querySelector = (selector) =>
      selector === 'input[type="file"]' ? world.input : null;
    this.dialog.querySelectorAll = (selector) =>
      selector === 'button' ? [world.confirm] : [];

    this.delivered = [];
  }

  /// 직방이 사진을 다 받았다 — 이제 [확인] 이 풀린다. 실물에서는 업로드가 끝나는 순간이다.
  accept(files) {
    this.delivered = files;
    this.confirmEnabled = files.length >= 5;
  }

  get opened() {
    return this.openAt !== null && this.clock.now >= this.openAt;
  }

  document() {
    const world = this;
    return {
      getElementById: () => null,
      querySelector(selector) {
        if (selector === 'input[name="images"]') return world.trigger;
        return null;
      },
      querySelectorAll(selector) {
        if (selector === '[role="dialog"]') return world.opened ? [world.dialog] : [];
        return [];
      },
      createElement: (tag) => element(tag, '', {}),
      head: {appendChild() {}},
      body: element('body', '', {}),
      documentElement: {style: {}},
      addEventListener() {},
    };
  }
}

const runZigbang = (world, clock) => {
  const sandbox = {
    console,
    atob: (value) => Buffer.from(value, 'base64').toString('binary'),
    location: {hostname: 'ceo.zigbang.com', pathname: '/ads/oneroom/ad-item/new'},
    Date: new Proxy(Date, {get: (t, key) => (key === 'now' ? () => clock.now : t[key])}),
    MutationObserver: class {
      constructor(callback) { this.callback = callback; }
      observe() {}
      disconnect() {}
    },
    File: class {
      constructor(parts, name, options) {
        this.size = parts.reduce((total, part) => total + (part.length || part.byteLength || 0), 0);
        this.name = name;
        this.type = (options || {}).type;
      }
    },
    DataTransfer: class {
      constructor() { this._files = []; this.items = {add: (file) => this._files.push(file)}; }
      get files() { const list = this._files.slice(); list.length = this._files.length; return list; }
    },
    FileReader: class { readAsArrayBuffer() { if (this.onload) this.onload(); } },
    Event: class { constructor(type) { this.type = type; } },
    PointerEvent: class { constructor(type) { this.type = type; } },
    MouseEvent: class { constructor(type) { this.type = type; } },
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.document = world.document();
  sandbox.window.addEventListener = () => {};
  // 파일이 들어오는 순간을 잡아 직방 몫의 반응을 낸다.
  const nativeSetter = world.input;
  Object.defineProperty(nativeSetter, 'files', {
    get() { return this._files || {length: 0}; },
    set(value) { this._files = value; world.accept([...value]); },
  });
  vm.createContext(sandbox);
  const opened = JSON.parse(vm.runInContext(bridgeSource, sandbox));
  if (opened.error) throw new Error('다리가 열리지 않았다: ' + opened.error);
  const call = (method, ...args) =>
    JSON.parse(vm.runInContext(
      `JSON.stringify(window.__flrPhotos.${method}(...${JSON.stringify(args)}))`,
      sandbox,
    ));
  return {call, sandbox};
};

/// 사진 한 장을 다리로 흘려보낸다. 마지막 장에서만 실제로 건네진다.
const stage = (call, number, total) => {
  call('begin', {name: 'photo-' + number + '.png', type: 'image/png', size: 4, lastModified: 0},
    total - number + 1);
  call('append', Buffer.from([1, 2, 3, number]).toString('base64'));
  return call('commit');
};

/// 창이 열릴 때까지 되묻는다 — 네이티브가 하는 그대로다.
const openWindow = (call, clock) => {
  for (let tries = 0; tries < 20; tries++) {
    if (call('open').ready) return true;
    clock.now += 250;
  }
  return false;
};

// ㉠ 창을 열기 전에는 파일 입력이 문서에 없다. 다리가 트리거를 눌러 창을 열고, 창이
//    뜰 때까지 「아직」이라고 답한다 — 그사이 트리거를 다시 누르면 창이 도로 닫힌다.
{
  const clock = {now: 1_000_000};
  const world = new ZigbangWorld(clock);
  const {call} = runZigbang(world, clock);
  const before = call('open');
  const opened = openWindow(call, clock);
  check('창을 눌러 열고 나서야 파일 입력에 닿는다',
    [before.ready, opened, world.taps], [false, true, 1]);
}

// ㉡ 다 모이기 전에는 쥐고만 있는다. 직방은 5장 미만을 받지 않으므로 한 장씩 건네면
//    매번 거절당한다 — 사람이 파일 선택 창에서 하듯 한 번에 건넨다.
{
  const clock = {now: 2_000_000};
  const world = new ZigbangWorld(clock);
  const {call} = runZigbang(world, clock);
  openWindow(call, clock);
  const steps = [];
  for (let number = 1; number <= 5; number++) steps.push(stage(call, number, 5));
  check('다섯 장이 다 모인 뒤에 한 번에 건넨다',
    [steps.map((s) => s.staged || 0), steps[4].dispatched, steps[4].files, world.delivered.length],
    [[1, 2, 3, 4, 0], true, 5, 5]);
}

// ㉢ [확인] 은 직방이 사진을 다 받고 나서야 풀린다. 잠겨 있는 동안은 아직이라고 답하고,
//    풀리면 누르고, 창이 닫힌 것을 보고서야 끝났다고 한다.
{
  const clock = {now: 3_000_000};
  const world = new ZigbangWorld(clock);
  const {call} = runZigbang(world, clock);
  openWindow(call, clock);
  for (let number = 1; number <= 4; number++) stage(call, number, 5);
  const locked = call('seal');
  stage(call, 5, 5);
  const pressing = call('seal');
  const closed = call('seal');
  check('확인이 풀려야 누르고, 창이 닫히면 끝이다',
    [locked.sealed, pressing.sealed, world.opened, closed.sealed],
    [false, false, false, true]);
}

// ㉣ 카드는 [확인] 뒤에야 생기고, 건넨 만큼 다 앉아야 끝이다. 한 장이라도 모자라면
//    아직이다 — 「다섯 장을 보냈는데 네 장만 붙었다」를 성공이라고 말하지 않는다.
{
  const clock = {now: 4_000_000};
  const world = new ZigbangWorld(clock);
  const {call} = runZigbang(world, clock);
  openWindow(call, clock);
  for (let number = 1; number <= 5; number++) stage(call, number, 5);
  const waiting = call('status');
  call('seal');
  call('seal');
  const short = world.cards.pop();
  const partial = call('status');
  world.cards.push(short);
  const done = call('status');
  check('카드가 다섯 장 다 앉아야 끝이다',
    [waiting.ready, waiting.want, partial.ready, partial.count, done.ready, done.count],
    [false, 5, false, 4, true, 5]);
}
} else {
  // ① 미러처럼 카드가 처리 완료(aria-disabled=false)로 앉으면 곧바로 끝이다.
  {
    const world = new World();
    const clock = {now: 1_000_000};
    const {call} = commitOne(world, clock);
    world.cards = [card('abc', false)];
    const state = call('status');
    check('처리 완료로 앉은 카드는 곧바로 ready', [state.ready, !!state.patient, state.id], [true, false, 'abc']);
  }

  // ② 실물처럼 서버 id 를 받고도 잠긴 채 남는 카드. 버티는 동안은 아직이고, 오래 버티면
  //    붙은 것으로 본다 — 이것이 없으면 **이미 올라간 사진**을 실패라고 말하게 된다.
  {
    const world = new World();
    const clock = {now: 2_000_000};
    const {call} = commitOne(world, clock);
    world.cards = [card('ieharLQK5nBwRbUQ5ujGG', true)];
    const early = call('status');
    clock.now += 1500;
    const middle = call('status');
    clock.now += 3000;
    const late = call('status');
    check('잠긴 카드는 버틴 뒤에야 인정한다',
      [early.ready, middle.ready, late.ready, !!late.patient, late.id],
      [false, false, true, true, 'ieharLQK5nBwRbUQ5ujGG']);
  }

  // ③ 카드가 잠깐 떴다가 사라졌다 = 폼이 쓸어 간 것이다. 기다림이 아니라 다시 붙이기가 답.
  {
    const world = new World();
    const clock = {now: 3_000_000};
    const {call, sandbox} = commitOne(world, clock);
    world.cards = [card('gone-me', true)];
    call('status');
    // 관찰자가 본 봉우리. 실기기에서 「카드가 한때 1장까지 보였다가 사라졌습니다」가 이것이다.
    vm.runInContext('window.__flrPhotos.peak = 1; window.__flrPhotos.peakAt = Date.now();', sandbox);
    world.cards = [];
    clock.now += 2000;
    const state = call('status');
    check('떴다 사라진 카드는 쓸려 간 것으로 말한다',
      [state.ready, state.gone, state.wiped, state.count], [false, true, true, 0]);
  }

  // ④ 사진 자리 노드가 갈렸다 = 폼이 통째로 다시 그려졌다. 관찰자는 옛 노드에 붙은 채
  //    남으므로 mutations 는 멈춘다 — 그것만으로는 「조용하다」와 구분되지 않는다.
  {
    const world = new World();
    const clock = {now: 4_000_000};
    const {call} = commitOne(world, clock);
    const before = call('status');
    world.rebuild();
    const after = call('status');
    check('사진 자리가 갈리면 remade 로 말한다',
      [before.remade, after.remade, after.wiped], [false, true, true]);
  }

  // ④-ㄴ 다시 그려지면서 **카드를 안고 간** 경우는 쓸려 간 것이 아니다. 여기서 쓸려 갔다고
  //      하면 이미 올라간 사진을 한 번 더 올려 남의 광고에 같은 사진이 두 장 붙는다.
  {
    const world = new World();
    const clock = {now: 4_500_000};
    const {call} = commitOne(world, clock);
    world.rebuild();
    world.cards = [card('survivor', false)];
    const state = call('status');
    check('카드를 안고 다시 그려졌으면 다시 붙이지 않는다',
      [state.ready, state.remade, state.wiped], [true, true, false]);
  }

  // ⑤ 인정한 카드가 잠긴 채 남아도 다음 사진을 막지 않는다. 막으면 2장째부터 늘 실패한다.
  {
    const world = new World();
    const clock = {now: 5_000_000};
    const {call} = commitOne(world, clock);
    world.cards = [card('first', true)];
    // 버팀은 **처음 본 순간부터** 잰다 — 한 번 보고 곧바로 인정하면 「떴다가 사라지는
    // 카드」까지 성공으로 세게 된다.
    const seen = call('status');
    clock.now += 5000;
    const first = call('status');
    let blocked = null;
    try {
      call('begin', {name: 'photo-2.png', type: 'image/png', size: 4, lastModified: 0}, 1);
    } catch (error) {
      blocked = String(error && error.message ? error.message : error);
    }
    check('인정한 카드는 다음 사진을 막지 않는다',
      [seen.ready, first.ready, blocked], [false, true, null]);
  }

  // ⑥ 「사진 붙이는 중」 표식. 폼 어댑터가 이것을 보고 폼을 건드리지 않는다.
  {
    const world = new World();
    const clock = {now: 6_000_000};
    const {call, sandbox} = commitOne(world, clock);
    const during = vm.runInContext('window.__flrPhotos.until > Date.now()', sandbox);
    call('clear');
    const after = vm.runInContext('window.__flrPhotos.until > Date.now()', sandbox);
    check('전송 중에만 폼을 잠근다', [during, after], [true, false]);
  }

}

const pass = cases.every((item) => item.pass);
console.log(JSON.stringify({pass, cases}, null, 2));
process.exit(pass ? 0 : 1);
