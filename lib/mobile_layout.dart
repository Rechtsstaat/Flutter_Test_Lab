import 'dart:convert';

import 'fields.dart';

/// Builds the non-destructive mobile presentation installed over a platform
/// page — the live 직방 CEO and 다방프로 pages, or their mirror.
///
/// The real controls remain in the DOM so React handlers, validation, focus and
/// trusted submit clicks continue to work. Only this platform's own corner of a
/// known site is eligible ([ListingPlatformConfig.siteOf]); anything else — the
/// Kakao postcode frame, 직방's account.zigbang.com login, another platform —
/// deliberately receives no script.
///
/// The hard part is never the content but what wraps it. These are desktop
/// pages, and a desktop page pins its width high up — 다방 carries
/// `#root { min-width: 1200px }` and `.root-layout > div { width: 1200px }`,
/// 당근 a `min-width: 1433px` column. Narrowing only the content leaves those
/// boxes at their desktop width, and since the page is then clipped at
/// `overflow-x: hidden` everything past the viewport becomes unreachable
/// rather than merely off to the side. That is how 다방's 등록 완료 button went
/// missing at x=499, and how its 로그인 fields sat at x=405 where no thumb
/// could reach them. So the script measures the page and releases every box in
/// normal flow that is still wider than the phone.
///
/// Every page the app puts in front of the agent gets this — the platform's
/// own 로그인, its 대시보드, its 광고 목록 and the 매물 등록 form. The form
/// alone also gets a surface, a submit bar and the section chips.
String? mirrorMobileLayoutScript(ListingPlatform platform, Uri pageUrl) {
  final site = platform.siteOf(pageUrl);
  if (site == null) return null;
  final urls = platform.urlsOn(site);
  final formUrl = Uri.parse(urls.form);

  final config = jsonEncode({
    'host': urls.host,
    'root': urls.root,
    'form': pageDirectory(formUrl),
    'profile': platform.name,
    'submitLabels': platform.submitLabels,
  });

  final script = StringBuffer()
    ..write('''
(() => {
  const config = ''')
    ..write(config)
    ..write(r''';
  const directory = value => {
    let path = value || '/';
    if (path.endsWith('index.html')) path = path.slice(0, -'index.html'.length);
    return path.endsWith('/') ? path : path + '/';
  };
  const inScope = () => location.host === config.host &&
    directory(location.pathname).startsWith(config.root);
  // The 매물 등록 form is the one page with a surface, a submit bar and chips.
  // Everything else only needs to stop being 1200px wide.
  const onForm = () => directory(location.pathname) === config.form;
  if (!inScope()) return false;

  const styleId = 'flr-mobile-form-layout';
  const rootAttribute = 'data-flr-mobile-layout';
  const surfaceAttribute = 'data-flr-mobile-surface';
  const pinnedAttribute = 'data-flr-mobile-pinned';
  const submitAttribute = 'data-flr-mobile-submit';
  const submitBarAttribute = 'data-flr-mobile-submit-bar';
  const overflowAttribute = 'data-flr-mobile-overflow';
  const flowAttribute = 'data-flr-mobile-flow';
  const dialogAttribute = 'data-flr-mobile-dialog-open';
  const barProperty = '--flr-mobile-bar';
  const normalize = value => String(value || '').replace(/\s+/g, ' ').trim();
  const root = document.documentElement;

  const commonCss = `
    html[data-flr-mobile-layout] {
      width: 100% !important;
      max-width: 100vw !important;
      min-width: 0 !important;
      overflow-x: hidden !important;
      -webkit-text-size-adjust: 100%;
    }
    html[data-flr-mobile-layout] body {
      width: 100% !important;
      max-width: 100vw !important;
      min-width: 0 !important;
      margin-left: 0 !important;
      margin-right: 0 !important;
      overflow-x: hidden !important;
      touch-action: pan-y;
    }
    html[data-flr-mobile-layout] *, html[data-flr-mobile-layout] *::before,
    html[data-flr-mobile-layout] *::after { box-sizing: border-box; }
    html[data-flr-mobile-layout] body > * { max-width: 100vw !important; }
    /* Every box a desktop page laid out wider than the phone. Without this the
       content narrows inside a 1200px shell and everything on its right sits
       outside the clip — 다방's 등록 완료 at x=499, its 로그인 fields at x=405. */
    html[data-flr-mobile-layout] [data-flr-mobile-pinned] {
      width: auto !important;
      /* 100vw, not 100%: a percentage resolves against the parent, and inside
         a grid track or a shrink-to-fit box that size is indefinite, so the
         clamp is dropped. 다방's dashboard cards sat 612px wide under exactly
         that. The viewport is always a definite length. */
      max-width: 100vw !important;
      min-width: 0 !important;
      margin-left: 0 !important;
      margin-right: 0 !important;
      float: none !important;
    }
    html[data-flr-mobile-layout] [data-flr-mobile-surface] {
      width: 100% !important;
      max-width: 100% !important;
      min-width: 0 !important;
      margin-left: 0 !important;
      margin-right: 0 !important;
    }
    html[data-flr-mobile-layout] [data-flr-mobile-surface] main,
    html[data-flr-mobile-layout] [data-flr-mobile-surface] form,
    html[data-flr-mobile-layout] [data-flr-mobile-surface] section,
    html[data-flr-mobile-layout] [data-flr-mobile-surface] article,
    html[data-flr-mobile-layout] [data-flr-mobile-surface] fieldset {
      min-width: 0 !important;
      max-width: 100% !important;
    }
    /* Fits the screen itself, but its own content spills out of it or a
       desktop gutter shoved it past the edge. Centring margins are 0 at this
       width anyway.
       Note there is deliberately no rule matching grid-cols- or md:flex-row by
       name. A Tailwind page has already said what it wants on a phone:
       unprefixed grid-cols-3 IS the phone layout, and md:grid-cols-6 /
       md:flex-row are dormant below 768px. Overriding by class name fought
       that — it stacked 직방's twelve 옵션 chips into twelve rows and stretched
       a checkbox to the height of its row. Only measurement decides here. */
    html[data-flr-mobile-layout] [data-flr-mobile-overflow] {
      width: 100% !important;
      max-width: 100% !important;
      min-width: 0 !important;
      margin-left: 0 !important;
      margin-right: 0 !important;
    }
    html[data-flr-mobile-layout] [data-flr-mobile-flow="flex"] {
      flex-wrap: wrap !important;
    }
    html[data-flr-mobile-layout] [data-flr-mobile-flow="grid"] {
      grid-template-columns: minmax(0, 1fr) !important;
    }
    html[data-flr-mobile-layout] input:not([type="checkbox"]):not([type="radio"]):not([type="file"]),
    html[data-flr-mobile-layout] select,
    html[data-flr-mobile-layout] textarea {
      max-width: 100% !important;
      min-width: 0 !important;
      font-size: 16px !important;
    }
    html[data-flr-mobile-layout] [data-flr-mobile-surface] input:not([type="checkbox"]):not([type="radio"]):not([type="file"]),
    html[data-flr-mobile-layout] [data-flr-mobile-surface] select,
    html[data-flr-mobile-layout] [data-flr-mobile-surface] textarea {
      width: 100% !important;
    }
    html[data-flr-mobile-layout] [data-flr-mobile-surface] textarea { resize: vertical; }
    html[data-flr-mobile-layout] img,
    html[data-flr-mobile-layout] video,
    html[data-flr-mobile-layout] canvas {
      max-width: 100% !important;
      height: auto;
    }
    /* Only the label is relaxed. A blanket min-height here stretched 직방's
       checkbox — that control is a <button role="checkbox"> 16px square, and
       a 44px floor turned it into a tall bar. Tap targets are the platforms'
       own; the one button 한방 cares about is sized as the submit below. */
    html[data-flr-mobile-layout] [data-flr-mobile-surface] button,
    html[data-flr-mobile-layout] [data-flr-mobile-surface] [role="button"],
    html[data-flr-mobile-layout] [data-flr-mobile-surface] input[type="submit"] {
      white-space: normal !important;
    }
    html[data-flr-mobile-layout] [role="dialog"] {
      width: min(100%, calc(100vw - 24px)) !important;
      max-width: calc(100vw - 24px) !important;
      min-width: 0 !important;
      max-height: calc(100dvh - 24px) !important;
      overflow-x: hidden !important;
      /* A capped height with no scroller just hides the bottom of the sheet,
         including whatever confirms it. */
      overflow-y: auto !important;
      overscroll-behavior: contain;
    }
    html[data-flr-mobile-layout] [role="dialog"] form,
    html[data-flr-mobile-layout] [role="dialog"] section,
    html[data-flr-mobile-layout] [role="dialog"] article,
    html[data-flr-mobile-layout] [role="dialog"] fieldset {
      width: 100% !important;
      max-width: 100% !important;
      min-width: 0 !important;
    }
    html[data-flr-mobile-layout] [role="dialog"]
      input:not([type="checkbox"]):not([type="radio"]):not([type="file"]),
    html[data-flr-mobile-layout] [role="dialog"] select,
    html[data-flr-mobile-layout] [role="dialog"] textarea {
      width: 100% !important;
      max-width: 100% !important;
      min-width: 0 !important;
    }
    html[data-flr-mobile-layout][data-flr-mobile-dialog-open]
      [data-flr-mobile-submit-bar] {
      z-index: 1 !important;
      pointer-events: none !important;
    }
    html[data-flr-mobile-layout] [data-flr-mobile-submit] {
      width: 100% !important;
      min-height: 52px !important;
      font-size: 16px !important;
      font-weight: 700 !important;
    }
    html[data-flr-mobile-layout] [data-flr-mobile-submit-bar] {
      position: sticky !important;
      z-index: 40 !important;
      bottom: 0 !important;
      width: 100% !important;
      max-width: 100% !important;
      padding: 10px 12px calc(10px + env(safe-area-inset-bottom)) !important;
      background: rgba(255, 255, 255, 0.97) !important;
      border-top: 1px solid #e5e7eb !important;
    }
    /* Mirror-only chrome (never on the real sites). It is placed for a 1200px
       window, where it sits beside the form; on a phone it lands on top of the
       CTA we just rescued, and the picker is wider than the screen. */
    html[data-flr-mobile-layout] [data-mirror="badge"] {
      left: 8px !important;
      right: 8px !important;
      bottom: calc(var(--flr-mobile-bar, env(safe-area-inset-bottom)) + 8px) !important;
      max-width: none !important;
    }
    html[data-flr-mobile-layout] [data-mirror="toast"] {
      max-width: calc(100vw - 24px) !important;
      bottom: calc(var(--flr-mobile-bar, env(safe-area-inset-bottom)) + 16px) !important;
    }
    html[data-flr-mobile-layout] [data-mirror="picker"] > div {
      width: min(440px, calc(100vw - 32px)) !important;
      max-height: calc(100dvh - 48px) !important;
      overflow-y: auto !important;
    }
    /* With a sheet up, the bar underneath it is already inert, and the strip
       above the bar is where the sheet keeps its own buttons. */
    html[data-flr-mobile-layout][data-flr-mobile-dialog-open] [data-mirror="badge"],
    html[data-flr-mobile-layout][data-flr-mobile-dialog-open] [data-mirror="toast"] {
      bottom: calc(env(safe-area-inset-bottom) + 8px) !important;
    }
  `;

  const profileCss = {
    zigbang: `
      html[data-flr-mobile-layout="zigbang"] header nav,
      html[data-flr-mobile-layout="zigbang"] .no-print[class*="w-[320px]"] { display: none !important; }
      html[data-flr-mobile-layout="zigbang"] [class*="mt-[72px]"] { margin-top: 56px !important; }
      html[data-flr-mobile-layout="zigbang"] .no-print > header {
        height: 56px !important; padding: 0 14px !important;
      }
      html[data-flr-mobile-layout="zigbang"] #default-content-layout { width: 100% !important; overflow-x: hidden !important; }
      html[data-flr-mobile-layout="zigbang"] [data-flr-mobile-surface] { padding: 16px 14px !important; }
      /* 가이드 floats 50px off the corner — on a phone that is on top of the
         등록 button. */
      html[data-flr-mobile-layout="zigbang"] .no-print[class~="fixed"][class~="bottom-[50px]"] {
        bottom: calc(var(--flr-mobile-bar, 0px) + 12px) !important;
      }
      html[data-flr-mobile-layout="zigbang"][data-flr-mobile-dialog-open]
        .no-print[class~="fixed"][class~="bottom-[50px]"] {
        bottom: calc(env(safe-area-inset-bottom) + 8px) !important;
      }
    `,
    dabang: `
      html[data-flr-mobile-layout="dabang"] nav.root-layout,
      html[data-flr-mobile-layout="dabang"] #footer { display: none !important; }
      html[data-flr-mobile-layout="dabang"] .root-layout {
        width: 100% !important; max-width: 100% !important; min-width: 0 !important;
        padding-left: 12px !important; padding-right: 12px !important;
      }
      /* 다방 centres every band in an unclassed 1200px child. The 매물 등록
         title band is not an ancestor of the form, so the ancestor pass never
         reaches it — name it here. */
      html[data-flr-mobile-layout="dabang"] .root-layout > div {
        width: 100% !important; max-width: 100% !important; min-width: 0 !important;
        margin-left: 0 !important; margin-right: 0 !important;
      }
      /* 46px on a 390px screen leaves no room beside 복사하기. */
      html[data-flr-mobile-layout="dabang"] [class*="styled__PageTitle-sc-tzlsz-"] > div {
        padding: 20px 0 12px !important; gap: 12px !important;
      }
      html[data-flr-mobile-layout="dabang"] [class*="styled__PageTitle-sc-tzlsz-"] h1 {
        font-size: 22px !important; line-height: 30px !important;
      }
      /* The hover tooltips hold one unbreakable line ~460px long, anchored to
         the right of a control that is already at the edge. */
      html[data-flr-mobile-layout="dabang"] [class*="styled__Tooltip-sc-"] {
        max-width: calc(100vw - 24px) !important;
        width: max-content !important;
        left: auto !important; right: 0 !important;
      }
      html[data-flr-mobile-layout="dabang"] [class*="styled__Tooltip-sc-"] > p {
        white-space: normal !important; overflow-wrap: anywhere !important;
      }
      html[data-flr-mobile-layout="dabang"] [class*="styled__Layout-sc-h5ond6-"] {
        display: block !important; width: 100% !important; min-width: 0 !important;
      }
      html[data-flr-mobile-layout="dabang"] [class*="styled__ContentContainer-sc-h5ond6-"] {
        display: block !important; width: 100% !important; min-width: 0 !important;
        padding-bottom: calc(var(--flr-mobile-bar, 132px) + 24px) !important;
      }
      html[data-flr-mobile-layout="dabang"] [data-flr-mobile-surface] table,
      html[data-flr-mobile-layout="dabang"] [data-flr-mobile-surface] tbody,
      html[data-flr-mobile-layout="dabang"] [data-flr-mobile-surface] tr,
      html[data-flr-mobile-layout="dabang"] [data-flr-mobile-surface] th,
      html[data-flr-mobile-layout="dabang"] [data-flr-mobile-surface] td {
        display: block !important; width: 100% !important; max-width: 100% !important;
        min-width: 0 !important; height: auto !important;
      }
      html[data-flr-mobile-layout="dabang"] [data-flr-mobile-surface] colgroup { display: none !important; }
      html[data-flr-mobile-layout="dabang"] [data-flr-mobile-surface] th { padding: 18px 12px 8px !important; }
      html[data-flr-mobile-layout="dabang"] [data-flr-mobile-surface] td { padding: 8px 12px 18px !important; }
      /* The CTA rail is a 164px desktop sidebar. Sticky cannot rescue it: its
         containing block is the 1200px content row, so it would keep its
         left edge out past the clip. Fixed takes it out of that flow and
         pins it to the viewport instead. */
      html[data-flr-mobile-layout="dabang"] [class*="styled__StickyContainer-sc-h5ond6-"] {
        position: fixed !important; left: 0 !important; right: 0 !important;
        bottom: 0 !important; top: auto !important;
        width: 100% !important; max-width: 100% !important; min-width: 0 !important;
        margin: 0 !important; padding: 0 !important;
        box-sizing: border-box !important; transform: none !important;
        z-index: 40 !important; background: rgba(255, 255, 255, 0.97) !important;
        border-top: 1px solid #ededed !important;
      }
      html[data-flr-mobile-layout="dabang"] [class*="styled__StickyContainer-sc-h5ond6-"]
        > [class*="styled__Container-sc-33x7dx-"] {
        position: static !important; top: auto !important; right: auto !important;
        bottom: auto !important; left: auto !important; transform: none !important;
        display: grid !important; grid-template-columns: minmax(0, 1fr) minmax(0, 1.5fr) !important;
        gap: 8px !important; width: 100% !important; max-width: 100% !important;
        min-width: 0 !important;
        padding: 8px 12px calc(8px + env(safe-area-inset-bottom)) !important;
        box-sizing: border-box !important;
      }
      html[data-flr-mobile-layout="dabang"] [class*="styled__StickyContainer-sc-h5ond6-"]
        > [class*="styled__Container-sc-33x7dx-"] > button {
        width: 100% !important; max-width: 100% !important; min-width: 0 !important;
        margin-top: 0 !important; height: 52px !important;
      }
      /* 「해당 항목으로 이동」 is the only way through a form this long, so it
         stays — as one scrolling row of chips above the two buttons. */
      html[data-flr-mobile-layout="dabang"] [class*="styled__StickyContainer-sc-h5ond6-"]
        [class*="styled__ContentList-sc-33x7dx-"] {
        display: block !important; grid-column: 1 / -1 !important;
        margin: 0 !important; padding: 0 !important; border: 0 !important;
        overflow-x: auto !important; overflow-y: hidden !important;
        -webkit-overflow-scrolling: touch; scrollbar-width: none;
        overscroll-behavior-x: contain;
      }
      html[data-flr-mobile-layout="dabang"] [class*="styled__StickyContainer-sc-h5ond6-"]
        [class*="styled__ContentList-sc-33x7dx-"]::-webkit-scrollbar { display: none !important; }
      html[data-flr-mobile-layout="dabang"] [class*="styled__StickyContainer-sc-h5ond6-"]
        [class*="styled__ContentList-sc-33x7dx-"] > h1 { display: none !important; }
      html[data-flr-mobile-layout="dabang"] [class*="styled__StickyContainer-sc-h5ond6-"]
        [class*="styled__ContentList-sc-33x7dx-"] > ul {
        display: flex !important; flex-wrap: nowrap !important; gap: 6px !important;
        width: max-content !important; min-width: 100% !important;
        margin: 0 !important; padding: 0 !important; list-style: none !important;
      }
      html[data-flr-mobile-layout="dabang"] [class*="styled__StickyContainer-sc-h5ond6-"]
        [class*="styled__ContentList-sc-33x7dx-"] > ul > li {
        flex: 0 0 auto !important; height: auto !important;
      }
      html[data-flr-mobile-layout="dabang"] [class*="styled__StickyContainer-sc-h5ond6-"]
        [class*="styled__ItemBtn-sc-33x7dx-"] {
        height: 34px !important;
        margin-left: 0 !important; padding: 0 12px !important;
        border: 1px solid #ededed !important; border-radius: 999px !important;
        background-color: #fff !important;
        white-space: nowrap !important;
      }
      html[data-flr-mobile-layout="dabang"] [class*="styled__StickyContainer-sc-h5ond6-"]
        [class*="styled__ItemBtn-sc-33x7dx-"].active {
        border-color: #326cf9 !important; background-color: #eef3ff !important;
      }
      html[data-flr-mobile-layout="dabang"] [class*="styled__StickyContainer-sc-h5ond6-"]
        [class*="styled__ItemBtn-sc-33x7dx-"] .contentName { white-space: nowrap !important; }
    `,
    daangn: `
      html[data-flr-mobile-layout="daangn"] [class*="desktop:pl-[180px]"] { padding-left: 0 !important; }
      html[data-flr-mobile-layout="daangn"] [class*="max-w-[720px]"] { max-width: 100% !important; }
      html[data-flr-mobile-layout="daangn"] [data-flr-mobile-surface] { padding-left: 12px !important; padding-right: 12px !important; }
      html[data-flr-mobile-layout="daangn"] [data-flr-mobile-surface] [class*="justify-between"] {
        flex-wrap: wrap !important; gap: 10px !important;
      }
      html[data-flr-mobile-layout="daangn"] #style-root [class~="fixed"][class~="bottom-0"] {
        left: 0 !important; right: 0 !important; padding-left: 0 !important;
      }
      html[data-flr-mobile-layout="daangn"] #style-root [class~="fixed"][class~="bottom-0"] p {
        display: none !important;
      }
      html[data-flr-mobile-layout="daangn"] #style-root [class~="fixed"][class~="bottom-0"]
        [class*="max-w-[720px]"] { padding: 10px 12px !important; gap: 8px !important; }
      html[data-flr-mobile-layout="daangn"] #style-root [class~="fixed"][class~="bottom-0"]
        [class~="gap-x3"] {
        display: grid !important; grid-template-columns: minmax(0, 1fr) minmax(0, 1.5fr) !important;
        gap: 8px !important; width: 100% !important; min-width: 0 !important;
      }
      html[data-flr-mobile-layout="daangn"] #style-root [class~="fixed"][class~="bottom-0"] button {
        width: 100% !important;
      }
      /* The support stack is pinned 48px off the corner, which on a phone is
         exactly where the CTA now is. */
      html[data-flr-mobile-layout="daangn"] [class~="fixed"][class~="bottom-[48px]"] {
        bottom: calc(var(--flr-mobile-bar, 0px) + 12px) !important;
        right: 12px !important;
      }
      html[data-flr-mobile-layout="daangn"][data-flr-mobile-dialog-open]
        [class~="fixed"][class~="bottom-[48px]"] {
        bottom: calc(env(safe-area-inset-bottom) + 8px) !important;
      }
      /* The mirror froze these hint bubbles at the coordinates 당근's floating
         layer computed for a desktop window — this one sits at x=341 with the
         text past the edge. Live 당근 would re-place them; a capture cannot. */
      html[data-flr-mobile-layout="daangn"] .seed-help-bubble__positioner {
        display: none !important;
      }
    `,
  };

  const findSurface = () => {
    if (config.profile === 'zigbang') return document.querySelector('main form');
    if (config.profile === 'dabang') {
      return document.querySelector('[class*="styled__ContentContainer-sc-h5ond6-"]') ||
        document.querySelector('[class*="styled__Layout-sc-h5ond6-"]');
    }
    const title = [...document.querySelectorAll('h1')]
      .find(element => normalize(element.textContent) === '매물 등록');
    return title && (title.closest('[class*="max-w-[720px]"]') || title.parentElement);
  };

  // The platform's own bar around the 등록 button. 직방 has no wrapper worth
  // naming, so its bar is whatever holds the button.
  const findSubmitBar = submit => {
    if (config.profile === 'dabang') {
      return document.querySelector('[class*="styled__StickyContainer-sc-h5ond6-"]');
    }
    if (config.profile === 'daangn') {
      return document.querySelector('#style-root [class~="fixed"][class~="bottom-0"]');
    }
    return submit && submit.parentElement;
  };

  const ensureViewport = () => {
    let viewport = document.querySelector('meta[name="viewport"]');
    if (!viewport) {
      viewport = document.createElement('meta');
      viewport.name = 'viewport';
      document.head.appendChild(viewport);
    }
    viewport.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
  };

  const available = () =>
    Math.max(document.documentElement.clientWidth, window.innerWidth || 0);

  // Whatever the page has parked against the bottom edge — 직방 keeps 시작하기
  // there on its 로그인, 당근 its CTA row. Asking the bottom edge what is under
  // it costs one hit test, where hunting for it costs a computed style per
  // element. Elements the page has made untouchable, the mirror's own badge
  // among them, are not in the answer.
  const findBottomBar = () => {
    const height = window.innerHeight || document.documentElement.clientHeight;
    let bar = null;
    for (const element of
         document.elementsFromPoint(Math.round(available() / 2), height - 4)) {
      if (element === document.body || element === root) break;
      const position = getComputedStyle(element).position;
      if (position === 'fixed' || position === 'sticky') bar = element;
    }
    return bar;
  };

  // How far up the mirror's badge and toast have to sit to stay off it.
  const reserve = bar => {
    const height = bar ? Math.ceil(bar.getBoundingClientRect().height) : 0;
    const next = height > 0 ? height + 'px' : '';
    if (root.style.getPropertyValue(barProperty) === next) return;
    if (next) root.style.setProperty(barProperty, next);
    else root.style.removeProperty(barProperty);
  };

  const scrollsSideways = element => {
    if (!element) return false;
    const overflowX = getComputedStyle(element).overflowX;
    return overflowX === 'auto' || overflowX === 'scroll';
  };

  // Nothing in normal flow may be wider than the phone, nor push its own
  // content past its edges. Which boxes those are is a question about this
  // page, not about its class names, so measure the page and ask it.
  //
  // Two answers, because they need different remedies. A box the desktop
  // *pinned* wide has to be let go of entirely; a box that merely *overflows*
  // fits once it is told to fill its parent and wrap.
  //
  // Marking is one-way on purpose. Releasing a box makes it narrow, which would
  // make the next pass judge it fine and re-pin it — a flap on every mutation.
  // The marks go away with cleanup(), which is when the page stops being ours.
  const measure = () => {
    const width = available();
    for (const element of document.body.querySelectorAll('*')) {
      if (element.hasAttribute(pinnedAttribute) ||
          element.hasAttribute(overflowAttribute)) continue;
      // The submit bar is laid out by the profile, and its section chips are
      // built to scroll sideways — as is anything else that says it does.
      if (element.closest('[' + submitBarAttribute + ']')) continue;
      if (scrollsSideways(element.parentElement)) continue;
      const computed = getComputedStyle(element);
      // Whatever is out of flow was put there by the page on purpose; its
      // offsets are its own business.
      if (computed.position === 'absolute' || computed.position === 'fixed') continue;
      const rect = element.getBoundingClientRect();
      const minWidth = parseFloat(computed.minWidth) || 0;
      if (rect.width > width + 1 || minWidth > width) {
        element.setAttribute(pinnedAttribute, '');
      } else if (rect.width > 0 &&
          // Shoved past the edge by a desktop gutter without being wide
          // itself — 다방's 369px map sits on a 16px margin.
          (rect.right > width + 1 || rect.left < -1 ||
          // Or holding a child that hangs out of it: 당근's 엑셀 매물 등록
          // button sticks 45px past the row it lives in.
          (!scrollsSideways(element) &&
            element.scrollWidth > element.clientWidth + 2))) {
        element.setAttribute(overflowAttribute, '');
      } else {
        continue;
      }
      if (computed.display.includes('flex')) element.setAttribute(flowAttribute, 'flex');
      if (computed.display.includes('grid')) element.setAttribute(flowAttribute, 'grid');
    }
  };

  const state = {observer: null, timer: 0};
  const cleanup = () => {
    state.observer?.disconnect();
    if (state.timer) clearTimeout(state.timer);
    state.timer = 0;
    window.removeEventListener('resize', schedule);
    window.removeEventListener('popstate', schedule);
    window.removeEventListener('hashchange', schedule);
    root.removeAttribute(rootAttribute);
    root.removeAttribute(dialogAttribute);
    root.style.removeProperty(barProperty);
    document.getElementById(styleId)?.remove();
    for (const element of document.querySelectorAll(
      '[' + surfaceAttribute + '],[' + ancestorAttribute + '],[' + submitAttribute +
        '],[' + submitBarAttribute + '],[' + overflowAttribute + '],[' + flowAttribute + ']',
    )) {
      element.removeAttribute(surfaceAttribute);
      element.removeAttribute(ancestorAttribute);
      element.removeAttribute(submitAttribute);
      element.removeAttribute(submitBarAttribute);
      element.removeAttribute(overflowAttribute);
      element.removeAttribute(flowAttribute);
    }
    if (window.__flrMobileFormLayout?.apply === apply) {
      delete window.__flrMobileFormLayout;
    }
  };

  const apply = () => {
    if (!inScope()) {
      cleanup();
      return false;
    }
    ensureViewport();
    root.setAttribute(rootAttribute, config.profile);
    let style = document.getElementById(styleId);
    if (!style) {
      style = document.createElement('style');
      style.id = styleId;
      document.head.appendChild(style);
    }
    const cssText = commonCss + (profileCss[config.profile] || '');
    if (style.textContent !== cssText) style.textContent = cssText;

    const form = onForm();
    let surface = null;
    if (form) {
      let submit = null;
      for (const button of document.querySelectorAll(
        'button, [role="button"], input[type="submit"], a',
      )) {
        // textContent, not innerText: innerText resolves layout for every
        // button on the page, and this runs after every React render.
        const label = normalize(button.textContent || button.value);
        if (!config.submitLabels.includes(label)) continue;
        button.setAttribute(submitAttribute, '');
        submit = submit || button;
      }
      const bar = findSubmitBar(submit);
      // The form has to end above the bar, and only the bar knows how tall it
      // is once its chips have wrapped or not.
      if (bar) bar.setAttribute(submitBarAttribute, '');
      reserve(bar);
      surface = findSurface();
      if (surface) surface.setAttribute(surfaceAttribute, '');
    } else {
      reserve(findBottomBar());
    }
    // Runs on every mirror page, form or not: the 로그인 screen was pinned to
    // 1200px just like the form was.
    measure();
    const dialogs = [...document.querySelectorAll('[role="dialog"]')];
    const modalOpen = dialogs.some(dialog => {
      if (dialog.hidden || dialog.getAttribute('aria-hidden') === 'true') return false;
      const computed = getComputedStyle(dialog);
      const visible = computed.display !== 'none' &&
        computed.visibility !== 'hidden' &&
        computed.visibility !== 'collapse' &&
        dialog.getClientRects().length > 0;
      return visible &&
        (dialog.getAttribute('aria-modal') === 'true' || computed.position === 'fixed');
    });
    root.toggleAttribute(dialogAttribute, modalOpen);
    return form ? !!surface : true;
  };

  const previous = window.__flrMobileFormLayout;
  if (previous) {
    previous.observer?.disconnect();
    if (previous.state && previous.state.timer) clearTimeout(previous.state.timer);
    if (previous.resizeHandler) {
      window.removeEventListener('resize', previous.resizeHandler);
    }
    if (previous.navigationHandler) {
      window.removeEventListener('popstate', previous.navigationHandler);
      window.removeEventListener('hashchange', previous.navigationHandler);
    }
  }
  // A frame is too eager: typing in the form re-renders React continuously, and
  // a pass reads computed styles for the whole surface. Coalescing into one
  // pass per idle moment keeps the page responsive under the agent's typing.
  const schedule = () => {
    if (state.timer) return;
    state.timer = setTimeout(() => { state.timer = 0; apply(); }, 120);
  };
  state.observer = new MutationObserver(schedule);
  state.observer.observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: [
      'class',
      'style',
      'hidden',
      'aria-hidden',
      'open',
      'data-state',
      'data-open',
    ],
  });
  window.addEventListener('resize', schedule, {passive: true});
  window.addEventListener('popstate', schedule, {passive: true});
  window.addEventListener('hashchange', schedule, {passive: true});
  window.__flrMobileFormLayout = {
    observer: state.observer,
    state,
    resizeHandler: schedule,
    navigationHandler: schedule,
    apply,
    cleanup,
  };
  apply();
  return true;
})();
''');
  return script.toString();
}
