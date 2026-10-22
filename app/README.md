# Handly 앱 (Flutter, PRD 13장 2단계)

```
app/
├─ handly_core/   판정 엔진 (순수 Dart): 좌표 처리 10-3, DTW 판정 M2-5, 힌트 M2-7
│                 demo/의 Python 과 같은 결과를 내는지 정답 데이터로 테스트함
└─ handly_app/    안드로이드 앱
   ├─ lib/theme.dart             디자인 토큰·아이콘 (handly-app-mockup.html 그대로)
   ├─ lib/recognizer.dart        카메라 → 손(hand_landmarker) + 어깨(ML Kit) → 좌표
   ├─ lib/judge_worker.dart      판정을 별도 Isolate 에서 실행
   ├─ lib/auto_judge.dart        게임용 자동 판정 (최근 3.5초를 0.6초마다)
   ├─ lib/store.dart             학습 기록 (연속 학습일·별·단어별 정답률·복습·배지, 폰 안에 저장)
   ├─ lib/screens/home_tab        01 홈
   ├─ lib/screens/lesson_screen   02 학습 · 카메라 촬영 (M1-1·M1-2·M2·M4-3)
   ├─ lib/screens/arcade_tab      03 아케이드 허브
   ├─ lib/screens/falling_game    04 수어 낙하
   ├─ lib/screens/match_game      05 단어 맞추기
   ├─ lib/screens/review_tab      06 복습노트 (M4-5)
   ├─ lib/screens/learn_tab       학습 탭: 단원·단어 목록 (목업에 없어서 같은 스타일로)
   ├─ lib/screens/profile_tab     내정보: 기록·배지(M4-4)·설정·개인정보 안내(M8-1)
   ├─ lib/screens/read_screen     읽기 연습 (M3-1, M3-4)
   ├─ lib/screens/test_screen     인식 테스트 (10-8, 내정보 → 개발용)
   └─ assets/handly_refs.json    단어 카드·기준값·기준 좌표 (demo/export_app_assets.py 가 만듦)
```

## 현재 상태 (2026-10-06)

| 항목 | 상태 |
|---|---|
| 개발 환경 | Flutter 3.47.6 (`C:\dev\flutter`), JDK 21 (Android Studio 내장), Android SDK + Command-line Tools + NDK 28.2 — `flutter doctor` Android 항목 모두 ✓ |
| 판정 엔진 이식 | Python ↔ Dart 정답 데이터 테스트 21개 통과 (좌표·DTW 거리·판정·힌트 문구 일치) |
| 빌드 | debug / release APK 빌드 성공. 폰용: `dist/Handly-test-arm64.apk` |
| 에뮬레이터 (Pixel_8, 노트북 웹캠) | 앱 실행·화면·판정 흐름 확인 |
| 10-8 테스트 1 (손·어깨 동시 실행) | 둘 다 동작 확인. **사람이 화면에 있을 때 점이 손 위에 맞게 그려지는지는 아직 확인 안 함** |
| 10-8 테스트 2 (속도) | 에뮬레이터 release(CPU): 손 31fps · 어깨 10.5fps · 카메라 30fps → 기준 15fps 통과. **실제 폰 미확인** |
| 10-8 테스트 3 (Python 과 차이) | 측정 기능 준비됨 (앱 "손목 좌표 3초 측정" ↔ `demo/measure_pose.py`). **미측정** |
| 에뮬레이터 GPU | MediaPipe GPU 가속 오류(`GL_INVALID_ENUM`) → 손 결과가 안 오면 자동으로 CPU 전환하게 함 |
| Firebase (계정·기록) | 아직 연결 안 함 (아래 6번, 사용자 Google 로그인 필요) |

## 개발할 때 쓰는 명령

```powershell
cd D:\dev\handly\app\handly_core
dart test                                   # 판정 엔진이 Python 과 같은지 확인

cd D:\dev\handly\app\handly_app
flutter run                                 # 에뮬레이터 또는 연결된 폰에서 실행
flutter run --release                       # 속도 측정은 반드시 release
flutter build apk --release --split-per-abi # 폰에 보낼 APK (arm64-v8a 사용)
```

기준 동작을 다시 녹화하거나 기준값을 바꾸면:

```powershell
cd D:\dev\handly\demo
python calibrate.py --save
python export_app_assets.py     # 앱 assets + 정답 데이터 갱신
cd ..\app\handly_core; dart test
```

## 알아둘 것

- **한글 경로**: 안드로이드 빌드는 경로에 한글이 있으면 실패하는 경우가 많아 저장소를 `D:\dev\handly`로 옮김
- **다른 드라이브**: pub 캐시(C:)와 프로젝트(D:)가 달라 Kotlin 증분 컴파일이 실패 → `android/gradle.properties`에 `kotlin.incremental=false`
- **release 빌드**: 코드 축소(R8)가 WorkManager·MediaPipe 클래스를 지워 시작하자마자 꺼짐 → `android/app/proguard-rules.pro`
- **좌표 방향**: 두 패키지 모두 "바로 세운 영상" 기준 좌표를 줌. 앞 카메라는 앱에서 x를 뒤집어 시연 프로그램(거울 모드)과 맞춤.
  오른손만 들었을 때 인식 테스트 화면에서 "오른쪽 손목"에 값이 나오면 맞는 것
- **SDK 패키지 설치**: 새 sdkmanager는 PowerShell에서 `;`가 든 이름을 잘못 읽음 → `cmd /c "sdkmanager.bat ""ndk;버전"""`

## 실제 폰에서 확인하기 (사용자가 할 일)

1. 폰: 설정 → 휴대전화 정보 → 소프트웨어 정보 → **빌드번호 7번 탭** → 개발자 옵션 → **USB 디버깅 켜기**
2. USB로 연결 → 폰의 "USB 디버깅 허용" → 허용
3. `cd D:\dev\handly\app\handly_app; flutter run --release`
   - USB 없이: `dist/Handly-test-arm64.apk`를 폰으로 보내 설치 (출처를 알 수 없는 앱 설치 허용 필요)
4. 앱 → 인식 테스트에서 확인
   - 손 점이 손 위에 그려지는지 (반대쪽이면 "표시 반전" 눌러 보고 결과 알려 주기)
   - 오른손만 들면 "오른쪽 손목"에 값이 나오는지
   - 속도 15fps 이상인지
   - "손목 좌표 3초 측정" 값과, 같은 자세로 노트북에서 `python demo/measure_pose.py` 값의 차이가 0.1 이내인지

## 6. Firebase (MVP 마무리 단계, 사용자 로그인 필요)

```powershell
npm install -g firebase-tools
firebase login                                   # 팀 공용 Google 계정 (브라우저 로그인)
dart pub global activate flutterfire_cli
```

1. https://console.firebase.google.com → 프로젝트 만들기 (예: `handly`) — **Spark(무료) 요금제 그대로**
2. Authentication → 로그인 방법 사용 설정 (이메일 또는 Google)
3. Firestore Database → 만들기 → 위치 `asia-northeast3 (서울)`
4. Storage는 쓰지 않음 (유료 요금제 필요, 영상은 앱 안에 포함)
5. 여기까지 해 주면 `flutterfire configure`와 앱 연결(로그인·학습 기록 저장)은 이어서 진행 가능
