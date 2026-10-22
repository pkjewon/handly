"""M7-1 기준 동작 녹화 도구 (운영팀용).

웹캠으로 녹화:
    python recorder.py --word 감사하다 --kind 비교 --person 재원
    (스페이스: 3·2·1 후 녹화 → 자동 저장 / Backspace: 방금 저장한 테이크 삭제 / Q: 종료)

휴대폰 등으로 찍은 영상 파일에서 좌표 추출 (파일 하나 = 동작 한 번):
    python recorder.py --word 감사하다 --kind 비교 --person 민수 --files a.mp4 b.mp4

저장: data/takes/단어_종류_번호.npz   (종류: 안내 / 비교 / 다른사람 / 오답)
--save-video 를 주면 videos/단어_종류_번호.mp4 도 저장 (M1-3 실제 영상, M3 읽기 연습용)
"""
from __future__ import annotations

import argparse
import shutil
import sys
import time
from pathlib import Path

import cv2
import numpy as np

import config
import processing
import ui
from landmarks import Extractor, RawTake, draw_landmarks, next_take_path


def take_summary(take: RawTake) -> str:
    seq = processing.process(take.arrays())
    dur = take.t[-1] - take.t[0] if len(take) > 1 else 0
    fps = (len(take) - 1) / dur if dur > 0 else 0
    if seq.error:
        return f"{len(take)}프레임, {fps:.0f}fps — 어깨 인식 실패"
    pr = seq.presence_ratio()
    return f"{len(take)}프레임, {fps:.0f}fps, 손 있음 왼{pr[0]:.0%}/오{pr[1]:.0%}"


def from_files(args):
    ex = Extractor()
    for f in args.files:
        f = Path(f)
        cap = cv2.VideoCapture(str(f))
        if not cap.isOpened():
            print(f"[건너뜀] 열 수 없음: {f}")
            continue
        fps = cap.get(cv2.CAP_PROP_FPS) or 30
        w, h = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        take = RawTake(w, h, mirrored=not args.no_flip,
                       meta=dict(word=args.word, kind=args.kind, person=args.person, source=f.name, fps=fps))
        idx, offset = 0, ex._last_ts + 1
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            if not args.no_flip:
                frame = cv2.flip(frame, 1)
            t = idx / fps  # 실제 시간 위치 (60fps 영상도 10-3에서 30개/초로 맞춤)
            take.add(t, ex.process(frame, offset + int(t * 1000)))
            idx += 1
        cap.release()
        if len(take) < 2:
            print(f"[건너뜀] 프레임 없음: {f}")
            continue
        out = next_take_path(args.word, args.kind)
        take.save(out)
        if args.save_video:
            config.VIDEOS_DIR.mkdir(parents=True, exist_ok=True)
            shutil.copy(f, config.VIDEOS_DIR / f"{out.stem}{f.suffix.lower()}")
        print(f"[저장] {out.name}  ({take_summary(take)})  ← {f.name}")
    ex.close()


