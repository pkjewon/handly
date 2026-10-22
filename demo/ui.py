"""화면 그리기 도구: 한글 글자(Pillow), 입체 손 안내(M1-2), 영상 재생(M1-3, M1-6)."""
from __future__ import annotations

import time
from functools import lru_cache
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

import config
from landmarks import HAND_EDGES
from processing import Seq

# 색 (BGR)
BG = (246, 244, 241)
PANEL = (255, 255, 255)
INK = (40, 36, 32)
SUB = (120, 115, 110)
LINE = (220, 216, 210)
GRAY = (170, 170, 170)
GREEN = (90, 185, 60)
RED = (60, 70, 225)
BLUE = (215, 140, 40)
ORANGE = (40, 150, 245)
SLOT_COLORS = [ORANGE, BLUE]


@lru_cache(maxsize=32)
def _font(size: int, bold: bool):
    return ImageFont.truetype(config.FONT_BOLD_PATH if bold else config.FONT_PATH, size)


class Text:
    """한 프레임의 한글 글자를 모아 두었다가 한 번에 그림 (Pillow 변환은 프레임당 1번)."""

    def __init__(self):
        self.items = []

    def add(self, text, xy, size=22, color=INK, bold=False, anchor="la"):
        self.items.append((str(text), xy, size, color, bold, anchor))

    def render(self, canvas: np.ndarray) -> np.ndarray:
        if not self.items:
            return canvas
        img = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
        d = ImageDraw.Draw(img)
        for text, xy, size, color, bold, anchor in self.items:
            d.text(xy, text, font=_font(size, bold), fill=color[::-1], anchor=anchor)
        self.items = []
        return cv2.cvtColor(np.asarray(img), cv2.COLOR_RGB2BGR)


def text_width(text: str, size: int, bold=False) -> int:
    return int(_font(size, bold).getlength(text))


def wrap(text: str, size: int, width: int) -> list[str]:
    """글자 폭에 맞춰 줄 나누기 (띄어쓰기 기준)."""
    lines, cur = [], ""
    for word in text.split(" "):
        test = f"{cur} {word}".strip()
        if text_width(test, size) <= width or not cur:
            cur = test
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def fit_image(img: np.ndarray, w: int, h: int, bg=(30, 30, 30)) -> np.ndarray:
    ih, iw = img.shape[:2]
    s = min(w / iw, h / ih)
    nw, nh = int(iw * s), int(ih * s)
    out = np.full((h, w, 3), bg, np.uint8)
    x, y = (w - nw) // 2, (h - nh) // 2
    out[y:y + nh, x:x + nw] = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_AREA)
    return out


def rounded_rect(img, x, y, w, h, color, r=14, thickness=-1):
    if thickness < 0:
        cv2.rectangle(img, (x + r, y), (x + w - r, y + h), color, -1)
        cv2.rectangle(img, (x, y + r), (x + w, y + h - r), color, -1)
        for cx, cy in ((x + r, y + r), (x + w - r, y + r), (x + r, y + h - r), (x + w - r, y + h - r)):
            cv2.circle(img, (cx, cy), r, color, -1, cv2.LINE_AA)
    else:
        cv2.rectangle(img, (x, y), (x + w, y + h), color, thickness, cv2.LINE_AA)


# ---------------------------------------------------------------- M1-2 입체 손 안내

