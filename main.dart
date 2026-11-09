// Study Planner — offline module tracker and reading timetable.
// All data is saved on the phone (no internet needed).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.load();
  runApp(StudyPlannerApp(store: store));
}

// ---------------------------------------------------------------- helpers

const List<int> kPalette = [
  0xFF0F7A63, 0xFF2F6FD6, 0xFFC2410C, 0xFF8B3FC4,
  0xFFC0365E, 0xFFB08900, 0xFF2A8A9C, 0xFF5B6B2F,
];
const List<String> kDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> kDaysFull = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];
const List<String> kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

int _idCounter = 0;
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}${_idCounter++}';

int todayIndex() => DateTime.now().weekday - 1; // Monday = 0

String fmtTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

String fmtDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

String fmtDate(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${d.day} ${kMonths[d.month - 1]}';
}

int nowMinutes() {
  final n = DateTime.now();
  return n.hour * 60 + n.minute;
}

// ---------------------------------------------------------------- models

class Unit {
  Unit({required this.id, required this.title, this.done = false, this.doneAt});
  String id;
  String title;
  bool done;
  int? doneAt;

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'done': done, 'doneAt': doneAt};
  factory Unit.fromJson(Map<String, dynamic> j) => Unit(
        id: j['id'] as String,
        title: j['title'] as String,
        done: (j['done'] as bool?) ?? false,
        doneAt: j['doneAt'] as int?,
      );
}

class Module {
  Module({
    required this.id,
    required this.name,
    this.code = '',
    required this.color,
    List<Unit>? units,
  }) : units = units ?? [];
  String id;
  String name;
  String code;
  int color;
  List<Unit> units;

  int get doneCount => units.where((u) => u.done).length;
  double get progress => units.isEmpty ? 0 : doneCount / units.length;
  bool get completed => units.isNotEmpty && doneCount == units.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'color': color,
        'units': units.map((u) => u.toJson()).toList(),
      };
  factory Module.fromJson(Map<String, dynamic> j) => Module(
        id: j['id'] as String,
        name: j['name'] as String,
        code: (j['code'] as String?) ?? '',
        color: j['color'] as int,
        units: ((j['units'] as List?) ?? [])
            .map((e) => Unit.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class Slot {
  Slot({
    required this.id,
    required this.day,
    required this.start,
    required this.end,
    required this.moduleId,
    this.note = '',
  });
  String id;
  int day; // 0 = Monday
  int start; // minutes after midnight
  int end;
  String moduleId;
  String note;

  int get length => end - start;

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': day,
        'start': start,
        'end': end,
        'moduleId': moduleId,
        'note': note,
      };
  factory Slot.fromJson(Map<String, dynamic> j) => Slot(
        id: j['id'] as String,
        day: j['day'] as int,
        start: j['start'] as int,
        end: j['end'] as int,
        moduleId: j['moduleId'] as String,
        note: (j['note'] as String?) ?? '',
      );
}

// ---------------------------------------------------------------- storage

class Store extends ChangeNotifier {
  static const _key = 'study_planner_v1';
  List<Module> modules = [];
  List<Slot> slots = [];

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      modules = ((data['modules'] as List?) ?? [])
          .map((e) => Module.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      slots = ((data['slots'] as List?) ?? [])
          .map((e) => Slot.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      modules = [];
      slots = [];
    }
  }

  Future<void> save() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'modules': modules.map((m) => m.toJson()).toList(),
        'slots': slots.map((s) => s.toJson()).toList(),
      }),
    );
  }

  Module? moduleById(String id) {
    for (final m in modules) {
      if (m.id == id) return m;
    }
    return null;
  }

  List<Slot> slotsForDay(int day) {
    final list = slots.where((s) => s.day == day).toList();
    list.sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  Slot? findClash(int day, int start, int end, {String? ignoreId}) {
    for (final s in slots) {
      if (s.id == ignoreId || s.day != day) continue;
      if (start < s.end && end > s.start) return s;
    }
    return null;
  }

  void addModule(Module m) {
    modules.add(m);
    save();
  }

  void deleteModule(Module m) {
    modules.removeWhere((x) => x.id == m.id);
    slots.removeWhere((s) => s.moduleId == m.id);
    save();
  }

  void toggleUnit(Unit u, bool value) {
    u.done = value;
    u.doneAt = value ? DateTime.now().millisecondsSinceEpoch : null;
    save();
  }

  void setAllUnits(Module m, bool value) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final u in m.units) {
      if (value && !u.done) u.doneAt = now;
      if (!value) u.doneAt = null;
      u.done = value;
    }
    save();
  }

  void loadExample() {
    Module mk(String name, String code, int color, int n, int done) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return Module(
        id: newId(),
        name: name,
        code: code,
        color: color,
        units: List.generate(
          n,
          (i) => Unit(
            id: newId(),
            title: 'Unit ${i + 1}',
            done: i < done,
            doneAt: i < done ? now - (done - i) * 86400000 : null,
          ),
        ),
      );
    }

    final a = mk('Example: Business Statistics', 'STA101', kPalette[1], 10, 4);
    final b = mk('Example: Financial Accounting', 'ACC110', kPalette[0], 8, 2);
    final c = mk('Example: Commercial Law', 'LAW120', kPalette[2], 6, 1);
    modules = [a, b, c];
    slots = [
      Slot(id: newId(), day: 0, start: 18 * 60, end: 19 * 60 + 30, moduleId: a.id),
      Slot(id: newId(), day: 1, start: 18 * 60, end: 19 * 60, moduleId: b.id),
      Slot(id: newId(), day: 2, start: 19 * 60, end: 20 * 60, moduleId: c.id),
      Slot(id: newId(), day: 3, start: 18 * 60, end: 19 * 60 + 30, moduleId: a.id),
      Slot(id: newId(), day: 5, start: 9 * 60, end: 11 * 60, moduleId: b.id, note: 'Past paper'),
    ];
    save();
  }
}