def from_webcam(args):
    cap = cv2.VideoCapture(config.CAMERA_INDEX, cv2.CAP_DSHOW)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, config.CAMERA_SIZE[0])
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, config.CAMERA_SIZE[1])
    if not cap.isOpened():
        sys.exit("웹캠을 열 수 없습니다.")
    ex = Extractor()
    win = "Handly 기준 동작 녹화"
    cv2.namedWindow(win, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(win, 1280, 720)
    text = ui.Text()

    state, t_state = "idle", 0.0
    take: RawTake | None = None
    frames_small: list[np.ndarray] = []
    saved: list[Path] = []
    msg = "스페이스를 누르면 3·2·1 후 녹화합니다"
    t0 = time.perf_counter()

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if config.MIRROR:
            frame = cv2.flip(frame, 1)
        now = time.perf_counter()
        fd = ex.process(frame, int((now - t0) * 1000))
        h, w = frame.shape[:2]

        if state == "countdown" and now - t_state >= config.COUNTDOWN_SEC:
            state, t_state = "record", now
            take = RawTake(w, h, config.MIRROR, meta=dict(word=args.word, kind=args.kind, person=args.person,
                                                          source="webcam"))
            frames_small = []
        if state == "record":
            take.add(now - t_state, fd)
            if args.save_video:
                frames_small.append(cv2.resize(frame, (w // 2, h // 2)))
            if now - t_state >= args.seconds:
                out = next_take_path(args.word, args.kind)
                take.save(out)
                saved.append(out)
                if args.save_video and len(frames_small) > 1:
                    fps = (len(take) - 1) / (take.t[-1] - take.t[0])
                    config.VIDEOS_DIR.mkdir(parents=True, exist_ok=True)
                    vw = cv2.VideoWriter(str(config.VIDEOS_DIR / f"{out.stem}.mp4"),
                                         cv2.VideoWriter_fourcc(*"mp4v"), fps, (w // 2, h // 2))
                    for f in frames_small:
                        vw.write(f)
                    vw.release()
                msg = f"저장: {out.name}  ({take_summary(take)})"
                print(msg)
                state = "idle"

        view = frame.copy()
        draw_landmarks(view, fd)
        canvas = ui.fit_image(view, 1280, 720)
        border = {"idle": ui.GRAY, "countdown": ui.ORANGE, "record": ui.RED}[state]
        cv2.rectangle(canvas, (0, 0), (1279, 719), border, 10)
        cv2.rectangle(canvas, (0, 0), (1280, 56), (30, 30, 30), -1)
        text.add(f"단어: {args.word}   종류: {args.kind}   촬영자: {args.person or '-'}   "
                 f"다음 파일: {next_take_path(args.word, args.kind).name}   이번에 저장: {len(saved)}개",
                 (20, 14), 22, (255, 255, 255))
        if state == "countdown":
            n = config.COUNTDOWN_SEC - int(now - t_state)
            text.add(str(n), (640, 360), 160, (255, 255, 255), True, "mm")
        elif state == "record":
            text.add(f"● 녹화 중 {now - t_state:.1f} / {args.seconds:.1f}초", (640, 90), 30, ui.RED, True, "ma")
        if not fd.pose_ok:
            text.add("어깨까지 화면에 나오게 서 주세요", (640, 640), 26, (80, 200, 255), True, "ma")
        text.add(msg, (20, 680), 22, (255, 255, 255))
        text.add("[스페이스] 녹화  [Backspace] 방금 테이크 삭제  [Q] 종료", (1260, 680), 20, (200, 200, 200), anchor="ra")
        cv2.imshow(win, text.render(canvas))

        key = cv2.waitKey(1) & 0xFF
        if key in (ord("q"), 27) or cv2.getWindowProperty(win, cv2.WND_PROP_VISIBLE) < 1:
            break
        if key == 32 and state == "idle":
            state, t_state = "countdown", now
        if key == 8 and state == "idle" and saved:
            last = saved.pop()
            last.unlink(missing_ok=True)
            (config.VIDEOS_DIR / f"{last.stem}.mp4").unlink(missing_ok=True)
            msg = f"삭제: {last.name}"

    cap.release()
    ex.close()
    cv2.destroyAllWindows()


def main():
    ap = argparse.ArgumentParser(description="Handly 기준 동작 녹화 (M7-1)")
    ap.add_argument("--word", required=True, help="단어 이름 (오답 동작은 아무 이름, 예: 없음)")
    ap.add_argument("--kind", required=True, choices=config.KINDS)
    ap.add_argument("--person", default="", help="촬영자 이름 (모델 학습 때 사람 기준으로 나누는 데 씀)")
    ap.add_argument("--seconds", type=float, default=config.RECORD_SEC + 0.5)
    ap.add_argument("--save-video", action="store_true", help="실제 영상도 videos/에 저장")
    ap.add_argument("--files", nargs="+", help="웹캠 대신 영상 파일에서 추출")
    ap.add_argument("--no-flip", action="store_true", help="영상 파일이 이미 거울 모드(좌우 반전)로 찍힌 경우")
    args = ap.parse_args()
    config.TAKES_DIR.mkdir(parents=True, exist_ok=True)
    if args.files:
        from_files(args)
    else:
        from_webcam(args)


if __name__ == "__main__":
    main()
