# 직방 매물 등록폼 — DOM 전수조사

`ceo.zigbang.com/ads/oneroom/ad-item/new` (원룸) 등록폼을 **DOM 조작 자동화**에 쓸 수 있는
형태로 정리한 문서다. 원본 캡처(16MB)를 다시 열지 않고 이 문서만으로 어댑터를 짤 수 있게 썼다.

> **이 문서는 이음 확장 분석과 무관하다.** 실물 폼만 보고 독립적으로 작성했다.

---

## 0. 근거와 검증 방법

| 근거 | 무엇 |
|---|---|
| `fieldlog_capture_ceo.zigbang.com_2026-09-08T12-43.json` | 필드 347 · 클릭대상 852 · 의미조작 168 · 원시이벤트 1,036 · 상태 5 |
| 상태 `s3` (자동: 시작, 12:36:54Z) | 등록폼 **초기 상태** DOM 114,698자 (`truncated: false`) |
| 상태 `s4` (자동: 정지, 12:43:15Z) | 등록폼 **최종 상태** DOM 146,202자 (`truncated: false`) |
| 상태 `s1`·`s2` | 같은 문서의 **이전 세션** — 매물 *목록* 페이지(`/ads/oneroom`). 등록폼이 아니다 |
| `pages[1]` | **주소 검색 팝업 창** (`windowName: "zikim-search-address"`) — 카카오 우편번호 iframe |
| SingleFile ×3 | `직방_매물등록폼.html`(21:36:48, 빈 폼) · `직방_매물등록폼_입력후.html`(21:43:57) · `…_입력후_2.html`(21:44:17) — **셋 다 같은 페이지 로드**(§5-3) |

검증 방식:

- 폼 골격은 상태 DOM을 lxml로 직접 파싱했다. 필드로그 요약(`labels`·`판정`)은 참고만 했다.
- 조건부 표시는 `actions` + `timeline` 의 인과 기록으로 확정했고 본문에 `[aNN]` 로 표시했다.
- **`<select>` 의 `<option>` 은 상태 DOM에서 값·텍스트를 그대로 읽었다.** 추정이 아니다.

### 이 문서가 다루지 못하는 것 · 원본 데이터의 함정

1. **`pages[0]` 은 두 세션이 합쳐진 레코드다** (`meta.sessions: 2`).
   `fields` 347개에는 매물 *목록* 화면의 칸과 GNB·광고 스크립트가 만든 잡 요소가 섞여 있다.
   등록폼만 보려면 `states[2]`(s3)·`states[3]`(s4) 의 DOM을 봐야 한다. **347을 폼 칸 수로 읽으면 안 된다.**
   등록폼 안의 `name`/`id` 를 가진 요소는 최종 상태 기준 **75개**다.
2. **`mutations` 는 0.06초~73.97초 구간만 남았다.** 2,500건 상한에 닿은 뒤로는
   **새 항목을 버린다**(`recorder.js:970`). 74초 이후는 `actions`·`timeline`·상태 DOM으로만 판단했다.
3. **`sideEffects` 2건은 오귀속이다. 믿지 말 것.**
   - `ho` → 단일동 체크박스 `false→true`: `ho` 변경 26.4초, 단일동 클릭 26.5~26.6초 `[a8,a9]`.
   - `sales.rent` → `jibun-open` `''→'on'`: `rent` 변경 47.01초, 「단독주택」 클릭 47.16초 `[a30]`.
     `jibun-open` 은 단독주택 선택으로 다시 마운트된 것이다.
     레코더의 부수효과 판정 창(250~450ms) 안에 **관계없는 클릭**이 들어와 생긴 잘못된 연결이다.
     실제로 확인된 자동 변환은 `sales.rent` 의 **천단위 콤마**뿐이다(§8).
4. **매물 종류는 「원룸」탭 하나만 캡처했다.** 좌측에 `원룸`/`빌라` 탭
   (`button#radix-:r36:-trigger-원룸`, `…-trigger-빌라`)이 있으나 **빌라 폼은 미확인**이다.
5. 캡처에 실제 주소·중개사무소 정보가 들어 있다. 이 문서에서는 가렸다.

---

## 1. 페이지 기본 성질

| 항목 | 값 | 근거 |
|---|---|---|
| URL | `https://ceo.zigbang.com/ads/oneroom/ad-item/new` | `states[2].url` |
| 진입 | `/ads/oneroom` 목록 → **SPA 클라이언트 라우팅**. 같은 문서(`captureId` 동일) | s1~s4가 한 레코드 |
| 프레임 | 등록폼 자체는 **top 프레임 단일**, iframe 없음 | 상태 DOM |
| open Shadow DOM | `<next-route-announcer>` 1개(264자)뿐 — **폼과 무관** | `openShadows` |
| `<form>` | **있음.** `form.max-w-screen-md2.bg-background.mx-auto.p-5` (문서에 1개) | s3/s4 |
| 프레임워크 | Next.js + React + **Radix UI(shadcn/ui)** + react-hook-form + react-day-picker | 클래스·속성 전수 |
| 오류 추적 | **Sentry**. `data-sentry-component` / `data-sentry-element` / `data-sentry-source-file` | §5-4 |
| 초기 컨트롤 수 | `input` 33 · `select` 8 · `textarea` 3 · `button` 78 | s3 |
| 최종 컨트롤 수 | `input` 46 · `select` 15 · `textarea` 3 · `button` 80 | s4 |
| 주소 입력 | **별도 브라우저 창**(`window.name = "zikim-search-address"`) 안의 **교차출처 iframe**(`postcode.map.kakao.com`) | `pages[1]` |

---

## 2. 화면 위 → 아래 골격 (초기 상태 `s3`)

`§` = 섹션 제목(`div.text-lg.font-bold`), `·` = 행 라벨(`label[for$="-form-item"]`),
`*` = 필수(라벨 안 `span.text-red-500`).

