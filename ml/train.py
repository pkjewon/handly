"""PRD 10-4 ⑤⑥: LSTM / GRU 학습·비교 → ONNX 내보내기. Google Colab(무료 GPU)에서 실행.

Colab 예시:
    from google.colab import drive; drive.mount('/content/drive')
    !git clone <비공개 저장소> handly && cd handly/ml
    !python train.py --data /content/drive/MyDrive/handly/dataset.npz --out /content/drive/MyDrive/handly/models

- 학습/검증/테스트는 사람 기준으로 나눔 (같은 사람이 학습과 테스트에 섞이지 않게)
- 데이터 증강: 작은 회전(±10도), 크기(±10%), 부분 속도 변화(0.8~1.2배), 약한 노이즈.
  위치 이동·좌우 반전은 쓰지 않음 (PRD 10-4 표)
- 판정 규칙(앱): 목표 단어가 1등이고 확률이 단어별 기준 이상이면 정답
"""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np
import torch
from torch import nn

FIXED_LEN = 30
FEAT = 2 * 21 * 3 + 2


# ---------------------------------------------------------------- 전처리·증강

def to_fixed(X: np.ndarray, P: np.ndarray, n: int = FIXED_LEN, warp: np.ndarray | None = None):
    """가변 길이 (L,2,21,3) → 고정 길이 n. warp: 0~1 단조 증가 시간 위치 (부분 속도 변화용)."""
    L = len(X)
    pos = (warp if warp is not None else np.linspace(0, 1, n)) * (L - 1)
    i0 = np.floor(pos).astype(int)
    i1 = np.minimum(i0 + 1, L - 1)
    w = (pos - i0)[:, None, None, None]
    Xf = (1 - w) * X[i0] + w * X[i1]
    Pf = np.where(w[:, :, 0, 0] < 0.5, P[i0], P[i1])
    Xf = Xf * Pf[..., None, None]
    return Xf.astype(np.float32), Pf


def random_warp(rng, n=FIXED_LEN, lo=0.8, hi=1.2):
    """구간마다 속도가 0.8~1.2배로 다른 시간 위치 (전체 길이는 고정 길이로 다시 맞추므로 부분 변화만 남음)."""
    knots = rng.uniform(lo, hi, 4)
    speed = np.interp(np.linspace(0, 3, n), np.arange(4), knots)
    pos = np.concatenate([[0], np.cumsum(speed[:-1])])
    return pos / pos[-1]


def augment(X, P, rng):
    X = X.copy()
    th = np.deg2rad(rng.uniform(-10, 10))
    c, s = np.cos(th), np.sin(th)
    x, y = X[..., 0].copy(), X[..., 1].copy()
    X[..., 0], X[..., 1] = c * x - s * y, s * x + c * y
    X *= rng.uniform(0.9, 1.1)
    X += rng.normal(0, 0.01, X.shape).astype(np.float32)
    X *= P[..., None, None]
    return X


def features(Xf, Pf):
    return np.concatenate([Xf.reshape(len(Xf), -1), Pf.astype(np.float32)], axis=1)


class SignData(torch.utils.data.Dataset):
    def __init__(self, d, idx, train, seed=0):
        self.d, self.idx, self.train = d, idx, train
        self.rng = np.random.default_rng(seed)

    def __len__(self):
        return len(self.idx)

    def __getitem__(self, k):
        i = self.idx[k]
        L = self.d["lengths"][i]
        X, P = self.d["X"][i, :L], self.d["P"][i, :L]
        if self.train:
            X = augment(X, P, self.rng)
            Xf, Pf = to_fixed(X, P, warp=random_warp(self.rng))
        else:
            Xf, Pf = to_fixed(X, P)
        return torch.from_numpy(features(Xf, Pf)), int(self.d["y"][i])


# ---------------------------------------------------------------- 모델

class SignRNN(nn.Module):
    def __init__(self, arch: str, n_classes: int, hidden=128, layers=2):
        super().__init__()
        rnn = nn.LSTM if arch == "lstm" else nn.GRU
        self.rnn = rnn(FEAT, hidden, layers, batch_first=True, dropout=0.3)
        self.head = nn.Sequential(nn.Dropout(0.3), nn.Linear(hidden, n_classes))

    def forward(self, x):
        out, _ = self.rnn(x)
        return self.head(out[:, -1])


# ---------------------------------------------------------------- 사람 기준 나누기