// ---------------------------------------------------------------- app

class StudyPlannerApp extends StatelessWidget {
  const StudyPlannerApp({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F7A63);
    return MaterialApp(
      title: 'Study Planner',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      ),
      home: HomeShell(store: store),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});
  final Store store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  int _selectedDay = todayIndex();

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final titles = ['Today', 'My modules', 'Reading timetable'];
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        Widget body;
        Widget? fab;
        switch (_tab) {
          case 0:
            body = TodayScreen(
              store: store,
              onOpenModules: () => setState(() => _tab = 1),
            );
            fab = store.modules.isEmpty
                ? null
                : FloatingActionButton.extended(
                    onPressed: () => showSlotSheet(context, store, day: todayIndex()),
                    icon: const Icon(Icons.add),
                    label: const Text('Reading time'),
                  );
            break;
          case 1:
            body = ModulesScreen(store: store);
            fab = FloatingActionButton.extended(
              onPressed: () => showModuleSheet(context, store),
              icon: const Icon(Icons.add),
              label: const Text('Module'),
            );
            break;
          default:
            body = TimetableScreen(
              store: store,
              selectedDay: _selectedDay,
              onDayChanged: (d) => setState(() => _selectedDay = d),
            );
            fab = FloatingActionButton.extended(
              onPressed: () {
                if (store.modules.isEmpty) {
                  showToast(context, 'Add a module first');
                  setState(() => _tab = 1);
                  return;
                }
                showSlotSheet(context, store, day: _selectedDay)
                    .then((day) {
                  if (day != null) setState(() => _selectedDay = day);
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Reading time'),
            );
        }
        return Scaffold(
          appBar: AppBar(title: Text(titles[_tab])),
          body: SafeArea(child: body),
          floatingActionButton: fab,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
              NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Modules'),
              NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Timetable'),
            ],
          ),
        );
      },
    );
  }
}

