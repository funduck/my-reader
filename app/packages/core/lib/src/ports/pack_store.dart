import 'package:meta/meta.dart';

/// Callback with download progress in the range 0.0..1.0.
typedef PackProgress = void Function(double fraction);

/// A pack offered by the service.
@immutable
final class PackManifestEntry {
  /// Creates an entry.
  const new({
    required this.id,
    required this.version,
    required this.sizeBytes,
    required this.sha256,
  });

  /// Pack id, e.g. `en-en`.
  final String id;

  /// Pack version; a different version means an update.
  final String version;

  /// Download size in bytes.
  final int sizeBytes;

  /// Expected SHA-256 of the file, lower-case hex.
  final String sha256;

  @override
  bool operator ==(Object other) =>
      other is PackManifestEntry &&
      other.id == id &&
      other.version == version &&
      other.sizeBytes == sizeBytes &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(id, version, sizeBytes, sha256);
}

/// A pack present on the device.
@immutable
final class InstalledPack {
  /// Creates a record.
  const new({required this.id, required this.version});

  /// Pack id.
  final String id;

  /// Installed version.
  final String version;

  @override
  bool operator ==(Object other) =>
      other is InstalledPack && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}

/// Data packs from the service: list, download, versions (P-3).
///
/// Network and checksum failures are thrown as exceptions; the previously
/// installed version stays intact when a download fails.
abstract interface class PackStore {
  /// Fetches the list of packs the service offers; needs network.
  Future<List<PackManifestEntry>> manifest();

  /// Lists packs installed on the device; works offline.
  Future<List<InstalledPack>> installed();

  /// Downloads and installs the latest version of pack [id], verifying sha256.
  ///
  /// Reports progress through [onProgress].
  Future<InstalledPack> download(String id, PackProgress onProgress);

  /// Returns the file path of installed pack [id], or null if not installed.
  Future<String?> pathOf(String id);

  /// Deletes installed pack [id]; does nothing if it is not installed.
  Future<void> remove(String id);
}
