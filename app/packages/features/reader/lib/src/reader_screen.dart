import 'dart:async';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';

import 'providers.dart';

final Logger _log = Logger('ReaderScreen');

/// How long the position must stay unchanged before it is saved.
const Duration saveDebounce = Duration(seconds: 1);

/// Shows a book: the engine's view, the table of contents in a side drawer.
///
/// The position is restored on open (from [locator] if given, else from the
/// saved progress) and saved [saveDebounce] after the last change, when the
/// app goes to the background and when the screen is closed.
class ReaderScreen extends ConsumerStatefulWidget {
  /// Creates the screen for [bookId]; [locator] opens it at that place.
  const new({
    required this.bookId,
    this.locator,
    this.onOpenCheatSheet,
    super.key,
  });

  /// The book to read.
  final BookId bookId;

  /// Where to open the book; `null` resumes from the saved position.
  final Locator? locator;

  /// Called by the "Разминка" button with the current position; without it
  /// the button is not shown.
  final void Function(Locator at)? onOpenCheatSheet;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  late final OpenBook _openBook;
  late final SaveProgress _saveProgress;
  late final ReaderEngineFactory _factory;

  ReaderEngine? _engine;
  OpenedBook? _opened;
  Book? _book;
  String? _error;
  StreamSubscription<ReaderEvent>? _events;
  Timer? _debounce;
  Locator? _pending;

  /// The last known position: reported by the engine, else where it opened.
  Locator? _current;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openBook = ref.read(openBookProvider);
    _saveProgress = ref.read(saveProgressProvider);
    _factory = ref.read(readerEngineFactoryProvider);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final outcome = await _openBook(widget.bookId);
      switch (outcome) {
        case BookNotFound():
          _fail('This book is not in the library.');
        case BookFileUnreadable(:final reason):
          _fail('The book cannot be opened: $reason');
        case BookOpened():
          await _attach(outcome);
      }
    } on Object catch (e, s) {
      _log.severe('Opening ${widget.bookId} failed', e, s);
      _fail('The book cannot be opened.');
    }
  }

  Future<void> _attach(BookOpened outcome) async {
    final opened = outcome.opened;
    if (!mounted) {
      await opened.close();
      return;
    }
    final engine = _factory();
    _opened = opened;
    _engine = engine;
    _current =
        widget.locator ??
        outcome.resumeAt ??
        (opened.spine.isEmpty
            ? null
            : Locator(
                book: widget.bookId,
                chapter: opened.spine.first,
                progression: 0,
              ));
    _events = engine.events.listen(_onEvent);
    await engine.load(
      opened,
      bookId: widget.bookId,
      at: widget.locator ?? outcome.resumeAt,
    );
    if (!mounted) return;
    setState(() => _book = outcome.book);
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  void _onEvent(ReaderEvent event) {
    switch (event) {
      case WordTapped(:final word, :final at, :final sentence):
        _lookup(word, at, sentence);
        return;
      case TextSelected(:final text, :final at, :final sentence):
        _lookup(text, at, sentence);
        return;
      case ChapterFinished():
        return;
      case PositionChanged():
        break;
    }
    _current = event.locator;
    _pending = event.locator;
    _debounce?.cancel();
    _debounce = Timer(saveDebounce, _flush);
  }

  void _lookup(String text, Locator at, String sentence) {
    if (!mounted) return;
    unawaited(_showLookup(text, at, sentence));
  }

  Future<void> _showLookup(String text, Locator at, String sentence) async {
    try {
      await ref.read(lookupPresenterProvider)(
        context,
        text: text,
        at: at,
        sentence: sentence,
      );
    } on Object catch (e, s) {
      _log.severe('Showing the lookup of "$text" failed', e, s);
    }
  }

  /// Saves the last reported position now, if it is not saved yet.
  void _flush() {
    _debounce?.cancel();
    _debounce = null;
    final at = _pending;
    final opened = _opened;
    if (at == null || opened == null) return;
    _pending = null;
    unawaited(
      _saveProgress(at, chapterCount: opened.spine.length).catchError((
        Object e,
        StackTrace s,
      ) {
        _log.severe('Saving the position failed', e, s);
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _flush();
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flush();
    unawaited(_events?.cancel());
    unawaited(_release(_engine, _opened));
    super.dispose();
  }

  Future<void> _release(ReaderEngine? engine, OpenedBook? opened) async {
    try {
      await engine?.dispose();
      await opened?.close();
    } on Object catch (e, s) {
      _log.warning('Releasing the reader failed', e, s);
    }
  }

  void _openCheatSheet() {
    final at = _current;
    if (at != null) {
      _flush();
      widget.onOpenCheatSheet?.call(at);
    }
  }

  Future<void> _goTo(TocEntry entry) async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.goTo(
        Locator(book: widget.bookId, chapter: entry.chapter, progression: 0),
      );
    } on Object catch (e, s) {
      _log.warning('Go to ${entry.title} failed', e, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final engine = _engine;
    final error = _error;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reader')),
        body: Center(child: Text(error)),
      );
    }
    if (book == null || engine == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reader')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(book.metadata.title),
        actions: [
          if (widget.onOpenCheatSheet != null)
            IconButton(
              icon: const Icon(Icons.lightbulb_outline),
              tooltip: 'Разминка',
              onPressed: _openCheatSheet,
            ),
        ],
      ),
      drawer: _TocDrawer(
        toc: _opened?.toc ?? const [],
        onSelect: (entry) {
          Navigator.of(context).pop();
          unawaited(_goTo(entry));
        },
      ),
      body: engine.buildView(context),
    );
  }
}

class _TocDrawer extends StatelessWidget {
  const new({required this.toc, required this.onSelect});

  final List<TocEntry> toc;
  final void Function(TocEntry entry) onSelect;

  @override
  Widget build(BuildContext context) {
    final rows = <(TocEntry, int)>[];
    void collect(List<TocEntry> entries, int depth) {
      for (final entry in entries) {
        rows.add((entry, depth));
        collect(entry.children, depth + 1);
      }
    }

    collect(toc, 0);
    return Drawer(
      child: SafeArea(
        child: rows.isEmpty
            ? const Center(child: Text('No table of contents.'))
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final (entry, depth) = rows[i];
                  return ListTile(
                    contentPadding: EdgeInsetsDirectional.only(
                      start: 16.0 + 16.0 * depth,
                      end: 16,
                    ),
                    title: Text(entry.title),
                    onTap: () => onSelect(entry),
                  );
                },
              ),
      ),
    );
  }
}