```
[GNB]  직방ㅣ호갱노노 CEO / 홈 · 광고관리 · 채팅 · 상품소개 · 허위광고OUT · 이용안내 · 마이페이지 · 전체 메뉴
[좌측] role=tablist(vertical): button#radix-:r36:-trigger-원룸 (aria-selected=true) / …-trigger-빌라
       직방 서비스 바로가기 / 호갱노노 서비스 바로가기 / 상품 및 이용문의
───────────────────────────────────────────────────────────────
h2 매물 등록                                   [취소]
   고지문 3줄 (독립 주거 형태만 / 불법 개조·증축 비권장 / 등록 기준 위반 시 종료)

<form class="max-w-screen-md2 bg-background mx-auto p-5">

§ 기본 정보
  · 주소 *              input[name=lat] readonly            ← 값은 주소 문자열. 팝업창이 채운다
                        (우측 링크: "주소 검색이 안되시나요?")
  · 동 *                □ 단일동  button#haveNoDong[role=checkbox]
                        input[name=dongDetail.dong]
  · 호 *                input[name=ho]
  · 건물 종류 *          [단독주택] button[name=residence.residenceType]
                        [그 외(직접 입력)] button (name 없음)
                        input[name=residence.residenceTypeDescription]  ← 초기 disabled
  · 거래 유형 *          □ 단기 매물  button#isShortTerm[role=checkbox]
                        [전세] button[name=sales.salesType]  [월세] button[name=sales.salesType]
  · 전용면적 *           input[name=sizeM2][type=text][inputmode=decimal] + 접미사 「㎡」
  · 사용승인일 *         input[name=approveDate] maxlength=20
                        (우측 링크: "검수 기준 보기")
  · 입주 가능일 *        □ 즉시 입주 가능  button#moveInImmediately[role=checkbox]
                        input[name=moveInDate] readonly   ← 클릭하면 캘린더
                        input[name=moveInDateExtra] maxlength=10 (「/ 10자 입력」 카운터)

§ 구조/시설 정보
  · 전체 층 *            button[role=combobox] + select[name=floorAll]      옵션 80 (1층~80층)
  · 해당 층 *            button[role=combobox] + select[name=floor]         옵션 2 → 동적(§6-3)
  · 구조 *              button[role=combobox] + select[name=roomType]      옵션 3
  · 주실 방향 *          [거실 기준] button[name=directionCriterionType] / [안방 기준] button
                        button[role=combobox] + select[name=roomDirection] 옵션 8
  · 화장실 수 *          button[role=combobox] + select[name=bathroomCnt]   옵션 5
  · 총 주차대수 *        □ 주차 불가능  button#no-parking[role=checkbox]
                        input[name=parkingAndHousehold.totalParkingCnt]
  · 총 세대 수           input[name=parkingAndHousehold.householdCnt]
  · 위반건축물 해당 여부 * [해당] button[name=nonCompliantBuilding] / [해당없음] button
                        (우측 링크: "건축물 대장 열람")
  · 융자금               [융자금 없음] button[name=noLoan] / [융자금 30%이하] button[name=loanUnder30]
  · 옵션                 button ×12 — 에어컨 냉장고 세탁기 가스레인지 인덕션 전자레인지
                                       책상 책장 침대 옷장 신발장 싱크대   ← 전부 name 없음
  · 엘리베이터 유무 *     [있음] button[name=isElevator] / [없음] button

§ 관리비 정보     (섹션 제목 옆) □ 관리비 없음  button#no-manage-cost[role=checkbox]
  고지문: 국토교통부 개선조치로 24년5월30일부터 (신)관리비 부과내역 세분화 표시 필수
  · 관리비 부과 방식 *    [정액 관리비] [기타] [확인 불가]  ← 셋 다 name 없음. 초기 선택 = 「기타」
  ── 아래는 「기타」 갈래의 화면 (초기 상태) ───────────────────────
  · 관리비 부과 기준 *    combobox + select[name=manageCostDetail.manageCostCriteria.manageCostCriteria] 옵션 4
                        input[name=…manageCostCriteriaEtcDescription] maxlength=20  ← 초기 disabled
  · 월 평균 관리비 *      input[name=manageCostDetail.basisDetail.avgManageCost] + 접미사 「원」
  · 관리비 포함 항목 *    button[name=manageCostDetail.detailIncludes] ×8
                        일반(공용) 관리비 / 전기료 / 수도료 / 가스 사용료 / 난방비 / 인터넷 사용료 / TV 사용료 / 기타 관리비
  · 관리비 실비 부과 세부 내역 *  combobox + select[name=manageCostDetail.basisDetail.basis] 옵션 7
                        input[name=…basisEtcDescription] maxlength=20  ← 초기 disabled

§ 매물 설명
  · 매물 사진 *          input[name=images] readonly   ← 클릭하면 「이미지 넣기」 모달
                        (우측 링크: 사진 촬영 가이드 → zigbang.notion.site/…)
  · 한줄 요약 *          input[name=title] maxlength=32 (최소 7자)
  · 상세 설명 *          textarea[name=description] maxlength=2000
  · 매물 조건            button[role=checkbox] ×6
                        #itemConditions.pet(반려동물 가능) / .loanLease(전세자금대출 가능)
                        / .digitalContract(전자계약) / .cctv(CCTV) / .terrace(테라스) / .evStation(전기차 충전)

§ 추가 정보
  · 비밀 메모 (비공개)    textarea[name=secretMemo] maxlength=200
  · 관심 태그            [관심 태그 현황] button + combobox + select[name=itemBaseTagId] 옵션 26
  · (라벨 없음)          [전화로 확인] [만나서 확인] [기타 방법으로 확인]
                        button[name=mediationRequest.mediationRequestType] ×3

§ 의뢰인 정보   (안내 4줄: 전화번호 인증 시 '실매물 확인' 뱃지 등)
  · 성함 또는 호칭        input[name=verification.lessorName]
  · 전화번호             input[name=verification.lessorPhone][type=tel] maxlength=11
                        [확인] button (초기 disabled)
  중복된 전화번호 입력 사유 선택*   <p name="verification.duplicatedLessor.reasonType">
    div[role=radiogroup]:
      button#MULTIPLE_OWNER[role=radio][value=MULTIPLE_OWNER]   의뢰인 다주택 보유
      button#CORPORATE_OWNER[role=radio][value=CORPORATE_OWNER] 법인 소유
      button#AGENT_DELEGATION[role=radio][value=AGENT_DELEGATION] 관리인·대리인 위임
      button#ETC[role=radio][value=ETC]                          기타 (0 / 32자 입력)
    textarea[name=verification.duplicatedLessor.reason] placeholder="기타 사유 입력(최소 5자)"

  div[data-scroll-field="agreesTerms"]
     button#agreesTerms[role=checkbox]  광고등록 관리 정책을 확인하였으며 …
  [매물 등록 완료] button[type=submit]        ← ⚠ 절대 누르지 말 것
</form>
```

---

## 3. 컨트롤 유형별 실제 마크업과 조작 방법

직방은 **6가지 패턴**만 쓴다.

### 3-1. 텍스트 입력 — 평범한 `<input>`

`name` 이 붙어 있고 `id=":rXX:-form-item"`, 라벨은 `label[for=":rXX:-form-item"]`.
react-hook-form 이 `register()` 로 붙인 controlled input 이므로
**네이티브 value setter + `input` 이벤트**로 넣어야 한다.

일부는 `readonly` 라 타이핑 자체가 막혀 있다 → `lat`, `moveInDate`, `images`.

### 3-2. 토글 버튼 — **`aria-pressed` 도 `data-state` 도 없다**

```html
<button type="button" name="residence.residenceType"
        class="… border-input bg-background text-secondary-foreground …">단독주택</button>
```

**선택 여부를 알려주는 속성이 하나도 없다. 클래스로만 구분된다.**

| 상태 | 클래스 |
|---|---|
| 선택됨 | `border-orange-500 text-orange-500` (그리고 `border-input`·`text-secondary-foreground` 없음) |
| 선택 안 됨 | `border-input` `text-secondary-foreground` |

s3/s4 대조로 확인했다. 예: s3에서 「기타」만 주황, s4에서 「정액 관리비」·「월세」·「단독주택」·
「해당」·「융자금 30%이하」·「에어컨」·「냉장고」·「없음」·「거실 기준」이 주황이었다.

⇒ **누르기 전에 클래스로 현재 상태를 읽어야 한다.** 켜져 있는데 또 누르면 꺼진다
(다중선택 그룹인 「옵션」·「관리비 포함 항목」에서 특히 위험. `[a101]~[a104]` 에 실제로
「책장」을 세 번 눌러 켜고 끄고 켠 기록이 있다).

**`name` 이 그룹마다 일관되지 않다.** 이것이 직방에서 가장 헷갈리는 부분이다.

| 그룹 | `name` 부여 방식 |
|---|---|
| 건물 종류 | 두 버튼 모두 `residence.residenceType` |
| 거래 유형 | 두 버튼 모두 `sales.salesType` |
| 중개 의뢰 방법 | 세 버튼 모두 `mediationRequest.mediationRequestType` |
| 관리비 포함 항목 | 여덟 버튼 모두 `manageCostDetail.detailIncludes` |
| 위반건축물 | 「해당」만 `nonCompliantBuilding`, 「해당없음」은 **name 없음** |
| 엘리베이터 | 「있음」만 `isElevator`, 「없음」은 **name 없음** |
| 주실 방향 기준 | 「거실 기준」만 `directionCriterionType`, 「안방 기준」은 **name 없음** |
| 융자금 | 「융자금 없음」=`noLoan`, 「융자금 30%이하」=`loanUnder30` — **서로 다른 이름** |
| 관리비 부과 방식 | 정액/기타/확인 불가 **셋 다 name 없음** |
| 옵션(가전 12종) | **12개 전부 name 없음** |

⇒ 안전한 방법: **행 라벨로 블록을 좁힌 뒤 버튼 텍스트로 고른다.**

```
label[for$="-form-item"] 중 텍스트가 "옵션"인 것
  → 그 라벨의 조상 [data-sentry-component="SubSection"]
  → 그 안에서 textContent === "에어컨" 인 button
```

### 3-3. 체크박스 / 라디오 — Radix, `<button role=…>` + 숨은 미러 `<input>`

```html
<div class="[&_input[aria-hidden='true']]:hidden">
  <button type="button" role="checkbox" id="haveNoDong" value="on"
          aria-checked="false" data-state="unchecked" class="…"></button>
  <input type="checkbox" value="on" aria-hidden="true" tabindex="-1"
         style="transform:translateX(-100%);position:absolute;opacity:0;width:0;height:0">
</div>
<label for="haveNoDong">단일동</label>
```

- **상태는 `aria-checked` 와 `data-state`(`checked`/`unchecked`)로 읽는다.** 토글 버튼과 달리 명시적이다.
- `id` 가 **의미 있는 고정 문자열**이다 → 직방에서 가장 좋은 셀렉터 (§5-1).
- 조작은 `button` 을 클릭한다. 숨은 `input[aria-hidden=true]` 는 폼 값 미러일 뿐이다.
- 라디오는 `div[role=radiogroup]` 안에 `button[role=radio][value=…]` 로 들어간다.
  ⚠ 관리비 「고지 받았습니다/받지 않았습니다」 라디오는 **`id="true"` / `id="false"`** 다.
  CSS 셀렉터로 쓰려면 `#\74 rue` 식 이스케이프가 필요하니 `getElementById` 나
  `[id="true"]` 속성 셀렉터를 쓰는 편이 낫다.

### 3-4. 드롭다운 — Radix Select (`button[role=combobox]` + 숨은 `<select>`)

```html
<button type="button" role="combobox" aria-expanded="false"
        aria-controls="radix-:r3s:" data-state="closed" class="…">
  <span>전체 층 선택</span><svg/>
</button>
<select name="floorAll" aria-hidden="true" tabindex="-1" style="…화면 밖…">
  <option value="1">1층</option> … <option value="80">80층</option>
</select>
```

**두 가지를 분명히 구분해야 한다.**

- **숨은 `<select>`** 는 Radix 의 값 미러다. `name` 과 전체 `<option>` 목록을 갖고 있어
  **옵션 카탈로그를 읽는 데는 완벽한 출처**이고, Radix 가 값이 바뀔 때마다 여기에 `change` 를
  발생시킨다(캡처의 `change select[floorAll]` 등이 그것이다).
  다만 이것은 **Radix → select 단방향**이다. 여기에 값을 써넣어도 Radix 내부 상태는 안 바뀐다.
- **실제 조작**은 `button[role=combobox]` 를 클릭 → 포털로 열리는 목록에서 항목을 클릭한다.

목록은 `document.body` 바로 아래 포털로 붙고 `[role=listbox]` 다.

```html
<div id="radix-:r3s:" role="listbox" data-state="open" data-side="bottom" …>
  <div data-radix-select-viewport role="presentation">
    <div role="option" aria-selected="false" data-state="unchecked"
         data-radix-collection-item aria-labelledby="radix-:rkf:" tabindex="-1">
      <span id="radix-:rkf:">1층</span>
    </div> …
  </div>
</div>
```

- 항목에는 **`value` 속성이 없다.** `<span>` 의 텍스트가 유일한 식별자다.
  → `select` 에서 `value → text` 를 먼저 읽어 두고, 그 텍스트로 `[role=option]` 을 찾는다.
- 열려 있는 listbox 는 문서에 하나뿐이었다. `aria-controls` 로 트리거와 목록을 짝지을 수 있다.

### 3-5. 캘린더 — react-day-picker + Radix Select

`input[name=moveInDate]`(readonly) 클릭 → `[role=dialog]` 안에 `div.rdp` 가 열린다.

