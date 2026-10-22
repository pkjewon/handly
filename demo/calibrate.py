"""M2-8 기준값 조정 도구 + M2-5a 오답 동작 확인.

    python calibrate.py                 # 단어별 거리 분포와 추천 기준값 보기 (그래프: data/calibration.png)
    python calibrate.py --save          # 추천 기준값을 data/thresholds.json 에 저장
    python calibrate.py --set 감사하다=0.42 --set 죄송하다=0.5   # 직접 정해서 저장

정답 테이크(비교·다른사람)는 자기 자신을 뺀 나머지 기준 테이크와의 거리,
오답 테이크(오답 + 다른 단어의 테이크)는 그 단어 기준 테이크와의 거리를 계산해서
두 분포 사이로 기준값을 정한다.
"""
from __future__ import annotations

import argparse
import json

import numpy as np

import config
import dtw


def main():
    ap = argparse.ArgumentParser(description="Handly 기준값 조정 (M2-8)")
    ap.add_argument("--save", action="store_true", help="추천 기준값 저장")
    ap.add_argument("--set", action="append", default=[], metavar="단어=값", help="기준값 직접 지정")
    ap.add_argument("--show", action="store_true", help="그래프 창 띄우기")
    args = ap.parse_args()

    print("테이크 불러오는 중...")
    lib = dtw.Library()
    for name, why in lib.skipped:
        print(f"  [제외] {name}: {why}")
    if not lib.words:
        print("기준 테이크가 없습니다. recorder.py 로 먼저 녹화하세요.")
        return
    for w in lib.words:
        kinds = {}
        for rt in lib.refs[w]:
            kinds[rt.kind] = kinds.get(rt.kind, 0) + 1
        slots = "+".join(["화면 왼쪽 손", "화면 오른쪽 손"][k] for k in lib.slots[w])
        print(f"  {w}: {kinds}  쓰는 손: {slots}")
    print(f"  오답 테이크: {len(lib.wrongs)}개\n")

    print("거리 계산 중 (테이크가 많으면 시간이 걸려요)...")
    table = dtw.distance_table(lib)
    current = dtw.load_thresholds()
    new = dict(current)

    for w, d in table.items():
        pos = [x for x, _ in d["pos"]]
        neg = [x for x, _ in d["neg"]]
        thr, all_far = dtw.suggest_threshold(pos, neg)
        print(f"■ {w}")
        if pos:
            print(f"   정답 거리: 최소 {min(pos):.3f}  중앙 {np.median(pos):.3f}  최대 {max(pos):.3f}  ({len(pos)}개)")
        else:
            print("   정답 거리: 없음 (비교·다른사람 테이크가 2개 이상 필요)")
        if not d["neg_all"]:
            print("   오답 거리: 없음 (오답 테이크를 녹화하세요, M2-5a)")
        elif neg:
            near = sorted(d["neg"])[:3]
            print(f"   이 단어가 가장 가깝게 나온 오답 {len(neg)}개: " + ", ".join(f"{n}({x:.3f})" for x, n in near))
        else:
            print(f"   오답 {len(d['neg_all'])}개 모두 다른 단어가 더 가까움 → '가장 가까운 단어' 조건에서 걸러짐")
        miss = {n for _, n in d["pos_miss"]}
        miss_names = {n.split("→")[0] for n in miss}
        acc = np.mean([x <= thr and n not in miss_names for x, n in d["pos"]]) if pos else float("nan")
        print(f"   추천 기준값 {thr:.3f}  → 정답 테이크 통과 {acc:.0%}, "
              f"오답이 모두 기준값보다 먼가: {'예' if all_far else '아니오 ⚠'}"
              f"   (현재 {lib.threshold(w):.3f})")
        if miss:
            print(f"   ⚠ 다른 단어가 더 가깝게 나온 정답 테이크: {', '.join(sorted(miss))}")
        if pos and neg and max(pos) >= min(neg):
            print("   ⚠ 정답·오답 거리가 겹칩니다. 촬영을 더 하거나 오답 동작을 확인하세요.")
        new[w] = thr
        print()

    for s in args.set:
        k, v = s.split("=")
        new[k.strip()] = float(v)

    _plot(table, new, args.show)

    if args.save or args.set:
        final = new if args.save else {**current, **{s.split("=")[0].strip(): float(s.split("=")[1]) for s in args.set}}
        config.THRESHOLDS_FILE.parent.mkdir(parents=True, exist_ok=True)
        config.THRESHOLDS_FILE.write_text(json.dumps(final, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"저장: {config.THRESHOLDS_FILE}")
        for k, v in final.items():
            print(f"   {k}: {v:.3f}")


def _plot(table, thresholds, show):
    import matplotlib
    if not show:
        matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib import font_manager

    font_manager.fontManager.addfont(config.FONT_PATH)
    plt.rcParams["font.family"] = font_manager.FontProperties(fname=config.FONT_PATH).get_name()
    plt.rcParams["axes.unicode_minus"] = False

    n = len(table)
    fig, axes = plt.subplots(n, 1, figsize=(8, 2.6 * n), squeeze=False)
    for ax, (w, d) in zip(axes[:, 0], table.items()):
        pos = [x for x, _ in d["pos"]]
        neg = [x for x, _ in d["neg_all"]]
        bins = np.linspace(0, max(pos + neg + [thresholds.get(w, 0) * 1.5, 0.1]), 30)
        ax.hist(pos, bins=bins, alpha=0.7, label="정답 테이크", color="#3a9a3a")
        ax.hist(neg, bins=bins, alpha=0.6, label="오답 테이크", color="#d04040")
        if w in thresholds:
            ax.axvline(thresholds[w], color="k", ls="--", label=f"기준값 {thresholds[w]:.3f}")
        ax.set_title(w)
        ax.set_xlabel("DTW 거리")
        ax.legend()
    fig.tight_layout()
    out = config.THRESHOLDS_FILE.parent / "calibration.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=110)
    print(f"그래프: {out}")
    if show:
        plt.show()


if __name__ == "__main__":
    main()