def split_by_person(persons, test_persons=None, seed=0):
    people = sorted(set(persons))
    rng = np.random.default_rng(seed)
    if test_persons:
        test = set(test_persons)
    else:
        if len(people) < 3:
            print(f"⚠ 촬영자가 {len(people)}명뿐이라 사람 기준으로 나눌 수 없어 테이크 기준으로 나눕니다 (정확도가 부풀려질 수 있음).")
            idx = rng.permutation(len(persons))
            n = len(idx)
            return idx[: int(n * .7)], idx[int(n * .7): int(n * .85)], idx[int(n * .85):]
        shuffled = [str(p) for p in rng.permutation(people)]
        test = {shuffled[0]}
    rest = [p for p in people if p not in test]
    val = {rest[int(rng.integers(len(rest)))]} if len(rest) > 1 else set()
    persons = np.asarray(persons)
    tr = np.flatnonzero(~np.isin(persons, list(test | val)))
    va = np.flatnonzero(np.isin(persons, list(val)))
    te = np.flatnonzero(np.isin(persons, list(test)))
    print(f"학습 {len(tr)} / 검증 {len(va)} / 테스트 {len(te)}   테스트 촬영자: {sorted(test)}  검증 촬영자: {sorted(val)}")
    return tr, va, te


def evaluate(model, loader, device):
    model.eval()
    probs, ys = [], []
    with torch.no_grad():
        for x, y in loader:
            probs.append(torch.softmax(model(x.to(device)), -1).cpu().numpy())
            ys.append(y.numpy())
    if not probs:
        return np.zeros((0, 0)), np.zeros(0)
    return np.concatenate(probs), np.concatenate(ys)


def train_one(arch, d, split, args, device):
    n_classes = len(d["classes"])
    tr, va, te = split
    mk = lambda idx, train: torch.utils.data.DataLoader(  # noqa: E731
        SignData(d, idx, train, args.seed), batch_size=args.batch, shuffle=train)
    tr_l, va_l, te_l = mk(tr, True), mk(va if len(va) else te, False), mk(te, False)

    torch.manual_seed(args.seed)
    model = SignRNN(arch, n_classes).to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-3)
    loss_fn = nn.CrossEntropyLoss()
    best, best_state = -1.0, None
    for ep in range(args.epochs):
        model.train()
        for x, y in tr_l:
            opt.zero_grad()
            loss = loss_fn(model(x.to(device)), y.to(device))
            loss.backward()
            opt.step()
        p, y = evaluate(model, va_l, device)
        acc = float((p.argmax(1) == y).mean()) if len(y) else 0.0
        if acc >= best:
            best, best_state = acc, {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
        if (ep + 1) % 10 == 0:
            print(f"  [{arch}] epoch {ep + 1}: loss {loss.item():.3f}  검증 정확도 {acc:.1%}")
    model.load_state_dict(best_state)

    p, y = evaluate(model, te_l, device)
    acc = float((p.argmax(1) == y).mean()) if len(y) else float("nan")
    t0 = time.perf_counter()
    with torch.no_grad():
        for _ in range(100):
            model(torch.zeros(1, FIXED_LEN, FEAT, device=device))
    ms = (time.perf_counter() - t0) * 10
    return model, acc, ms, p, y


def word_thresholds(p, y, classes):
    """단어별 확률 기준: 테스트에서 정답 테이크 확률의 하위 10% (최소 0.5)."""
    out = {}
    for i, c in enumerate(classes[:-1]):
        ps = p[y == i, i] if len(y) else []
        out[c] = float(max(0.5, np.percentile(ps, 10))) if len(ps) else 0.5
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="dataset.npz")
    ap.add_argument("--out", default="models")
    ap.add_argument("--arch", choices=["lstm", "gru", "both"], default="both")
    ap.add_argument("--epochs", type=int, default=80)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--test-person", nargs="*")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    z = np.load(args.data, allow_pickle=False)
    d = {k: z[k] for k in z.files}
    classes = [str(c) for c in d["classes"]]
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"클래스 {classes}, 데이터 {len(d['y'])}개, 장치 {device}")
    split = split_by_person([str(p) for p in d["person"]], args.test_person, args.seed)

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    results = {}
    for arch in (["lstm", "gru"] if args.arch == "both" else [args.arch]):
        model, acc, ms, p, y = train_one(arch, d, split, args, device)
        thr = word_thresholds(p, y, classes)
        results[arch] = dict(test_acc=acc, ms_per_sample=ms, thresholds=thr)
        print(f"■ {arch.upper()}: 테스트 정확도 {acc:.1%}, 1개 판정 {ms:.2f}ms ({device})")
        torch.save({"state": model.state_dict(), "arch": arch, "classes": classes}, out / f"handly_{arch}.pt")
        model.cpu().eval()
        try:
            torch.onnx.export(model, torch.zeros(1, FIXED_LEN, FEAT), str(out / f"handly_{arch}.onnx"),
                              input_names=["x"], output_names=["logits"], opset_version=17)
            print(f"  ONNX 저장: {out / f'handly_{arch}.onnx'}")
        except Exception as e:  # 모바일 변환은 [확인 필요] 항목이라 실패해도 학습 결과는 남김
            print(f"  ONNX 변환 실패: {e}")
        model.to(device)

    meta = dict(classes=classes, fixed_len=FIXED_LEN, feat=FEAT, results=results)
    (out / "handly_model.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