void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

Future<bool> confirm(BuildContext context, String title, String body, String action) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ---------------------------------------------------------------- shared widgets

class ColorDot extends StatelessWidget {
  const ColorDot(this.color, {super.key, this.size = 12});
  final int color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle),
      );
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, required this.color});
  final double value;
  final int color;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 8,
          color: Color(color),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      );
}

class EmptyBox extends StatelessWidget {
  const EmptyBox({super.key, required this.text, this.child});
  final String text;
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          if (child != null) ...[const SizedBox(height: 12), child!],
        ],
      ),
    );
  }
}

class SlotTile extends StatelessWidget {
  const SlotTile({super.key, required this.store, required this.slot, this.isNow = false});
  final Store store;
  final Slot slot;
  final bool isNow;

  @override
  Widget build(BuildContext context) {
    final m = store.moduleById(slot.moduleId);
    if (m == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final details = [
      if (m.code.isNotEmpty) m.code,
      fmtDuration(slot.length),
      if (slot.note.isNotEmpty) slot.note,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isNow ? const BorderSide(color: Color(0xFFF2B134), width: 2) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showSlotSheet(context, store, existing: slot),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 6, color: Color(m.color)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(fmtTime(slot.start), style: const TextStyle(fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()])),
                    Text(fmtTime(slot.end), style: TextStyle(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(details, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              if (isNow)
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFF2B134), borderRadius: BorderRadius.circular(99)),
                    child: const Text('Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2B1D00))),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Today

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.store, required this.onOpenModules});
  final Store store;
  final VoidCallback onOpenModules;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final dateLine = '${kDaysFull[todayIndex()]}, ${now.day} ${kMonths[now.month - 1]}';

    if (store.modules.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(dateLine, style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          EmptyBox(
            text: "Add the modules you're studying, tick off units as you read them, and set the times you'll read each week.",
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(
                  onPressed: () => showModuleSheet(context, store),
                  child: const Text('Add your first module'),
                ),
                OutlinedButton(
                  onPressed: () {
                    store.loadExample();
                    showToast(context, 'Example plan loaded. Edit or delete it any time.');
                  },
                  child: const Text('Load an example plan'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final nm = nowMinutes();
    final today = store.slotsForDay(todayIndex());
    final totalUnits = store.modules.fold<int>(0, (a, m) => a + m.units.length);
    final doneUnits = store.modules.fold<int>(0, (a, m) => a + m.doneCount);
    final weekMinutes = store.slots.fold<int>(0, (a, s) => a + s.length);
    final weekAgo = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final readThisWeek = store.modules.fold<int>(
        0, (a, m) => a + m.units.where((u) => u.done && (u.doneAt ?? 0) > weekAgo).length);
    Slot? next;
    for (final s in today) {
      if (s.start > nm) {
        next = s;
        break;
      }
    }

    Widget stat(String value, String label) => Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(label, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Text(dateLine, style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        Row(
          children: [
            stat('${totalUnits == 0 ? 0 : (doneUnits * 100 / totalUnits).round()}%', 'of all units read'),
            const SizedBox(width: 8),
            stat('$readThisWeek', 'units read in 7 days'),
            const SizedBox(width: 8),
            stat(fmtDuration(weekMinutes), 'planned per week'),
          ],
        ),
        const SizedBox(height: 20),
        Text("Today's reading", style: text.titleLarge),
        const SizedBox(height: 10),
        if (today.isEmpty)
          const EmptyBox(text: 'No reading planned for today.')
        else
          ...today.map((s) => SlotTile(store: store, slot: s, isNow: s.start <= nm && nm < s.end)),
        if (next != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Next up at ${fmtTime(next.start)}: ${store.moduleById(next.moduleId)?.name ?? ''}',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 20),
        Text('Module progress', style: text.titleLarge),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: store.modules
                  .map((m) => InkWell(
                        onTap: () => openModule(context, store, m),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  ColorDot(m.color),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(m.name)),
                                  Text('${m.doneCount}/${m.units.length}',
                                      style: TextStyle(color: cs.onSurfaceVariant)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ProgressBar(value: m.progress, color: m.color),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Modules

void openModule(BuildContext context, Store store, Module m) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ModuleDetailPage(store: store, moduleId: m.id)),
  );
}

class ModulesScreen extends StatelessWidget {
  const ModulesScreen({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (store.modules.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EmptyBox(
            text: "No modules yet. Add a module to start tracking what you've read.",
            child: FilledButton(
              onPressed: () => showModuleSheet(context, store),
              child: const Text('Add a module'),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: store.modules.map((m) {
        final pct = (m.progress * 100).round();
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openModule(context, store, m),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ColorDot(m.color, size: 14),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            if (m.code.isNotEmpty)
                              Text(m.code, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                          ],
                        ),
                      ),
                      Text('$pct%', style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ProgressBar(value: m.progress, color: m.color),
                  const SizedBox(height: 8),
                  Text(
                    '${m.doneCount} of ${m.units.length} units read${m.completed ? ' · Completed ✓' : ''}',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class ModuleDetailPage extends StatelessWidget {
  const ModuleDetailPage({super.key, required this.store, required this.moduleId});
  final Store store;
  final String moduleId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final m = store.moduleById(moduleId);
        if (m == null) return const Scaffold(body: SizedBox.shrink());
        final cs = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: Text(m.name),
            actions: [
              IconButton(
                tooltip: 'Edit module',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showModuleSheet(context, store, existing: m),
              ),
              IconButton(
                tooltip: 'Delete module',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    'Delete this module?',
                    '"${m.name}" and its reading progress will be removed, along with its timetable slots.',
                    'Delete',
                  );
                  if (ok && context.mounted) {
                    Navigator.of(context).pop();
                    store.deleteModule(m);
                  }
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showUnitSheet(context, store, m),
            icon: const Icon(Icons.add),
            label: const Text('Unit'),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (m.code.isNotEmpty)
                  Text(m.code, style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: ProgressBar(value: m.progress, color: m.color)),
                    const SizedBox(width: 12),
                    Text('${(m.progress * 100).round()}%', style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('${m.doneCount} of ${m.units.length} units read',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 12),
                if (m.units.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final markAll = !m.completed;
                        store.setAllUnits(m, markAll);
                        if (markAll) showToast(context, '${m.name} completed');
                      },
                      icon: Icon(m.completed ? Icons.remove_done : Icons.done_all),
                      label: Text(m.completed ? 'Mark all unread' : 'Mark all read'),
                    ),
                  ),
                const SizedBox(height: 8),
                if (m.units.isEmpty)
                  const EmptyBox(text: 'No units yet. Tap "Unit" to add chapters or topics.')
                else
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final u in m.units)
                          ListTile(
                            leading: Checkbox(
                              value: u.done,
                              activeColor: Color(m.color),
                              onChanged: (v) {
                                store.toggleUnit(u, v ?? false);
                                if ((v ?? false) && m.completed) {
                                  showToast(context, '${m.name} completed');
                                }
                              },
                            ),
                            title: Text(
                              u.title,
                              style: u.done
                                  ? TextStyle(decoration: TextDecoration.lineThrough, color: cs.onSurfaceVariant)
                                  : null,
                            ),
                            subtitle: u.done && u.doneAt != null ? Text('Read ${fmtDate(u.doneAt!)}') : null,
                            trailing: IconButton(
                              tooltip: 'Rename unit',
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => showUnitSheet(context, store, m, existing: u),
                            ),
                            onTap: () => store.toggleUnit(u, !u.done),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> showModuleSheet(BuildContext context, Store store, {Module? existing}) {
  final isNew = existing == null;
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final codeCtrl = TextEditingController(text: existing?.code ?? '');
  final unitsCtrl = TextEditingController(text: '8');
  int color = existing?.color ?? kPalette[store.modules.length % kPalette.length];
  String? error;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(isNew ? 'Add a module' : 'Edit module', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                autofocus: isNew,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Module name', hintText: 'e.g. Financial Accounting', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Module code (optional)', hintText: 'e.g. ACC101', border: OutlineInputBorder()),
              ),
              if (isNew) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: unitsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Number of chapters/units',
                    helperText: 'Created as Unit 1, Unit 2… You can rename them later.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text('Colour'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: kPalette
                    .map((c) => GestureDetector(
                          onTap: () => setSheet(() => color = c),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: c == color ? Theme.of(ctx).colorScheme.onSurface : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontWeight: FontWeight.bold)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    setSheet(() => error = 'Give the module a name.');
                    return;
                  }
                  if (isNew) {
                    final n = (int.tryParse(unitsCtrl.text.trim()) ?? 0).clamp(0, 100).toInt();
                    store.addModule(Module(
                      id: newId(),
                      name: name,
                      code: codeCtrl.text.trim(),
                      color: color,
                      units: List.generate(n, (i) => Unit(id: newId(), title: 'Unit ${i + 1}')),
                    ));
                  } else {
                    existing!.name = name;
                    existing!.code = codeCtrl.text.trim();
                    existing!.color = color;
                    store.save();
                  }
                  Navigator.pop(ctx);
                  showToast(context, isNew ? 'Module added' : 'Module saved');
                },
                child: Text(isNew ? 'Add module' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showUnitSheet(BuildContext context, Store store, Module m, {Unit? existing}) {
  final isNew = existing == null;
  final ctrl = TextEditingController(text: existing?.title ?? 'Unit ${m.units.length + 1}');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(isNew ? 'Add a unit' : 'Rename unit', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Unit or chapter title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (!isNew)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
                  onPressed: () {
                    m.units.remove(existing);
                    store.save();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Remove unit'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  final t = ctrl.text.trim();
                  if (t.isEmpty) return;
                  if (isNew) {
                    m.units.add(Unit(id: newId(), title: t));
                  } else {
                    existing!.title = t;
                  }
                  store.save();
                  Navigator.pop(ctx);
                },
                child: Text(isNew ? 'Add' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- Timetable

class TimetableScreen extends StatelessWidget {
  const TimetableScreen({
    super.key,
    required this.store,
    required this.selectedDay,
    required this.onDayChanged,
  });
  final Store store;
  final int selectedDay;
  final ValueChanged<int> onDayChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final slots = store.slotsForDay(selectedDay);
    final perModule = <Module, int>{};
    for (final s in store.slots) {
      final m = store.moduleById(s.moduleId);
      if (m != null) perModule[m] = (perModule[m] ?? 0) + s.length;
    }
    final maxMin = perModule.values.fold<int>(1, (a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(7, (i) {
              final count = store.slots.where((s) => s.day == i).length;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: i == selectedDay,
                  onSelected: (_) => onDayChanged(i),
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(kDays[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        i == todayIndex() ? 'today' : (count == 0 ? '—' : '$count'),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 16),
        Text(kDaysFull[selectedDay], style: text.titleLarge),
        const SizedBox(height: 10),
        if (store.modules.isEmpty)
          const EmptyBox(text: 'Add a module first, then plan when you will read it.')
        else if (slots.isEmpty)
          EmptyBox(text: 'Nothing planned for ${kDaysFull[selectedDay]}. Tap "Reading time" to add a slot.')
        else
          ...slots.map((s) => SlotTile(store: store, slot: s)),
        if (perModule.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Weekly hours by module', style: text.titleLarge),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: perModule.entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  ColorDot(e.key.color),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(e.key.name)),
                                  Text(fmtDuration(e.value), style: TextStyle(color: cs.onSurfaceVariant)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ProgressBar(value: e.value / maxMin, color: e.key.color),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Opens the add/edit reading-time sheet. Returns the day the slot was saved on.
Future<int?> showSlotSheet(BuildContext context, Store store, {Slot? existing, int day = 0}) {
  if (store.modules.isEmpty) {
    showToast(context, 'Add a module first');
    return Future.value(null);
  }
  final isNew = existing == null;
  String moduleId = existing?.moduleId ?? store.modules.first.id;
  final days = <int>{existing?.day ?? day};
  int start = existing?.start ?? 18 * 60;
  int end = existing?.end ?? 19 * 60;
  final noteCtrl = TextEditingController(text: existing?.note ?? '');
  String? error;

  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        Future<void> pick(bool isStart) async {
          final current = isStart ? start : end;
          final t = await showTimePicker(
            context: ctx,
            initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
          );
          if (t != null) {
            setSheet(() {
              if (isStart) {
                start = t.hour * 60 + t.minute;
              } else {
                end = t.hour * 60 + t.minute;
              }
              error = null;
            });
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(isNew ? 'Add reading time' : 'Edit reading time', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: moduleId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Module', border: OutlineInputBorder()),
                  items: store.modules
                      .map((m) => DropdownMenuItem(
                            value: m.id,
                            child: Row(
                              children: [
                                ColorDot(m.color),
                                const SizedBox(width: 10),
                                Expanded(child: Text(m.name, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setSheet(() => moduleId = v ?? moduleId),
                ),
                const SizedBox(height: 16),
                Text(isNew ? 'Days (pick one or more)' : 'Day'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(7, (i) {
                    return FilterChip(
                      label: Text(kDays[i]),
                      selected: days.contains(i),
                      onSelected: (sel) => setSheet(() {
                        if (isNew) {
                          if (sel) {
                            days.add(i);
                          } else {
                            days.remove(i);
                          }
                        } else {
                          days
                            ..clear()
                            ..add(i);
                        }
                        error = null;
                      }),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => pick(true),
                        icon: const Icon(Icons.schedule),
                        label: Text('Start ${fmtTime(start)}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => pick(false),
                        icon: const Icon(Icons.schedule),
                        label: Text('End ${fmtTime(end)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'What to read (optional)',
                    hintText: 'e.g. Units 3–4, past paper',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontWeight: FontWeight.bold)),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (!isNew)
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
                        onPressed: () {
                          store.slots.removeWhere((s) => s.id == existing!.id);
                          store.save();
                          Navigator.pop(ctx);
                          showToast(context, 'Removed from timetable');
                        },
                        child: const Text('Delete'),
                      ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        if (days.isEmpty) {
                          setSheet(() => error = 'Pick at least one day.');
                          return;
                        }
                        if (end <= start) {
                          setSheet(() => error = 'The end time must be after the start time.');
                          return;
                        }
                        for (final d in days) {
                          final clash = store.findClash(d, start, end, ignoreId: existing?.id);
                          if (clash != null) {
                            final name = store.moduleById(clash.moduleId)?.name ?? 'another slot';
                            setSheet(() => error =
                                'That overlaps $name on ${kDaysFull[d]} (${fmtTime(clash.start)}–${fmtTime(clash.end)}).');
                            return;
                          }
                        }
                        final note = noteCtrl.text.trim();
                        if (isNew) {
                          for (final d in days) {
                            store.slots.add(Slot(
                              id: newId(),
                              day: d,
                              start: start,
                              end: end,
                              moduleId: moduleId,
                              note: note,
                            ));
                          }
                        } else {
                          existing!
                            ..day = days.first
                            ..start = start
                            ..end = end
                            ..moduleId = moduleId
                            ..note = note;
                        }
                        store.save();
                        final sorted = days.toList()..sort();
                        Navigator.pop(ctx, sorted.first);
                        showToast(context, isNew ? 'Added to timetable' : 'Saved');
                      },
                      child: Text(isNew ? 'Add to timetable' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
