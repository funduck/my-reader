import 'package:core/ports.dart';

/// An in-memory [PackStore] with scripted manifest and failures.
///
/// [download] installs the manifest entry of the pack; no file exists, so
/// [pathOf] returns a made-up path `/fake/packs/<id>.sqlite`. A failed
/// download leaves the installed version untouched.
class FakePackStore implements PackStore {
  /// Creates a store offering [offered] and having [installedPacks] installed.
  new({
    List<PackManifestEntry> offered = const [],
    List<InstalledPack> installedPacks = const [],
  }) : offered = List.of(offered),
       _installed = {for (final p in installedPacks) p.id: p};

  /// What the service offers; tests may edit it.
  final List<PackManifestEntry> offered;

  /// If not null, [manifest] and [download] throw it (network failure).
  Exception? error;

  final Map<String, InstalledPack> _installed;

  @override
  Future<List<PackManifestEntry>> manifest() async {
    final error = this.error;
    if (error != null) throw error;
    return List.unmodifiable(offered);
  }

  @override
  Future<List<InstalledPack>> installed() async =>
      List.unmodifiable(_installed.values);

  @override
  Future<InstalledPack> download(String id, PackProgress onProgress) async {
    final error = this.error;
    if (error != null) throw error;
    final entry = offered.where((e) => e.id == id).firstOrNull;
    if (entry == null) throw StateError('Pack not offered: $id');
    onProgress(0);
    onProgress(0.5);
    final pack = InstalledPack(id: id, version: entry.version);
    _installed[id] = pack;
    onProgress(1);
    return pack;
  }

  @override
  Future<String?> pathOf(String id) async =>
      _installed.containsKey(id) ? '/fake/packs/$id.sqlite' : null;

  @override
  Future<void> remove(String id) async => _installed.remove(id);
}
