import 'dart:async';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:handly_core/handly_core.dart';

/// 카메라 → 손 21점×2 (hand_landmarker) + 어깨 기준점 (ML Kit 포즈) → FrameData (PRD 10-8).
///
/// - 두 패키지에 같은 CameraImage 를 넣음
/// - 좌표는 둘 다 "바로 세운 영상" 기준이라, 0~1 로 맞춘 뒤 앞 카메라는 좌우 반전 (시연 프로그램의 거울 모드와 같게)
/// - 어깨는 [poseEvery] 프레임마다 한 번만 계산 (어깨는 수어 중 거의 안 움직임)
/// - 카메라 영상은 기기 안에서만 처리하고 좌표만 씀 (M8-1)
class Recognizer {
  Recognizer({this.poseEvery = 3, this.useGpu = true});

  final int poseEvery;
  final bool useGpu;

  CameraController? controller;
  HandLandmarkerPlugin? _hands;
  PoseDetector? _pose;
  StreamSubscription<List<Hand>>? _handSub;

  final _frames = StreamController<FrameData>.broadcast();

  /// 손 결과가 올 때마다 (그 시점의 최신 어깨와 묶어서) 나옴
  Stream<FrameData> get frames => _frames.stream;

  FrameData? latest;
  int uprightWidth = 0, uprightHeight = 0;
  bool mirror = true;

  // 속도 측정 (10-8 테스트 2)
  final stats = RecognizerStats();

  int _cameraCount = 0;
  bool _poseBusy = false;
  List<List<double>> _lastPose = List.generate(5, (_) => [0.0, 0.0, 0.0]);
  bool _lastPoseOk = false;
  DateTime _lastPoseTime = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    final cameras = await availableCameras();
    final cam = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    mirror = cam.lensDirection == CameraLensDirection.front;
    final c = CameraController(cam, ResolutionPreset.medium,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
    await c.initialize();
    controller = c;

    _createHands(useGpu);
    _pose = PoseDetector(options: PoseDetectorOptions(mode: PoseDetectionMode.stream, model: PoseDetectionModel.base));
    await c.startImageStream(_onCameraImage);
  }

  /// 손 인식 실행 방식: GPU 또는 CPU
  bool gpu = true;
  int _handEvents = 0, _framesSinceCreate = 0;

  void _createHands(bool useGpu) {
    gpu = useGpu;
    _hands = HandLandmarkerPlugin.create(
      numHands: 2,
      minHandDetectionConfidence: 0.5,
      delegate: useGpu ? HandLandmarkerDelegate.gpu : HandLandmarkerDelegate.cpu,
    );
    _handEvents = 0;
    _framesSinceCreate = 0;
    _handSub = _hands!.landmarkStream.listen(_onHands);
  }

  /// GPU 에서 손 결과가 하나도 안 오면 CPU 로 바꿈 (에뮬레이터는 GPU 가속 오류, 10-8 확인 결과)
  void _fallbackToCpu() {
    debugPrint('hand_landmarker: GPU 결과 없음 → CPU 로 전환');
    _handSub?.cancel();
    _hands?.dispose();
    _createHands(false);
  }

  void _onCameraImage(CameraImage image) {
    final rot = controller!.description.sensorOrientation;
    final swap = rot == 90 || rot == 270;
    uprightWidth = swap ? image.height : image.width;
    uprightHeight = swap ? image.width : image.height;
    stats.tick(stats.camera);
    if (gpu && _handEvents == 0 && ++_framesSinceCreate > 45) _fallbackToCpu();

    try {
      _hands?.processFrame(image, rot);
    } catch (e) {
      debugPrint('hand_landmarker 오류: $e');
    }

    if (_cameraCount++ % poseEvery == 0 && !_poseBusy) {
      _poseBusy = true;
      _detectPose(image, rot).whenComplete(() => _poseBusy = false);
    }
  }