```html
<div class="rdp mt-3 p-0" data-sentry-component="Calendar" data-sentry-source-file="calendar.tsx">
  <button role="combobox" aria-controls="radix-:r9t:"><span>2026년</span></button>   ← 연도 Select
  <button role="combobox" aria-controls="radix-:r9u:"><span>9월</span></button>      ← 월 Select
  <button name="previous-month" aria-label="Go to previous month">
  <button name="next-month"     aria-label="Go to next month">
  …
  <td …><button name="day" role="gridcell" type="button" tabindex="-1" class="rdp-button…">3</button></td>
</div>
```

- 날짜 칸은 전부 `button[name="day"]` (한 달에 35개)이고 **텍스트가 일(day) 숫자뿐**이다.
  `aria-label` 도 `data-*` 도 없다. 앞뒤 달의 넘침 날짜도 같은 `name` 을 갖는다
  → **`.rdp-day_outside` 계열 클래스로 걸러내거나, 표시된 연·월을 먼저 맞춘 뒤 고를 것.**
- 고른 뒤 다이얼로그 하단 버튼의 텍스트가
  `"날짜를 선택해 주세요."` → `"2033년 3월 3일로 선택"` 으로 바뀐다. **이 버튼을 눌러야 확정된다** `[a48→a49]`.
- 연·월은 Radix Select 라 §3-4 와 같은 방식(트리거 클릭 → 포털 listbox 항목 클릭)이다.
  `[a47]` 에서 월 목록 12개가 열린 것이 기록돼 있다.
- 확정 후 `input[name=moveInDate].value` 는 **`"2033년 3월 3일"`** 형식이다.

### 3-6. 사진 — 모달 안의 숨은 file input

`input[name=images]`(readonly) 클릭 → `[role=dialog]` 「이미지 넣기」가 열린다 `[a153]`.

```html
<div role="dialog" id="radix-:r4p:" data-state="open">
  <h2>이미지 넣기</h2>
  <div data-sentry-component="Dropzone" role="presentation" tabindex="0">
    <input type="file" accept="image/*,.png,.jpg,.jpeg" multiple tabindex="-1"
           style="clip:rect(0,0,0,0);width:1px;height:1px;position:absolute;…">
    …
  </div>
  … [확인] [Close]
</div>
```

규칙(모달 안내문): JPG/JPEG/PNG만, 장당 최대 10MB, **최소 5장 최대 20장**, 첫 장이 대표 사진.

---

## 4. 주소 입력 — **별도 창 + 교차출처 iframe**

`input[name=lat]` 은 `readonly` 이고 `cursor-pointer` 클래스를 갖는다. 값은 주소 문자열이다
(**필드명이 `lat` 인데 위도가 아니라 주소 문자열이 들어간다.** 최종 상태 값은 `"〈시 구 동 지번〉"` 형태의
실제 주소였다 — 개인정보라 여기엔 옮기지 않는다).

같은 세션에서 **별도 브라우저 창**이 하나 잡혔다 (`pages[1]`).

```json
"frameContext": { "depth": 0, "ancestorOrigins": [],
                  "referrer": "https://ceo.zigbang.com/ads/oneroom/ad-item/new",
                  "windowName": "zikim-search-address" }
```

그 창의 문서 전체는 이것뿐이다.

```html
<html lang="ko"><head><title>Kakao Postcode Service</title>…</head>
<body><iframe id="__kakao__viewerFrame_1" title="우편번호 검색 프레임"
  src="https://postcode.map.kakao.com/search?origin=https%3A%2F%2Fceo.zigbang.com&…&fullpath=%2Fads%2Foneroom"
  style="width:100%;height:100%;min-width:300px"></iframe></body></html>
```

**자동화 관점의 결론:**

- 주소 검색 UI는 **`ceo.zigbang.com` 문서 안에 없다.** 별도 창의, 게다가 **교차출처
  (`postcode.map.kakao.com`) iframe** 안에 있다. 메인 페이지의 content script로는 손댈 수 없다.
- 값이 들어오는 경로도 **입력 이벤트가 아니다.** 캡처 전체에 `lat` 에 대한 `input`/`change`
  이벤트가 **0건**인데 최종 값은 채워져 있다 → 팝업의 콜백이 react-hook-form 상태를 직접 갱신했다.
  ⇒ `lat` 에 값을 써넣는 방식으로는 폼 상태가 바뀌지 않을 가능성이 높다. **미검증이지만 위험 신호다.**
- 팝업을 여는 클릭은 이 캡처에 없다. 팝업 레코드는 세션 시작 4.7초 시점에 이미 존재했고,
  첫 조작 기록(`[a1]`)은 9.9초다. **무엇을 눌러 열리는지는 미확인.**

---

## 5. 셀렉터 안정성

### 5-1. 최우선 — 의미 있는 고정 `id` (Radix 체크박스/라디오 19개)

| id | 라벨 |
|---|---|
| `haveNoDong` | 단일동 |
| `isShortTerm` | 단기 매물 |
| `moveInImmediately` | 즉시 입주 가능 |
| `no-parking` | 주차 불가능 |
| `no-manage-cost` | 관리비 없음 |
| `jibun-open` | 집주인이 정확한 지번공개를 원합니다.(선택) |
| `itemConditions.pet` / `.loanLease` / `.digitalContract` / `.cctv` / `.terrace` / `.evStation` | 반려동물 가능 / 전세자금대출 가능 / 전자계약 / CCTV / 테라스 / 전기차 충전 |
| `agreesTerms` | 광고등록 규정 동의 |
| `MULTIPLE_OWNER` / `CORPORATE_OWNER` / `AGENT_DELEGATION` / `ETC` | 중복 전화번호 사유 4종 |
| `true` / `false` | 관리비 고지 받았습니다 / 받지 않았습니다 |

⚠ `ETC`, `true`, `false` 는 **다른 곳과 충돌하기 쉬운 이름**이다. 반드시 섹션으로 좁혀서 쓸 것.

### 5-2. 다음 — `name` (§9 전수표)

등록폼 안에서 `name` 은 대부분 유일하다. 중복은 4종뿐이다.

| `name` | 개수 | 구분 |
|---|---:|---|
| `manageCostDetail.detailIncludes` | 8 | 버튼 텍스트 (「기타」 갈래에서만 존재) |
| `mediationRequest.mediationRequestType` | 3 | 버튼 텍스트 |
| `residence.residenceType` | 2 | 버튼 텍스트 |
| `sales.salesType` | 2 | 버튼 텍스트 (전세/월세) |

### 5-3. 쓰면 안 되는 것 — `id=":rXX:-form-item"` (React `useId`)

