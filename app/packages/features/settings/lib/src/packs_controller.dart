import 'dart:async';

import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('PacksController');

/// State of one pack in the list.
enum PackStatus {
  /// Offered by the service, not on the device.
  available,

  /// Installed and up to date (or the service is unreachable).
  installed,

  /// Installed, but the service offers another version.
  updatable,

  /// Being downloaded.
  downloading,
}

/// A row of the packs list.
@immutable
class PackRow {
  /// Creates a row.
  const new({
    required this.id,
    required this.status,
    this.offered,
    this.installedVersion,
    this.progress,
    this.error,
  });

  /// Pack id.
  final String id;

  /// Current state.
  final PackStatus status;

  /// Entry from the manifest; null while the manifest is not loaded.
  final PackManifestEntry? offered;

  /// Version on the device, if installed.
  final String? installedVersion;

  /// Download progress from 0 to 1 while [status] is downloading.
  final double? progress;

  /// Message of the last failed download.
  final String? error;
}

/// State of the packs section.
@immutable
class PacksState {
  /// Creates a state.
  const new({
    this.loading = true,
    this.manifest = const [],
    this.installed = const {},
    this.progress = const {},
    this.errors = const {},
    this.manifestError,
  });

  /// Whether the list is being (re)loaded.
  final bool loading;

  /// What the service offers; empty if it was not reached.
  final List<PackManifestEntry> manifest;

  /// Installed versions by pack id.
  final Map<String, String> installed;

  /// Progress of running downloads by pack id.
  final Map<String, double> progress;

  /// Messages of failed downloads by pack id.
  final Map<String, String> errors;

  /// Message if the manifest could not be loaded.
  final String? manifestError;

  /// Rows: every offered pack, then installed packs the service does not offer.
  List<PackRow> get rows {
    final offered = {for (final e in manifest) e.id: e};
    final ids = {...offered.keys, ...installed.keys};
    return [
      for (final id in ids)
        PackRow(
          id: id,
          offered: offered[id],
          installedVersion: installed[id],
          progress: progress[id],
          error: errors[id],
          status: _statusOf(id, offered[id]),
        ),
    ];
  }

  PackStatus _statusOf(String id, PackManifestEntry? entry) {
    if (progress.containsKey(id)) return PackStatus.downloading;
    final version = installed[id];
    if (version == null) return PackStatus.available;
    if (entry != null && entry.version != version) return PackStatus.updatable;
    return PackStatus.installed;
  }

  /// Copy with some fields replaced; [manifestError] can be cleared.
  PacksState copyWith({
    bool? loading,
    List<PackManifestEntry>? manifest,
    Map<String, String>? installed,
    Map<String, double>? progress,
    Map<String, String>? errors,
    String? Function()? manifestError,
  }) => PacksState(
    loading: loading ?? this.loading,
    manifest: manifest ?? this.manifest,
    installed: installed ?? this.installed,
    progress: progress ?? this.progress,
    errors: errors ?? this.errors,
    manifestError: manifestError != null ? manifestError() : this.manifestError,
  );
}

/// Loads the packs list and runs downloads.
///
/// Rebuilt (and so reloaded) when [packStoreProvider] changes, for example
/// after the service address is edited.
class PacksController extends Notifier<PacksState> {
  @override
  PacksState build() {
    ref.watch(packStoreProvider);
    // The state is not set yet: start after build returns.
    unawaited(Future<void>.microtask(refresh));
    return const PacksState();
  }

  /// Reloads installed packs (works offline) and the manifest (needs network).
  Future<void> refresh() async {
    final store = ref.read(packStoreProvider);
    state = state.copyWith(loading: true);
    try {
      final installed = await store.installed();
      if (!ref.mounted) return;
      state = state.copyWith(
        installed: {for (final p in installed) p.id: p.version},
      );
    } on Exception catch (e, s) {
      _log.warning('Cannot read installed packs', e, s);
      if (!ref.mounted) return;
      state = state.copyWith(manifestError: () => 'Cannot read packs: $e');
    }
    try {
      final manifest = await store.manifest();
      if (!ref.mounted) return;
      state = state.copyWith(manifest: manifest, manifestError: () => null);
    } on Exception catch (e) {
      _log.warning('Service is not reachable', e);
      if (!ref.mounted) return;
      state = state.copyWith(
        manifest: const [],
        manifestError: () => 'Service is not reachable: $e',
      );
    }
    if (ref.mounted) state = state.copyWith(loading: false);
  }

  /// Downloads (or updates) pack [id], reporting progress in the state.
  Future<void> download(String id) async {
    if (state.progress.containsKey(id)) return;
    final store = ref.read(packStoreProvider);
    state = state.copyWith(
      progress: {...state.progress, id: 0},
      errors: {...state.errors}..remove(id),
    );
    try {
      final pack = await store.download(id, (fraction) {
        if (!ref.mounted) return;
        state = state.copyWith(progress: {...state.progress, id: fraction});
      });
      if (!ref.mounted) return;
      state = state.copyWith(
        installed: {...state.installed, pack.id: pack.version},
        progress: {...state.progress}..remove(id),
      );
    } on Exception catch (e, s) {
      _log.warning('Download of $id failed', e, s);
      if (!ref.mounted) return;
      state = state.copyWith(
        progress: {...state.progress}..remove(id),
        errors: {...state.errors, id: 'Download failed: $e'},
      );
    }
  }
}

/// Provider of [PacksController].
final NotifierProvider<PacksController, PacksState> packsControllerProvider =
    NotifierProvider<PacksController, PacksState>(PacksController.new);
