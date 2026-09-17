/// The JavaScript 한방 runs inside each mirror: the Kakao postcode bridge, the
/// per-platform adapters, and the frame script that picks a Kakao result.
/// `MirrorSession` decides when each one runs.
library;

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

String zigbangInjectionScript(String payload) =>
    '''

(async () => {
  const data = $payload;
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const output = {applied: 0, missing: [], unsupported: [], verified: 0, violations: []};
  // These names were read from the published mirror form. Never rely on its
  // generated Radix ids: they change on every page render.
  const names = {
    building: 'dongDetail.dong', unit: 'ho', exclusiveArea: 'sizeM2',
    residenceDescription: 'residence.residenceTypeDescription',
    floorAll: 'floorAll', floor: 'floor', approvalDate: 'approveDate',
    trade: 'sales.salesType', deposit: 'sales.deposit', monthlyRent: 'sales.rent',
    roomLayout: 'roomType', bathrooms: 'bathroomCnt',
    directionBase: 'directionCriterionType', direction: 'roomDirection',
    parkingCount: 'parkingAndHousehold.totalParkingCnt', elevator: 'isElevator',
    violation: 'nonCompliantBuilding', manageBasis: 'manageCostDetail.manageCostCriteria.manageCostCriteria',
    managementFee: 'manageCostDetail.basisDetail.avgManageCost',
    otherFeeReason: 'manageCostDetail.basisDetail.basis', title: 'title',
    description: 'description', privateMemo: 'secretMemo', moveInDate: 'moveInDate',
    moveInNegotiable: 'moveInDateExtra', ownerPhone: 'verification.lessorPhone'
  };
  const unavailable = {
    supplyArea: '공급면적: 직방 원룸 폼에 입력란이 없습니다.',
    salePrice: '매매 금액: 직방 원룸 폼은 매매를 지원하지 않습니다.',
    floorPrivate: '층수 비공개: 직방 원룸 폼은 실제 층수만 지원합니다.',
    buildingUse: '건축물 용도: 직방 원룸 폼은 건축물대장 연동으로만 처리하며 법정 용도 선택란이 없습니다.',
    parkingPerHousehold: '세대당 주차 대수: 직방은 총 주차대수만 지원합니다.',
    heating: '난방 방식: 직방 원룸 폼에 입력란이 없습니다.',
    lh: 'LH 전세임대 여부: 직방 원룸 폼에 입력란이 없습니다.',
    rooms: '방 개수: 직방 원룸 폼은 방 구조로 방 수를 정하며 별도 방 개수 입력란이 없습니다.',
    unknownFeeReason: '확인 불가 법정 사유: 직방 원룸 미러의 관리비 방식에는 확인 불가 분기가 없습니다.',
    photoCount: '사진: 직방 미러는 아직 사진 첨부 기능을 지원하지 않습니다. 통합 폼에서 선택한 사진은 다방·당근 미러에 자동 첨부할 수 있습니다.'
  };
  const esc = s => (window.CSS && CSS.escape) ? CSS.escape(String(s)) : String(s).replace(/[^a-zA-Z0-9_-]/g, '\\\\\$&');
  const find = name => document.querySelector('[name="' + esc(name) + '"], #' + esc(name) + ', [data-flr-key="' + esc(name) + '"]');
  const strict = window.FLR && window.FLR.strict;
  const strictSet = strict && typeof strict.setValue === 'function' ? strict.setValue.bind(strict) : null;
  const strictClick = strict && typeof strict.click === 'function' ? strict.click.bind(strict) : null;
  const press = el => {
    if (!el) return false;
    if (strictClick) { strictClick(el); return true; }
    el.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true}));
    el.dispatchEvent(new MouseEvent('mousedown', {bubbles: true}));
    el.dispatchEvent(new PointerEvent('pointerup', {bubbles: true}));
    el.dispatchEvent(new MouseEvent('mouseup', {bubbles: true}));
    el.dispatchEvent(new MouseEvent('click', {bubbles: true}));
    el.click();
    return true;
  };
  const setValue = (el, value) => {
    if (!el) return false;
    if (strictSet) strictSet(el, String(value));
    const setter = Object.getOwnPropertyDescriptor(el.tagName === 'SELECT' ? HTMLSelectElement.prototype : el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype, 'value')?.set;
    if (!strictSet) { if (setter) setter.call(el, String(value)); else el.value = String(value); }
    ['input', 'change', 'blur'].forEach(type => el.dispatchEvent(new Event(type, {bubbles: true})));
    return true;
  };
  const normalize = value => String(value ?? '').replace(/[ \\t\\r\\n]+/g, '').replace(/향\$/, '').replace(/층\$/, '').replace(/개\$/, '');
  const exactly = (actual, wanted) => normalize(actual) === normalize(wanted);
  const matches = (actual, wanted) => {
    const a = normalize(actual), b = normalize(wanted);
    return exactly(actual, wanted) || a.includes(b) || b.includes(a);
  };
  const waitFor = async (predicate, timeout = 1800) => {
    const until = Date.now() + timeout;
    while (Date.now() < until) {
      const result = predicate();
      if (result) return result;
      await sleep(50);
    }
    return null;
  };
  const selectedButton = el => el?.getAttribute('aria-checked') === 'true' || el?.getAttribute('aria-pressed') === 'true' || (el?.classList?.contains('text-orange-500') && el?.classList?.contains('border-orange-500'));
  const clickCandidate = async el => {
    if (el) {
      press(el);
      ['input','change'].forEach(type => el.dispatchEvent(new Event(type, {bubbles:true})));
      return !!await waitFor(() => selectedButton(el));
    }
    return false;
  };
  const clickText = async (name, value) => {
    // Most radio-like groups repeat the same name on every button.  Prefer
    // that exact target over a nearby label: the latter can accidentally be a
    // hidden select belonging to the next field.
    const named = [...document.querySelectorAll('button[name], [role="radio"][name]')]
        .find(n => n.getAttribute('name') === name && matches(n.textContent.trim(), value));
    if (named) return clickCandidate(named);
    const anchor = find(name);
    const scope = anchor?.parentElement?.parentElement || anchor?.parentElement || document;
    return clickCandidate([...scope.querySelectorAll('label,button,[role="radio"],[role="option"]')]
        .find(n => matches(n.textContent.trim(), value)));
  };
  const clickLabel = async (labelText, value) => {
    const label = [...document.querySelectorAll('label')]
        .find(n => matches(n.textContent.trim().replace('*', ''), labelText));
    let scope = label?.parentElement;
    while (scope && scope !== document.body) {
      const candidate = [...scope.querySelectorAll('button')]
          .find(n => matches(n.textContent.trim(), value));
      if (candidate) return clickCandidate(candidate);
      scope = scope.parentElement;
    }
    return false;
  };
  // A Radix Select is a visible trigger plus a hidden native select.  Setting
  // that native select alone does not call React/Radix's onValueChange.  Open
  // the trigger, then click the rendered option, and read both representations
  // back before reporting success.  This also honours the mirror's strict
  // pointerdown/click ordering and delayed reactions.
  const choose = async (name, value) => {
    const el = find(name);
    if (!el) return false;
    if (el.tagName === 'SELECT') {
      const options = [...el.options];
      const option = options.find(o => exactly(o.textContent.trim(), value) || exactly(o.value, value)) ||
          options.find(o => matches(o.textContent.trim(), value) || matches(o.value, value));
      if (!option) return false;
      const trigger = el.previousElementSibling?.getAttribute('role') === 'combobox'
          ? el.previousElementSibling
          : el.parentElement?.querySelector('[role="combobox"]');
      if (!trigger || trigger.disabled) return false;
      press(trigger);
      const list = await waitFor(() => document.querySelector('[data-mirror="listbox"], [role="listbox"]'));
      if (!list) return false;
      const renderedOptions = [...list.querySelectorAll('[role="option"]')];
      const rendered = renderedOptions.find(item => exactly(item.textContent.trim(), option.textContent.trim())) ||
          renderedOptions.find(item => matches(item.textContent.trim(), option.textContent.trim()));
      if (!rendered) return false;
      press(rendered);
      return !!await waitFor(() =>
        el.value === option.value &&
        matches(trigger.textContent.trim(), option.textContent.trim()) &&
        trigger.getAttribute('aria-expanded') !== 'true',
      );
    }
    return clickText(name, value);
  };
  const check = async (id, wanted) => {
    const el = document.getElementById(id);
    if (!el) return false;
    const checked = el.getAttribute('aria-checked') === 'true';
    if (checked !== wanted) press(el);
    return !!await waitFor(() => (el.getAttribute('aria-checked') === 'true') === wanted);
  };
  // 이 어댑터의 clickText·choose·check 는 미러가 선택 상태를 돌려줄 때까지 기다린 뒤에만
  // true 를 준다. 그래서 「입력됨」은 곧 「확인됨」이다.
  const mark = (key, ok) => {
    if (ok) { output.applied++; output.verified++; }
    else output.missing.push(key + ': 미러의 대상 DOM을 찾거나 선택하지 못했습니다.');
  };
  const note = message => { if (!output.unsupported.includes(message)) output.unsupported.push(message); };
  const publish = () => window.ListingResult.postMessage(JSON.stringify(output));
  const labelled = word => [...document.querySelectorAll('main label')]
      .find(label => label.textContent.trim().replace('*', '') === word);
  try {
    if (typeof strict === 'function') {
      const strictResult = await strict(data);
      Object.assign(output, strictResult || {});
      window.ListingResult.postMessage(JSON.stringify(output)); return;
    }
    if (strict && typeof strict !== 'function' && !strictSet && !strictClick) output.violations.push('FLR.strict에 호출 가능한 helper가 없어 DOM 대체 입력을 사용했습니다.');
    for (const [key, reason] of Object.entries(unavailable)) {
      if (key === 'photoCount' ? Number(data[key]) > 0 : data[key] !== undefined && data[key] !== '') {
        output.unsupported.push(reason);
      }
    }
    const input = (key, value, transform = v => v) => {
      if (value === undefined || value === null || value === '') return;
      const el = find(names[key]);
      if (!el) return mark(key, false);
      const wanted = String(transform(value));
      setValue(el, wanted);
      if (String(el.value) === wanted) return mark(key, true);
      output.applied++;
      output.missing.push(key + ': 값을 넣었지만 폼에서 같은 값을 다시 읽지 못했습니다.');
    };
    const choice = (key, value, transform = v => v) => { if (value === undefined || value === null || value === '') return; mark(key, choose(names[key], transform(value))); };
    // The mirror exposes only 단독주택 and an explicit free-text escape hatch.
    // Keep the source classification by choosing that documented escape hatch
    // instead of pretending that a one-room/villa category was selected.
    const residenceChoice = data.propertyType === '단독주택'
        ? '단독주택' : '그 외(직접 입력)';
    mark('propertyType', await clickText('residence.residenceType', residenceChoice));
    if (residenceChoice === '그 외(직접 입력)') {
      await sleep(350);
      input('residenceDescription', data.propertyType);
    }
    input('building', data.building); mark('singleBuilding', await check('haveNoDong', data.singleBuilding === true)); input('unit', data.unit);
    const targetFloor = data.floor === '옥탑' ? '옥탑방' : /^\\d+\$/.test(String(data.floor)) ? data.floor + '층' : data.floor;
    input('exclusiveArea', data.exclusiveArea); mark('floorAll', await choose(names.floorAll, data.floorAll));
    // The mirror rebuilds the floor options after the delayed whole-floor
    // selection.  Retry only after the rebuilt native select is observable.
    await sleep(650);
    let floorOk = await choose(names.floor, targetFloor);
    if (!floorOk) { await sleep(450); floorOk = await choose(names.floor, targetFloor); }
    mark('floor', floorOk);
    input('approvalDate', data.approvalDate); mark('trade', await clickText('sales.salesType', data.trade)); await sleep(400); if (data.trade === '월세' || data.trade === '전세') input('deposit', data.deposit); if (data.trade === '월세') input('monthlyRent', data.monthlyRent);
    mark('shortTerm', await check('isShortTerm', data.shortTerm === true));
    if (data.loan === '없음') mark('loan', await clickText('noLoan', '융자금 없음'));
    else if (data.loan === '30%이하' || data.loan === '융자금 30%이하') mark('loan', await clickText('loanUnder30', '융자금 30%이하'));
    else if (data.loan !== undefined && data.loan !== null && data.loan !== '') output.unsupported.push('융자금 ' + data.loan + ': 직방 원룸 미러는 융자금 없음 또는 30% 이하만 선택할 수 있어 임의 금액을 자동 변환하지 않았습니다.');
    mark('noManagementFee', await check('no-manage-cost', data.noManagementFee === true));
    if (data.noManagementFee !== true) { mark('manageMethod', await clickLabel('관리비 부과 방식', data.manageMethod === '기타 부과' ? '기타' : data.manageMethod)); await sleep(400); }
    if (data.manageMethod === '정액 관리비' && data.noManagementFee !== true) { mark('manageBasis', await choose(names.manageBasis, ({'3개월 평균 관리비':'최근 3개월 관리비 평균','1년 평균 관리비':'최근 1년 관리비 평균','기타 직접 입력':'직접 입력'})[data.manageBasis] || data.manageBasis)); input('managementFee', data.managementFee, v => String(Number(v) * 10000)); }
    const feeNames = {'인터넷':'인터넷 사용료','유선TV':'TV 사용료','청소비':'일반(공용) 관리비','수도료':'수도료','가스사용료':'가스 사용료','전기료':'전기료','난방비':'난방비'};
    for (const fee of (data.manageIncludes || [])) { if (feeNames[fee]) mark('manageIncludes.' + fee, await clickText('manageCostDetail.detailIncludes', feeNames[fee])); else output.unsupported.push('관리비 포함 항목 ' + fee + ': 직방 원룸 폼에 대응 항목이 없습니다.'); }
    if (data.manageMethod === '기타 부과') mark('otherFeeReason', await choose(names.otherFeeReason, ({
      '면적 및 세대별 부과':'공용관리비는 면적/세대별로 부과하고, 사용료는 사용량에 따른 부과',
      '전체 세대 균등 부과':'전체 사용량을 세대수로 나누어 부과',
      '계량기별 실비 부과':'세대별 사용량(별도 계량기)에 따라 부과',
      '의뢰인 미고지':'중개 의뢰인이 관리비 세부내역 미제시로 관리비 추정 금액 입력',
      '기타':'직접 입력',
    })[data.otherFeeReason] || data.otherFeeReason));
    // 「관리비 실비 부과 세부 내역」은 정액 관리비에서도 필수(*)다. 총액이 10만원 미만인
    // 것은 입력한 금액에서 그대로 따라오므로 그때만 자동으로 고른다.
    if (data.manageMethod === '정액 관리비' && data.noManagementFee !== true) {
      const total = Number(data.managementFee);
      if (!Number.isNaN(total) && total < 10) mark('basisDetail', await choose(names.otherFeeReason, '관리비 월 10만원 미만'));
      else note('관리비 실비 부과 세부 내역: 정액 관리비 10만원 이상은 직방이 부과 근거를 따로 고르게 하는데 통합 폼에 대응하는 값이 없어 화면에서 직접 골라 주셔야 합니다.');
    }
    if (data.manageMethod === '정액 관리비' && data.manageDetail) {
      const detailKeys = {
        electricity: '전기료', water: '수도료', gas: '가스사용료',
        heating: '난방비', internet: '인터넷', tv: '유선TV',
        normalManageCost: '청소비', etcManageCost: '기타'
      };
      for (const el of document.querySelectorAll('select[name\$=".type"]')) {
        const source = Object.keys(detailKeys).find(key => el.name.includes(key));
        if (!source) continue;
        const masterValue = data.manageDetail[detailKeys[source]];
        if (!masterValue) {
          output.unsupported.push('관리비 세부 ' + detailKeys[source] + ': 통합 폼 값이 없어 미러에 입력하지 않았습니다.');
          continue;
        }
        mark('manageDetail.' + detailKeys[source], await choose(el.name, masterValue));
      }
      // 「정액」으로 고른 비목은 금액 칸이 켜지고 필수가 된다 — 통합 폼에는 비목별 금액이 없다.
      const pending = [...document.querySelectorAll('main input[placeholder*="금액"]')]
          .filter(el => !el.disabled && !el.value).length;
      if (pending) note('비목별 정액 금액 ' + pending + '칸: 직방은 「정액」으로 고른 비목마다 금액을 따로 요구하지만 통합 폼은 총액만 받아 비워 두었습니다.');
    }
    mark('roomLayout', await choose(names.roomLayout, ({'오픈형 원룸':'오픈형 원룸 (방1)','분리형 원룸':'분리형 원룸 (방1,거실1)','복층형 원룸':'복층형 원룸'})[data.roomLayout] || data.roomLayout));
    mark('bathrooms', await choose(names.bathrooms, String(data.bathrooms).replace(' 이상', '개'))); mark('directionBase', await clickText('directionCriterionType', data.directionBase === '주실 기준' ? '거실 기준' : data.directionBase)); mark('direction', await choose(names.direction, data.direction));
    mark('parking', await check('no-parking', data.parking === '주차 불가능')); if (data.parking === '주차 가능') input('parkingCount', data.parkingCount);
    mark('elevator', await clickText('isElevator', data.elevator)); mark('violation', await clickText('nonCompliantBuilding', data.violation === '해당 없음' ? '해당없음' : '해당'));
    mark('loanAvailable', await check('itemConditions.loanLease', data.loanAvailable === '가능')); mark('petAllowed', await check('itemConditions.pet', data.petAllowed === '가능'));
    const optionLabel = [...document.querySelectorAll('label')].find(label => label.textContent.trim() === '옵션');
    const optionScope = optionLabel?.parentElement?.parentElement || document;
    for (const option of (data.appliances || [])) { const button = [...optionScope.querySelectorAll('button')].find(b => b.textContent.trim() === option); if (button) { press(button); if (await waitFor(() => selectedButton(button))) { output.applied++; output.verified++; } else output.missing.push('appliances.' + option + ': 미러에서 선택 상태를 확인하지 못했습니다.'); } else output.unsupported.push('가전·가구 옵션 ' + option + ': 직방 원룸 미러에 대응 옵션이 없습니다.'); }
    const conditionIds = {'CCTV':'itemConditions.cctv','테라스':'itemConditions.terrace','전기차 충전시설':'itemConditions.evStation'}; for (const item of (data.facilities || [])) { if (conditionIds[item]) { if (await check(conditionIds[item], true)) { output.applied++; output.verified++; } else output.missing.push('facilities.' + item + ': 미러에서 선택 상태를 확인하지 못했습니다.'); } else output.unsupported.push('보안 및 시설 옵션 ' + item + ': 직방 원룸 미러에 대응 옵션이 없습니다.'); }
    if (data.moveInType === '즉시 입주') mark('moveInType', await check('moveInImmediately', true)); else if (data.moveInType === '날짜 지정') { mark('moveInType', await check('moveInImmediately', false)); input('moveInDate', data.moveInDate); } else output.unsupported.push('입주 방식 협의 가능: 직방 원룸 미러는 즉시 입주 또는 날짜 선택만 지원합니다.');
    if (data.moveInNegotiable === true) input('moveInNegotiable', '협의 가능');
    input('title', data.title); input('description', data.description); input('privateMemo', data.privateMemo); input('ownerPhone', data.ownerPhone);
    for (const message of (window.__flrPostcode ? window.__flrPostcode.notes : [])) note(message);

    // 주소 — 직방 미러는 주소 칸을 누르면 카카오 우편번호 창을 띄운다. 브리지가 그 창을
    // 웹뷰 안 전체 화면 겹으로 바꿔 놓았으므로, 여기서 눌러 주면 사용자가 결과만 고르면 된다.
    // 고르고 나면 미러가 「소재지 공개 확인」 창을 띄운다 — 매물 대분류로 답이 정해진다.
    if (data.address) {
      if (window.__flrPostcode) window.__flrPostcode.query = data.address;
      const lat = find('lat');
      if (!lat) mark('address', false);
      else {
        if (!window.__flrZigbangAddressWatch) {
          const multiUnit = data.propertyType === '다가구주택' ? '예' : '아니요';
          window.__flrZigbangAddressWatch = new MutationObserver(() => {
            const dialog = [...document.querySelectorAll('[data-mirror="modal"] [role="dialog"]')]
                .find(box => box.textContent.includes('소재지 공개 확인'));
            if (!dialog) return;
            const answer = [...dialog.querySelectorAll('button')]
                .find(button => button.textContent.trim() === multiUnit);
            if (!answer) return;
            press(answer);
            const index = output.unsupported.findIndex(message => message.startsWith('매물 기본 주소:'));
            if (index >= 0) output.unsupported.splice(index, 1);
            note('소재지 공개 확인: 매물 대분류가 ' + data.propertyType + '이므로 「' + multiUnit + '」로 답했습니다.');
            if (String(lat.value) !== '') { output.applied++; output.verified++; }
            publish();
          });
          window.__flrZigbangAddressWatch.observe(document.body, {subtree: true, childList: true});
        }
        note('매물 기본 주소: 카카오 주소 검색을 띄웠습니다. 자동으로 고르지 못하면 결과를 직접 눌러 주세요. 고르면 직방 주소 칸이 채워집니다.');
        press(lat);
      }
    }
    for (const violation of (window.__FLR_VIOLATIONS__ || [])) {
      const detail = typeof violation === 'string' ? violation : [violation.kind, violation.target, violation.detail].filter(Boolean).join(': ');
      output.violations.push('깐깐이 위반: ' + detail);
    }
  } catch (error) { output.violations.push('자동 입력 오류: ' + String(error)); }
  window.ListingResult.postMessage(JSON.stringify(output));
})();
''';