- 값에 **콜론이 들어간다.** CSS로 쓰려면 `#\:r39\:-form-item` 처럼 이스케이프해야 한다.
- **재로드 안정성은 이 캡처로 증명하지 못했다.** SingleFile 3개가 전부 **같은 페이지 로드**였다
  (세 파일 모두 `:r39:`·`:r3d:`·`:r3e:` 로 시작하고,
  GNB의 `radix-:R15dkq:-trigger-…` 도 동일). 세션 중 SPA 이동만 있었고 새 로드가 없었다.
- 다만 **한 로드 안에서도 나중에 마운트된 칸은 훨씬 큰 번호를 받는다.**
  보증금·월세가 생기면서 `:r9n:`·`:r9p:` 를 받았고, 캘린더의 연·월 Select 는 `:r9t:`·`:r9u:`,
  관리비 상세의 listbox 는 `:r12u:`·`:r157:`·`:r16o:`·`:r17s:`·`:r182:`·`:r185:`·`:r18b:`·`:r18e:` 였다.
- React `useId` 는 **렌더 트리의 순서에서 결정된다.** 배포로 컴포넌트가 하나만 추가돼도
  그 뒤 모든 번호가 밀린다. 당근에서는 재로드마다 100% 바뀌는 것이 실측됐다.
  **직방에서도 쓰지 말 것을 권한다** (증명은 못 했으니 이건 판단이다 — §11 재수집 항목).

### 5-4. 보조 — Sentry 속성

빌드 시점에 소스에서 박히는 값이라 클래스나 경로보다 안정적이다.

| 속성 | 값 예 | 쓸모 |
|---|---|---|
| `data-sentry-component` | `Section`(6) `SubSection`(20) `ConditionButton`(6) `FieldCheckbox`(5) `FieldRightUnderLineText`(4) `CriteriaField` `DetailFeeBox` `Calendar` `Dropzone` | **행 단위로 블록을 잡는 데 가장 좋다** |
| `data-sentry-source-file` | `Section.tsx` `FieldCheckbox.tsx` `MoveInDateField.tsx` `OwnerInfoField.tsx` `calendar.tsx` `dropzone.tsx` | 어느 컴포넌트인지 판별 |
| `data-sentry-element` | `Input` `Button` `Checkbox` `RadioGroup` `SelectPrimitive.Trigger` `DayPicker` `SelectValue` | 요소 종류 판별 |

⚠ 컴포넌트 이름이 바뀌면 같이 바뀐다. **1차 셀렉터가 아니라 보조로만 쓸 것.**

기타: `data-scroll-field="agreesTerms"` 1건, `data-gtm-form-interact-field-id`(GTM이 상호작용 후
동적으로 붙임 — 초기 DOM에는 없다), `data-radix-collection-item`(Radix 내부).
**`data-testid` 는 0건이다.**

### 5-5. 라벨 텍스트

`label[for$="-form-item"]` 의 텍스트에는 필수 표시 `*` 가 **`<span class="text-red-500">*</span>`**
로 붙어 있다. `textContent` 로 읽으면 `"주소 *"` 가 아니라 `"주소*"` 로 붙어 나온다.
**`*` 를 떼고 비교할 것.**

### 5-6. ⚠ `label[for]` → `id` 로 칸을 찾으면 안 된다 — **10/38 만 실제로 이어져 있다**

라벨이 `for=` 를 갖고 있으니 「라벨 텍스트 → `for` → 그 `id` 의 칸」 경로가 될 것 같지만 **대부분 끊겨 있다.**
SingleFile 3개 전부에서 `<label for=…>` 를 전수 판정한 결과다.

| 판정 | 초기(`직방_매물등록폼.html`) | 입력후 ×2 |
|---|---:|---:|
| ✅ 라벨 대상이 될 수 있는 태그를 가리킴 (`<input>` 4 · `<button>` 6) | **10** | **13** |
| ⚠ `<div>` 를 가리킴 — `<label>` 은 `<div>` 를 라벨링할 수 없다 | 14 | 14 |
| ❌ 그 `id` 를 가진 태그가 문서에 **없다** | 14 | 21 |
| 합계 | 38 | 48 |

`aria-labelledby` 는 **문서 전체에 0건**이다. 즉 만회 경로도 없다.

끊긴 칸의 예 (초기 상태):

```
❌ id 없음   전용면적 · 사용승인일 · 입주 가능일 · 전체 층 · 해당 층 · 구조 · 화장실 수
             관리비 부과 기준 · 관리비 실비 부과 세부 내역 · 매물 사진 · 한줄 요약
             상세 설명 · 비밀 메모(비공개) · 관심 태그
⚠ div 지목   건물 종류 · 거래 유형 · 주실 방향 · 총 주차대수 · 총 세대 수 · 위반건축물 해당 여부
             융자금 · 옵션 · 엘리베이터 유무 · 관리비 부과 방식 · 월 평균 관리비
             관리비 포함 항목 · 매물 조건 · 전화번호
```

실물 (「전용면적」):

```html
<label for=:r3j:-form-item>전용면적<span class=text-red-500>*</span></label>
</div><div>
<input placeholder="소수점 자리까지 입력해주세요." inputmode=decimal type=text name=sizeM2 value>
       ↑ id 가 아예 없다. :r3j:-form-item 은 문서 어디에도 존재하지 않는다
```

**원인.** shadcn/ui 의 `FormItem` 이 `useId` 로 만든 번호를 `FormLabel` 의 `for` 와 컨트롤의 `id` 에
양쪽으로 심는 구조인데, 컨트롤이 그 `id` 를 전달받지 않으면 **감싸는 `<div>` 에 붙거나 아무 데도 안 붙는다.**
`for` 가 없는 `id` 를 가리켜도, `<div>` 를 가리켜도 **브라우저는 아무 에러를 내지 않는다.**
화면상 증상은 「라벨 글자를 클릭해도 칸이 안 눌린다」뿐이라 눈으로는 발견되지 않는다.

**살아 있는 10개는 전부 `id` 가 자동 번호가 아니라 뜻이 있는 이름이다**
(`haveNoDong` `isShortTerm` `moveInImmediately` …). 즉 §5-1 의 고정 `id` 목록과 겹친다.
⇒ **라벨↔칸 연결은 `for` 가 아니라 위치(라벨의 부모 → 다음 형제 블록)로 추론해야 한다.**

> 접근성 부작용: 이 28개 칸은 화면낭독기가 이름을 읽어 주지 못한다.
> 이 문서의 범위 밖이지만, **접근성이 끊긴 곳은 자동화도 같은 이유로 어렵다.**

