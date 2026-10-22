"""DTW 동작 비교, 판정(M2-5), 틀린 이유 힌트(M2-7), 기준값 계산(M2-8)."""
from __future__ import annotations

import json
from dataclasses import dataclass, field

import numpy as np

import config
import processing
from landmarks import list_takes, load_take
from processing import Seq


# ---------------------------------------------------------------- DTW

def frame_costs(a: Seq, b: Seq, slots: list[int]) -> np.ndarray:
    """(N, M) 프레임 거리. 손 21점 위치 차이 + 손목 기준 손 모양 차이 (x, y만 사용)."""
    N, M = len(a), len(b)
    if not slots:
        return np.zeros((N, M))
    total = np.zeros((N, M))
    for k in slots:
        A, B = a.X[:, k, :, :2], b.X[:, k, :, :2]
        pos = np.linalg.norm(A[:, None] - B[None], axis=-1).mean(-1)
        Ar, Br = A - A[:, :1], B - B[:, :1]
        shape = np.linalg.norm(Ar[:, None] - Br[None], axis=-1).mean(-1)
        c = pos + shape
        pa, pb = a.P[:, k][:, None], b.P[:, k][None, :]
        c = np.where(pa & pb, c, np.where(pa | pb, config.ABSENT_PENALTY, 0.0))
        total += c
    return total / len(slots)


def dtw(cost: np.ndarray) -> tuple[float, list[tuple[int, int]]]:
    """기본 DTW. 반환: 경로 길이로 나눈 거리, 짝지어진 프레임 (i, j) 목록."""
    N, M = cost.shape
    D = np.full((N + 1, M + 1), np.inf)
    D[0, 0] = 0.0
    c = cost.tolist()
    rows = D.tolist()
    for i in range(1, N + 1):
        ci, up, cur = c[i - 1], rows[i - 1], rows[i]
        for j in range(1, M + 1):
            m = up[j - 1]
            if up[j] < m:
                m = up[j]
            if cur[j - 1] < m:
                m = cur[j - 1]
            cur[j] = ci[j - 1] + m
    D = np.array(rows)
    i, j, path = N, M, []
    while i > 0 and j > 0:
        path.append((i - 1, j - 1))
        steps = ((D[i - 1, j - 1], i - 1, j - 1), (D[i - 1, j], i - 1, j), (D[i, j - 1], i, j - 1))
        _, i, j = min(steps, key=lambda s: s[0])
    path.reverse()
    return float(D[N, M]) / len(path), path


# ---------------------------------------------------------------- 기준 동작 모음

@dataclass
class RefTake:
    path: object
    word: str
    kind: str
    person: str
    seq: Seq            # trimmed


@dataclass
class Judgement:
    status: str                      # "correct" / "wrong" / "fail"
    message: str
    hints: list[str] = field(default_factory=list)
    distances: dict[str, float] = field(default_factory=dict)
    target_dist: float | None = None
    threshold: float | None = None


def load_thresholds() -> dict[str, float]:
    if config.THRESHOLDS_FILE.exists():
        return json.loads(config.THRESHOLDS_FILE.read_text(encoding="utf-8"))
    return {}


class Library:
    """data/takes 의 테이크를 읽어 단어별 기준 동작과 오답 동작으로 나눠 둔다."""

    def __init__(self, words: list[str] | None = None):
        self.refs: dict[str, list[RefTake]] = {}
        self.wrongs: list[RefTake] = []
        self.skipped: list[tuple[str, str]] = []
        for path, word, kind in list_takes():
            take = load_take(path)
            seq = processing.process(take)
            if seq.error or seq.no_hand_ratio() >= 1.0:
                self.skipped.append((path.name, seq.error or "no_hand"))
                continue
            rt = RefTake(path, word, kind, take["meta"].get("person", ""), seq.trimmed())
            if kind == config.KIND_WRONG:
                self.wrongs.append(rt)
            elif kind in config.REFERENCE_KINDS and (words is None or word in words):
                self.refs.setdefault(word, []).append(rt)
        self.slots = {w: self._used_slots(r) for w, r in self.refs.items()}
        self.thresholds = load_thresholds()

    @staticmethod
    def _used_slots(takes: list[RefTake]) -> list[int]:
        ratio = np.mean([t.seq.presence_ratio() for t in takes], axis=0)
        used = [k for k in range(2) if ratio[k] >= config.HAND_USED_RATIO]
        return used or [int(np.argmax(ratio))]

    @property
    def words(self) -> list[str]:
        return list(self.refs)

    def threshold(self, word: str) -> float:
        return float(self.thresholds.get(word, config.DEFAULT_THRESHOLD))

    def guide_take(self, word: str) -> RefTake | None:
        takes = self.refs.get(word, [])
        guides = [t for t in takes if t.kind == config.KIND_GUIDE]
        return (guides or takes or [None])[0]

    def word_distance(self, seq: Seq, word: str, exclude=None) -> tuple[float, RefTake | None]:
        """단어까지 거리 = 기준 테이크 중 가장 가까운 TOP_K개의 평균."""
        slots = self.slots[word]
        scored = []
        for rt in self.refs[word]:
            if exclude is not None and rt.path == exclude:
                continue
            d, _ = dtw(frame_costs(seq, rt.seq, slots))
            scored.append((d, rt))
        if not scored:
            return float("inf"), None
        scored.sort(key=lambda s: s[0])
        top = scored[: config.TOP_K]
        return float(np.mean([s[0] for s in top])), scored[0][1]

    # ------------------------------------------------------------ 판정 (M2-5)

    def judge(self, raw_seq: Seq, target: str) -> Judgement:
        if raw_seq.error == "no_shoulder":
            return Judgement("fail", "어깨까지 화면에 나오게 해 주세요")
        if raw_seq.error or raw_seq.no_hand_ratio() >= config.NO_HAND_FAIL_RATIO:
            return Judgement("fail", "손이 잘 보이지 않아요", ["두 손이 화면에 나오게 해 주세요"])
        if target not in self.refs:
            return Judgement("fail", f"'{target}' 기준 동작이 아직 없어요")

        seq = raw_seq.trimmed()
        slots = self.slots[target]
        if len(slots) == 2:
            missing = 1 - seq.presence_ratio()
            if (missing >= config.MISSING_HAND_RATIO).any():
                return Judgement("fail", "두 손이 화면에 나오게 해 주세요")

        dists, bests = {}, {}
        for w in self.refs:
            dists[w], bests[w] = self.word_distance(seq, w)
        thr = self.threshold(target)
        d_t = dists[target]
        closest = min(dists, key=dists.get)
        if d_t <= thr and closest == target:
            return Judgement("correct", "잘했어요!", [], dists, d_t, thr)

        hints = make_hints(seq, bests[target], slots)
        if closest != target:
            hints.append(f"'{closest}' 동작과 더 비슷해요")
        if not hints:
            hints.append("왼쪽 안내를 다시 보고 해 보세요")
        return Judgement("wrong", "다시 해 볼까요?", hints, dists, d_t, thr)