String dabangInjectionScript(String payload) =>
    '''
(async () => {
  const data = $payload;
  const output = {applied: 0, missing: [], unsupported: [], verified: 0, violations: []};
  const publish = () => window.ListingResult.postMessage(JSON.stringify(output));
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  // 깐깐이(mirror 의 엄격 층)는 click/input/change 를 삼켰다가 0.3초 뒤에 다시 쏜다.
  // 그래서 조작 하나하나의 반응을 기다려야 한다.
  const REACT = 420;
  const text = el => el ? (el.textContent || '').replace(/\\s+/g, ' ').trim() : '';
  const norm = value => String(value === undefined || value === null ? '' : value).replace(/\\s+/g, '');
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

  // 미러는 반응할 때마다 <tr> 을 틀에서 새로 만들어 통째로 갈아 끼운다(setRow).
  // 그래서 붙잡아 둔 노드는 곧 화면 밖의 유령이 된다 — 자리는 늘 함수로 다시 찾는다.
  const at = target => { try { return typeof target === 'function' ? target() : target; } catch (_) { return null; } };
  const ready = (locate, timeout) => waitUntil(() => {
    const el = at(locate);
    return el && !el.disabled ? el : null;
  }, timeout);

  const fill = (key, locate, value, transform = v => v) => {
    if (!filled(value)) return false;
    const el = at(locate);
    if (!el) { miss(key, '다방 폼에서 입력란을 찾지 못했습니다.'); return false; }
    if (el.disabled) { miss(key, '입력란이 잠겨 있어 값을 넣지 못했습니다.'); return false; }
    const wanted = String(transform(value));
    setNative(el, wanted);
    const again = at(locate) || el;
    if (String(again.value) === wanted) { ok(); return true; }
    output.applied++;
    miss(key, '값을 넣었지만 폼에서 같은 값을 다시 읽지 못했습니다.');
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
      ok(); await sleep(REACT); return true;
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
    if (el.checked === wanted) { ok(); return true; }
    press(el);
    if (await waitUntil(() => { const now = at(locate); return now && now.checked === wanted; }, 2000)) {
      ok(); await sleep(REACT); return true;
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

  const modal = title => {
    const box = document.getElementById('modal-container');
    return box && norm(text(box)).includes(norm(title)) ? box : null;
  };
  const modalButton = (box, wanted) =>
    [...box.querySelectorAll('button')].find(button => norm(text(button)) === norm(wanted));

  /* ── 주소 ───────────────────────────────────────────────────
   * 「검색」은 카카오 우편번호 화면을 띄운다(브리지가 웹뷰 안 전체 화면 겹으로 그린다).
   * 결과를 고르면 미러가 도로명·지번을 채우고 동/호 칸을 켜고 건축물대장 창을 띄운다.
   * 그 순간을 관찰해 동/호를 자동으로 넣고, 대장 창은 「직접 입력」으로 닫는다 —
   * 대장 조회는 이미 넣은 면적·용도·승인일을 공공데이터 값으로 덮어쓰기 때문이다. */
  const addressCell = () => cellOf('room_info', '매물 주소');
  const afterAddressPicked = () => {
    const cell = addressCell();
    if (!cell) return;
    const ledger = modal('건축물대장');
    if (ledger) {
      const keep = modalButton(ledger, '아니요, 직접 입력할게요') || modalButton(ledger, '닫기');
      if (keep) {
        press(keep);
        note('건축물대장 자동 조회: 이미 입력한 면적·용도·승인일이 공공데이터 값으로 덮어써지지 않도록 「직접 입력」으로 닫았습니다.');
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
        if (/^(매물 기본 주소|동 정보|호수 정보):/.test(bucket[i])) bucket.splice(i, 1);
      }
    }
    fill('building', dong, data.building);
    fill('unit', ho, data.unit);
    output.applied++;
    output.verified++;
    publish();
  };
  const watchAddress = () => {
    if (window.__flrDabangAddressWatch) return;
    window.__flrDabangAddressWatch = new MutationObserver(() => afterAddressPicked());
    window.__flrDabangAddressWatch.observe(document.body, {
      subtree: true, childList: true, attributes: true, attributeFilter: ['disabled'],
    });
  };

  /* ── 월 관리비 상세입력 창 ─────────────────────────────────── */
  const FEE_INCLUDES = {
    '청소비': '공용 관리비', '승강기유지비': '공용 관리비', '주차비': '공용 관리비', '경비비': '공용 관리비',
    '전기료': '전기', '수도료': '수도', '가스사용료': '가스', '난방비': '난방',
    '인터넷': '인터넷', '유선TV': 'TV', '기타': '기타 관리비',
  };
  const completeFeeModal = async () => {
    const box = await waitUntil(() => modal('월 관리비 상세입력'));
    if (!box) { miss('managementFee', '「관리비 있음」 뒤에 상세입력 창이 열리지 않았습니다.'); return; }
    const method = data.manageMethod === '기타 부과' ? '기타부과'
      : data.manageMethod === '확인 불가' ? '확인불가' : '정액관리비';
    const tab = modalButton(box, method);
    if (tab) { press(tab); await sleep(REACT + 200); } else miss('manageMethod', '상세입력 창에서 「' + method + '」 탭을 찾지 못했습니다.');

    if (method !== '확인불가') {
      const total = Number(data.managementFee);
      if (!filled(data.managementFee) || Number.isNaN(total)) {
        // 다방은 정액·기타 어느 쪽이든 총액이 있어야 「확인」이 켜진다.
        note('관리비 총액: 다방 상세입력 창은 부과 방식과 상관없이 총액을 요구하지만 통합 폼에 금액이 없어 창을 저장하지 않았습니다.');
        const close = modalButton(box, '닫기');
        if (close) press(close);
        return;
      }
      fill('managementFee', () => box.querySelector('input[name="detailCost"]'), data.managementFee, v => String(Number(v) * 10000));
      await sleep(REACT);
      if (method === '정액관리비') {
        // 10만원 미만/이상은 입력한 총액에서 그대로 따라온다.
        await choose('managementFee.threshold', () => box, total >= 10 ? '10만원 이상' : '10만원 미만');
        const basis = {
          '직전월 관리비 기준': '직전 월 관리비',
          '3개월 평균 관리비': '최근 3개월 관리비 평균',
          '1년 평균 관리비': '최근 1년 관리비 평균',
          '기타 직접 입력': '기타',
        }[data.manageBasis];
        if (basis) await choose('manageBasis', () => box, basis);
        else if (filled(data.manageBasis)) note('관리비 부과 기준 ' + data.manageBasis + ': 다방 상세입력 창에 대응하는 기준이 없습니다.');
      }
      if (method === '기타부과' && filled(data.otherFeeReason)) {
        await select('otherFeeReason', () => box.querySelector('[data-mirror-group="feeKind"] select'), {
          '관리규약에 따라 부과': '관리규약 등에 따라 부과',
          '면적 및 세대별 부과': '공용 관리비는 면적/세대별로 부과하고 사용료는 사용량에 따른 부과',
          '전체 세대 균등 부과': '전체 사용량을 세대수로 나누어 부과',
          '계량기별 실비 부과': '세대별 사용량(별도 계량기)에 따라 부과',
          '의뢰인 미고지': '정액관리비이지만 중개의뢰인이 세부내역 미고지한 경우',
          '기타': '기타',
        }[data.otherFeeReason] || data.otherFeeReason);
      }
      const seen = new Set();
      for (const item of (data.manageIncludes || [])) {
        const target = FEE_INCLUDES[item];
        if (!target) { note('관리비 포함 항목 ' + item + ': 다방 상세입력 창에 대응 항목이 없습니다.'); continue; }
        if (seen.has(target)) continue;
        seen.add(target);
        await choose('manageIncludes.' + item, () => box, target);
      }
    }

    const confirm = await waitUntil(() => {
      const button = modalButton(box, '확인');
      return button && !button.disabled ? button : null;
    });
    if (!confirm) {
      miss('managementFee', '상세입력 값을 넣었지만 「확인」이 켜지지 않았습니다. 창을 열어 둔 채 두었으니 직접 확인해 주세요.');
      return;
    }
    press(confirm);
    if (await waitUntil(() => !modal('월 관리비 상세입력'))) ok();
    else miss('managementFee', '「확인」을 눌렀지만 상세입력 창이 닫히지 않았습니다.');
  };

  /* ── 매물유형 ──────────────────────────────────────────────── */
  const PROPERTY = {
    '오픈형 원룸': ['주택', '빌라/연립/다세대'], '분리형 원룸': ['주택', '빌라/연립/다세대'],
    '복층형 원룸': ['주택', '빌라/연립/다세대'], '투룸 빌라': ['주택', '빌라/연립/다세대'],
    '쓰리룸 이상 빌라': ['주택', '빌라/연립/다세대'], '단독주택': ['주택', '단독주택'],
    '다가구주택': ['주택', '다가구주택'], '상가주택': ['주택', '상가주택'],
    '오피스텔 원룸형': ['오피스텔', null], '오피스텔 분리/투룸형': ['오피스텔', null],
    '아파트': ['아파트', null],
  };
  let complexProperty = false;
  const applyPropertyType = async () => {
    const mapping = PROPERTY[data.propertyType];
    if (!mapping) {
      note('매물 대분류 ' + data.propertyType + ': 다방 주거용 매물 등록 폼에 대응하는 유형이 없습니다.');
      return false;
    }
    const [major, minor] = mapping;
    // 대분류는 소분류 라디오(주택/빌라)나 단지 검색 칸(오피스텔·아파트)의 유무로 알아본다.
    const isHouse = () => !!document.querySelector('#room_info input[name="buildingType"]');
    const majorButton = () => [...(rowOf('room_info', '매물유형') || document).querySelectorAll('button')]
      .find(item => norm(text(item)).startsWith(norm(major)));
    const selected = button => !!button && (
      button.getAttribute('aria-pressed') === 'true' || button.getAttribute('aria-selected') === 'true' ||
      /(^|[\\s_-])(active|selected|checked|on)([\\s_-]|\$)/i.test(button.className || '') ||
      !!button.querySelector('input:checked'));
    // 주택/비주택 DOM만 보면 아파트와 오피스텔을 구분할 수 없다. 선택 표식이
    // 확실하지 않은 비주택 버튼은 다시 눌러도 멱등이므로 눌러 목표 대분류를 보장한다.
    const button = majorButton();
    const mustSwitch = major === '주택' ? !isHouse() : isHouse() || !selected(button);
    if (mustSwitch) {
      if (!button) { miss('propertyType', '대분류 「' + major + '」 버튼을 찾지 못했습니다.'); return false; }
      press(button);
      // 대분류를 바꾸면 매물 정보·추가 정보의 7개 행이 통째로 다시 그려진다.
      await waitUntil(() => (major === '주택') === isHouse(), 3000);
      await sleep(REACT);
    }
    if (!minor) {
      complexProperty = true;
      ok();
      return true;
    }
    // 소분류 라디오는 매물유형 행의 두 번째 칸에 있다.
    return choose('propertyType', () => rowOf('room_info', '매물유형'), minor);
  };

  // 아파트·오피스텔은 카카오 우편번호 대신 시/도 → 시/군/구 → 동 → 단지를
  // 차례로 고른다. 통합 주소에 들어 있는 지역명과 카카오가 돌려준 건물명을 쓴다.
  const enterComplexAddress = async major => {
    if (!filled(data.address)) return false;
    const wantedAddresses = [data.address, data.roadAddress, data.jibunAddress]
      .filter(filled).map(norm);
    const wantedAddress = wantedAddresses.join('|');
    const wantedBuilding = norm(data.buildingName);
    const selectAt = index => {
      const cell = addressCell();
      return cell ? cell.querySelectorAll('select')[index] : null;
    };
    for (let index = 0; index < 3; index++) {
      const element = await waitUntil(() => {
        const candidate = selectAt(index);
        return candidate && !candidate.disabled && candidate.options.length > 1 ? candidate : null;
      }, 5000);
      if (!element) {
        miss('address', major + ' 단지 검색의 ' + (index + 1) + '번째 지역 선택란이 준비되지 않았습니다.');
        return false;
      }
      const option = [...element.options].filter(item => item.value !== '')
        .find(item => wantedAddress.includes(norm(text(item))) || wantedAddress.includes(norm(item.value)));
      if (!option) {
        miss('address', '주소 「' + data.address + '」에 맞는 ' + (index + 1) + '번째 지역 선택지를 찾지 못했습니다.');
        return false;
      }
      if (!await select('address.region.' + index, () => selectAt(index), option.value, 5000)) return false;
    }

    const list = await waitUntil(() => {
      const cell = addressCell();
      const items = cell ? [...cell.querySelectorAll('ul[class*=SearchList] > li')] : [];
      return items.length ? items : null;
    }, 8000);
    if (!list) {
      miss('address', major + ' 단지 목록이 검색 뒤에도 나타나지 않았습니다.');
      return false;
    }
    const searchable = candidate => norm([
      text(candidate), candidate.getAttribute('title'), candidate.getAttribute('aria-label'),
      ...[...candidate.attributes].filter(attribute => attribute.name.startsWith('data-'))
        .map(attribute => attribute.value),
    ].filter(Boolean).join(' '));
    const addressMatches = list.filter(candidate => wantedAddresses.some(address => {
      const value = searchable(candidate);
      return value.includes(address) || address.includes(value);
    }));
    const named = wantedBuilding ? list.filter(candidate => {
      const value = norm(text(candidate));
      return value === wantedBuilding || value.includes(wantedBuilding) || wantedBuilding.includes(value);
    }) : [];
    const namedAndAddressed = named.filter(candidate => addressMatches.includes(candidate));
    // 검색 결과 자체의 유일한 도로명/지번, 주소+건물명의 유일한 교집합,
    // 유일한 건물명, 전체 유일 후보만 자동 선택한다. 여러 후보를 임의로 누르면
    // 검증 시점에는 이미 잘못된 단지가 폼에 반영되므로 첫 후보 fallback은 금지한다.
    const item = addressMatches.length === 1 ? addressMatches[0]
      : namedAndAddressed.length === 1 ? namedAndAddressed[0]
      : named.length === 1 ? named[0]
      : list.length === 1 ? list[0]
      : null;
    if (!item) {
      miss('address', major + ' 단지 후보 ' + list.length + '개 중 주소와 건물명으로 하나를 확정할 수 없습니다. 화면에서 직접 골라 주세요.');
      return false;
    }
    press(item.querySelector('button, label, a') || item);
    const picked = await waitUntil(() => {
      const cell = addressCell();
      const summary = cell && cell.querySelector('[class*=AddressList]');
      return summary && ((wantedBuilding && norm(text(summary)).includes(wantedBuilding)) ||
        wantedAddresses.some(address => norm(text(summary)).includes(address) ||
          address.includes(norm(text(summary))))) ? summary : null;
    }, 5000);
    if (!picked) {
      miss('address', '「' + data.buildingName + '」 단지를 눌렀지만 주소가 확정되지 않았습니다.');
      return false;
    }
    ok();
    afterAddressPicked();
    return true;
  };

  try {
    if (window.__flrPostcode) window.__flrPostcode.query = data.address || '';
    watchAddress();

    // ① 매물유형 — 대분류를 바꾸면 매물 정보 7행이 통째로 다시 그려지므로 가장 먼저.
    await applyPropertyType();

    // ② 주소 — 검색어만 미리 넣고, 결과 선택은 마지막에 띄우는 카카오 화면에서 받는다.
    if (complexProperty) {
      await enterComplexAddress(PROPERTY[data.propertyType][0]);
    } else {
      const keyword = addressCell() && addressCell().querySelector('input[name="keyword"]');
      if (filled(data.address) && keyword) {
        setNative(keyword, data.address);
        if (keyword.value === String(data.address)) output.applied++;
      }
    }
    afterAddressPicked();

    // ③ 면적 — 평/㎡ 두 칸이 짝이다. ㎡ 칸에 넣으면 미러가 평을 계산한다.
    const sizeCell = () => cellOf('room_info', '매물 크기');
    const areaInput = (heading, name) => () => {
      const group = groupOf(sizeCell(), heading);
      return group ? group.querySelectorAll('input[name="' + name + '"]')[1] : null;
    };
    fill('exclusiveArea', areaInput('전용면적', 'room'), data.exclusiveArea);
    fill('supplyArea', areaInput('공급면적(선택)', 'supply'), data.supplyArea);

    // ④ 건축물 용도·승인
    const pick = (section, label, selector, index = 0) => () => {
      const cell = cellOf(section, label);
      return cell ? cell.querySelectorAll(selector)[index] : null;
    };
    await select('buildingUse', pick('room_info', '건축물용도', 'select'), data.buildingUse);
    await select('approvalDateType', pick('room_info', '건축물승인', 'select'), '사용승인일');
    fill('approvalDate', pick('room_info', '건축물승인', 'input[type="text"]'), data.approvalDate, v => String(v).replace(/-/g, ''));

    // ⑤ 방 정보 — 방 수를 넣어야 방 거실 형태·방 특징이 켜진다.
    // 방 수를 넣으면 미러가 이 행을 통째로 다시 그린다 — 뒤의 자리는 반드시 새로 찾는다.
    const roomGroup = heading => () => groupOf(cellOf('room_info', '방 정보'), heading);
    fill('rooms', () => {
      const group = roomGroup('방 수')();
      return group ? group.querySelector('input') : null;
    }, data.rooms, v => String(v).replace(' 이상', ''));
    await sleep(REACT);
    const layout = {'오픈형 원룸': '오픈형', '분리형 원룸': '분리형', '복층형 원룸': null}[data.roomLayout];
    if (layout) await choose('roomLayout', roomGroup('방 거실 형태'), layout);
    else if (data.roomLayout !== '복층형 원룸' && filled(data.roomLayout)) {
      note('방 구조 ' + data.roomLayout + ': 다방의 오픈형/분리형에 정확히 대응하지 않습니다.');
    }
    if (data.petAllowed === '가능') await choose('petAllowed', roomGroup('방 특징(선택)'), '반려동물');
    else if (filled(data.petAllowed)) {
      note('반려동물 ' + data.petAllowed + ': 다방은 「허용」 체크만 제공해 불가능·확인 필요를 구분해 저장할 수 없습니다.');
    }

    // ⑥ 거래 종류 — 고르면 가격 정보 행과 LH 행이 다시 그려진다. 다 그려진 뒤에 넣는다.
    const tradeCell = () => cellOf('trade_info', '거래 종류');
    await choose('trade', tradeCell, data.trade);
    // 거래 종류를 고르면 가격 정보 행이 그 종류의 틀로 새로 그려진다. 다 그려진 뒤에 넣는다.
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
    if (data.shortTerm === true) {
      await choose('shortTerm', tradeCell, '단기임대');
      note('단기 매물 계약기간: 다방은 개월 수와 협의 여부를 함께 요구하지만 통합 폼에 기간 정보가 없어 화면에서 직접 골라 주셔야 합니다.');
    }

    // ⑦ 융자금 — 다방은 시세 대비 비율만 받는다.
    if (data.loan === '없음') await select('loan', pick('trade_info', '융자금 여부', 'select'), '없음');
    else if (filled(data.loan)) {
      note('융자금 ' + data.loan + (filled(data.loanAmount) ? ' (' + data.loanAmount + '만원)' : '') +
        ': 다방은 시세 대비 30% 이상/미만 구간만 받아 통합 폼의 금액만으로는 구간을 정할 수 없습니다.');
    }

    // ⑧ LH — 전세·월세에서만 나온다.
    if (filled(data.lh)) {
      if (cellOf('trade_info', 'LH')) await choose('lh', () => cellOf('trade_info', 'LH'), data.lh);
      else note('LH 전세임대 여부: 이 거래 종류에서는 다방 폼에 LH 항목이 나타나지 않습니다.');
    }

    // ⑨ 관리비
    await select('noManagementFee', pick('trade_info', '관리비', 'select'), data.noManagementFee === true ? '없음' : '있음');
    if (data.noManagementFee !== true) await completeFeeModal();
    if (filled(data.unknownFeeReason) && data.manageMethod === '확인 불가') {
      note('확인 불가 법정 사유: 다방 상세입력 창의 「확인불가」에는 사유를 고르는 칸이 없습니다.');
    }
    if (filled(data.manageDetail) && data.manageMethod === '정액 관리비') {
      note('비목별 실비·정액 내역: 다방은 포함 항목 체크만 받고 비목별 부과 방식은 저장하지 않습니다.');
    }

    // ⑩ 입주
    const moveIn = () => cellOf('trade_info', '입주 가능 일자');
    if (data.moveInType === '즉시 입주') await choose('moveInType', moveIn, '즉시 입주');
    else if (data.moveInType === '날짜 지정') {
      await choose('moveInType', moveIn, '일자 선택');
      fill('moveInDate', pick('trade_info', '입주 가능 일자', 'input[type="text"]'), data.moveInDate, v => String(v).replace(/-/g, ''));
    } else if (data.moveInType === '협의 가능') {
      await choose('moveInType', moveIn, '즉시 입주');
      await choose('moveInNegotiable', moveIn, '협의 가능할 경우');
      note('입주 방식 협의 가능: 다방은 즉시 입주/일자 선택 중 하나를 고른 뒤 「협의 가능할 경우」를 덧붙이는 구조라 즉시 입주 + 협의 가능으로 넣었습니다.');
    }
    if (data.moveInNegotiable === true) await choose('moveInNegotiable', moveIn, '협의 가능할 경우');

    // ⑪ 층 수 — 전체 층을 고르면 해당 층 목록이 다시 만들어진다.
    await select('floorAll', pick('additional_info', '층 수', 'select', 0), String(data.floorAll) + '층');
    await select('floor', pick('additional_info', '층 수', 'select', 1), data.floor === '옥탑' ? '옥탑' : String(data.floor));
    if (data.floorPrivate === true) {
      const hide = pick('additional_info', '층 수', 'input[type="checkbox"]');
      if (hide() && !hide().disabled) {
        await toggle('floorPrivate', hide, true, '저/중/고 표기');
        note('층수 비공개: 다방은 해당 층을 고른 뒤 저/중/고 표기만 대신 노출합니다. 표기 구간은 화면에서 직접 골라 주세요.');
      } else note('층수 비공개: 다방은 해당 층을 반드시 고르게 되어 있어 완전한 비공개로 둘 수 없습니다.');
    }

    // ⑫ 방향
    const base = {'거실 기준': '거실', '안방 기준': '안방', '주실 기준': '거실'}[data.directionBase];
    if (data.directionBase === '주실 기준') {
      note('방향 기준 주실 기준: 다방은 안방/거실만 제공해 「거실」로 넣었습니다(공인중개사법의 주실 = 거실이나 안방).');
    }
    if (base) {
      await select('directionBase', pick('additional_info', '방향 기준', 'select', 0), base);
      await select('direction', pick('additional_info', '방향 기준', 'select', 1), data.direction);
    }

    // ⑬ 욕실·엘리베이터 — 같은 줄의 다른 칸이다.
    fill('bathrooms', pick('additional_info', '욕실 수', 'input'), data.bathrooms, v => String(v).replace(' 이상', ''));
    await choose('elevator', () => cellOf('additional_info', '엘리베이터'), data.elevator);

    // ⑭ 주차
    const parkingOk = await select('parking', pick('additional_info', '주차 가능 여부', 'select'), data.parking === '주차 가능' ? '가능' : '불가능');
    if (parkingOk && data.parking === '주차 가능') {
      const count = pick('additional_info', '주차 가능 여부', 'input[type="text"]');
      if (await ready(count)) fill('parkingCount', count, data.parkingCount);
      else miss('parkingCount', '주차 대수 입력란이 켜지지 않았습니다.');
    }
    if (filled(data.parkingPerHousehold)) note('세대당 주차 대수: 다방은 총 주차 대수만 받습니다.');

    // ⑮ 복층
    if (filled(data.roomLayout)) {
      await choose('roomLayout.duplex', () => cellOf('additional_info', '복층 여부'), data.roomLayout === '복층형 원룸' ? '복층' : '단층');
    }

    // ⑯ 시설
    await choose('heating', () => cellOf('facility_info', '난방 시설'), data.heating);
    const living = () => cellOf('facility_info', '생활 시설');
    for (const item of (data.appliances || [])) {
      if (item === '에어컨') {
        note('에어컨: 다방은 벽걸이형·스탠드형·천장형 중 하나를 고르게 되어 있는데 통합 폼에는 종류 정보가 없어 임의로 고르지 않았습니다.');
        continue;
      }
      if (labelInput(living(), item)) await choose('appliances.' + item, living, item);
      else note('가전·가구 옵션 ' + item + ': 다방 생활 시설에 대응 항목이 없습니다.');
    }
    const FACILITY = {
      'CCTV': ['보안 시설', 'CCTV'], '인터폰': ['보안 시설', '인터폰'], '비디오폰': ['보안 시설', '비디오폰'],
      '공동현관보안': ['보안 시설', '현관보안'], '사설경비': ['보안 시설', '사설경비'],
      '무인택배함': ['기타 시설', '무인택배함'], '테라스': ['기타 시설', '테라스'], '베란다/발코니': ['기타 시설', '베란다'],
    };
    for (const item of (data.facilities || [])) {
      const target = FACILITY[item];
      if (!target) { note('보안 및 시설 옵션 ' + item + ': 다방 시설 정보에 대응 항목이 없습니다.'); continue; }
      await choose('facilities.' + item, () => cellOf('facility_info', target[0]), target[1]);
    }

    // ⑰ 글
    fill('title', pick('detail_info', '제목', 'input,textarea'), data.title);
    fill('description', pick('detail_info', '상세설명', 'textarea,input'), data.description);
    fill('privateMemo', pick('detail_info', '비공개 메모', 'textarea,input'), data.privateMemo);

    if (filled(data.violation) && data.violation !== '해당 없음') {
      note('위반건축물 여부: 다방 등록 폼에 별도 입력란이 없어 상세 설명에 「위반건축물」로 표시해야 합니다.');
    }
    if (filled(data.loanAvailable)) note('대출 가능 여부: 다방 등록 폼에 대응 입력란이 없습니다.');
    if (filled(data.ownerPhone)) note('집주인 연락처: 다방 등록 폼에 집주인 연락처 입력란이 없습니다.');
    if (data.singleBuilding === true) note('단일동 여부: 다방은 「등기부등본 상에 동 정보가 없을 경우」 체크만 제공하며 주소를 고른 뒤에 켜집니다.');
    for (const message of (window.__flrPostcode ? window.__flrPostcode.notes : [])) note(message);

    // ⑱ 마지막에 주소 검색 화면을 띄운다 — 전체 화면 겹이라 다른 입력을 가린다.
    if (filled(data.address) && !complexProperty) {
      const cell = addressCell();
      const search = cell && [...cell.querySelectorAll('button')].find(button => norm(text(button)) === '검색');
      if (search) {
        note('매물 기본 주소: 카카오 주소 검색을 띄웠습니다. 자동으로 고르지 못하면 결과를 직접 눌러 주세요. 고르면 주소·동·호가 채워집니다.');
        press(search);
      } else miss('address', '매물 주소의 「검색」 버튼을 찾지 못했습니다.');
    }
  } catch (error) {
    output.violations.push('다방 자동 입력 오류: ' + String(error && error.stack ? error.stack : error));
  }
  for (const violation of (window.__FLR_VIOLATIONS__ || [])) {
    const detail = typeof violation === 'string' ? violation
      : [violation.kind, violation.target, violation.detail].filter(Boolean).join(' · ');
    output.violations.push('깐깐이 위반: ' + detail);
  }
  // 「임시저장」·「등록 완료」·#submit 은 어떤 경우에도 누르지 않는다. 이 어댑터는 채우기만 한다.
  publish();
})();
''';