---

## 6. 조건부 표시 그래프

### 6-1. 건물 종류

| 조작 | 결과 | 근거 |
|---|---|---|
| 「단독주택」 선택 | `jibun-open` 체크박스 + 안내문 생성 | `[a11]` |
| 「그 외(직접 입력)」 선택 | `jibun-open` 제거 (그리고 `residence.residenceTypeDescription` 이 쓸 수 있게 되는 것으로 보이나 **미검증** — s3·s4 모두 `disabled` 상태로만 잡혔다) | `[a18]` |
| `jibun-open` 조작 | `[role=dialog]` 「소재지 공개 확인」이 뜬다 — *"건물 종류가 다중, 다가구주택에 해당합니까?"* [아니요] [예] | `[a12,a13,a17]` |

### 6-2. 거래 유형 → 가격 칸

| 상태 | 나타나는 칸 | 근거 |
|---|---|---|
| `isShortTerm` 체크 | `sales.deposit`(보증금 *) + `sales.rent`(월세 *) 가 생김 | `[a21,a22]` 39.2초 |
| 「전세」 클릭 | `sales.rent` **제거** (보증금만 남음). 동시에 `isShortTerm` 미러가 `checked:true → false` 로 바뀜 = **단기 매물 자동 해제** | `[a23,a24]` 40.3~40.4초 원시 이벤트로 확인 |
| 「월세」 클릭 | `sales.rent` **재등장** | `[a25]` |

단기 매물이 켜져 있을 때 행 안에 `"* 단기 매물인 경…"` 안내문이 함께 붙었다가 사라지는 것도
원시 이벤트의 `composedPath` 텍스트에서 확인된다.

두 칸 모두 `max="99999999"`, 접미사 「만원」.

### 6-3. 전체 층 → 해당 층 (동적 옵션)

`select[name=floor]` 의 옵션이 `floorAll` 값에 따라 다시 만들어진다.

| 시점 | `floor` 옵션 | 근거 |
|---|---|---|
| 초기 | 2개 — `반지하`, `옥탑방` | s3 |
| `floorAll = 9` 선택 후 | 11개 | `[a53]` (`옵션 2→11`) |
| `floorAll = 13` 선택 후 | 15개 — `반지하`, `1층`…`13층`, `옥탑방` | `[a59]` (`옵션 11→15`), s4 |

**즉 `해당 층` 은 `전체 층` 을 먼저 정해야 원하는 값이 목록에 생긴다.** 순서가 강제된다.
`value` 는 층수 문자열(`"1"`…`"13"`)이고 지하·옥탑은 `"반지하"`, `"옥탑방"` 그 자체다.

### 6-4. 관리비 — 「관리비 없음」 × 부과 방식 3갈래

```
□ 관리비 없음 (no-manage-cost) = ON            [a107]
   ⇒ 관리비 부과 기준 · 월 평균 관리비 · 관리비 포함 항목 · 실비 부과 세부 내역이 전부 DOM에서 제거
   OFF 로 되돌리면 그대로 복구                    [a109]

□ 관리비 없음 = OFF 일 때, 부과 방식 3갈래:

  ├ [기타]  ← 페이지 로드 시 기본 선택 (s3에서 이 버튼만 border-orange-500)   [a121,a131]
  │    · 관리비 부과 기준 *  select[name=manageCostDetail.manageCostCriteria.manageCostCriteria]
  │    · (직접 입력 선택 시) input[name=…manageCostCriteriaEtcDescription] maxlength=20
  │    · 월 평균 관리비 *    input[name=manageCostDetail.basisDetail.avgManageCost]
  │    · 관리비 포함 항목 *  button[name=manageCostDetail.detailIncludes] ×8
  │    · 관리비 실비 부과 세부 내역 *  select[name=manageCostDetail.basisDetail.basis]
  │    · (직접 입력 선택 시) input[name=…basisEtcDescription] maxlength=20
  │
  ├ [정액 관리비]                                                       [a111,a135]
  │    · 라디오 button#true「고지 받았습니다.」 / button#false「고지 받지 않았습니다.」
  │    · 관리비 부과 기준 * (그대로 유지)
  │    · 항목별 8행 — 각 행 = combobox + select + 금액 input
  │        일반(공용) 관리비  manageCostDetail.detail.normalManageCost.{type,amount}
  │        전기료            manageCostDetail.detail.usageFee.electricity.{type,amount}
  │        수도료            …usageFee.water.{type,amount}
  │        가스 사용료        …usageFee.gas.{type,amount}
  │        난방비            …usageFee.heating.{type,amount}
  │        인터넷 사용료      …usageFee.internet.{type,amount}
  │        TV 사용료         …usageFee.tv.{type,amount}
  │        기타 관리비        select 는 **name 없음** + manageCostDetail.detail.etcManageCost.{description,amount}
  │    ⇒ 「기타」 갈래의 avgManageCost · detailIncludes · basisDetail.* 는 전부 제거됨      [a142]
  │
  └ [확인 불가]                                                        [a124,a125]
       · 확인 불가 사유 *  select[name=manageCostDetail.reason] (옵션 3)
       ⇒ 부과 기준 · 월 평균 관리비 · 포함 항목 · 실비 세부 내역이 전부 제거됨
```

**「정액 관리비」 갈래의 금액 칸은 같은 행 select 값에 따라 `disabled` 가 갈린다.**
s4 실측: `electricity`=`actual`(실비) → `amount` **disabled**, `water`=`fixed`(정액) → `amount` **활성**.
`gas`·`heating`·`tv` = `actual` → disabled, `internet` = `fixed` → 활성.
⇒ **`actual`(실비)·`none`·`unknown` 을 고르면 금액을 못 넣는다. `fixed`(정액)일 때만 넣을 수 있다.**

### 6-5. 그 밖

| 조작 | 결과 | 근거 |
|---|---|---|
| `haveNoDong`(단일동) 체크 | `input[name=dongDetail.dong]` 가 `disabled` 로 바뀜 | s3 vs s4 |
| 「기타 방법으로 확인」 선택 | `input[name=mediationRequest.mediationRequestTypeDescription]`(의뢰 방법 입력) 생성 | `[a165]` |
| `no-parking`(주차 불가능) 체크/해제 | 폼 칸에는 변화 없음. 광고 스크립트 요소만 붙었다 뗐다 함 | `[a77]~[a80]` |
| `moveInImmediately` 체크/해제 | 폼 칸 변화 없음 (`moveInDate` 는 그대로 남음) | `[a38]~[a41]` |

---

