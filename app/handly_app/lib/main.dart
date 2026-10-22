import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:handly_core/handly_core.dart';

import 'judge_worker.dart';
import 'screens/arcade_tab.dart';
import 'screens/home_tab.dart';
import 'screens/learn_tab.dart';
import 'screens/profile_tab.dart';
import 'screens/review_tab.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final json = await rootBundle.loadString('assets/handly_refs.json');
  final lib = RefLibrary.fromJsonString(json);
  final progress = await Progress.load();
  final worker = await JudgeWorker.start(json);
  runApp(HandlyApp(app: AppData(lib, progress, worker)));
}

/// 앱 전체에서 쓰는 데이터: 단어·기준 동작(lib), 학습 기록(progress), 판정 작업자(worker)
class AppData {
  AppData(this.lib, this.progress, this.worker);

  final RefLibrary lib;
  final Progress progress;
  final JudgeWorker worker;

  List<String> get words => lib.words.map((w) => w.name).toList();
  List<WordEntry> get playable => lib.words.where((w) => w.refs.isNotEmpty).toList();
}

class Handly extends InheritedNotifier<Progress> {
  Handly({super.key, required this.app, required super.child}) : super(notifier: app.progress);

  final AppData app;

  static AppData of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<Handly>()!.app;
}

class HandlyApp extends StatelessWidget {
  const HandlyApp({super.key, required this.app});

  final AppData app;

  @override
  Widget build(BuildContext context) => Handly(
        app: app,
        child: MaterialApp(
          title: 'Handly',
          debugShowCheckedModeBanner: false,
          theme: handlyTheme(),
          home: const Shell(),
        ),
      );
}

/// 하단 탭 5개: 홈 · 학습 · 아케이드 · 복습 · 내정보
class Shell extends StatefulWidget {
  const Shell({super.key});

  static void goTab(BuildContext context, int i) => context.findAncestorStateOfType<_ShellState>()?.setTab(i);

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  void setTab(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final sky = _tab == 2;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: sky ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(index: _tab, children: const [HomeTab(), LearnTab(), ArcadeTab(), ReviewTab(), ProfileTab()]),
        bottomNavigationBar: _BottomNav(index: _tab, sky: sky, onTap: setTab),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.sky, required this.onTap});

  final int index;
  final bool sky;
  final ValueChanged<int> onTap;

  static const _items = [
    (HIcons.home, '홈'),
    (HIcons.learn, '학습'),
    (HIcons.arcade, '아케이드'),
    (HIcons.review, '복습'),
    (HIcons.profile, '내정보'),
  ];

  @override
  Widget build(BuildContext context) {
    final bg = sky ? const Color(0x590A0916) : C.paperRaised;
    final border = sky ? Colors.white.withValues(alpha: 0.14) : C.line;
    final active = sky ? C.skyLow : C.teal;
    final idle = sky ? const Color(0xFFC9C5DC) : C.inkSoft;
    return Container(
      decoration: BoxDecoration(color: bg, border: Border(top: BorderSide(color: border))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    HIcon(_items[i].$1, size: 22, color: i == index ? active : idle),
                    const SizedBox(height: 4),
                    Text(_items[i].$2,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: i == index ? active : idle)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
