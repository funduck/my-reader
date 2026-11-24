import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../logging.dart';
import '../router.dart';
import 'demo_ports.dart';
import 'scenarios.dart';

/// Root of the demo app: the list of scenarios, or the scenario [initial]
/// right away.
class DemoApp extends StatefulWidget {
  /// Creates the demo app; [initial] is a scenario id (unknown — the list).
  const new({this.initial, super.key});

  /// Id of the scenario to open at start.
  final String? initial;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  late DemoScenario? _running = widget.initial == null
      ? null
      : demoScenarioById(widget.initial!);

  @override
  Widget build(BuildContext context) {
    final running = _running;
    if (running != null) {
      return DemoScenarioView(key: ValueKey(running.id), scenario: running);
    }
    return MaterialApp(
      title: 'My reader demo',
      home: _ScenarioList(onPick: (s) => setState(() => _running = s)),
    );
  }
}

class _ScenarioList extends StatelessWidget {
  const new({required this.onPick});

  final ValueChanged<DemoScenario> onPick;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Demo scenarios')),
      body: ListView(
        children: [
          for (final s in demoScenarios)
            ListTile(
              title: Text(s.title),
              subtitle: Text(s.id),
              onTap: () => onPick(s),
            ),
        ],
      ),
    );
  }
}

/// The app in [scenario]: the real screens over the demo ports.
class DemoScenarioView extends StatefulWidget {
  /// Creates the view; a new key gives fresh data.
  const new({required this.scenario, super.key});

  /// What to show.
  final DemoScenario scenario;

  @override
  State<DemoScenarioView> createState() => _DemoScenarioViewState();
}

class _DemoScenarioViewState extends State<DemoScenarioView> {
  late final Future<List<Override>> _overrides = buildDemoOverrides(
    widget.scenario,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _overrides,
      builder: (context, snapshot) {
        final overrides = snapshot.data;
        if (overrides == null) return const SizedBox.shrink();
        return ProviderScope(
          overrides: overrides,
          observers: const [LoggingProviderObserver()],
          child: _AfterFirstFrame(
            action: widget.scenario.afterFirstFrame,
            child: const MyReaderApp(),
          ),
        );
      },
    );
  }
}

/// Runs [action] over the app navigator once, after the first frame.
class _AfterFirstFrame extends ConsumerStatefulWidget {
  const new({required this.action, required this.child});

  final DemoAction? action;

  final Widget child;

  @override
  ConsumerState<_AfterFirstFrame> createState() => _AfterFirstFrameState();
}

class _AfterFirstFrameState extends ConsumerState<_AfterFirstFrame> {
  @override
  void initState() {
    super.initState();
    final action = widget.action;
    if (action == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = ref.read(routerProvider);
      final navigator = router.routerDelegate.navigatorKey.currentContext;
      if (navigator == null) return;
      unawaited(action(navigator));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
