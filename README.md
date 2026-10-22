# Handly — 카메라 인식 수어 학습

> 저장소 위치: `D:\dev\handly`

PRD: [docs/Handly_PRD_v2.2.md](docs/Handly_PRD_v2.2.md) · 진행 상황과 할 일: [docs/진행상황.md](docs/진행상황.md)

| 폴더 | 내용 | PRD |
|---|---|---|
| `demo/` | Python 시연 프로그램 (DTW 판정) | 13장 1단계 + 1+ 단계 |
| `ml/` | LSTM/GRU 데이터셋·학습 코드 (Colab) | 10-4, 13장 병행 단계 |
| `app/` | Flutter 앱: 판정 엔진(`handly_core`) + 안드로이드 앱(`handly_app`). 자세한 내용은 [app/README.md](app/README.md) | 10-8, 13장 2단계 |
| `dist/` | 폰에 설치할 APK (git 제외) | |
| `data/` | 촬영 목록·라벨 | 10-7 |
| `docs/` | PRD, 회의록 | 10-7 |

## 시연 프로그램 실행

```powershell
cd demo
pip install -r requirements.txt     # mediapipe, opencv-python, numpy, pillow, matplotlib
```

모델 파일 2개는 `demo/models/`에 넣습니다 (저장소에는 올리지 않음):

```powershell
curl.exe -L -o models/hand_landmarker.task https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
curl.exe -L -o models/pose_landmarker.task https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task
```

### 1) 기준 동작 녹화 (M7-1, 운영팀)

```powershell
python recorder.py --word 감사하다 --kind 안내 --person 재원 --save-video   # 입체 손 안내 + 실제 영상용 3~5회
python recorder.py --word 감사하다 --kind 비교 --person 재원                # 판정 기준용 약 15회 (촬영 조건 섞기, 11-1)
python recorder.py --word 감사하다 --kind 다른사람 --person 민수            # 다른 사람 약 5회
python recorder.py --word 가만히 --kind 오답 --person 재원                  # 오답 동작 (M2-5a): 가만히, 손 흔들기, 다른 단어 섞기 등
python recorder.py --word 감사하다 --kind 비교 --person 재원 --files a.mp4 b.mp4   # 휴대폰 영상(60fps도 가능)
```

- 저장 위치: `demo/data/takes/단어_종류_번호.npz` (종류: 안내 / 비교 / 다른사람 / 오답)
- 스페이스 → 3·2·1 → 약 4초 녹화 → 자동 저장, Backspace → 방금 테이크 삭제
- 웹캠은 거울 모드(좌우 반전)로 처리합니다. 휴대폰 영상이 이미 거울 모드로 찍혔다면 `--no-flip`
- 머리부터 허리까지 나오게 서야 어깨 기준점이 잡힙니다.

### 2) 기준값 정하기 (M2-8)

```powershell
python calibrate.py            # 단어별 정답·오답 거리 분포, 추천 기준값, 그래프(data/calibration.png)
python calibrate.py --save     # 추천 기준값 저장 → data/thresholds.json
python calibrate.py --set 감사하다=0.42   # 직접 조정
```

"오답이 모두 기준값보다 먼가: 아니오 ⚠"가 나오면 엉뚱한 동작이 정답 처리될 수 있습니다 (M2-5a).
촬영을 더 하거나 기준값을 낮추세요.

### 3) 시연 (study.py)

```powershell
python study.py
```

| 키 | 동작 |
|---|---|
| 스페이스 | 3·2·1 후 따라 하기 녹화 → 판정 |
| ← → | 이전·다음 단어 |
| V | 입체 손 안내 ↔ 실제 영상 (`demo/videos/단어*.mp4`) |
| S | 속도 1 / 0.75 / 0.5배 |
| R | 읽기 연습 ↔ 따라 하기 |
| 1~4, N | (읽기 연습) 보기 고르기, 다음 문제 |
| Q | 종료 |

버튼은 마우스로도 누를 수 있습니다.

### 구현한 PRD 항목

| 항목 | 구현 |
|---|---|
| M1-1 단어 카드 | `words.json` (동작 설명은 예시 — 감수 후 고쳐 주세요) |
| M1-2 입체 손 안내 | 안내 테이크의 기준 좌표로 두 손 + 흐린 머리·어깨 선 반복 재생, 깊이(z)에 따라 굵기·밝기 |
| M1-3 실제 영상 | `--save-video`로 저장한 영상 또는 `videos/`에 넣은 영상 |
| M1-6 속도 조절 | 0.5 / 0.75 / 1배 |
| M2-1~3 | 두 손 + 어깨 인식, 어깨 기준 정규화, 손 관절 표시 |
| M2-4 | 3·2·1 카운트다운 후 3.5초 녹화 (`config.RECORD_SEC`) |
| M2-5 / M2-5a | DTW 거리: 목표 단어 거리 ≤ 기준값 **그리고** 목표 단어가 가장 가까움 → 정답 |
| M2-6 | 대기 회색 / 녹화 주황 / 정답 초록 / 오답·인식 실패 빨강 |
| M2-7 힌트 | DTW가 짝지은 프레임의 손목 높이·바깥쪽 차이, 동작 시간 비율, 손 없음 |
| M2-8 | `calibrate.py` |
| M3-1, M3-4 | 읽기 연습: 다른사람 영상 → 실제 영상 → 다른사람·비교 테이크의 입체 손 순으로 문제, 속도 조절 |
| M4-3 | 1/3 표시, 완료 점(초록), 이전·다음 |
| M7-1 | `recorder.py` (웹캠·영상 파일) |
| 10-3 | `processing.py`: 왼/오손 다시 정하기, 0.2초 이하 끊김 보간, 어깨 정규화, 1초당 30개 재샘플링 |

숫자 규칙(끊김 0.2초, 손 없음 50%, 힌트 기준 등)은 모두 `demo/config.py`에 모여 있습니다.

## 모델 (병행, Colab)

```powershell
python ml/build_dataset.py --out "<Google Drive>/handly/dataset.npz"   # 10-3 규칙 그대로 적용
```

Colab에서 `ml/train.py` 실행 → LSTM·GRU 정확도·속도 비교, 단어별 확률 기준, ONNX 내보내기 (파일 맨 위 설명 참고).
테스트 세트는 촬영자 기준으로 나뉘므로 `recorder.py --person`을 꼭 적어 주세요.
