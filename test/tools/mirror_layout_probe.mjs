// Drives one mirror in a phone-sized headless Chrome and reports what the
// agent's thumb would find. Every URL comes from the caller, so this harness
// cannot drift from what the app actually loads.
//
// Three jobs:
//
//   --job=layout  install the layout script on --form and measure the CTA
//   --job=signin  install it on --login and measure the sign-in controls
//   --job=routes  sign in at --login, then report where each app URL lands
//
// The first exists because greping the generated CSS cannot tell whether the
// 등록 button is on the screen — 다방's sat 499px past the right edge while
// every such assertion passed. The second exists because nothing offline can
// tell whether the mirror will even serve the form: it gates 직방 and 다방
// behind their own login and answers 302 to everything else, which once left
// 매물 등록 staring at 직방's landing page for a three-minute timeout.
//
// Prints one JSON object on stdout. `skip` is set, rather than a failure,
// when the environment cannot run the probe at all (no Chrome, no mirror).
import {spawn} from 'node:child_process';
import {existsSync, mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const AUTH = 'Basic ' + Buffer.from('mirror:money').toString('base64');
const UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

const CHROMES = [
  process.env.CHROME_PATH,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
].filter(Boolean);

const args = Object.fromEntries(
  process.argv.slice(2).map(part => {
    const [key, ...rest] = part.replace(/^--/, '').split('=');
    return [key, rest.join('=')];
  }),
);
const job = args.job || 'layout';
const width = Number(args.width || 390);
const height = Number(args.height || 844);
const labels = args.labels ? args.labels.split('\0') : [];

const done = value => {
  process.stdout.write(JSON.stringify(value));
  process.exit(0);
};
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

// The mirror serves `.../oneroom/index.html` as a 308 to `.../oneroom/`, so
// compare the directory form, exactly as mirrorDirectory() does in Dart.
const directory = url => {
  let path = new URL(url).pathname;
  if (path.endsWith('index.html')) path = path.slice(0, -'index.html'.length);
  return path.endsWith('/') ? path : path + '/';
};

const binary = CHROMES.find(path => existsSync(path));
if (!binary) done({skip: 'no Chrome binary found'});

const MEASURE = `(() => {
  const norm = value => String(value || '').replace(/\\s+/g, ' ').trim();
  const labels = ${JSON.stringify(labels)};
  const vw = document.documentElement.clientWidth;
  const vh = document.documentElement.clientHeight;
  const ctas = [...document.querySelectorAll('button, [role="button"], input[type="submit"], a')]
    .filter(el => labels.includes(norm(el.textContent || el.value)))
    .map(el => {
      const r = el.getBoundingClientRect();
      const hit = document.elementFromPoint(
        Math.min(Math.max(r.left + r.width / 2, 1), vw - 1),
        Math.min(Math.max(r.top + r.height / 2, 1), vh - 1));
      return {
        label: norm(el.textContent),
        rect: {x: Math.round(r.x), y: Math.round(r.y),
               w: Math.round(r.width), h: Math.round(r.height)},
        insideX: r.left >= -1 && r.right <= vw + 1,
        insideY: r.top >= -1 && r.bottom <= vh + 1,
        // Nothing the page paints later is sitting on top of it.
        hitsSelf: !!hit && (hit === el || el.contains(hit)),
      };
    });
  // What the agent can no longer reach. Not everything past the edge counts:
  // a box whose ancestor already clips or scrolls it is the page's own doing
  // (당근's dashboard runs a 3041px review rail inside an overflow-clip card),
  // and the submit bar's chips scroll sideways on purpose.
  const contained = el => {
    for (let n = el.parentElement; n && n !== document.documentElement; n = n.parentElement) {
      const overflowX = getComputedStyle(n).overflowX;
      if (overflowX === 'visible') continue;
      if (n.getBoundingClientRect().right <= vw + 2) return true;
    }
    return false;
  };
  const lost = [...document.querySelectorAll('body *')].filter(el => {
    if (el.closest('[data-flr-mobile-submit-bar]')) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && (r.right > vw + 2 || r.left < -2) && !contained(el);
  });
  // Only the outermost: everything under one of these has the same problem.
  const wide = lost
    .filter(el => !lost.includes(el.parentElement))
    .slice(0, 12)
    .map(el => {
      const r = el.getBoundingClientRect();
      return el.tagName + '.' + String(el.className).slice(0, 52) +
        ' [' + Math.round(r.left) + '..' + Math.round(r.right) + ']';
    });
  return {
    viewport: vw,
    docScrollWidth: document.documentElement.scrollWidth,
    bodyScrollWidth: document.body.scrollWidth,
    title: document.title,
    url: location.href,
    ctas,
    wide,
  };
})()`;

// Can a thumb actually reach what the sign-in page asks for? 다방 laid these
// out at x=405 on a 390px screen, which made onboarding impossible to finish.
const CONTROLS = `(() => {
  const vw = document.documentElement.clientWidth;
  const vh = document.documentElement.clientHeight;
  const text = el => (el.textContent || '').replace(/\\s+/g, ' ').trim();
  // 직방 submits with a <div>, not a button, and calls it 시작하기.
  const submit = document.querySelector('form button[type=submit]') ||
    [...document.querySelectorAll('button, div[role=button], div, a')]
      .filter(el => /^(시작하기|로그인)$/.test(text(el)))
      .sort((a, b) => a.querySelectorAll('*').length - b.querySelectorAll('*').length)[0];
  const measure = (what, el) => {
    if (!el) return null;
    // A control below the fold is reached by scrolling down, so scroll the way
    // the agent would before asking whether anything covers it. Sideways is a
    // different matter: scrollIntoView will happily pan right to fetch a
    // control the page put off-screen, and that would score 다방's 로그인 at
    // x=405 as reachable. Put the page back at its left edge — that is where
    // the WebView shows it, and where the thumb has to find things.
    el.scrollIntoView({block: 'center'});
    window.scrollTo(0, window.scrollY);
    const r = el.getBoundingClientRect();
    const hit = document.elementFromPoint(
      Math.min(Math.max(r.left + r.width / 2, 1), vw - 1),
      Math.min(Math.max(r.top + r.height / 2, 1), vh - 1));
    return {
      what,
      rect: {x: Math.round(r.x), y: Math.round(r.y),
             w: Math.round(r.width), h: Math.round(r.height)},
      onScreen: r.width > 0 && r.left >= -1 && r.right <= vw + 1,
      hittable: !!hit && (hit === el || el.contains(hit)),
    };
  };
  return {
    viewport: vw,
    title: document.title,
    url: location.href,
    bodyScrollWidth: document.body.scrollWidth,
    controls: [
      measure('아이디', document.querySelector(
        'input[name=email],input[type=email],input[type=text]')),
      measure('비밀번호', document.querySelector('input[type=password]')),
      measure('로그인', submit),
    ].filter(Boolean),
  };
})()`;

// Fills and submits whatever sign-in form the platform put up. Each mirror
// spells its submit differently, so press what looks like one.
const SIGN_IN = `(() => {
  const email = document.querySelector('input[name=email],input[type=email],input[type=text]');
  const password = document.querySelector('input[type=password]');
  if (!email || !password) return 'no sign-in fields on ' + location.pathname;
  const set = (el, value) => Object.getOwnPropertyDescriptor(
    HTMLInputElement.prototype, 'value').set.call(el, value);
  set(email, 'mirror@test.kr');
  set(password, 'mirror');
  email.dispatchEvent(new Event('input', {bubbles: true}));
  password.dispatchEvent(new Event('input', {bubbles: true}));
  const text = el => (el.textContent || '').replace(/\\s+/g, ' ').trim();
  const submit = document.querySelector('form button[type=submit]') ||
    [...document.querySelectorAll('button, div[role=button], div, a')]
      .filter(el => /^(시작하기|로그인)$/.test(text(el)))
      .sort((a, b) => a.querySelectorAll('*').length - b.querySelectorAll('*').length)[0];
  if (!submit) return 'no submit control on ' + location.pathname;
  submit.click();
  return 'ok';
})()`;

const profile = mkdtempSync(join(tmpdir(), 'flr-mirror-'));
let chrome = null;
let socket = null;

const shutdown = () => {
  try { socket?.close(); } catch (_) { /* already gone */ }
  try { chrome?.kill(); } catch (_) { /* already gone */ }
  try { rmSync(profile, {recursive: true, force: true}); } catch (_) { /* ok */ }
};
process.on('exit', shutdown);

try {
  const port = 9300 + Math.floor(Math.random() * 600);
  chrome = spawn(binary, [
    '--headless=new',
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${profile}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-gpu',
    '--hide-scrollbars',
    `--window-size=${width},${height}`,
    'about:blank',
  ], {stdio: 'ignore'});

  let targets = null;
  for (let attempt = 0; attempt < 120 && !targets?.length; attempt++) {
    await sleep(100);
    try {
      targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    } catch (_) { /* not listening yet */ }
  }
  const target = targets?.find(entry => entry.type === 'page');
  if (!target) done({skip: 'Chrome did not expose a debugging target'});

  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.onopen = resolve;
    socket.onerror = () => reject(new Error('devtools socket refused'));
  });

  let nextId = 0;
  const pending = new Map();
  let loaded = false;
  socket.onmessage = event => {
    const message = JSON.parse(event.data);
    if (message.id == null) {
      if (message.method === 'Page.loadEventFired') loaded = true;
      return;
    }
    const waiter = pending.get(message.id);
    pending.delete(message.id);
    if (!waiter) return;
    message.error ? waiter.reject(new Error(JSON.stringify(message.error)))
                  : waiter.resolve(message.result);
  };
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++nextId;
    pending.set(id, {resolve, reject});
    socket.send(JSON.stringify({id, method, params}));
  });

  const evaluate = async expression => {
    const result = await send('Runtime.evaluate', {
      expression, returnByValue: true, awaitPromise: true,
    });
    if (result.exceptionDetails) {
      throw new Error(result.exceptionDetails.exception?.description ||
        JSON.stringify(result.exceptionDetails));
    }
    return result.result.value;
  };
  const goto = async url => {
    loaded = false;
    await send('Page.navigate', {url});
    for (let waited = 0; !loaded && waited < 20000; waited += 100) await sleep(100);
    await sleep(700);
  };

  await send('Page.enable');
  await send('Runtime.enable');
  await send('Network.enable');
  await send('Network.setExtraHTTPHeaders', {headers: {Authorization: AUTH}});
  await send('Emulation.setUserAgentOverride', {userAgent: UA});
  await send('Emulation.setDeviceMetricsOverride', {
    width, height, deviceScaleFactor: 2, mobile: true,
  });
  await send('Emulation.setTouchEmulationEnabled', {enabled: true, maxTouchPoints: 5});

  // Where each app URL lands with no session at all. This is the state a fresh
  // install is in, and what the old stand-in login left the WebView in.
  const signedOut = {};
  if (job === 'routes') {
    for (const name of ['login', 'dashboard', 'form', 'listings']) {
      if (!args[name]) continue;
      await goto(args[name]);
      signedOut[name] = {
        landed: directory(await evaluate('location.href')),
        wanted: directory(args[name]),
        title: await evaluate('document.title'),
      };
    }
  }

  // Sign in the way the agent does: on the platform's own page.
  await goto(args.login);

  if (job === 'signin') {
    await evaluate(readFileSync(args.script, 'utf8'));
    await sleep(1200);
    done({job, ...(await evaluate(CONTROLS))});
  }

  const signedInAt = directory(await evaluate('location.href'));
  let outcome = 'ok';
  if (signedInAt === directory(args.login) && args.login !== args.dashboard) {
    outcome = await evaluate(SIGN_IN);
    if (outcome !== 'ok') done({skip: 'mirror sign-in unavailable: ' + outcome});
    for (let attempt = 0; attempt < 40; attempt++) {
      await sleep(250);
      if (directory(await evaluate('location.href')) !== directory(args.login)) break;
    }
    await sleep(800);
  }
  const afterLogin = {
    landed: directory(await evaluate('location.href')),
    wanted: directory(args.dashboard),
    title: await evaluate('document.title'),
  };

  if (job === 'routes') {
    const signedIn = {};
    for (const name of ['dashboard', 'form', 'listings']) {
      if (!args[name]) continue;
      await goto(args[name]);
      signedIn[name] = {
        landed: directory(await evaluate('location.href')),
        wanted: directory(args[name]),
        title: await evaluate('document.title'),
      };
    }
    done({job, signedOut, afterLogin, signedIn});
  }

  await goto(args.form);
  const landed = directory(await evaluate('location.href'));
  if (landed !== directory(args.form)) {
    done({skip: 'mirror did not serve the form (landed on ' + landed + ')'});
  }

  const installed = await evaluate(readFileSync(args.script, 'utf8'));
  await sleep(1200);
  // The CTA lives at the bottom; look where the agent would look.
  await evaluate('window.scrollTo(0, document.documentElement.scrollHeight)');
  await sleep(500);
  done({installed, ...(await evaluate(MEASURE))});
} catch (error) {
  done({skip: 'probe could not run: ' + (error?.message || error)});
}
