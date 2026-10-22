import 'dart:convert';
import 'dart:io';

import 'package:handly_core/handly_core.dart';
import 'package:test/test.dart';

/// demo/export_app_assets.py 가 만든 정답 데이터와 Dart 결과 비교.
/// Python 쪽 규칙을 바꾸면 export_app_assets.py 를 다시 실행하고 이 테스트로 확인.
void main() {
  final lib = RefLibrary.fromJsonString(File('../handly_app/assets/handly_refs.json').readAsStringSync());
  final goldens = Directory('test/golden').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('정답 데이터가 있음', () {
    expect(goldens, isNotEmpty);
    expect(lib.words.where((w) => w.refs.isNotEmpty), isNotEmpty);
  });

  for (final f in goldens) {
    final g = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final name = g['name'] as String;

    group(name, () {
      final raw = RawTake.fromJson((g['raw'] as Map).cast<String, dynamic>());
      final seq = processTake(raw, lib.cfg);
      final exp = (g['processed'] as Map).cast<String, dynamic>();

      test('좌표 처리 (10-3)', () {
        expect(seq.error, exp['error']);
        if (seq.error != null) return;
        final t = (exp['t'] as List).cast<num>();
        expect(seq.length, t.length);
        final P = exp['P'] as List;
        final X = exp['X'] as List;
        var maxDiff = 0.0;
        for (var i = 0; i < seq.length; i++) {
          expect(seq.t[i], closeTo(t[i], 1e-9));
          for (var k = 0; k < 2; k++) {
            expect(seq.present(i, k), P[i][k] == 1, reason: 'frame $i slot $k presence');
            for (var j = 0; j < kPoints; j++) {
              for (var c = 0; c < kDims; c++) {
                final d = (seq.get(i, k, j, c) - (X[i][k][j][c] as num)).abs();
                if (d > maxDiff) maxDiff = d;
              }
            }
          }
        }
        expect(maxDiff, lessThan(1e-4), reason: '좌표 최대 차이 $maxDiff');
        final head = (exp['head'] as List).cast<num>();
        for (var c = 0; c < 3; c++) {
          expect(seq.head[c], closeTo(head[c], 1e-4));
        }
        expect(seq.noHandRatio(), closeTo((exp['no_hand_ratio'] as num).toDouble(), 1e-9));
        if (exp['trim_len'] != null) expect(seq.trimmed().length, exp['trim_len']);
      });

      final judgements = (g['judgements'] as Map).cast<String, dynamic>();
      for (final target in judgements.keys) {
        test('판정: 목표 $target', () {
          final e = (judgements[target] as Map).cast<String, dynamic>();
          final j = lib.judge(seq, target);
          expect(j.status, e['status']);
          expect(j.message, e['message']);
          expect(j.hints, (e['hints'] as List).cast<String>());
          final ed = (e['distances'] as Map).cast<String, dynamic>();
          expect(j.distances.keys.toSet(), ed.keys.toSet());
          for (final w in ed.keys) {
            expect(j.distances[w], closeTo((ed[w] as num).toDouble(), 1e-4), reason: w);
          }
        });
      }
    });
  }
}
