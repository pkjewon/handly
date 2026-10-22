"""PRD 10-3 좌표 처리 규칙. 기준 동작과 학습자 동작에 반드시 똑같이 적용한다.

① 화면 비율 보정 → ② 어깨 기준점 → ③ 왼/오손 다시 정하기 → ④ 짧은 끊김 보간
→ ⑤ 어깨 기준 정규화 → ⑥ 1초당 30개로 다시 샘플링
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

import config
from landmarks import P_LEAR, P_LSH, P_NOSE, P_REAR, P_RSH

SLOT_NAMES = ["화면 왼쪽 손", "화면 오른쪽 손"]


@dataclass
class Seq:
    """정리된 좌표 시퀀스. slot 0 = 화면 왼쪽 손, slot 1 = 화면 오른쪽 손."""
    t: np.ndarray        # (N,) 초, 1/30초 간격
    X: np.ndarray        # (N, 2, 21, 3) 어깨 가운데 원점, 어깨 너비 1
    P: np.ndarray        # (N, 2) bool 손 있음
    head: np.ndarray     # (3,) 머리 위치 x, y, 반지름 (그리기용, 정규화 좌표)
    error: str | None = None

    def __len__(self):
        return len(self.t)

    @property
    def duration(self) -> float:
        return float(self.t[-1] - self.t[0]) if len(self.t) > 1 else 0.0

    def no_hand_ratio(self) -> float:
        if len(self) == 0:
            return 1.0
        return float(np.mean(~self.P.any(axis=1)))

    def presence_ratio(self) -> np.ndarray:
        if len(self) == 0:
            return np.zeros(2)
        return self.P.mean(axis=0)

    def trimmed(self) -> "Seq":
        """앞뒤로 손이 하나도 없는 프레임을 잘라냄 (동작 구간만 남김)."""
        any_hand = np.flatnonzero(self.P.any(axis=1))
        if len(any_hand) == 0:
            return self
        a, b = any_hand[0], any_hand[-1] + 1
        return Seq(self.t[a:b] - self.t[a], self.X[a:b], self.P[a:b], self.head, self.error)


def _empty(error: str) -> Seq:
    return Seq(np.zeros(0), np.zeros((0, 2, 21, 3), np.float32), np.zeros((0, 2), bool), np.zeros(3), error)


def _assign_slots(t, hands, hand_ok, cx, sw):
    """MediaPipe의 왼/오 라벨 대신, 손목이 몸 중심의 어느 쪽에 있는지로 정함.
    손목이 몸 중심 가까이(애매한 구역)에 있을 때만 직전 위치를 이어 봄."""
    N = len(t)
    out = np.zeros((N, 2, 21, 3), np.float32)
    ok = np.zeros((N, 2), bool)
    last = [None, None]  # slot별 (시간, 손목 xy)
    recent_sec = 0.3
    ambiguous = 0.25 * sw   # 몸 중심에서 이 거리 안이면 어느 쪽 손인지 애매
    near_dist = 0.4 * sw    # 직전 위치와 이 거리 안이어야 같은 손으로 봄

    def dist(h, k):
        return float(np.linalg.norm(h[0, :2] - last[k][1]))

    for i in range(N):
        det = [hands[i, k] for k in range(2) if hand_ok[i, k]]
        recent = [k for k in range(2) if last[k] is not None and t[i] - last[k][0] <= recent_sec]
        slots: list[int] = []
        if len(det) == 2:
            det.sort(key=lambda h: h[0, 0])
            slots = [0, 1]
            # 두 손목이 거의 같은 x일 때(손이 겹침)만 직전 위치로 판단
            if len(recent) == 2 and det[1][0, 0] - det[0][0, 0] < ambiguous:
                straight = dist(det[0], 0) + dist(det[1], 1)
                swapped = dist(det[0], 1) + dist(det[1], 0)
                if swapped < straight:
                    slots = [1, 0]
        elif len(det) == 1:
            h = det[0]
            slots = [0 if h[0, 0] < cx else 1]
            if abs(h[0, 0] - cx) < ambiguous:
                near = [k for k in recent if dist(h, k) < near_dist]
                if near:
                    slots = [min(near, key=lambda k: dist(h, k))]
        for h, k in zip(det, slots):
            out[i, k] = h
            ok[i, k] = True
            last[k] = (t[i], h[0, :2].copy())
    return out, ok


def _fill_short_gaps(t, X, ok):
    """slot별로 짧게(≤0.2초) 끊긴 구간을 앞뒤 프레임으로 선형 보간."""
    X, ok = X.copy(), ok.copy()
    tol = config.SHORT_GAP_SEC + 0.5 / config.TARGET_FPS
    for k in range(2):
        valid = np.flatnonzero(ok[:, k])
        for a, b in zip(valid[:-1], valid[1:]):
            if b - a > 1 and t[b] - t[a] <= tol:
                for i in range(a + 1, b):
                    w = (t[i] - t[a]) / (t[b] - t[a])
                    X[i, k] = (1 - w) * X[a, k] + w * X[b, k]
                    ok[i, k] = True
    return X, ok


def _resample(t, X, ok, fps):
    """실제 시간 위치 기준으로 1초당 fps개로 다시 샘플링."""
    n = int(np.floor(t[-1] * fps)) + 1
    tt = np.arange(n) / fps
    Xo = np.zeros((n, 2, 21, 3), np.float32)
    Po = np.zeros((n, 2), bool)
    nearest = np.clip(np.searchsorted(t, tt), 0, len(t) - 1)
    prev = np.clip(nearest - 1, 0, len(t) - 1)
    nearest = np.where(np.abs(t[prev] - tt) < np.abs(t[nearest] - tt), prev, nearest)
    for k in range(2):
        v = np.flatnonzero(ok[:, k])
        if len(v) == 0:
            continue
        flat = X[v, k].reshape(len(v), -1)
        res = np.stack([np.interp(tt, t[v], flat[:, d]) for d in range(flat.shape[1])], axis=1)
        Xo[:, k] = res.reshape(n, 21, 3)
        Po[:, k] = ok[nearest, k]
        Xo[~Po[:, k], k] = 0
    return tt, Xo, Po


def process(take: dict) -> Seq:
    t = np.asarray(take["t"], np.float64)
    if len(t) < 2:
        return _empty("too_short")
    aspect = take["width"] / take["height"]
    scale = np.array([aspect, 1.0, aspect], np.float32)
    hands = take["hands"] * scale
    pose = take["pose"] * scale
    pose_ok = take["pose_ok"]

    # 어깨 기준점: 몇 초 동안 어깨는 거의 안 움직이므로 중앙값 사용
    if pose_ok.sum() < max(3, 0.2 * len(t)):
        return _empty("no_shoulder")
    pv = pose[pose_ok]
    lsh, rsh = np.median(pv[:, P_LSH, :2], axis=0), np.median(pv[:, P_RSH, :2], axis=0)
    center = (lsh + rsh) / 2
    sw = float(np.linalg.norm(lsh - rsh))
    if sw < 1e-3:
        return _empty("no_shoulder")
    nose = np.median(pv[:, P_NOSE, :2], axis=0)
    ear_w = float(np.median(np.linalg.norm(pv[:, P_LEAR, :2] - pv[:, P_REAR, :2], axis=1)))
    r = max(ear_w / sw * 0.85, 0.25)
    head = np.array([(nose[0] - center[0]) / sw, (nose[1] - center[1]) / sw - 0.3 * r, r])

    X, ok = _assign_slots(t, hands, take["hand_ok"], center[0], sw)
    X, ok = _fill_short_gaps(t, X, ok)

    X = X.copy()
    X[..., 0] -= center[0]
    X[..., 1] -= center[1]
    X /= sw
    X[~ok] = 0

    tt, Xr, Pr = _resample(t, X, ok, config.TARGET_FPS)
    return Seq(tt, Xr, Pr, head.astype(np.float32))