  Future<void> _detectPose(CameraImage image, int rot) async {
    try {
      final input = InputImage.fromBytes(
        bytes: yuv420ToNv21(image),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(rot) ?? InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
      final poses = await _pose!.processImage(input);
      stats.tick(stats.pose);
      if (poses.isEmpty) {
        _lastPoseOk = false;
        return;
      }
      final lm = poses.first.landmarks;
      const types = [
        PoseLandmarkType.nose,
        PoseLandmarkType.leftEar,
        PoseLandmarkType.rightEar,
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
      ];
      final w = uprightWidth.toDouble(), h = uprightHeight.toDouble();
      final pts = <List<double>>[];
      var ok = true;
      for (final t in types) {
        final p = lm[t];
        if (p == null) {
          ok = false;
          pts.add([0, 0, 0]);
          continue;
        }
        // ML Kit 은 픽셀 좌표 → 이미지 크기로 나눠 0~1 (손 좌표와 단위 맞춤, 10-8)
        final x = p.x / w;
        pts.add([mirror ? 1 - x : x, p.y / h, 0]);
      }
      final sh = lm[PoseLandmarkType.leftShoulder], sh2 = lm[PoseLandmarkType.rightShoulder];
      if (sh == null || sh2 == null || sh.likelihood < 0.5 || sh2.likelihood < 0.5) ok = false;
      _lastPose = pts;
      _lastPoseOk = ok;
      _lastPoseTime = DateTime.now();
    } catch (e) {
      debugPrint('ML Kit 포즈 오류: $e');
    }
  }

  void _onHands(List<Hand> hands) {
    _handEvents++;
    stats.tick(stats.hand);
    final hs = List.generate(2, (_) => List.generate(kPoints, (_) => [0.0, 0.0, 0.0]));
    final ok = [false, false];
    for (var k = 0; k < hands.length && k < 2; k++) {
      final lms = hands[k].landmarks;
      if (lms.length < kPoints) continue;
      for (var j = 0; j < kPoints; j++) {
        final l = lms[j];
        hs[k][j] = [mirror ? 1 - l.x : l.x, l.y, l.z];
      }
      ok[k] = true;
    }
    final poseFresh = DateTime.now().difference(_lastPoseTime).inMilliseconds < 500;
    final fd = FrameData(hs, ok, [for (final p in _lastPose) [...p]], _lastPoseOk && poseFresh);
    latest = fd;
    _frames.add(fd);
  }

  Future<void> dispose() async {
    await _handSub?.cancel();
    try {
      await controller?.stopImageStream();
    } catch (_) {}
    await controller?.dispose();
    _hands?.dispose();
    await _pose?.close();
    await _frames.close();
  }
}

/// 카메라 YUV420 (3평면) → NV21 (ML Kit 안드로이드 입력 형식)
Uint8List yuv420ToNv21(CameraImage image) {
  final w = image.width, h = image.height;
  final yP = image.planes[0], uP = image.planes[1], vP = image.planes[2];
  final out = Uint8List(w * h + 2 * (w ~/ 2) * (h ~/ 2));
  var idx = 0;
  for (var row = 0; row < h; row++) {
    out.setRange(idx, idx + w, yP.bytes, row * yP.bytesPerRow);
    idx += w;
  }
  final rowStride = uP.bytesPerRow, pixStride = uP.bytesPerPixel ?? 1;
  final u = uP.bytes, v = vP.bytes;
  for (var row = 0; row < h ~/ 2; row++) {
    for (var col = 0; col < w ~/ 2; col++) {
      final o = row * rowStride + col * pixStride;
      out[idx++] = o < v.length ? v[o] : 128;
      out[idx++] = o < u.length ? u[o] : 128;
    }
  }
  return out;
}

class RecognizerStats {
  final camera = <DateTime>[];
  final hand = <DateTime>[];
  final pose = <DateTime>[];

  void tick(List<DateTime> l) {
    final now = DateTime.now();
    l.add(now);
    while (l.isNotEmpty && now.difference(l.first).inMilliseconds > 2000) {
      l.removeAt(0);
    }
  }

  /// 최근 2초 동안의 초당 횟수
  double fps(List<DateTime> l) {
    final now = DateTime.now();
    final n = l.where((t) => now.difference(t).inMilliseconds <= 2000).length;
    return n / 2.0;
  }
}
