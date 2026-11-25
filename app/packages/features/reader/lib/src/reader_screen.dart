import 'dart:async';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';

import 'display_settings.dart';
import 'providers.dart';
import 'quick_settings_sheet.dart';
import 'system_chrome.dart';

final Logger _log = Logger('ReaderScreen');

/// How long the position must stay unchanged before it is saved.
const Duration saveDebounce = Duration(seconds: 1);

/// How long display settings must stay unchanged before they are saved.
const Duration displaySaveDebounce = Duration(milliseconds: 300);

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
    this.onOpenHistory,
    this.onOpenSettings,
    super.key,
  });

  /// The book to read.
  final BookId bookId;

  /// Where to open the book; `null` resumes from the saved position.
  final Locator? locator;

  /// Called by the "Разминка" button with the current position; without it
  /// the button is not shown.
  final void Function(Locator at)? onOpenCheatSheet;

  /// Called by the "History" button; without it the button is not shown.
  final VoidCallback? onOpenHistory;

  /// Called by the "Settings" button; without it the button is not shown.
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  late final OpenBook _openBook;
  late final SaveProgress _saveProgress;
  late final ReaderEngineFactory _factory;
  late final ProfileRepository _profiles;
  late final SystemChromeGateway _chrome;

  /// Fullscreen reading (T-087): only on a phone. On a desktop the menu is
  /// always shown and `SystemChrome` is not touched.
  late final bool _phone;

  /// Whether the menu (the app bar and the system bars) is shown; phone only.
  bool _menuVisible = false;

  /// The screen left through a menu button and is not back yet.
  bool _away = false;

  /// The last top inset seen while the menu was hidden; kept while it is
  /// shown so that the text does not move.
  double _hiddenTop = 0;

  ReaderEngine? _engine;
  OpenedBook? _opened;
  Book? _book;
  String? _error;
  StreamSubscription<ReaderEvent>? _events;
  Timer? _debounce;
  Locator? _pending;

  final ValueNotifier<DisplayPrefs> _display = ValueNotifier(
    const DisplayPrefs(),
  );
  StreamSubscription<UserProfile>? _profileSub;
  Timer? _displayDebounce;
  bool _displayLoaded = false;

  /// The last known position: reported by the engine, else where it opened.
  Locator? _current;

  /// Chapter index of the last [PositionChanged]; `null` until there is one.
  /// Read by the table of contents, which does not rebuild with the screen.
  final ValueNotifier<int?> _chapter = ValueNotifier(null);

  /// The position shown in the progress panel: where the book opened, then
  /// the last [PositionChanged].
  final ValueNotifier<Locator?> _position = ValueNotifier(null);

  /// Text length of every chapter, once measured in the background (T-104);
  /// until then the fraction of the book is estimated by chapter count.
  final ValueNotifier<List<int>?> _lengths = ValueNotifier(null);

  /// The screen is being closed; the measuring stops.
  bool _closing = false;

  /// Ranges marked in the text apart from the word being looked up: the
  /// place opened from a route link (history).
  List<Locator> _marks = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openBook = ref.read(openBookProvider);
    _saveProgress = ref.read(saveProgressProvider);
    _factory = ref.read(readerEngineFactoryProvider);
    _profiles = ref.read(profileRepositoryProvider);
    _chrome = ref.read(systemChromeProvider);
    _phone =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    _applyBars();
    _profileSub = _profiles.watch().listen(
      _onProfile,
      onError: (Object e, StackTrace s) =>
          _log.warning('Watching the profile failed', e, s),
    );
    unawaited(_start());
  }

  /// Puts the system bars in the state of [_menuVisible], or of [visible].
  void _applyBars({bool? visible}) {
    if (!_phone) return;
    final mode = (visible ?? _menuVisible)
        ? SystemUiMode.edgeToEdge
        : SystemUiMode.immersiveSticky;
    unawaited(
      _chrome.setMode(mode).catchError((Object e, StackTrace s) {
        _log.warning('Switching the system bars failed', e, s);
      }),
    );
  }

  void _setMenu({required bool visible}) {
    if (!_phone || _menuVisible == visible) return;
    setState(() => _menuVisible = visible);
    _applyBars();
  }

  /// Runs a menu button's [action]; the bars are back to normal until the
  /// screen is current again.
  void _leave(VoidCallback action) {
    _away = true;
    _applyBars(visible: true);
    action();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_away && (ModalRoute.of(context)?.isCurrent ?? true)) {
      _away = false;
      _applyBars();
    }
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
    _position.value = _current;
    _events = engine.events.listen(_onEvent);
    await engine.load(
      opened,
      bookId: widget.bookId,
      at: widget.locator ?? outcome.resumeAt,
    );
    if (!mounted) return;
    if (!_displayLoaded) {
      _display.value = (await _profiles.get()).display;
      _displayLoaded = true;
      if (!mounted) return;
    }
    final font = _display.value.font;
    if (font != null) {
      await loadUserFont(font);
      if (!mounted) return;
    }
    engine.applySettings(readerSettingsFrom(_display.value));
    // A place opened from a route link (history) is marked in the text.
    final target = widget.locator;
    if (target != null) {
      _marks = [target];
      engine.highlight(_focus(_marks));
    }
    setState(() => _book = outcome.book);
    unawaited(_measure(opened));
  }

  /// Measures the chapters of [opened] in the background; the fraction of the
  /// book then follows the text lengths. A failure keeps the estimate.
  Future<void> _measure(OpenedBook opened) async {
    try {
      final lengths = await measureChapterLengths(
        opened,
        shouldStop: () => _closing,
      );
      if (lengths != null && !_closing) _lengths.value = lengths;
    } on Object catch (e, s) {
      if (!_closing) _log.warning('Measuring the chapters failed', e, s);
    }
  }

  void _onProfile(UserProfile profile) {
    // While the user is changing a value here, the stored one is older.
    if (_displayDebounce != null) return;
    _displayLoaded = true;
    if (profile.display == _display.value) return;
    final fontChanged = profile.display.font != _display.value.font;
    _display.value = profile.display;
    final font = profile.display.font;
    if (fontChanged && font != null) {
      unawaited(_applyAfterFontLoad(font, profile.display));
    } else {
      _engine?.applySettings(readerSettingsFrom(profile.display));
    }
  }

  /// Registers [font], then applies [prefs] unless newer ones came meanwhile.
  Future<void> _applyAfterFontLoad(FontChoice font, DisplayPrefs prefs) async {
    await loadUserFont(font);
    if (!mounted || _display.value != prefs) return;
    _engine?.applySettings(readerSettingsFrom(prefs));
  }

  /// Applies [prefs] at once and saves them after [displaySaveDebounce], or
  /// right away when [immediate].
  void _changeDisplay(DisplayPrefs prefs, {bool immediate = false}) {
    _display.value = prefs;
    _engine?.applySettings(readerSettingsFrom(prefs));
    _displayDebounce?.cancel();
    if (immediate) {
      _displayDebounce = null;
      unawaited(_saveDisplay(prefs));
    } else {
      _displayDebounce = Timer(displaySaveDebounce, _flushDisplay);
    }
  }

  void _flushDisplay() {
    if (_displayDebounce == null) return;
    _displayDebounce?.cancel();
    _displayDebounce = null;
    unawaited(_saveDisplay(_display.value));
  }

  Future<void> _saveDisplay(DisplayPrefs prefs) async {
    try {
      await _profiles.save((await _profiles.get()).copyWith(display: prefs));
    } on Object catch (e, s) {
      _log.severe('Saving the display settings failed', e, s);
    }
  }

  void _toggleMode() {
    final prefs = _display.value;
    _changeDisplay(
      prefs.copyWith(
        mode: prefs.mode == DisplayMode.day
            ? DisplayMode.night
            : DisplayMode.day,
      ),
      immediate: true,
    );
  }

  void _toggleTranslate() {
    final prefs = _display.value;
    _changeDisplay(
      prefs.copyWith(translateOnSelect: !prefs.translateOnSelect),
      immediate: true,
    );
  }

  void _openQuickSettings() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) =>
          QuickSettingsSheet(display: _display, onChanged: _changeDisplay),
    );
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  void _onEvent(ReaderEvent event) {
    switch (event) {
      case TextSelected(:final text, :final at, :final sentence):
        _lookup(text, at, sentence);
        return;
      case ViewTapped():
        _setMenu(visible: !_menuVisible);
        return;
      case ChapterFinished():
        return;
      case PositionChanged():
        break;
    }
    _current = event.locator;
    _position.value = event.locator;
    _chapter.value = event.locator.chapter.index;
    _pending = event.locator;
    _debounce?.cancel();
    _debounce = Timer(saveDebounce, _flush);
  }

  void _lookup(String text, Locator at, String sentence) {
    if (!mounted) return;
    unawaited(_showLookup(text, at, sentence));
  }

  /// [places] as the `focus` highlights: the open translation and the place
  /// of a history link; no places clear everything.
  ReaderHighlights _focus(List<Locator> places) => places.isEmpty
      ? ReaderHighlights.none
      : ReaderHighlights(ranges: {HighlightKind.focus: places});

  /// Shows the lookup of [text]; while it is open, [at] is marked in the
  /// text so that the reader sees which word the tap hit.
  Future<void> _showLookup(String text, Locator at, String sentence) async {
    _engine?.highlight(_focus([..._marks, at]));
    try {
      await ref.read(lookupPresenterProvider)(
        context,
        text: text,
        at: at,
        sentence: sentence,
      );
    } on Object catch (e, s) {
      _log.severe('Showing the lookup of "$text" failed', e, s);
    } finally {
      if (mounted) _engine?.highlight(_focus(_marks));
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
      _saveProgress(
        at,
        chapterCount: opened.spine.length,
        chapterLengths: _lengths.value,
      ).catchError((Object e, StackTrace s) {
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
        // Android may bring the bars back while the app is in the background.
        if (!_menuVisible && !_away) _applyBars();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closing = true;
    _applyBars(visible: true);
    _flush();
    _flushDisplay();
    unawaited(_profileSub?.cancel());
    _display.dispose();
    _chapter.dispose();
    _position.dispose();
    _lengths.dispose();
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
      _leave(() => widget.onOpenCheatSheet?.call(at));
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
    final appBar = AppBar(
      title: Text(book.metadata.title),
      actions: [
        ValueListenableBuilder<DisplayPrefs>(
          valueListenable: _display,
          builder: (context, prefs, _) => IconButton(
            icon: Icon(
              prefs.mode == DisplayMode.day
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            tooltip: 'Day / Night',
            onPressed: _toggleMode,
          ),
        ),
        ValueListenableBuilder<DisplayPrefs>(
          valueListenable: _display,
          builder: (context, prefs, _) => IconButton(
            // On: filled button with a check mark; off: plain icon.
            isSelected: prefs.translateOnSelect,
            icon: const Icon(Icons.translate),
            selectedIcon: const Badge(
              label: Icon(Icons.check, size: 10),
              child: Icon(Icons.translate),
            ),
            style: prefs.translateOnSelect
                ? IconButton.styleFrom(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .secondaryContainer,
                  )
                : null,
            tooltip: prefs.translateOnSelect
                ? 'Translate: on'
                : 'Translate: off',
            onPressed: _toggleTranslate,
          ),
        ),
        IconButton(
          icon: const Text('Аа'),
          tooltip: 'Text',
          onPressed: _openQuickSettings,
        ),
        if (widget.onOpenCheatSheet != null)
          IconButton(
            icon: const Icon(Icons.lightbulb_outline),
            tooltip: 'Разминка',
            onPressed: _openCheatSheet,
          ),
        if (widget.onOpenHistory != null)
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () => _leave(widget.onOpenHistory!),
          ),
        if (widget.onOpenSettings != null)
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => _leave(widget.onOpenSettings!),
          ),
      ],
    );
    if (!_phone) {
      return Scaffold(
        appBar: appBar,
        drawer: _drawer(),
        body: Stack(
          children: [
            Positioned.fill(child: engine.buildView(context)),
            _progressPanel(visible: true),
          ],
        ),
      );
    }
    // Fullscreen: the app bar lies over the text and slides in, so the text
    // never changes its height or its place.
    final top = MediaQuery.viewPaddingOf(context).top;
    if (!_menuVisible) _hiddenTop = top;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _SlidingAppBar(visible: _menuVisible, child: appBar),
      drawer: _drawer(),
      body: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollStartNotification>(
              onNotification: (n) {
                if (n.dragDetails != null && _menuVisible) {
                  _setMenu(visible: false);
                }
                return false;
              },
              child: Builder(
                builder: (context) {
                  final data = MediaQuery.of(context);
                  // The cutout of the camera stays free of text; the bars
                  // are hidden, so the body would otherwise start at the
                  // very top.
                  return MediaQuery(
                    data: data.copyWith(
                      padding: data.padding.copyWith(top: _hiddenTop),
                    ),
                    child: Builder(builder: engine.buildView),
                  );
                },
              ),
            ),
          ),
          _progressPanel(visible: _menuVisible),
        ],
      ),
    );
  }

  /// The bottom panel with the progress of the book (T-104); it lies over the
  /// text, so the text does not move.
  Widget _progressPanel({required bool visible}) => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    child: _SlidingPanel(
      visible: visible,
      child: _ProgressPanel(
        toc: _opened?.toc ?? const [],
        chapterCount: _opened?.spine.length ?? 0,
        position: _position,
        lengths: _lengths,
      ),
    ),
  );

  Widget _drawer() => _TocDrawer(
    toc: _opened?.toc ?? const [],
    chapter: _chapter,
    onSelect: (entry) {
      Navigator.of(context).pop();
      unawaited(_goTo(entry));
    },
  );
}

