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
//   node test/tools/photo_bridge_probe.mjs --script=<다리 JS 파일>
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
    querySelectorAll() { return []; },
    contains(other) { return other === this; },
    dispatchEvent() { return true; },
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

const pass = cases.every((item) => item.pass);
console.log(JSON.stringify({pass, cases}, null, 2));
process.exit(pass ? 0 : 1);
