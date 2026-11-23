import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The system bars (status and navigation) of the phone.
///
/// A small interface so that tests can fake and check the calls.
abstract interface class SystemChromeGateway {
  /// Switches the system bars to [mode].
  Future<void> setMode(SystemUiMode mode);
}

/// [SystemChromeGateway] over `SystemChrome`.
final class PlatformSystemChrome implements SystemChromeGateway {
  /// Creates the gateway.
  const new();

  @override
  Future<void> setMode(SystemUiMode mode) =>
      SystemChrome.setEnabledSystemUIMode(mode);
}

/// The system bars the reader hides while reading (T-087); override in tests.
final Provider<SystemChromeGateway> systemChromeProvider =
    Provider<SystemChromeGateway>(
      (ref) => const PlatformSystemChrome(),
      name: 'systemChromeProvider',
    );
