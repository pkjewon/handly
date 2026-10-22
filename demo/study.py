"""Handly 시연 프로그램 (PRD 13장 1단계 + 1+ 단계).

    python study.py

따라 하기 (M1-1·M1-2·M1-3·M1-6, M2 전체, M4-3)
  왼쪽: 단어 카드 + 입체 손 안내 / 실제 영상     오른쪽: 웹캠 + 손 관절, 3·2·1 녹화, DTW 판정
읽기 연습 (M3-1, M3-4)
  다른 사람의 수어를 보고 뜻 고르기

키: [스페이스] 따라 하기 시작  [←][→] 이전·다음 단어  [V] 실제 영상 ↔ 입체 손  [S] 속도
    [R] 읽기 연습 ↔ 따라 하기  [1~4] 보기 고르기  [N] 다음 문제  [Q] 종료   (버튼은 마우스로도 누를 수 있음)
"""
from __future__ import annotations

import json
import random
import sys
import time

import cv2
import numpy as np

import config
import dtw
import processing
import ui
from landmarks import Extractor, RawTake, draw_landmarks

W, H = 1280, 760
LEFT = (20, 84, 400, 656)      # x, y, w, h
CAM = (440, 84, 820, 461)
GUIDE = (40, 170, 360, 270)
SPEEDS = [1.0, 0.75, 0.5]
KEY_LEFT, KEY_RIGHT = 2424832, 2555904


class App:
    def __init__(self):
        data = json.loads(config.WORDS_FILE.read_text(encoding="utf-8"))
        self.lesson = data.get("lesson", "")
        self.cards = data["words"]
        self.names = [c["name"] for c in self.cards]
        print("기준 동작 불러오는 중...")
        self.lib = dtw.Library(self.names)
        for name, why in self.lib.skipped:
            print(f"  [제외] {name}: {why}")
        for w in self.names:
            n = len(self.lib.refs.get(w, []))
            print(f"  {w}: 기준 테이크 {n}개, 기준값 {self.lib.threshold(w):.3f}")
        if not config.THRESHOLDS_FILE.exists():
            print("  ※ 기준값 파일이 없어 기본값을 씁니다. calibrate.py --save 로 정하세요 (M2-8).")

        self.guides = {w: ui.GuidePlayer(t.seq if (t := self.lib.guide_take(w)) else None) for w in self.names}
        self.idx = 0
        self.done: set[str] = set()
        self.mode = "follow"
        self.speed_i = 0
        self.show_video = False
        self.video: ui.VideoPlayer | None = None

        self.state, self.t_state = "idle", 0.0
        self.take: RawTake | None = None
        self.result: dtw.Judgement | None = None

        self.quiz = None
        self.quiz_score = [0, 0]

        self.buttons: list[tuple[tuple[int, int, int, int], callable]] = []
        self.text = ui.Text()

        self.cap = cv2.VideoCapture(config.CAMERA_INDEX, cv2.CAP_DSHOW)
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, config.CAMERA_SIZE[0])
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, config.CAMERA_SIZE[1])
        if not self.cap.isOpened():
            sys.exit("웹캠을 열 수 없습니다.")
        self.ex = Extractor(pose_every=2)
        self.t0 = time.perf_counter()
        self.last_frame = None
        self.last_fd = None

    # ------------------------------------------------------------ 공통

    @property
    def word(self) -> str:
        return self.names[self.idx]

    @property
    def speed(self) -> float:
        return SPEEDS[self.speed_i]

    def go(self, step: int):
        self.idx = (self.idx + step) % len(self.names)
        self.reset_follow()

    def reset_follow(self):
        self.state, self.result = "idle", None
        self.set_video(self.show_video)
        self.guides[self.word].restart()

    def set_video(self, on: bool):
        if self.video:
            self.video.close()
            self.video = None
        self.show_video = False
        if on:
            vids = ui.find_videos(self.word)
            if vids:
                self.video = ui.VideoPlayer(vids[0])
                self.video.speed = self.speed
                self.show_video = self.video.ok

    def cycle_speed(self):
        self.speed_i = (self.speed_i + 1) % len(SPEEDS)
        for g in self.guides.values():
            g.speed = self.speed
        if self.video:
            self.video.speed = self.speed
            self.video.restart()
        if self.quiz:
            self.quiz["player"].speed = self.speed
            self.quiz["player"].restart()

    def toggle_mode(self):
        if self.mode == "follow":
            self.mode = "read"
            self.new_question()
        else:
            self.mode = "follow"
            self.close_quiz()
            self.reset_follow()

    def button(self, canvas, rect, label, action, color=ui.INK, fill=(240, 237, 233), size=20):
        x, y, w, h = rect
        ui.rounded_rect(canvas, x, y, w, h, fill, r=10)
        self.text.add(label, (x + w // 2, y + h // 2), size, color, True, "mm")
        self.buttons.append((rect, action))

    def on_mouse(self, event, x, y, *_):
        if event != cv2.EVENT_LBUTTONDOWN:
            return
        for (bx, by, bw, bh), action in self.buttons:
            if bx <= x <= bx + bw and by <= y <= by + bh:
                action()
                break

    # ------------------------------------------------------------ 따라 하기 (M2)

    def start_record(self):
        if self.mode == "follow" and self.state in ("idle", "result"):
            self.state, self.t_state, self.result = "countdown", time.perf_counter(), None

    def update_follow(self, frame, fd, now):
        h, w = frame.shape[:2]
        if self.state == "countdown" and now - self.t_state >= config.COUNTDOWN_SEC:
            self.state, self.t_state = "record", now
            self.take = RawTake(w, h, config.MIRROR, meta=dict(word=self.word, kind="학습자"))
        elif self.state == "record":
            self.take.add(now - self.t_state, fd)
            if now - self.t_state >= config.RECORD_SEC:
                self.state = "judging"
        elif self.state == "judging":
            seq = processing.process(self.take.arrays())
            self.result = self.lib.judge(seq, self.word)
            if self.result.status == "correct":
                self.done.add(self.word)
            d = self.result.distances
            print(f"[{self.word}] {self.result.status}  목표 거리 {self.result.target_dist}  "
                  + "  ".join(f"{k}:{v:.3f}" for k, v in d.items()))
            self.state = "result"

    def draw_follow(self, canvas, frame, fd, now):
        card = self.cards[self.idx]
        x, y, w, h = LEFT
        ui.rounded_rect(canvas, x, y, w, h, ui.PANEL)
        self.text.add(card["name"], (40, 98), 40, ui.INK, True)
        self.text.add(card.get("meaning", ""), (42, 146), 18, ui.SUB)

        gx, gy, gw, gh = GUIDE
        if self.show_video and self.video:
            f = self.video.read()
            box = ui.fit_image(f, gw, gh) if f is not None else np.zeros((gh, gw, 3), np.uint8)
            label = "실제 영상"
        else:
            g = self.guides[self.word]
            box = g.render(gw, gh)
            label = "입체 손 안내"
            if g.seq is None:
                self.text.add("기준 동작이 아직 없어요", (gx + gw // 2, gy + gh // 2 - 14), 20, ui.SUB, True, "mm")
                self.text.add("recorder.py로 녹화하세요", (gx + gw // 2, gy + gh // 2 + 16), 16, ui.SUB, False, "mm")
        canvas[gy:gy + gh, gx:gx + gw] = box
        cv2.rectangle(canvas, (gx, gy), (gx + gw, gy + gh), ui.LINE, 1)
        self.text.add(label, (gx, gy + gh + 8), 15, ui.SUB)

        has_video = bool(ui.find_videos(self.word))
        vlabel = "입체 손 보기" if self.show_video else "▶ 실제 영상 보기"
        self.button(canvas, (gx + gw - 150, gy + gh + 6, 150, 30), vlabel,
                    lambda: self.set_video(not self.show_video), ui.INK if has_video else ui.GRAY, size=15)
        self.button(canvas, (gx + gw - 230, gy + gh + 6, 72, 30), f"{self.speed}배", self.cycle_speed, size=15)

        ty = 490
        for label, key in (("손 모양", "shape"), ("위치", "position"), ("움직임", "movement")):
            self.text.add(label, (42, ty), 16, ui.SUB, True)
            for line in ui.wrap(card.get(key, ""), 17, 280):
                self.text.add(line, (110, ty), 17, ui.INK)
                ty += 26
            ty += 8

        # M4-3 진행 표시
        n = len(self.names)
        cx0 = x + w // 2 - (n - 1) * 15
        for i, name in enumerate(self.names):
            c = (cx0 + i * 30, 708)
            if name in self.done:
                cv2.circle(canvas, c, 9, ui.GREEN, -1, cv2.LINE_AA)
            else:
                cv2.circle(canvas, c, 9, ui.INK if i == self.idx else ui.LINE, 2, cv2.LINE_AA)
            if i == self.idx:
                cv2.circle(canvas, (c[0], c[1] + 18), 3, ui.INK, -1, cv2.LINE_AA)
        self.button(canvas, (x + 16, 692, 70, 34), "◀ 이전", lambda: self.go(-1), size=15)
        self.button(canvas, (x + w - 86, 692, 70, 34), "다음 ▶", lambda: self.go(1), size=15)

        # 오른쪽: 웹캠 (M2-3 손 관절 표시)
        view = frame.copy()
        draw_landmarks(view, fd)
        cx, cy, cw, ch = CAM
        canvas[cy:cy + ch, cx:cx + cw] = ui.fit_image(view, cw, ch)
        status = self.result.status if (self.state == "result" and self.result) else "idle"
        color = {"correct": ui.GREEN, "wrong": ui.RED, "fail": ui.RED}.get(status, ui.GRAY)
        if self.state == "record":
            color = ui.ORANGE
        cv2.rectangle(canvas, (cx - 4, cy - 4), (cx + cw + 4, cy + ch + 4), color, 8)

        if self.state == "countdown":
            k = config.COUNTDOWN_SEC - int(now - self.t_state)
            self.text.add(str(k), (cx + cw // 2, cy + ch // 2), 170, (255, 255, 255), True, "mm")
        elif self.state == "record":
            self.text.add(f"● 녹화 중  {now - self.t_state:.1f}초", (cx + 20, cy + 16), 24, (255, 255, 255), True)
        elif self.state == "judging":
            self.text.add("판정 중...", (cx + cw // 2, cy + ch // 2), 40, (255, 255, 255), True, "mm")
        if not fd.pose_ok and self.state in ("idle", "countdown", "record"):
            self.text.add("어깨까지 화면에 나오게 해 주세요", (cx + cw // 2, cy + ch - 40), 22, (80, 200, 255), True, "ma")

        # 결과 (M2-6, M2-7)
        bx, by, bw, bh = cx, cy + ch + 16, cw, H - (cy + ch + 16) - 20
        ui.rounded_rect(canvas, bx, by, bw, bh, ui.PANEL)
        if self.state == "result" and self.result:
            r = self.result
            mark = "○ 정답" if r.status == "correct" else ("× 인식 실패" if r.status == "fail" else "× 오답")
            self.text.add(f"{mark}  {r.message}", (bx + 24, by + 18), 30, color, True)
            for i, hint in enumerate(r.hints[:3]):
                self.text.add(f"· {hint}", (bx + 28, by + 66 + i * 28), 19, ui.INK)
            if r.target_dist is not None:
                self.text.add(f"거리 {r.target_dist:.3f} / 기준값 {r.threshold:.3f}", (bx + bw - 20, by + 24), 14,
                              ui.SUB, anchor="ra")
            self.button(canvas, (bx + bw - 170, by + bh - 50, 150, 36), "다시 하기", self.start_record, size=17)
            if r.status == "correct":
                self.button(canvas, (bx + bw - 330, by + bh - 50, 150, 36), "다음 단어 ▶", lambda: self.go(1),
                            (255, 255, 255), ui.GREEN, 17)
        elif self.state == "idle":
            self.text.add("왼쪽 안내를 보고 준비되면 시작하세요", (bx + 24, by + 22), 24, ui.INK, True)
            self.text.add("3·2·1 후 약 3~4초 동안 동작을 기록합니다. 머리부터 허리까지 화면에 나오게 서 주세요.",
                          (bx + 24, by + 62), 16, ui.SUB)
            self.button(canvas, (bx + bw - 190, by + bh - 54, 170, 40), "따라 하기 시작", self.start_record,
                        (255, 255, 255), ui.INK, 18)
        else:
            self.text.add("동작을 해 보세요", (bx + 24, by + 22), 24, ui.SUB, True)

    # ------------------------------------------------------------ 읽기 연습 (M3-1)

    def close_quiz(self):
        if self.quiz and isinstance(self.quiz["player"], ui.VideoPlayer):
            self.quiz["player"].close()
        self.quiz = None

    def _quiz_source(self, word):
        """다른 사람 영상 → 실제 영상 → 다른 사람·비교 테이크의 입체 손 순으로 문제 소스를 고름."""
        vids = ui.find_videos(word)
        others = [v for v in vids if config.KIND_OTHER in v.stem]
        pick = random.choice(others or vids) if vids else None
        if pick:
            p = ui.VideoPlayer(pick)
            if p.ok:
                return p
        takes = [t for t in self.lib.refs.get(word, []) if t.kind != config.KIND_GUIDE] or self.lib.refs.get(word, [])
        if takes:
            return ui.GuidePlayer(random.choice(takes).seq)
        return None

    def new_question(self):
        self.close_quiz()
        pool = [w for w in self.names if ui.find_videos(w) or self.lib.refs.get(w)]
        if not pool:
            self.quiz = {"player": None, "answer": None, "choices": [], "picked": None}
            return
        answer = random.choice(pool)
        others = random.sample([w for w in self.names if w != answer], min(3, len(self.names) - 1))
        choices = others + [answer]
        random.shuffle(choices)
        player = self._quiz_source(answer)
        if player is not None:
            player.speed = self.speed
        self.quiz = {"player": player, "answer": answer, "choices": choices, "picked": None}

    def pick(self, i):
        q = self.quiz
        if not q or q["picked"] is not None or i >= len(q["choices"]):
            return
        q["picked"] = i
        self.quiz_score[1] += 1
        if q["choices"][i] == q["answer"]:
            self.quiz_score[0] += 1

    def draw_read(self, canvas):
        x, y, w, h = LEFT
        ui.rounded_rect(canvas, x, y, w, h, ui.PANEL)
        self.text.add("읽기 연습", (40, 98), 40, ui.INK, True)
        self.text.add("다른 사람의 수어를 보고", (42, 160), 20, ui.INK)
        self.text.add("무슨 뜻인지 골라 보세요", (42, 190), 20, ui.INK)
        self.text.add(f"맞힌 문제  {self.quiz_score[0]} / {self.quiz_score[1]}", (42, 250), 22, ui.INK, True)
        self.text.add(f"재생 속도  {self.speed}배", (42, 296), 18, ui.SUB)
        self.text.add("천천히(0.5배) → 보통 속도로 올려 가며 연습하세요", (42, 324), 15, ui.SUB)
        self.button(canvas, (40, 360, 120, 36), "속도 바꾸기", self.cycle_speed, size=16)
        self.button(canvas, (40, 640, 360, 44), "따라 하기로 돌아가기", self.toggle_mode, size=18)

        q = self.quiz
        cx, cy, cw, ch = CAM
        if not q or q["player"] is None:
            ui.rounded_rect(canvas, cx, cy, cw, ch, ui.PANEL)
            self.text.add("문제로 쓸 영상이나 기준 동작이 없어요", (cx + cw // 2, cy + ch // 2), 24, ui.SUB, True, "mm")
            return
        p = q["player"]
        if isinstance(p, ui.VideoPlayer):
            f = p.read()
            box = ui.fit_image(f, cw, ch) if f is not None else np.zeros((ch, cw, 3), np.uint8)
        else:
            box = p.render(cw, ch)
        canvas[cy:cy + ch, cx:cx + cw] = box

        picked = q["picked"]
        n = len(q["choices"])
        bw = (cw - (n - 1) * 12) // n
        for i, c in enumerate(q["choices"]):
            fill, col = (240, 237, 233), ui.INK
            if picked is not None and c == q["answer"]:
                fill, col = ui.GREEN, (255, 255, 255)
            elif picked == i:
                fill, col = ui.RED, (255, 255, 255)
            self.button(canvas, (cx + i * (bw + 12), cy + ch + 20, bw, 64), f"{i + 1}. {c}",
                        lambda i=i: self.pick(i), col, fill, 22)
        if picked is not None:
            ok = q["choices"][picked] == q["answer"]
            msg = "정답이에요!" if ok else f"아쉬워요. 정답은 '{q['answer']}'"
            self.text.add(msg, (cx, cy + ch + 108), 26, ui.GREEN if ok else ui.RED, True)
            self.button(canvas, (cx + cw - 170, cy + ch + 100, 170, 44), "다음 문제 ▶", self.new_question,
                        (255, 255, 255), ui.INK, 18)

    # ------------------------------------------------------------ 루프

    def run(self):
        win = "Handly"
        cv2.namedWindow(win, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(win, W, H)
        cv2.setMouseCallback(win, self.on_mouse)
        while True:
            now = time.perf_counter()
            canvas = np.full((H, W, 3), ui.BG, np.uint8)
            self.buttons = []

            # 헤더
            cv2.rectangle(canvas, (0, 0), (W, 64), ui.PANEL, -1)
            cv2.line(canvas, (0, 64), (W, 64), ui.LINE, 1)
            self.text.add("Handly", (20, 14), 28, ui.INK, True)
            title = "수어 따라 하기" if self.mode == "follow" else "읽기 연습"
            self.text.add(f"{self.lesson} · {title}" if self.lesson else title, (140, 20), 22, ui.INK)
            if self.mode == "follow":
                self.text.add(f"{self.idx + 1} / {len(self.names)}", (W - 190, 18), 24, ui.INK, True, "ra")
                self.button(canvas, (W - 160, 14, 140, 36), "읽기 연습", self.toggle_mode, size=17)
            self.text.add("[스페이스] 시작  [←→] 단어  [V] 영상  [S] 속도  [R] 읽기 연습  [Q] 종료",
                          (W // 2 + 60, 744), 13, ui.SUB, anchor="mm")

            if self.mode == "follow":
                ok, frame = self.cap.read()
                if not ok:
                    print("웹캠 프레임을 읽을 수 없습니다.")
                    break
                if config.MIRROR:
                    frame = cv2.flip(frame, 1)
                fd = self.ex.process(frame, int((now - self.t0) * 1000))
                self.update_follow(frame, fd, now)
                self.draw_follow(canvas, frame, fd, now)
            else:
                self.draw_read(canvas)

            cv2.imshow(win, self.text.render(canvas))
            key = cv2.waitKeyEx(1)
            if key in (ord("q"), ord("Q"), 27) or cv2.getWindowProperty(win, cv2.WND_PROP_VISIBLE) < 1:
                break
            if key == -1:
                continue
            ch = chr(key).lower() if 0 <= key < 256 else ""
            if ch == "r":
                self.toggle_mode()
            elif ch == "s":
                self.cycle_speed()
            elif self.mode == "follow":
                if key == 32:
                    self.start_record()
                elif key == KEY_LEFT or ch == "a":
                    self.go(-1)
                elif key == KEY_RIGHT or ch == "d":
                    self.go(1)
                elif ch == "v":
                    self.set_video(not self.show_video)
            else:
                if ch in "1234" and ch:
                    self.pick(int(ch) - 1)
                elif ch == "n" or key == 32:
                    self.new_question()

        self.close_quiz()
        self.set_video(False)
        self.cap.release()
        self.ex.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    App().run()
