# release 빌드(R8)가 리플렉션으로 만드는 클래스를 지워서 앱이 시작하자마자 꺼지는 문제 방지

# WorkManager (camera / ML Kit 의존성) - Room 이 이름으로 찾는 생성 클래스
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }

# MediaPipe (hand_landmarker) - 네이티브 코드가 이름으로 부르는 클래스
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**

# hand_landmarker JNI 바인딩 (Dart 에서 클래스·메서드 이름으로 호출)
-keep class io.github.iot_gamer.hand_landmarker.** { *; }
-keep class com.github.dart_lang.jni.** { *; }

# ML Kit
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }