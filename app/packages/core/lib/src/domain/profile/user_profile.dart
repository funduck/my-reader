import 'package:meta/meta.dart';

import '../lookup/cefr_level.dart';
import '../lookup/ids.dart';
import '../lookup/lookup_mode.dart';
import 'cheat_sheet_scope.dart';
import 'display_prefs.dart';
import 'highlight_prefs.dart';
import 'last_screen.dart';

/// Cheat sheet limit of a new profile.
const defaultCheatSheetLimit = 10;

/// Smallest cheat sheet limit.
const minCheatSheetLimit = 1;

/// Largest cheat sheet limit.
const maxCheatSheetLimit = 500;

/// A missing key or a value that is not a number gives the default; an
/// explicit null (once "all") gives the maximum; a number is clamped to
/// [minCheatSheetLimit]..[maxCheatSheetLimit].
int _limitFromJson(Map<String, Object?> json) {
  if (!json.containsKey('cheatSheetLimit')) return defaultCheatSheetLimit;
  final value = json['cheatSheetLimit'];
  if (value == null) return maxCheatSheetLimit;
  if (value is! num || !value.isFinite) return defaultCheatSheetLimit;
  return value.toInt().clamp(minCheatSheetLimit, maxCheatSheetLimit);
}

/// User settings that the core needs.
@immutable
final class UserProfile {
  /// Creates a profile; every field has a default.
  const new({
    this.mode = LookupMode.enEn,
    this.level = CefrLevel.b2,
    this.scope = CheatSheetScope.defaultScope,
    this.cheatSheetLimit = defaultCheatSheetLimit,
    this.providerOrder = const [],
    this.serviceUrl,
    this.display = const DisplayPrefs(),
    this.highlights = const HighlightPrefs(),
    this.lastScreen,
  });

  /// Reads a profile; missing or invalid fields take defaults.
  factory fromJson(Map<String, Object?> json) {
    final level = CefrLevel.fromJson(json['level']);
    final order = json['providerOrder'];
    final url = json['serviceUrl'];
    return UserProfile(
      mode: LookupMode.fromJson(json['mode']),
      level: level.isKnown ? level : CefrLevel.b2,
      scope: CheatSheetScope.fromJson(json['scope']),
      cheatSheetLimit: _limitFromJson(json),
      providerOrder: order is List<Object?>
          ? [
              for (final e in order)
                if (e is String) ProviderId(e),
            ]
          : const [],
      serviceUrl: url is String && url.isNotEmpty ? url : null,
      display: DisplayPrefs.fromJson(json['display']),
      highlights: HighlightPrefs.fromJson(json['highlights']),
      lastScreen: LastScreen.fromJson(json['lastScreen']),
    );
  }

  /// Default lookup mode.
  final LookupMode mode;

  /// Reader's level; cheat sheet shows words above it.
  final CefrLevel level;

  /// Size of the cheat sheet piece.
  final CheatSheetScope scope;

  /// Most words on the cheat sheet. Only
  /// [minCheatSheetLimit]..[maxCheatSheetLimit] are allowed.
  final int cheatSheetLimit;

  /// Preferred provider order; empty means "use registration order".
  final List<ProviderId> providerOrder;

  /// Address of the service, if configured.
  final String? serviceUrl;

  /// How the reader looks.
  final DisplayPrefs display;

  /// Which text highlights are on and the frequency threshold.
  final HighlightPrefs highlights;

  /// The reader or cheat sheet to reopen at launch; `null` — the library.
  final LastScreen? lastScreen;

  /// Copy with some fields replaced. [serviceUrl] and [lastScreen] take a
  /// function so that `() => null` can clear them.
  UserProfile copyWith({
    LookupMode? mode,
    CefrLevel? level,
    CheatSheetScope? scope,
    int? cheatSheetLimit,
    List<ProviderId>? providerOrder,
    String? Function()? serviceUrl,
    DisplayPrefs? display,
    HighlightPrefs? highlights,
    LastScreen? Function()? lastScreen,
  }) => UserProfile(
    mode: mode ?? this.mode,
    level: level ?? this.level,
    scope: scope ?? this.scope,
    cheatSheetLimit: cheatSheetLimit ?? this.cheatSheetLimit,
    providerOrder: providerOrder ?? this.providerOrder,
    serviceUrl: serviceUrl != null ? serviceUrl() : this.serviceUrl,
    display: display ?? this.display,
    highlights: highlights ?? this.highlights,
    lastScreen: lastScreen != null ? lastScreen() : this.lastScreen,
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'mode': mode.toJson(),
    'level': level.toJson(),
    'scope': scope.toJson(),
    'cheatSheetLimit': cheatSheetLimit,
    'providerOrder': [for (final p in providerOrder) p.value],
    'serviceUrl': serviceUrl,
    'display': display.toJson(),
    'highlights': highlights.toJson(),
    'lastScreen': lastScreen?.toJson(),
  };

  @override
  bool operator ==(Object other) {
    if (other is! UserProfile ||
        other.mode != mode ||
        other.level != level ||
        other.scope != scope ||
        other.cheatSheetLimit != cheatSheetLimit ||
        other.serviceUrl != serviceUrl ||
        other.display != display ||
        other.highlights != highlights ||
        other.lastScreen != lastScreen ||
        other.providerOrder.length != providerOrder.length) {
      return false;
    }
    for (var i = 0; i < providerOrder.length; i++) {
      if (other.providerOrder[i] != providerOrder[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    level,
    scope,
    cheatSheetLimit,
    serviceUrl,
    display,
    highlights,
    lastScreen,
    Object.hashAll(providerOrder),
  );
}