## 7. 선택지 카탈로그 (전수 — 숨은 `<select>` 에서 그대로 읽음)

| `select[name]` | 라벨 | 옵션 (`value` = 표시) |
|---|---|---|
| `floorAll` | 전체 층 | `1`=1층 … `80`=80층 (**80개**) |
| `floor` | 해당 층 | `반지하`=반지하, `1`=1층 … `N`=N층, `옥탑방`=옥탑방 (**전체 층에 따라 동적**) |
| `roomType` | 구조 | `01`=오픈형 원룸 (방1) · `02`=분리형 원룸 (방1,거실1) · `03`=복층형 원룸 |
| `roomDirection` | 주실 방향 | `E`=동 `W`=서 `S`=남 `N`=북 `NE`=북동 `SE`=남동 `NW`=북서 `SW`=남서 |
| `bathroomCnt` | 화장실 수 | `1`=1개 … `5`=5개 |
| `manageCostDetail.manageCostCriteria.manageCostCriteria` | 관리비 부과 기준 | `01`=직전월 관리비 기준 · `02`=최근 3개월 관리비 평균 · `03`=최근 1년 관리비 평균 · `04`=직접 입력 |
| `manageCostDetail.basisDetail.basis` | 관리비 실비 부과 세부 내역 | `01`=관리규약에 따라 부과 · `02`=공용관리비는 면적/세대별로 부과하고, 사용료는 사용량에 따른 부과 · `03`=전체 사용량을 세대수로 나누어 부과 · `04`=세대별 사용량(별도 계량기)에 따라 부과 · `05`=중개 의뢰인이 관리비 세부내역 미제시로 관리비 추정 금액 입력 · `06`=관리비 월 10만원 미만 · `07`=직접 입력 |
| `manageCostDetail.reason` | 확인 불가 사유 | `01`=건축법 시행령 별표1의 제1호 가목의 단독주택 · `02`=오피스텔 제외 상가 건물에 해당하는 경우 · `03`=미등기건물, 신축건물 등 관리비 내역이 확인불가한 경우 |
| `manageCostDetail.detail.normalManageCost.type` | 일반(공용) 관리비 | `fixed`=정액 · `actual`=실비 · `unknown`=의뢰인 미제공 (**3개 — 「해당없음」이 없다**) |
| `…usageFee.{electricity,water,gas,heating,internet,tv}.type` | 전기료/수도료/가스/난방/인터넷/TV | `none`=해당없음 · `fixed`=정액 · `actual`=실비 · `unknown`=의뢰인 미제공 (각 4개) |
| (name 없음) | 기타 관리비 | `none`=해당없음 · `parkingAndInsurance`=주차, 건물 보험료 등 · `custom`=직접 입력 · `unConfirmed`=의뢰인 미제공 |
| `itemBaseTagId` | 관심 태그 | `26`=선택안함, `1`=A … `25`=Y (**26개**) |

**버튼 그룹 선택지**

| 그룹 | 선택지 |
|---|---|
| 건물 종류 | 단독주택 / 그 외(직접 입력) |
| 거래 유형 | 전세 / 월세 (+ 별도 체크박스 「단기 매물」) |
| 주실 방향 기준 | 거실 기준 / 안방 기준 |
| 위반건축물 | 해당 / 해당없음 |
| 융자금 | 융자금 없음 / 융자금 30%이하 |
| 엘리베이터 유무 | 있음 / 없음 |
| 관리비 부과 방식 | 정액 관리비 / 기타 / 확인 불가 |
| 관리비 포함 항목(다중) | 일반(공용) 관리비 / 전기료 / 수도료 / 가스 사용료 / 난방비 / 인터넷 사용료 / TV 사용료 / 기타 관리비 |
| 옵션(다중, 12종) | 에어컨 / 냉장고 / 세탁기 / 가스레인지 / 인덕션 / 전자레인지 / 책상 / 책장 / 침대 / 옷장 / 신발장 / 싱크대 |
| 중개 의뢰 방법 | 전화로 확인 / 만나서 확인 / 기타 방법으로 확인 |
| 매물 조건(다중, 체크박스) | 반려동물 가능 / 전세자금대출 가능 / 전자계약 / CCTV / 테라스 / 전기차 충전 |
| 중복 전화번호 사유(라디오) | 의뢰인 다주택 보유 / 법인 소유 / 관리인·대리인 위임 / 기타 |

---

## 8. 값 자동 변환·형식

| 칸 | 관측 | 근거 |
|---|---|---|
| `sales.rent` | `6545` → **`6,545`** 로 자동 콤마 | `reformatted: {from:"6545", to:"6,545"}` |
| `sales.deposit` | 관측 값이 `56` 이라 콤마 여부 미확인 (`rent` 와 같은 컴포넌트이므로 같을 가능성이 높으나 **미검증**) | — |
| `approveDate` | 최종 값 `20260808`. **자동 서식 없음**(`reformatted` 없음). placeholder 는 「2025년 1월 1일」 형식을 안내하지만 숫자 8자리를 그대로 받았다 | observations |
| `moveInDate` | 캘린더가 채운다. 형식 `2033년 3월 3일`. readonly | s4 |
| `sizeM2` | `type=text` + `inputmode=decimal`. 변환 없음 | observations |
| `lat` | readonly. 팝업이 채운다. 입력 이벤트 0건 | §4 |
| `images` | readonly. 모달이 채운다 | §3-6 |

`rejected` 는 폼 전체에서 **0건** — 값을 거절한 칸은 확인되지 않았다.

**글자 수 제한**: `title` 32(최소 7) · `description` 2000 · `secretMemo` 200 ·
`moveInDateExtra` 10 · `approveDate` 20 · `…EtcDescription` 각 20 ·
`verification.lessorPhone` 11 · 기타 사유 32.

---

## 9. `name` 전수표 (최종 상태 기준 57개)

