"""앱(Flutter)용 데이터 내보내기.

1) app/handly_app/assets/handly_refs.json
   단어 카드(M1-1), 기준값(M2-8), 쓰는 손, 입체 손 안내 좌표(M1-2), DTW 기준 좌표(M2-5)
2) app/handly_core/test/golden/*.json
   Dart로 옮긴 좌표 처리(10-3)·DTW·판정이 Python과 같은 결과를 내는지 확인하는 정답 데이터

    python export_app_assets.py
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

import config
import dtw
import processing
from landmarks import load_take

APP = config.ROOT.parent / "app"
ASSETS = APP / "handly_app" / "assets" / "handly_refs.json"
GOLDEN = APP / "handly_core" / "test" / "golden"
DECIMALS = 3

GOLDEN_TAKES = ["감사하다_비교_05", "죄송하다_비교_08", "안녕하세요_비교_04", "이상하게_오답_02", "가만히_오답_01"]


def r(a, d=DECIMALS):
    return np.round(np.asarray(a, np.float64), d)


def round_seq(seq: processing.Seq) -> processing.Seq:
    """앱에 넣는 값과 똑같이 반올림 (정답 데이터도 반올림된 기준 좌표로 계산해야 Dart와 맞음)."""
    X = r(seq.X).astype(np.float64)
    return processing.Seq(np.asarray(seq.t, np.float64), X, seq.P.copy(), r(seq.head), seq.error)


def seq_json(seq: processing.Seq, with_z: bool) -> dict:
    X = seq.X if with_z else seq.X[..., :2]
    return {
        "n": len(seq),
        "P": seq.P.astype(int).tolist(),
        "X": r(X).tolist(),
        "head": r(seq.head).tolist(),
    }


def crop_like_learner(take: dict) -> dict:
    """촬영 영상을 학습자 녹화처럼 RECORD_SEC 길이로 자름 (처음 손이 나오기 0.3초 전부터)."""
    t = take["t"]
    seen = np.flatnonzero(take["hand_ok"].any(axis=1))
    start = t[seen[0]] - 0.3 if len(seen) else 0.0
    keep = (t >= start) & (t <= start + config.RECORD_SEC)
    out = dict(take)
    for k in ("hands", "hand_ok", "pose", "pose_ok"):
        out[k] = take[k][keep]
    out["t"] = t[keep] - t[keep][0]
    return out


def config_json() -> dict:
    keys = ["TARGET_FPS", "SHORT_GAP_SEC", "HAND_USED_RATIO", "NO_HAND_FAIL_RATIO", "MISSING_HAND_RATIO",
            "ABSENT_PENALTY", "TOP_K", "DEFAULT_THRESHOLD", "HINT_POS_DIFF", "HINT_FAST_RATIO", "HINT_SLOW_RATIO",
            "COUNTDOWN_SEC", "RECORD_SEC", "MIRROR"]
    return {k: getattr(config, k) for k in keys}


def main():
    cards = json.loads(config.WORDS_FILE.read_text(encoding="utf-8"))
    names = [c["name"] for c in cards["words"]]
    lib = dtw.Library(names)
    for w in lib.refs:
        for rt in lib.refs[w]:
            rt.seq = round_seq(rt.seq)

    words = []
    for c in cards["words"]:
        w = c["name"]
        refs = lib.refs.get(w, [])
        guide = lib.guide_take(w)
        words.append({
            **c,
            "threshold": lib.threshold(w),
            "slots": lib.slots.get(w, []),
            "guide": seq_json(guide.seq, with_z=True) if guide else None,
            "refs": [{"name": rt.path.stem, "kind": rt.kind, **seq_json(rt.seq, with_z=False)} for rt in refs],
        })
    data = {"version": 1, "lesson": cards.get("lesson", ""), "config": config_json(), "words": words}
    ASSETS.parent.mkdir(parents=True, exist_ok=True)
    ASSETS.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    n_refs = sum(len(w["refs"]) for w in words)
    print(f"저장: {ASSETS}  ({ASSETS.stat().st_size / 1e6:.2f}MB, 단어 {len(words)}개, 기준 테이크 {n_refs}개)")

    # ---- 정답 데이터 (golden)
    GOLDEN.mkdir(parents=True, exist_ok=True)
    for name in GOLDEN_TAKES:
        path = config.TAKES_DIR / f"{name}.npz"
        if not path.exists():
            print(f"  [건너뜀] {name}")
            continue
        take = crop_like_learner(load_take(path))
        seq = processing.process(take)
        out = {
            "name": name,
            "raw": {
                "width": take["width"], "height": take["height"],
                "t": take["t"].tolist(),
                "hands": take["hands"].astype(np.float64).tolist(),
                "hand_ok": take["hand_ok"].astype(int).tolist(),
                "pose": take["pose"].astype(np.float64).tolist(),
                "pose_ok": take["pose_ok"].astype(int).tolist(),
            },
            "processed": {
                "error": seq.error,
                "t": np.asarray(seq.t).tolist(),
                "X": np.asarray(seq.X, np.float64).tolist(),
                "P": seq.P.astype(int).tolist(),
                "head": np.asarray(seq.head, np.float64).tolist(),
                "no_hand_ratio": seq.no_hand_ratio(),
            },
            "judgements": {},
        }
        if not seq.error and len(seq):
            tr = seq.trimmed()
            out["processed"]["trim_len"] = len(tr)
        for target in names:
            j = lib.judge(seq, target)
            out["judgements"][target] = {
                "status": j.status, "message": j.message, "hints": j.hints,
                "distances": j.distances, "target_dist": j.target_dist,
            }
        f = GOLDEN / f"{name}.json"
        f.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
        print(f"  정답 데이터: {f.name}  " + ", ".join(f"{k}:{v['status']}" for k, v in out["judgements"].items()))


if __name__ == "__main__":
    main()
