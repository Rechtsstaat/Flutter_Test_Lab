#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""직방 매물 등록폼 재현본 만들기.

원본 SingleFile 스냅샷은 읽기만 하고 건드리지 않는다.
빈 폼 스냅샷을 바탕으로, 「입력후」 스냅샷에서 조건부 블록의 실제 마크업을 떼어다
템플릿으로 심고, live.js 를 주입한 새 HTML 을 이 폴더에 만든다.

    python3 재현/직방/build.py
"""
import json, os, re, sys
from bs4 import BeautifulSoup

# 실제 주소·단지명을 여기에 적으면 이 스크립트 자체가 개인정보를 담게 된다.
# 특정 값 대신 "도로명+번길/번지" 꼴과 "○○아파트/맨션/빌라" 꼴을 일반 패턴으로 잡는다.
RE_ADDR = r"[가-힣]{2,6}(?:로|길)\s?\d+(?:번길)?\s?\d|[가-힣]{2,8}(?:아파트|맨션|빌라|푸르지오|자이|힐스테이트)"

HERE = os.path.dirname(os.path.abspath(__file__))
SNAP = os.path.normpath(os.path.join(HERE, "..", "..",
       "captures", "2026-09-08-현장수집", "직방", "singlefile"))
BASE = os.path.join(SNAP, "직방_매물등록폼.html")          # 빈 폼 · 개인정보 없음
DONOR = os.path.join(SNAP, "직방_매물등록폼_입력후.html")   # 조건부 블록 공여
OUT  = os.path.join(HERE, "직방_매물등록폼_재현.html")

for p in (BASE, DONOR):
    if not os.path.exists(p):
        sys.exit("원본 스냅샷이 없다: %s\n  captures/ 는 git 추적 대상이 아니다. 원본을 먼저 놓을 것." % p)


def scrub(node):
    """공여 블록에서 입력값·개인정보·상태를 지운다."""
    for el in node.find_all(["input", "textarea"]):
        if el.get("type") in ("checkbox", "radio"):
            el.attrs.pop("checked", None)
        else:
            el["value"] = ""
        if el.name == "textarea":
            el.string = ""
        for a in list(el.attrs):
            if a.startswith("data-gtm"):
                del el[a]
    for b in node.select("button[role=checkbox], button[role=radio]"):
        b["data-state"] = "unchecked"
        b["aria-checked"] = "false"
        b.clear()
    # 「56만원」 같은 입력값 요약 라벨 제거
    for p in node.select('[data-sentry-component="FieldAmountLabel"]'):
        p.decompose()
    return node


def block_by_label(form, prefix):
    for l in form.find_all("label"):
        if (l.get("for") or "").endswith("-form-item") and l.get_text(strip=True).startswith(prefix):
            return l.parent.parent
    return None


def main():
    base = BeautifulSoup(open(BASE, encoding="utf-8").read(), "lxml")
    donor = BeautifulSoup(open(DONOR, encoding="utf-8").read(), "lxml")
    dform = donor.find("form")

    T = {}

    # 체크 아이콘 (Radix 가 checked 일 때 넣는 span)
    ck = dform.select_one('button[role=checkbox][data-state=checked]')
    T["checkIcon"] = "".join(str(c) for c in ck.contents) if ck else ""

    # 6-2 보증금 / 월세 블록
    for key, prefix in (("deposit", "보증금"), ("rent", "월세")):
        blk = block_by_label(dform, prefix)
        T[key] = str(scrub(blk)) if blk else ""

    # 6-1 지번공개 체크박스 블록
    jb = dform.select_one("#jibun-open")
    if jb:
        wrap = jb.find_parent("label")          # 체크박스와 안내 문구를 함께 감싸는 라벨
        T["jibun"] = str(scrub(wrap)) if wrap else ""

    # 6-5 의뢰 방법 직접입력 칸
    md = dform.select_one('input[name="mediationRequest.mediationRequestTypeDescription"]')
    T["mediationDesc"] = str(scrub(md)) if md else ""

    missing = [k for k, v in T.items() if not v]
    if missing:
        print("  ! 공여 스냅샷에서 못 찾은 템플릿: %s" % missing)

    # 개인정보 방어 — 공여 블록에 실제 주소·연락처가 섞여 나오지 않았는지 확인
    joined = "\n".join(T.values())
    for pat, name in ((r"01[016789][-\s]?\d{3,4}[-\s]?\d{4}", "휴대폰"),
                      (RE_ADDR, "실주소·단지명"),
                      (r"[가-힣]{2,10}공인중개사", "중개사무소명")):
        if re.search(pat, joined):
            sys.exit("템플릿에 %s 가 섞였다. scrub() 를 고칠 것." % name)

    live = open(os.path.join(HERE, "live.js"), encoding="utf-8").read()
    head = base.find("head") or base.find("html")
    tag = base.new_tag("script")
    tag.string = ("window.__FLR_TEMPLATES__ = %s;\n" % json.dumps(T, ensure_ascii=False)) + live
    (base.find("body") or head).append(tag)

    html = str(base)
    open(OUT, "w", encoding="utf-8").write(html)
    print("만들었다: %s  (%.1fMB)" % (OUT, len(html.encode()) / 1048576))
    print("템플릿: %s" % ", ".join("%s %d자" % (k, len(v)) for k, v in T.items()))


if __name__ == "__main__":
    main()
