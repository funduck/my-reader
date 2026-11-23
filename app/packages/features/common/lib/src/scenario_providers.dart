import 'package:core/application.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'port_providers.dart';

/// The scenario "mark a word known / learning", built from ports.
///
/// Shared by the lookup sheet, the history and the cheat sheet; its ports are
/// wired by the app, and reading it before that throws `PortNotWiredError`.
final Provider<SetTermStatus> setTermStatusProvider = Provider<SetTermStatus>(
  (ref) => SetTermStatus(
    terms: ref.watch(termRepositoryProvider),
    levels: ref.watch(levelDictionaryProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
  name: 'setTermStatusProvider',
);