# ---------------------------------------------------------------- 힌트 (M2-7)

def make_hints(seq: Seq, ref: RefTake | None, slots: list[int]) -> list[str]:
    if ref is None:
        return []
    _, path = dtw(frame_costs(seq, ref.seq, slots))
    ii = np.array([p[0] for p in path])
    jj = np.array([p[1] for p in path])
    hints: list[str] = []
    dys, dxs = [], []
    for k in slots:
        both = seq.P[ii, k] & ref.seq.P[jj, k]
        if both.sum() < 3:
            continue
        lw = seq.X[ii[both], k, 0, :2]
        rw = ref.seq.X[jj[both], k, 0, :2]
        dys.append(float(np.mean(lw[:, 1] - rw[:, 1])))          # +: 학습자 손이 더 아래
        dxs.append(float(np.mean(np.abs(lw[:, 0]) - np.abs(rw[:, 0]))))  # +: 더 바깥쪽
    if dys:
        dy, dx = max(dys, key=abs), max(dxs, key=abs)
        if dy > config.HINT_POS_DIFF:
            hints.append("손 위치가 낮아요. 조금 더 위로 올려 보세요")
        elif dy < -config.HINT_POS_DIFF:
            hints.append("손 위치가 높아요. 조금 더 아래로 내려 보세요")
        if dx > config.HINT_POS_DIFF:
            hints.append("손을 더 몸 쪽으로 가져와 보세요")
        elif dx < -config.HINT_POS_DIFF:
            hints.append("손을 더 바깥쪽으로 벌려 보세요")
    if ref.seq.duration > 0:
        ratio = seq.duration / ref.seq.duration
        if ratio < config.HINT_FAST_RATIO:
            hints.append("동작이 너무 빨라요. 천천히 해 보세요")
        elif ratio > config.HINT_SLOW_RATIO:
            hints.append("동작이 너무 느려요. 조금 더 빠르게 해 보세요")
    return hints


# ---------------------------------------------------------------- 기준값 계산 (M2-8)

def distance_table(lib: Library) -> dict[str, dict[str, list[tuple[float, str]]]]:
    """단어별 거리 목록 (테이크마다 자기 자신은 빼고 계산).
    pos: 그 단어의 비교·다른사람 테이크 / pos_miss: 그중 다른 단어가 더 가까워 기준값과 상관없이 오답이 되는 것
    neg_all: 오답 테이크 + 다른 단어 테이크 / neg: 그중 이 단어가 가장 가까워서 기준값으로만 걸러야 하는 것"""
    takes = [rt for w in lib.words for rt in lib.refs[w]] + lib.wrongs
    dist = {}
    for rt in takes:
        dist[rt.path] = {w: lib.word_distance(rt.seq, w, exclude=rt.path)[0] for w in lib.words}
    table = {}
    for w in lib.words:
        e = {"pos": [], "pos_miss": [], "neg": [], "neg_all": []}
        for rt in takes:
            d = dist[rt.path]
            closest = min(d, key=d.get)
            item = (d[w], rt.path.name)
            if rt.word == w and rt.kind != config.KIND_WRONG:
                if rt.kind != config.KIND_GUIDE and np.isfinite(d[w]):
                    e["pos"].append(item)
                    if closest != w:
                        e["pos_miss"].append((d[w], f"{rt.path.name}→{closest}"))
            else:
                e["neg_all"].append(item)
                if closest == w:
                    e["neg"].append(item)
        table[w] = e
    return table


def suggest_threshold(pos: list[float], neg: list[float]) -> tuple[float, bool]:
    """정답 거리와 (이 단어가 가장 가까운) 오답 거리 사이로 기준값을 정함.
    반환: (기준값, 오답이 모두 기준값보다 먼지)."""
    if not pos:
        return config.DEFAULT_THRESHOLD, False
    hi = float(max(pos))
    cap = hi * 1.3  # 정답 테이크보다 너무 멀리 잡으면 처음 보는 엉뚱한 동작이 통과할 수 있음
    if not neg:
        return round(cap, 4), True
    lo = float(min(neg))
    thr = min((hi + lo) / 2, cap) if lo > hi else lo * 0.97
    return round(thr, 4), all(n > thr for n in neg)
