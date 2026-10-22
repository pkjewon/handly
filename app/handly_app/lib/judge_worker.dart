import 'dart:async';
import 'dart:isolate';

import 'package:handly_core/handly_core.dart';

/// 판정(좌표 처리 + DTW)을 별도 Isolate 에서 실행해 화면이 끊기지 않게 함.
/// 기준 동작 데이터는 Isolate 안에 한 번만 읽어 둠.
class JudgeWorker {
  JudgeWorker._(this._send, this._receive);

  final SendPort _send;
  final ReceivePort _receive;
  final _pending = <int, Completer<Judgement>>{};
  int _nextId = 0;

  static Future<JudgeWorker> start(String refsJson) async {
    final receive = ReceivePort();
    await Isolate.spawn(_main, [receive.sendPort, refsJson]);
    final completer = Completer<SendPort>();
    late JudgeWorker worker;
    receive.listen((msg) {
      if (msg is SendPort) {
        completer.complete(msg);
      } else if (msg is List) {
        final c = worker._pending.remove(msg[0] as int);
        final m = (msg[1] as Map).cast<String, dynamic>();
        c?.complete(Judgement(
          m['status'] as String,
          m['message'] as String,
          hints: (m['hints'] as List).cast<String>(),
          distances: (m['distances'] as Map).cast<String, double>(),
          targetDist: m['targetDist'] as double?,
          threshold: m['threshold'] as double?,
        ));
      }
    });
    worker = JudgeWorker._(await completer.future, receive);
    return worker;
  }

  Future<Judgement> judge(RawTake take, String target) {
    final id = _nextId++;
    final c = Completer<Judgement>();
    _pending[id] = c;
    _send.send([id, target, take.width, take.height, take.t, take.hands, take.handOk, take.pose, take.poseOk]);
    return c.future;
  }

  void dispose() => _receive.close();

  static void _main(List<dynamic> args) {
    final reply = args[0] as SendPort;
    final lib = RefLibrary.fromJsonString(args[1] as String);
    final port = ReceivePort();
    reply.send(port.sendPort);
    port.listen((msg) {
      final m = msg as List;
      final take = RawTake(m[2] as int, m[3] as int);
      take.t.addAll((m[4] as List).cast<double>());
      take.hands.addAll((m[5] as List).cast<double>());
      take.handOk.addAll((m[6] as List).cast<bool>());
      take.pose.addAll((m[7] as List).cast<double>());
      take.poseOk.addAll((m[8] as List).cast<bool>());
      final j = lib.judge(processTake(take, lib.cfg), m[1] as String);
      reply.send([
        m[0],
        {
          'status': j.status,
          'message': j.message,
          'hints': j.hints,
          'distances': j.distances,
          'targetDist': j.targetDist,
          'threshold': j.threshold,
        }
      ]);
    });
  }
}

/// 최근 몇 초의 프레임을 계속 들고 있다가 RawTake 로 꺼냄 (게임: 자동 판정)
class FrameWindow {
  FrameWindow(this.seconds);

  final double seconds;
  final _frames = <(double, FrameData)>[];
  final _clock = Stopwatch()..start();

  void add(FrameData f) {
    final now = _clock.elapsedMicroseconds / 1e6;
    _frames.add((now, f));
    while (_frames.isNotEmpty && now - _frames.first.$1 > seconds) {
      _frames.removeAt(0);
    }
  }

  void clear() => _frames.clear();

  double get span => _frames.length < 2 ? 0 : _frames.last.$1 - _frames.first.$1;

  /// 최근 구간에 손이 보였는지 (손이 없으면 판정 안 함)
  bool get handsVisible => _frames.where((f) => f.$2.handOk[0] || f.$2.handOk[1]).length > _frames.length * 0.4;

  RawTake toTake(int width, int height) {
    final take = RawTake(width, height);
    if (_frames.isEmpty) return take;
    final t0 = _frames.first.$1;
    for (final (t, f) in _frames) {
      take.add(t - t0, f);
    }
    return take;
  }
}
