/// Base of all failures thrown by `HttpPackStore`.
///
/// Sealed so callers can switch exhaustively. A failed download never
/// touches the previously installed version of the pack.
sealed class PackException implements Exception {
  const new(this.message);

  /// Human-readable description for logs (not for the UI).
  final String message;

  @override
  String toString() => 'PackException: $message';
}

/// The service is unreachable, the connection dropped, a request timed out,
/// the response ended early, or the server answered with an error status.
final class PackNetworkException extends PackException {
  /// Creates the exception; [statusCode] is set for HTTP error statuses.
  const new(super.message, {this.statusCode, this.cause});

  /// HTTP status code, or null for transport failures.
  final int? statusCode;

  /// The original error, if any.
  final Object? cause;
}

/// The downloaded file does not match the sha256 from the manifest.
final class PackHashMismatchException extends PackException {
  /// Creates the exception for pack [id].
  new({required this.id, required this.expected, required this.actual})
    : super('sha256 of $id: expected $expected, got $actual');

  /// Pack id.
  final String id;

  /// Hash from the manifest.
  final String expected;

  /// Hash of the downloaded bytes.
  final String actual;
}

/// The manifest is not valid JSON of the expected shape.
final class PackManifestException extends PackException {
  /// Creates the exception.
  const new(super.message);
}

/// The manifest does not list the requested pack.
final class PackNotFoundException extends PackException {
  /// Creates the exception for pack [id].
  new(this.id) : super('pack $id is not in the manifest');

  /// Requested pack id.
  final String id;
}