class GuidePlayer:
    """기준 좌표로 그린 두 손 + 흐린 머리·어깨 선을 반복 재생."""

    def __init__(self, seq: Seq | None):
        self.seq = seq
        self.speed = 1.0
        self.start = time.perf_counter()
        self.hold = 0.7  # 끝에서 잠깐 멈춤

    def restart(self):
        self.start = time.perf_counter()

    def frame_index(self) -> int:
        if self.seq is None or len(self.seq) == 0:
            return 0
        period = self.seq.duration / self.speed + self.hold
        t = ((time.perf_counter() - self.start) % period) * self.speed
        return min(int(t * config.TARGET_FPS), len(self.seq) - 1)

    def render(self, w: int, h: int, idx: int | None = None) -> np.ndarray:
        img = np.full((h, w, 3), (250, 248, 245), np.uint8)
        if self.seq is None or len(self.seq) == 0:
            return img
        i = self.frame_index() if idx is None else idx
        scale = min(w * 0.30, h * 0.36)
        ox, oy = w / 2, h * 0.52

        def P(x, y):
            return int(ox + x * scale), int(oy + y * scale)

        # 흐린 머리·어깨 선
        hx, hy, hr = self.seq.head
        faint = (215, 210, 205)
        cv2.circle(img, P(hx, hy), int(hr * scale), faint, 2, cv2.LINE_AA)
        cv2.line(img, P(-0.5, 0), P(0.5, 0), faint, 3, cv2.LINE_AA)
        cv2.line(img, P(-0.5, 0), P(-0.45, 1.3), faint, 2, cv2.LINE_AA)
        cv2.line(img, P(0.5, 0), P(0.45, 1.3), faint, 2, cv2.LINE_AA)
        cv2.line(img, P(hx - 0.12, hy + hr), P(-0.12, -0.05), faint, 2, cv2.LINE_AA)
        cv2.line(img, P(hx + 0.12, hy + hr), P(0.12, -0.05), faint, 2, cv2.LINE_AA)

        # 손의 이동 궤적 (손목, 옅게)
        for k in range(2):
            pts = [P(*self.seq.X[j, k, 0, :2]) for j in range(len(self.seq)) if self.seq.P[j, k]]
            for a, b in zip(pts[:-1], pts[1:]):
                cv2.line(img, a, b, (232, 226, 220), 2, cv2.LINE_AA)

        # 두 손: z(카메라 쪽으로 가까울수록 음수)로 두께·크기·밝기를 바꿔 입체감
        for k in range(2):
            if not self.seq.P[i, k]:
                continue
            X = self.seq.X[i, k]
            z = X[:, 2] - X[0, 2]
            base = np.array(SLOT_COLORS[k], float)
            edges = sorted(HAND_EDGES, key=lambda e: -(z[e[0]] + z[e[1]]))
            for a, b in edges:
                zz = (z[a] + z[b]) / 2
                near = float(np.clip(-zz * 6, -1, 1))
                col = tuple(int(c) for c in np.clip(base * (0.75 + 0.25 * near) + 40 * (1 - near), 0, 255))
                cv2.line(img, P(*X[a, :2]), P(*X[b, :2]), col, max(2, int(5 + 3 * near)), cv2.LINE_AA)
            for j in np.argsort(-z):
                near = float(np.clip(-z[j] * 6, -1, 1))
                r = max(2, int(5 + 3 * near))
                cv2.circle(img, P(*X[j, :2]), r, (255, 255, 255), -1, cv2.LINE_AA)
                cv2.circle(img, P(*X[j, :2]), r, SLOT_COLORS[k], 2, cv2.LINE_AA)
        return img


# ---------------------------------------------------------------- M1-3 실제 영상 (반복·속도 조절)

class VideoPlayer:
    def __init__(self, path: Path):
        self.path = path
        self.cap = cv2.VideoCapture(str(path))
        self.fps = self.cap.get(cv2.CAP_PROP_FPS) or 30
        self.speed = 1.0
        self.frame = None
        self.start = time.perf_counter()
        self.shown = 0

    @property
    def ok(self) -> bool:
        return self.cap.isOpened()

    def restart(self):
        self.cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
        self.start = time.perf_counter()
        self.shown = 0

    def read(self) -> np.ndarray | None:
        want = int((time.perf_counter() - self.start) * self.fps * self.speed)
        while self.shown <= want:
            ok, f = self.cap.read()
            if not ok:
                self.restart()
                ok, f = self.cap.read()
                if not ok:
                    return self.frame
            self.frame = f
            self.shown += 1
        return self.frame

    def close(self):
        self.cap.release()


def find_videos(word: str) -> list[Path]:
    """videos/ 에서 단어 영상 찾기. 안내 영상을 먼저."""
    vids = [p for p in config.VIDEOS_DIR.glob(f"{word}*") if p.suffix.lower() in (".mp4", ".avi", ".mov", ".mkv")]
    return sorted(vids, key=lambda p: (config.KIND_GUIDE not in p.stem, p.name))
