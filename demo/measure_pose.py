"""PRD 10-8 테스트 3: Python 과 앱의 어깨 기준 차이 확인.

같은 사람·같은 자세로 이 프로그램과 앱의 "인식 테스트 → 손목 좌표 3초 측정"을 각각 실행해
정규화한 손목 좌표(어깨 가운데 원점, 어깨 너비 1)를 비교한다. 차이가 0.1(어깨 너비의 10%) 이내면 통과.

    python measure_pose.py        # 스페이스: 3초 측정, Q: 종료
"""
from __future__ import annotations

import time

import cv2
import numpy as np

import config
import ui
from landmarks import P_LSH, P_RSH, Extractor, draw_landmarks


def norm_wrists(fd, w, h):
    """앱 test_screen.dart _normWrists 와 같은 계산."""
    if not fd.pose_ok:
        return [None] * 4
    a = w / h
    l, r = fd.pose[P_LSH], fd.pose[P_RSH]
    cx, cy = (l[0] + r[0]) / 2 * a, (l[1] + r[1]) / 2
    sw = float(np.hypot((l[0] - r[0]) * a, l[1] - r[1]))
    out = [None] * 4
    for k in range(2):
        if not fd.hand_ok[k]:
            continue
        x, y = fd.hands[k, 0, 0] * a, fd.hands[k, 0, 1]
        slot = 0 if x < cx else 1
        out[slot * 2], out[slot * 2 + 1] = (x - cx) / sw, (y - cy) / sw
    return out


def main():
    cap = cv2.VideoCapture(config.CAMERA_INDEX, cv2.CAP_DSHOW)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, config.CAMERA_SIZE[0])
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, config.CAMERA_SIZE[1])
    ex = Extractor()
    text = ui.Text()
    win = "Handly 손목 좌표 측정 (10-8)"
    t0 = time.perf_counter()
    measuring, start, samples, result = False, 0.0, [], "스페이스: 3초 측정"
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame = cv2.flip(frame, 1) if config.MIRROR else frame
        now = time.perf_counter()
        fd = ex.process(frame, int((now - t0) * 1000))
        h, w = frame.shape[:2]
        cur = norm_wrists(fd, w, h)
        if measuring:
            samples.append(cur)
            if now - start >= 3:
                measuring = False
                arr = np.array([[np.nan if v is None else v for v in s] for s in samples], float)
                m = [np.nanmean(arr[:, i]) if np.isfinite(arr[:, i]).any() else None for i in range(4)]
                f = lambda v: "  -  " if v is None else f"{v:.3f}"  # noqa: E731
                result = f"화면 왼쪽 손목 ({f(m[0])}, {f(m[1])})   화면 오른쪽 손목 ({f(m[2])}, {f(m[3])})   프레임 {len(samples)}개"
                print(result)
        view = frame.copy()
        draw_landmarks(view, fd)
        canvas = ui.fit_image(view, 1280, 720)
        fmt = lambda v: "-" if v is None else f"{v:+.2f}"  # noqa: E731
        text.add(f"왼({fmt(cur[0])}, {fmt(cur[1])})  오({fmt(cur[2])}, {fmt(cur[3])})", (20, 20), 28, (255, 255, 255), True)
        text.add("측정 중..." if measuring else result, (20, 670), 24, (80, 220, 255), True)
        cv2.imshow(win, text.render(canvas))
        key = cv2.waitKey(1) & 0xFF
        if key in (ord("q"), 27):
            break
        if key == 32 and not measuring:
            measuring, start, samples = True, now, []
    cap.release()
    ex.close()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
