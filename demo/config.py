"""Handly 시연 프로그램 공통 설정 (PRD v2.2 10-3, M2 규칙의 숫자들)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MODEL_DIR = ROOT / "models"
HAND_MODEL = MODEL_DIR / "hand_landmarker.task"
POSE_MODEL = MODEL_DIR / "pose_landmarker.task"
TAKES_DIR = ROOT / "data" / "takes"          # 녹화한 좌표 파일 (단어_종류_번호.npz)
VIDEOS_DIR = ROOT / "videos"                  # 실제 영상 (M1-3/M1-4, M3-1)
WORDS_FILE = ROOT / "words.json"              # 단어 카드 (M1-1)
THRESHOLDS_FILE = ROOT / "data" / "thresholds.json"  # 단어별 DTW 기준값 (M2-8)
FONT_PATH = "C:/Windows/Fonts/malgun.ttf"
FONT_BOLD_PATH = "C:/Windows/Fonts/malgunbd.ttf"

# 촬영 종류 (파일 이름의 "종류" 부분, PRD 11-1)
KIND_GUIDE = "안내"      # 안내용: 입체 손 안내(M1-2)
KIND_REF = "비교"        # 비교용: 판정 기준
KIND_OTHER = "다른사람"  # 다른 사람
KIND_WRONG = "오답"      # 오답 동작 (M2-5a)
KINDS = [KIND_GUIDE, KIND_REF, KIND_OTHER, KIND_WRONG]
REFERENCE_KINDS = {KIND_GUIDE, KIND_REF, KIND_OTHER}

# 카메라 / 녹화
CAMERA_INDEX = 0
CAMERA_SIZE = (1280, 720)
MIRROR = True            # 기준 녹화와 학습자 화면 모두 좌우 반전 (10-3)
COUNTDOWN_SEC = 3
RECORD_SEC = 3.5         # M2-4: 약 3~4초 [추정]

# 10-3 좌표 처리 규칙
TARGET_FPS = 30          # 1초당 30개로 다시 샘플링
SHORT_GAP_SEC = 0.2      # 이 이하로 끊긴 손은 선형 보간
HAND_USED_RATIO = 0.5    # 기준 동작에서 이 비율 이상 나온 손만 "쓰는 손"
NO_HAND_FAIL_RATIO = 0.5 # 녹화 구간 절반 이상 손 없음 → 인식 실패
MISSING_HAND_RATIO = 0.4 # 두 손 단어에서 한 손이 이 비율 이상 없음 → 판정 안 함
ABSENT_PENALTY = 1.0     # 한쪽만 손이 있을 때 프레임 거리 (어깨 너비 단위)

# M2-5 판정
TOP_K = 3                # 단어까지 거리 = 기준 테이크 중 가까운 K개의 평균
DEFAULT_THRESHOLD = 0.35 # 기준값 조정(M2-8) 전 기본값 [추정]

# M2-7 힌트
HINT_POS_DIFF = 0.25     # 손목 평균 위치 차이 (어깨 너비 단위)
HINT_FAST_RATIO = 0.6
HINT_SLOW_RATIO = 1.6