```
기본       lat  dongDetail.dong  ho  residence.residenceType(×2)
           residence.residenceTypeDescription  sales.salesType(×2)
           sales.deposit  sales.rent  sizeM2  approveDate
           moveInDate  moveInDateExtra
구조/시설   floorAll  floor  roomType  directionCriterionType  roomDirection
           bathroomCnt  parkingAndHousehold.totalParkingCnt
           parkingAndHousehold.householdCnt  nonCompliantBuilding
           noLoan  loanUnder30  isElevator
관리비(기타) manageCostDetail.manageCostCriteria.manageCostCriteria
           manageCostDetail.manageCostCriteria.manageCostCriteriaEtcDescription
           manageCostDetail.basisDetail.avgManageCost
           manageCostDetail.basisDetail.basis
           manageCostDetail.basisDetail.basisEtcDescription
           manageCostDetail.detailIncludes(×8)
관리비(정액) manageCostDetail.detail.normalManageCost.type / .amount
           manageCostDetail.detail.usageFee.electricity.type / .amount
           manageCostDetail.detail.usageFee.water.type / .amount
           manageCostDetail.detail.usageFee.gas.type / .amount
           manageCostDetail.detail.usageFee.heating.type / .amount
           manageCostDetail.detail.usageFee.internet.type / .amount
           manageCostDetail.detail.usageFee.tv.type / .amount
           manageCostDetail.detail.etcManageCost.description / .amount   (type select 는 name 없음)
관리비(확불) manageCostDetail.reason
설명       images  title  description
추가       secretMemo  itemBaseTagId  mediationRequest.mediationRequestType(×3)
           mediationRequest.mediationRequestTypeDescription
의뢰인      verification.lessorName  verification.lessorPhone
           verification.duplicatedLessor.reasonType(<p> 에 붙어 있음)
           verification.duplicatedLessor.reason
```

id 로만 잡히는 것: `haveNoDong  isShortTerm  moveInImmediately  no-parking  no-manage-cost
jibun-open  itemConditions.{pet,loanLease,digitalContract,cctv,terrace,evStation}
agreesTerms  MULTIPLE_OWNER  CORPORATE_OWNER  AGENT_DELEGATION  ETC  true  false`

이름도 id 도 없는 것: 「옵션」 12개 버튼, 관리비 부과 방식 3개 버튼,
그리고 각 토글 그룹의 **두 번째 버튼**(해당없음 / 없음 / 안방 기준).

---

## 10. 자동화 구현 체크리스트

1. **셀렉터 우선순위**: 고정 `id`(§5-1) → `name` → `[data-sentry-component]` 블록 + 텍스트 → 라벨 텍스트.
   `:rXX:-form-item` 은 쓰지 말 것(콜론 이스케이프 문제 + useId 순서 의존).
2. **토글 버튼은 상태 속성이 없다.** `border-orange-500` 유무로 켜짐/꺼짐을 읽고 나서 눌러야 한다.
   특히 「옵션」12종·「관리비 포함 항목」8종은 다중선택이라 재클릭하면 꺼진다.
3. **Radix 체크박스/라디오는 `button[role=…]` 을 누른다.** `aria-checked`/`data-state` 로 상태 확인.
   숨은 `input[aria-hidden=true]` 는 건드리지 말 것(미러일 뿐).
4. **Radix Select 는 숨은 `<select>` 에 값을 써도 안 된다.** 트리거(`button[role=combobox]`) 클릭 →
   포털의 `[role=listbox] [role=option]` 을 **텍스트로** 찾아 클릭.
   `value→text` 대응은 숨은 `<select>` 에서 미리 읽어 둔다.
5. **순서가 강제된다.**
   ① 주소(팝업) → ② 건물 종류 → ③ 거래 유형(전세/월세) → ④ 보증금·월세 →
   ⑤ 전체 층 → ⑥ **해당 층**(전체 층에 의존) → ⑦ 나머지 → ⑧ 관리비(부과 방식 먼저) → ⑨ 사진.
   「전세」를 고르면 「단기 매물」이 자동 해제되므로 단기 설정은 월세 선택 뒤에 한다.
6. **관리비는 부과 방식을 먼저 정한다.** 갈래를 바꾸면 반대 갈래의 칸이 통째로 사라져 입력값이 날아간다.
   「정액 관리비」 갈래에서는 각 행 select 를 `fixed`(정액)로 해야 금액 칸의 `disabled` 가 풀린다.
7. **날짜는 캘린더로만 넣을 수 있다.** `moveInDate` 는 readonly.
   연·월 Select 를 맞추고 → `button[name="day"]` 중 목표 일자를 고르고 → **하단 확정 버튼**을 누른다.
   `approveDate` 는 일반 텍스트 칸이라 그냥 타이핑하면 된다.
8. **주소는 DOM 조작으로 못 넣을 가능성이 높다.** 별도 창 + 교차출처 iframe이고,
   `lat` 은 readonly이며 값이 이벤트 없이 들어왔다(§4). 확장 설계 단계에서 별도로 다뤄야 한다.
9. **사진은 모달 안 숨은 `input[type=file]`.** 최소 5장 제약이 있다.
10. **`[매물 등록 완료]`(`button[type=submit]`)와 상단 `[취소]` 는 누르지 말 것.**
11. `label` 텍스트에 붙는 `*` 를 떼고 비교할 것 (`"주소*"` 로 붙어 나온다).
12. 광고/추적 스크립트가 만드는 잡 요소(`id`·`ev`·`dl`·`cd[...]`·`expv2[38]` 같은 이름의 input)가
    수시로 붙었다 떨어진다. **`form` 안쪽으로 범위를 한정할 것.**
13. **`label[for]` → `id` 경로를 쓰지 말 것.** 38개 중 10개만 실제로 이어져 있다(§5-6).
    라벨↔칸은 위치로 추론한다.
14. **미러를 읽어 검증할 때는 즉시 읽지 말 것.** 항목 클릭 → 숨은 `<select>` 의 `change` 까지
    **82~168ms(중앙값 143ms, n=12)** 가 걸렸다. 고정 대기보다 **조건 폴링**을 쓸 것.
    (버튼의 표시 글자 갱신은 그보다 더 늦다 — 방향 사례에서 항목 클릭 +412ms.)

---

## 11. 다시 캡처해야 알 수 있는 것

| 항목 | 왜 지금 모르나 |
|---|---|
| **`:rXX:-form-item` id 의 재로드 안정성** | SingleFile 3개가 전부 같은 페이지 로드였다. **새로고침 후 한 번 더 저장하면 즉시 판정된다** |
| 「빌라」 탭 폼 | 원룸 탭만 캡처 |
| 주소 팝업을 여는 클릭 | 팝업이 첫 조작 기록 이전에 이미 열려 있었다 |
| `lat` 에 값을 써넣어도 폼 상태가 갱신되는지 | 팝업 콜백 경로만 관측 |
| 「그 외(직접 입력)」 선택 시 `residence.residenceTypeDescription` 이 풀리는지 | s3·s4 모두 `disabled` 로만 잡혔다 |
| `sales.deposit` 의 콤마 서식 | 두 자리 값만 넣어 봤다 |
| 유효성 검사 메시지·필수값 처리 | 제출하지 않았으므로 전무 |
| 74초 이후의 세밀한 DOM 변이 | `mutations` 상한 초과로 이후가 전부 버려짐 |
