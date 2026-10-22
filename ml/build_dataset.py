"""PRD 10-4 ①~④: 녹화 테이크(npz) → 모델 학습용 데이터셋.

시연과 똑같은 10-3 정리 규칙(demo/processing.py)을 그대로 적용한 뒤, 동작 구간만 남겨 저장한다.
고정 길이 맞춤과 데이터 증강은 학습할 때(train.py) 한다.

    python build_dataset.py                       # demo/data/takes → ml/dataset.npz
    python build_dataset.py --takes "G:/내 드라이브/handly/takes" --out "G:/내 드라이브/handly/dataset.npz"
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

DEMO = Path(__file__).resolve().parent.parent / "demo"
sys.path.insert(0, str(DEMO))
import config  # noqa: E402
import processing  # noqa: E402
from landmarks import load_take, parse_take_name  # noqa: E402

WRONG_CLASS = "오답"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--takes", default=str(config.TAKES_DIR))
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent / "dataset.npz"))
    ap.add_argument("--words", nargs="*", help="쓸 단어 (기본: words.json 의 단어)")
    args = ap.parse_args()

    words = args.words or [w["name"] for w in json.loads(config.WORDS_FILE.read_text(encoding="utf-8"))["words"]]
    classes = list(words) + [WRONG_CLASS]
    seqs, labels, persons, names = [], [], [], []
    for f in sorted(Path(args.takes).glob("*.npz")):
        p = parse_take_name(f)
        if not p:
            continue
        word, kind, _ = p
        if kind == config.KIND_WRONG:
            label = WRONG_CLASS
        elif word in words:
            label = word
        else:
            continue
        take = load_take(f)
        seq = processing.process(take)
        if seq.error or seq.no_hand_ratio() >= config.NO_HAND_FAIL_RATIO:
            print(f"[제외] {f.name}: {seq.error or '손 없음'}")
            continue
        seq = seq.trimmed()
        seqs.append(seq)
        labels.append(classes.index(label))
        persons.append(take["meta"].get("person") or "unknown")
        names.append(f.name)

    if not seqs:
        sys.exit("데이터가 없습니다.")
    L = max(len(s) for s in seqs)
    X = np.zeros((len(seqs), L, 2, 21, 3), np.float32)
    P = np.zeros((len(seqs), L, 2), bool)
    lengths = np.array([len(s) for s in seqs])
    for i, s in enumerate(seqs):
        X[i, :len(s)] = s.X
        P[i, :len(s)] = s.P
    np.savez_compressed(args.out, X=X, P=P, lengths=lengths, y=np.array(labels), person=np.array(persons),
                        name=np.array(names), classes=np.array(classes))
    print(f"저장: {args.out}  ({len(seqs)}개)")
    for i, c in enumerate(classes):
        ps = sorted({persons[j] for j in range(len(labels)) if labels[j] == i})
        print(f"  {c}: {labels.count(i)}개, 촬영자 {len(ps)}명 {ps}")


if __name__ == "__main__":
    main()