/// The app bar that slides up out of the screen while it is hidden.
///
/// It stays in the tree (the `Scaffold` keeps its height), so the body does
/// not change; hidden, it takes no touches, focus or screen-reader reading.
class _SlidingAppBar extends StatelessWidget implements PreferredSizeWidget {
  const new({required this.visible, required this.child});

  final bool visible;
  final PreferredSizeWidget child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    excluding: !visible,
    child: ExcludeFocus(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          offset: visible ? Offset.zero : const Offset(0, -1),
          child: child,
        ),
      ),
    ),
  );
}

/// The bottom panel that slides down out of the screen while it is hidden.
///
/// Like [_SlidingAppBar], it stays in the tree; hidden, it takes no touches,
/// focus or screen-reader reading.
class _SlidingPanel extends StatelessWidget {
  const new({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    excluding: !visible,
    child: ExcludeFocus(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          offset: visible ? Offset.zero : const Offset(0, 1),
          child: child,
        ),
      ),
    ),
  );
}

/// The progress of the book: a bar and the caption `<chapter> · 37%`.
///
/// The fraction comes from [bookFraction] (by the chapter lengths when they
/// are known); the chapter is the table of contents entry of the position.
/// Without an entry the caption is only the percent. The bar only shows the
/// progress: it cannot be dragged.
class _ProgressPanel extends StatelessWidget {
  const new({
    required this.toc,
    required this.chapterCount,
    required this.position,
    required this.lengths,
  });

