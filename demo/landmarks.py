"""MediaPipe Tasks API로 두 손(Hand Landmarker) + 어깨 기준점(Pose Landmarker) 좌표 추출.

녹화 한 번(테이크)의 원본 좌표는 RawTake로 모으고 .npz로 저장한다.
정리(왼/오손 구분, 빈 프레임, 정규화, 시간 맞춤)는 processing.py가 맡는다.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python import vision

import config

# Pose 33점 중 쓰는 점: 코, 왼귀, 오른귀, 왼어깨, 오른어깨
POSE_IDS = [0, 7, 8, 11, 12]
P_NOSE, P_LEAR, P_REAR, P_LSH, P_RSH = range(5)

# 손 21점 연결선 (그리기용)
HAND_EDGES = [
    (0, 1), (1, 2), (2, 3), (3, 4),
    (0, 5), (5, 6), (6, 7), (7, 8),
    (5, 9), (9, 10), (10, 11), (11, 12),
    (9, 13), (13, 14), (14, 15), (15, 16),
    (13, 17), (0, 17), (17, 18), (18, 19), (19, 20),
]


@dataclass
class FrameData:
    hands: np.ndarray      # (2, 21, 3) 화면 좌표 0~1, 감지 순서 그대로
    hand_ok: np.ndarray    # (2,) bool
    pose: np.ndarray       # (5, 3)
    pose_ok: bool


class Extractor:
    """웹캠·영상 프레임 → FrameData. VIDEO 모드라 timestamp는 계속 커져야 한다."""

    def __init__(self, pose_every: int = 1):
        hand_opts = vision.HandLandmarkerOptions(
            base_options=BaseOptions(model_asset_buffer=config.HAND_MODEL.read_bytes()),
            running_mode=vision.RunningMode.VIDEO,
            num_hands=2,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        pose_opts = vision.PoseLandmarkerOptions(
            base_options=BaseOptions(model_asset_buffer=config.POSE_MODEL.read_bytes()),
            running_mode=vision.RunningMode.VIDEO,
            num_poses=1,
        )
        self.hand = vision.HandLandmarker.create_from_options(hand_opts)
        self.pose = vision.PoseLandmarker.create_from_options(pose_opts)
        self.pose_every = max(1, pose_every)
        self._count = 0
        self._last_ts = -1
        self._last_pose: tuple[np.ndarray, bool] = (np.zeros((5, 3), np.float32), False)

    def process(self, frame_bgr: np.ndarray, ts_ms: int) -> FrameData:
        ts_ms = max(int(ts_ms), self._last_ts + 1)
        self._last_ts = ts_ms
        rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

        hands = np.zeros((2, 21, 3), np.float32)
        hand_ok = np.zeros(2, bool)
        res = self.hand.detect_for_video(image, ts_ms)
        for i, lms in enumerate(res.hand_landmarks[:2]):
            hands[i] = [(p.x, p.y, p.z) for p in lms]
            hand_ok[i] = True

        # 어깨는 수어 중 거의 안 움직여서 pose_every 프레임마다 한 번만 계산해도 됨 (10-8)
        if self._count % self.pose_every == 0:
            pres = self.pose.detect_for_video(image, ts_ms)
            if pres.pose_landmarks:
                lms = pres.pose_landmarks[0]
                pose = np.array([(lms[i].x, lms[i].y, lms[i].z) for i in POSE_IDS], np.float32)
                self._last_pose = (pose, True)
            else:
                self._last_pose = (np.zeros((5, 3), np.float32), False)
        self._count += 1
        pose, pose_ok = self._last_pose
        return FrameData(hands, hand_ok, pose.copy(), pose_ok)

    def close(self):
        self.hand.close()
        self.pose.close()


@dataclass
class RawTake:
    """테이크 하나의 원본 좌표. 저장 형식은 기준 동작·학습자 동작 모두 같다."""
    width: int
    height: int
    mirrored: bool
    meta: dict = field(default_factory=dict)
    t: list = field(default_factory=list)
    hands: list = field(default_factory=list)
    hand_ok: list = field(default_factory=list)
    pose: list = field(default_factory=list)
    pose_ok: list = field(default_factory=list)

    def add(self, t_sec: float, fd: FrameData):
        self.t.append(t_sec)
        self.hands.append(fd.hands)
        self.hand_ok.append(fd.hand_ok)
        self.pose.append(fd.pose)
        self.pose_ok.append(fd.pose_ok)

    def __len__(self):
        return len(self.t)

    def arrays(self) -> dict:
        t = np.asarray(self.t, np.float64)
        if len(t):
            t = t - t[0]
        return dict(
            t=t,
            hands=np.asarray(self.hands, np.float32).reshape(-1, 2, 21, 3),
            hand_ok=np.asarray(self.hand_ok, bool).reshape(-1, 2),
            pose=np.asarray(self.pose, np.float32).reshape(-1, 5, 3),
            pose_ok=np.asarray(self.pose_ok, bool),
            width=self.width, height=self.height, mirrored=self.mirrored,
        )

    def save(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        np.savez_compressed(path, meta=json.dumps(self.meta, ensure_ascii=False), **self.arrays())


def load_take(path: Path) -> dict:
    with np.load(path, allow_pickle=False) as z:
        d = {k: z[k] for k in z.files}
    d["meta"] = json.loads(str(d["meta"]))
    d["width"], d["height"] = int(d["width"]), int(d["height"])
    d["mirrored"] = bool(d["mirrored"])
    d["path"] = path
    return d


_NAME_RE = re.compile(r"^(?P<word>.+)_(?P<kind>[^_]+)_(?P<num>\d+)$")


def parse_take_name(path: Path) -> tuple[str, str, int] | None:
    """`단어_종류_번호.npz` → (단어, 종류, 번호)"""
    m = _NAME_RE.match(path.stem)
    if not m:
        return None
    return m["word"], m["kind"], int(m["num"])


def next_take_path(word: str, kind: str) -> Path:
    nums = [p[2] for f in config.TAKES_DIR.glob(f"{word}_{kind}_*.npz") if (p := parse_take_name(f))]
    return config.TAKES_DIR / f"{word}_{kind}_{max(nums, default=0) + 1:02d}.npz"


def list_takes() -> list[tuple[Path, str, str]]:
    out = []
    for f in sorted(config.TAKES_DIR.glob("*.npz")):
        p = parse_take_name(f)
        if p:
            out.append((f, p[0], p[1]))
    return out


def draw_landmarks(img: np.ndarray, fd: FrameData, color=(80, 220, 255)):
    """카메라 화면 위에 손 관절 점·선, 어깨선 표시 (M2-3)."""
    h, w = img.shape[:2]
    for k in range(2):
        if not fd.hand_ok[k]:
            continue
        pts = [(int(x * w), int(y * h)) for x, y, _ in fd.hands[k]]
        for a, b in HAND_EDGES:
            cv2.line(img, pts[a], pts[b], (255, 255, 255), 2, cv2.LINE_AA)
        for p in pts:
            cv2.circle(img, p, 4, color, -1, cv2.LINE_AA)
    if fd.pose_ok:
        ls = (int(fd.pose[P_LSH, 0] * w), int(fd.pose[P_LSH, 1] * h))
        rs = (int(fd.pose[P_RSH, 0] * w), int(fd.pose[P_RSH, 1] * h))
        cv2.line(img, ls, rs, (180, 180, 180), 2, cv2.LINE_AA)
        for p in (ls, rs):
            cv2.circle(img, p, 6, (180, 180, 180), -1, cv2.LINE_AA)