String daangnInjectionScript(String payload) =>
    '''
(async () => {
  const data = $payload;
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
  const target = $target;
  if (!target) return;
  if (window.__flrPickerRan || window.__flrPickerRunning) return;
  window.__flrPickerRunning = true;
  // Only the search this app started gets picked for the user. If they clear the
  // box and look for somewhere else, that is their choice to make.
  const squash = value => String(value === undefined || value === null ? '' : value).replace(/\\s+/g, '');
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
    let text = squash(value);
    for (const [full, short] of SIDO) {
      if (text.startsWith(full)) { text = short + text.slice(full.length); break; }
      if (text.startsWith(short)) break;
    }
    // 건물 이름은 통합 폼 주소에 없을 때가 많다 — 점수에서 뺀다.
    return text.replace(/\\(.*?\\)/g, '');
  };

  const wanted = normalize(target);
  // 번지·건물번호는 「123」과 「123-4」를 가르는 결정적인 부분이라 따로 본다.
  const numbersOf = text => (text.match(/\\d+(-\\d+)?/g) || []);
  const wantedNumbers = numbersOf(wanted);

  const score = candidate => {
    const value = normalize(candidate);
    if (!value) return -1;
    if (value === wanted) return 1000;
    let points = 0;
    // 앞에서부터 같은 길이 — 시/도 → 구 → 도로명 순으로 겹칠수록 높다.
    let prefix = 0;
    while (prefix < value.length && prefix < wanted.length && value[prefix] === wanted[prefix]) prefix++;
    points += prefix * 4;
    const values = numbersOf(value);
    for (const number of wantedNumbers) {
      if (values.includes(number)) points += 60;
      else if (values.some(other => other.split('-')[0] === number.split('-')[0])) points += 20;
    }
    // 찾는 주소에 없는 번지가 후보에 더 붙어 있으면(123 → 123-4) 그만큼 뺀다.
    points -= Math.max(0, values.length - wantedNumbers.length) * 15;
    if (value.includes(wanted) || wanted.includes(value)) points += 40;
    return points;
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
    if (!item) return false;
    const value = normalize(item.address);
    if (value === wanted) return true;
    const values = numbersOf(value);
    const exactNumbers = wantedNumbers.length > 0 &&
      wantedNumbers.every(number => values.includes(number));
    let prefix = 0;
    while (prefix < value.length && prefix < wanted.length && value[prefix] === wanted[prefix]) prefix++;
    const localityLength = Math.min(8, wanted.replace(/\\d.*\$/, '').length);
    // 이전 검색 결과가 남아 있어도 같은 번지와 충분한 시/구/도로명 접두사가
    // 겹치기 전에는 누르지 않는다. 번지 없는 주소는 포함 관계만 허용한다.
    return wantedNumbers.length > 0
      ? exactNumbers && prefix >= localityLength
      : (value.includes(wanted) || wanted.includes(value));
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
      return squash(value) === squash(target) ? value : null;
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
    window.__flrPickerRan = true;
    try { sessionStorage.setItem('flrPicked', '1'); } catch (_) { /* ignore */ }
    press(pick.button);

    // 도로명 하나에 지번이 여럿이면 카카오가 지번 고르는 화면을 한 번 더 띄운다.
    const second = await waitFor(() => {
      const list = document.querySelector('.main_jibun, .list_jibun, [class*=mapping_jibun]');
      if (!list) return null;
      const items = candidates().filter(item => list.contains(item.span));
      return items.length ? items : null;
    }, 2500);
    if (!second) return;
    const follow = best(second);
    // 어느 지번인지 가릴 근거가 없으면 카카오가 준 첫 줄을 쓴다.
    press((follow || second[0]).button);
  })().finally(() => { window.__flrPickerRunning = false; });
})();
''';