  final List<TocEntry> toc;
  final int chapterCount;
  final ValueListenable<Locator?> position;
  final ValueListenable<List<int>?> lengths;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Above the system navigation bar.
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 3,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8 + bottom),
        child: ListenableBuilder(
          listenable: Listenable.merge([position, lengths]),
          builder: (context, _) {
            final at = position.value;
            final fraction = at == null
                ? 0.0
                : bookFraction(
                    at,
                    chapterCount: chapterCount,
                    chapterLengths: lengths.value,
                  );
            final percent = '${(fraction * 100).round()}%';
            final title = at == null
                ? null
                : currentTocEntry(toc, at.chapter.index)?.title;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title == null ? percent : '$title · $percent',
                  style: theme.textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: fraction,
                  semanticsLabel: 'Reading progress',
                  semanticsValue: percent,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The table of contents; the entry of the current chapter is selected and
/// scrolled into view when the drawer opens.
class _TocDrawer extends StatefulWidget {
  const new({required this.toc, required this.chapter, required this.onSelect});

  final List<TocEntry> toc;

  /// Index of the chapter being read, `null` while the position is unknown.
  final ValueListenable<int?> chapter;
  final void Function(TocEntry entry) onSelect;

  @override
  State<_TocDrawer> createState() => _TocDrawerState();
}

class _TocDrawerState extends State<_TocDrawer> {
  final GlobalKey _currentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = _currentKey.currentContext;
      if (current != null) {
        Scrollable.ensureVisible(current, alignment: 0.5);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(TocEntry, int)>[];
    void collect(List<TocEntry> entries, int depth) {
      for (final entry in entries) {
        rows.add((entry, depth));
        collect(entry.children, depth + 1);
      }
    }

    collect(widget.toc, 0);
    final index = widget.chapter.value;
    final current = index == null ? null : currentTocEntry(widget.toc, index);
    return Drawer(
      child: SafeArea(
        child: rows.isEmpty
            ? const Center(child: Text('No table of contents.'))
            : SingleChildScrollView(
                child: Column(
                  children: [
                    for (final (entry, depth) in rows)
                      ListTile(
                        key: identical(entry, current) ? _currentKey : null,
                        contentPadding: EdgeInsetsDirectional.only(
                          start: 16.0 + 16.0 * depth,
                          end: 16,
                        ),
                        selected: identical(entry, current),
                        title: Text(
                          entry.title,
                          style: identical(entry, current)
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null,
                        ),
                        onTap: () => widget.onSelect(entry),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
