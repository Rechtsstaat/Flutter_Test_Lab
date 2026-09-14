/* 직방 매물 등록폼 — 정적 스냅샷 되살리기
 *
 * SingleFile 스냅샷에는 <script> 가 하나도 없다. DOM 과 CSS 만 남아 있어
 * 눌러도 아무 반응이 없다. 이 파일은 그 위에 "관측된 동작"만 다시 얹는다.
 *
 * 모든 규칙의 근거는 captures/2026-09-08-현장수집/직방/DOM-전수조사.md 다.
 * 추측으로 넣은 동작은 없다. 근거가 없는 것은 §미재현 에 적고 넣지 않았다.
 */
(function () {
  "use strict";
  var T = window.__FLR_TEMPLATES__ || {};
  var form = document.querySelector("form");
  if (!form) return;

  /* ── 유틸 ───────────────────────────────────────────── */
  var ORANGE = ["border-orange-500", "text-orange-500"];
  var DIMMED = ["border-input", "text-secondary-foreground"];
  var OFF_CLASS = new WeakMap();   // 버튼마다 "꺼진 상태"의 클래스를 미리 계산해 둔다
  function isOn(b) { return b.classList.contains("border-orange-500"); }

  // 토글 버튼은 변형이 셋이다 (border-input · bg-white · bg-background).
  // 처음부터 켜져 있는 버튼(예: 관리비 부과 방식의 「기타」)은 켜진 클래스를 갖고 시작하므로,
  // 그것을 그대로 "원본"으로 기억하면 다시는 꺼지지 않는다. 그래서 그룹을 보고 꺼진 모습을 만든다.
  function initGroupClasses(members) {
    var hasDimmed = members.some(function (m) {
      return DIMMED.every(function (c) { return m.classList.contains(c); });
    });
    members.forEach(function (m) {
      var off = m.className;
      if (isOn(m)) {
        var cl = off.split(/\s+/).filter(function (c) { return ORANGE.indexOf(c) < 0; });
        if (hasDimmed) DIMMED.forEach(function (c) { if (cl.indexOf(c) < 0) cl.push(c); });
        off = cl.join(" ");
      }
      OFF_CLASS.set(m, off);
    });
  }
  function setOn(b, on) {
    var off = OFF_CLASS.get(b) || b.className;
    if (!on) { b.className = off; return; }
    var cl = off.split(/\s+/).filter(function (c) { return DIMMED.indexOf(c) < 0; });
    ORANGE.forEach(function (c) { if (cl.indexOf(c) < 0) cl.push(c); });
    b.className = cl.join(" ");
  }

  // 관리비 섹션에는 SubSection 이 없다. 조상으로 찾으면 엉뚱한 라벨을 잡는다.
  // 문서 순서상 el 바로 앞에 오는 행 라벨을 쓴다.
  var ROW_LABELS = null;
  function rowLabel(el) {
    if (!ROW_LABELS) ROW_LABELS = Array.prototype.slice.call(form.querySelectorAll('label[for$="-form-item"]'));
    var best = "";
    for (var i = 0; i < ROW_LABELS.length; i++) {
      if (ROW_LABELS[i].compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING) {
        best = ROW_LABELS[i].textContent.replace(/\*$/, "").trim();
      } else break;
    }
    return best;
  }
  function fire(name, detail) { document.dispatchEvent(new CustomEvent(name, { detail: detail })); }

  /* ── 1. 드롭다운 (button[role=combobox] + 숨은 select) ── */
  var openPanel = null;
  function closePanel() {
    if (openPanel) { openPanel.remove(); openPanel = null; }
    form.querySelectorAll('button[role=combobox][data-state="open"]')
      .forEach(function (t) { t.setAttribute("data-state", "closed"); t.setAttribute("aria-expanded", "false"); });
  }
  document.addEventListener("click", function (e) {
    if (openPanel && !openPanel.contains(e.target)) closePanel();
  }, true);
  window.addEventListener("scroll", closePanel, true);

  function selectOf(trigger) {
    var n = trigger.nextElementSibling;
    return n && n.tagName === "SELECT" ? n : trigger.parentElement.querySelector("select");
  }
  function setValue(trigger, sel, value, text) {
    var span = trigger.querySelector("span");
    if (span) span.textContent = text;
    trigger.removeAttribute("data-placeholder");
    if (sel) {
      sel.value = value;
      Array.prototype.forEach.call(sel.options, function (o) {
        if (o.value === value) o.setAttribute("selected", ""); else o.removeAttribute("selected");
      });
    }
    fire("flr:select", { name: sel && sel.name, value: value, text: text, trigger: trigger });
  }
  function openSelect(trigger) {
    var sel = selectOf(trigger);
    if (!sel) return;
    closePanel();
    trigger.setAttribute("data-state", "open");
    trigger.setAttribute("aria-expanded", "true");
    var r = trigger.getBoundingClientRect();
    var p = document.createElement("div");
    p.setAttribute("data-flr", "panel");
    p.setAttribute("role", "listbox");
    p.style.cssText = "position:absolute;z-index:99999;background:#fff;border:1px solid #e4e4e7;" +
      "border-radius:6px;box-shadow:0 10px 26px rgba(0,0,0,.15);padding:4px;overflow:auto;" +
      "font-size:14px;line-height:1.4;color:#18181b;" +
      "left:" + (r.left + scrollX) + "px;top:" + (r.bottom + scrollY + 4) + "px;" +
      "min-width:" + r.width + "px;max-height:" + Math.min(300, innerHeight - r.bottom - 24) + "px;";
    Array.prototype.forEach.call(sel.options, function (o) {
      var it = document.createElement("div");
      it.setAttribute("role", "option");
      it.textContent = o.textContent;
      it.style.cssText = "padding:7px 30px 7px 10px;border-radius:4px;cursor:pointer;white-space:nowrap;";
      if (o.value === sel.value) it.style.background = "#f4f4f5";
      it.onmouseenter = function () { it.style.background = "#f4f4f5"; };
      it.onmouseleave = function () { it.style.background = o.value === sel.value ? "#f4f4f5" : ""; };
      it.onclick = function (ev) {
        ev.stopPropagation();
        setValue(trigger, sel, o.value, o.textContent);
        closePanel();
      };
      p.appendChild(it);
    });
    document.body.appendChild(p);
    openPanel = p;
  }
  form.querySelectorAll('button[role=combobox]').forEach(function (t) {
    t.addEventListener("click", function (e) {
      e.preventDefault(); e.stopPropagation();
      if (t.getAttribute("data-state") === "open") closePanel(); else openSelect(t);
    });
  });

  /* ── 2. 토글 버튼 ───────────────────────────────────── */
  var MULTI = ["옵션", "관리비 포함 항목"];       // §7 다중선택 그룹
  var TOGGLE_SIG = /border-orange-500|text-secondary-foreground|bg-white/;
  var groups = new Map();
  form.querySelectorAll("button[type=button]").forEach(function (b) {
    if (b.getAttribute("role") || b.hasAttribute("aria-controls")) return;  // 콤보박스 제외
    if (!TOGGLE_SIG.test(b.className || "")) return;
    var key = rowLabel(b);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(b);
  });
  groups.forEach(function (members, key) {
    initGroupClasses(members);
    var texts = members.map(function (m) { return m.textContent.trim(); });
    // 「중개 의뢰를 받은 방법」 행에는 form-item 라벨이 없어 앞 행 이름이 잡힌다. 내용으로 식별한다.
    var isMediation = texts.indexOf("전화로 확인") >= 0;
    var multi = MULTI.indexOf(key) >= 0;
    members.forEach(function (b) {
      b.addEventListener("click", function (e) {
        e.preventDefault();
        if (multi) {
          setOn(b, !isOn(b));                       // 다중선택: 다시 누르면 꺼진다 (§10-2)
        } else {
          members.forEach(function (m) { setOn(m, false); });
          setOn(b, true);                           // 택1: 누른 것이 선택된다. 해제는 관측되지 않았다
        }
        fire("flr:toggle", { label: key, text: b.textContent.trim(), on: isOn(b),
                             group: members, mediation: isMediation });
      });
    });
  });

  /* ── 3. Radix 체크박스 / 라디오 ─────────────────────── */
  function paint(btn, on) {
    btn.setAttribute("data-state", on ? "checked" : "unchecked");
    btn.setAttribute("aria-checked", on ? "true" : "false");
    btn.innerHTML = on ? (T.checkIcon || "") : "";
    var mirror = btn.parentElement.querySelector('input[aria-hidden="true"]');
    if (mirror) mirror.checked = on;
  }
  form.querySelectorAll('button[role=checkbox]').forEach(function (b) {
    b.addEventListener("click", function (e) {
      e.preventDefault();
      paint(b, b.getAttribute("data-state") !== "checked");
      fire("flr:check", { id: b.id, on: b.getAttribute("data-state") === "checked" });
    });
  });
  form.querySelectorAll('button[role=radio]').forEach(function (b) {
    b.addEventListener("click", function (e) {
      e.preventDefault();
      var g = b.closest('[role=radiogroup]') || form;
      g.querySelectorAll('button[role=radio]').forEach(function (o) { paint(o, o === b); });
      fire("flr:radio", { id: b.id, value: b.value });
    });
  });
  // 라벨을 눌러도 켜지게 (원본과 같은 동작)
  form.querySelectorAll("label[for]").forEach(function (l) {
    var t = document.getElementById(l.getAttribute("for"));
    if (t && t.tagName === "BUTTON") l.addEventListener("click", function (e) { e.preventDefault(); t.click(); });
  });

  /* ── 4. 조건부 표시 (전부 DOM-전수조사.md §6 근거) ──── */

  // 6-3 전체 층 → 해당 층 옵션 재생성 (반지하 · 1~N층 · 옥탑방)
  document.addEventListener("flr:select", function (e) {
    if (e.detail.name !== "floorAll") return;
    var n = parseInt(e.detail.value, 10);
    var sel = form.querySelector('select[name="floor"]');
    if (!sel || !n) return;
    var opts = ['<option value="반지하">반지하</option>'];
    for (var i = 1; i <= n; i++) opts.push('<option value="' + i + '">' + i + '층</option>');
    opts.push('<option value="옥탑방">옥탑방</option>');
    sel.innerHTML = opts.join("");
    var trg = sel.previousElementSibling;
    if (trg && trg.getAttribute("role") === "combobox") {
      trg.querySelector("span").textContent = "해당 층 선택";
      trg.setAttribute("data-placeholder", "");
    }
  });

  // 6-2 거래 유형 → 보증금 / 월세 칸
  function priceRow() {
    var sub = Array.prototype.find.call(
      form.querySelectorAll('[data-sentry-component="SubSection"]'),
      function (s) { var l = s.querySelector('label[for$="-form-item"]'); return l && l.textContent.indexOf("거래 유형") === 0; });
    if (!sub) return null;
    var row = sub.querySelector('[data-flr="price-row"]');
    if (!row) {
      row = document.createElement("div");
      row.setAttribute("data-flr", "price-row");
      row.className = "flex w-full flex-col gap-4 md:flex-row";
      row.style.marginTop = "16px";
      sub.appendChild(row);
    }
    return row;
  }
  document.addEventListener("flr:toggle", function (e) {
    if (e.detail.label.indexOf("거래 유형") !== 0) return;
    var row = priceRow(); if (!row) return;
    var t = e.detail.text;
    row.innerHTML = "";
    if (t === "전세") row.innerHTML = T.deposit || "";
    else if (t === "월세") row.innerHTML = (T.deposit || "") + (T.rent || "");
  });

  // 6-1 건물 종류 = 단독주택 → 지번공개 체크박스
  document.addEventListener("flr:toggle", function (e) {
    if (e.detail.label.indexOf("건물 종류") !== 0) return;
    var sub = e.detail.group[0].closest('[data-sentry-component="SubSection"]');
    var old = sub.querySelector('[data-flr="jibun"]');
    if (old) old.remove();
    if (e.detail.text === "단독주택" && T.jibun) {
      var d = document.createElement("div");
      d.setAttribute("data-flr", "jibun");
      d.style.marginTop = "12px";
      d.innerHTML = T.jibun;
      sub.appendChild(d);
      d.querySelectorAll('button[role=checkbox]').forEach(function (b) {
        paint(b, false);
        b.addEventListener("click", function (ev) { ev.preventDefault(); paint(b, b.getAttribute("data-state") !== "checked"); });
      });
    }
    // 그 외(직접 입력) → 직접입력 칸 활성 (빈 폼에서는 disabled 로 굳어 있다)
    var desc = form.querySelector('input[name="residence.residenceTypeDescription"]');
    if (desc) desc.disabled = e.detail.text !== "그 외(직접 입력)";
  });

  // 6-5 단일동 체크 → 동 입력 비활성
  document.addEventListener("flr:check", function (e) {
    if (e.detail.id !== "haveNoDong") return;
    var d = form.querySelector('input[name="dongDetail.dong"]');
    if (d) { d.disabled = e.detail.on; d.style.opacity = e.detail.on ? .5 : 1; }
  });

  // 6-4 관리비 없음 체크 → 관리비 상세 전부 사라짐 (부과 방식 버튼까지, [a107/a110])
  document.addEventListener("flr:check", function (e) {
    if (e.detail.id !== "no-manage-cost") return;
    var sec = document.getElementById("no-manage-cost").closest("section");
    var rows = sec && sec.querySelector(".mt-8");     // 관리비 행들을 담은 컨테이너
    if (rows) rows.style.display = e.detail.on ? "none" : "";
  });

  // 6-5 「기타 방법으로 확인」 → 의뢰 방법 직접입력 칸 ([a165])
  document.addEventListener("flr:toggle", function (e) {
    if (!e.detail.mediation) return;
    var host = e.detail.group[0].parentElement.parentElement;
    var old = host.querySelector('[data-flr="mediation-desc"]');
    if (old) old.remove();
    if (e.detail.text.indexOf("기타 방법") === 0 && T.mediationDesc) {
      // 원본에서 이 input 은 감싸개 없이 행 컨테이너의 직계 자식이고, 스타일은 input 자신이 갖고 있다.
      // 그래서 여기서는 클래스를 붙이지 않는다. data-flr 만 달아 재현본이 만든 것임을 표시한다.
      var d = document.createElement("div");
      d.setAttribute("data-flr", "mediation-desc");
      d.style.marginTop = "12px";
      d.innerHTML = T.mediationDesc;
      host.appendChild(d);
    }
  });

  /* ── 5. 제출 봉인 ───────────────────────────────────── */
  form.addEventListener("submit", function (e) { e.preventDefault(); });
  form.querySelectorAll('button[type=submit]').forEach(function (b) {
    b.addEventListener("click", function (e) {
      e.preventDefault(); e.stopPropagation();
      alert("재현본입니다. 실제로 등록되지 않습니다.");
    });
  });

  /* ── 6. 재현본 표식 ─────────────────────────────────── */
  var tag = document.createElement("div");
  tag.style.cssText = "position:fixed;left:12px;bottom:12px;z-index:100000;background:#111827;color:#fff;" +
    "font:12px/1.5 -apple-system,BlinkMacSystemFont,'Apple SD Gothic Neo',sans-serif;padding:8px 12px;" +
    "border-radius:8px;box-shadow:0 6px 18px rgba(0,0,0,.3);max-width:330px;";
  tag.innerHTML = "<b>재현본</b> — 직방 매물 등록폼 (2026-09-08 스냅샷)<br>" +
    "<span style='opacity:.75'>실제 사이트가 아닙니다. 드롭다운·토글·체크박스와 " +
    "일부 조건부 칸만 되살렸습니다. 재현하지 않은 것은 README 참조.</span>";
  document.body.appendChild(tag);
})();
