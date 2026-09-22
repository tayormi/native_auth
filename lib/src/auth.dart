import 'dart:async';
import 'dart:math';
import 'bindings.dart';
import 'transport.dart';

/// Android accepts only Class 3 (strong) biometrics in either policy.
enum AuthPolicy { biometricsOnly, biometricsOrDeviceCredential }

enum AuthAvailabilityStatus {
  available,
  notEnrolled,
  noHardware,
  unavailable,
  lockedOut,
  passcodeNotSet,
  unsupported,
  invalidConfiguration,
  nativeError,
}

enum AuthStatus {
  success,
  failed,
  userCancelled,
  systemCancelled,
  appCancelled,
  timeout,
  busy,
  notEnrolled,
  noHardware,
  unavailable,
  lockedOut,
  passcodeNotSet,
  unsupported,
  invalidConfiguration,
  nativeError,
}

/// iOS does not identify the method used by its combined policy.
enum AuthMethod { biometric, deviceCredential, unknown }

final class AuthAvailability {
  const AuthAvailability(this.status, {this.platformCode});
  final AuthAvailabilityStatus status;
  final String? platformCode;
  bool get canAuthenticate => status == AuthAvailabilityStatus.available;
}

final class AuthResult {
  const AuthResult(
    this.status, {
    this.method = AuthMethod.unknown,
    this.platformCode,
  });
  final AuthStatus status;
  final AuthMethod method;

  /// An OS error code or a package diagnostic. Never contains credentials.
  final String? platformCode;
  bool get authenticated => status == AuthStatus.success;
}

/// System authentication prompts. This is not a server login or a key-unlock API.
final class NativeAuth {
  NativeAuth() : _transport = null;
  NativeAuth.withTransport(AuthTransport transport) : _transport = transport;

  final AuthTransport? _transport;
  String? _activeId;
  bool _disposed = false;
  static bool get isSupported => NativeAuthBindings.isSupported;
  AuthTransport get _backend => _transport ?? NativeAuthBindings.instance;

  Future<AuthAvailability> checkAvailability({
    AuthPolicy policy = AuthPolicy.biometricsOnly,
  }) async {
    _checkDisposed();
    if (_transport == null && !isSupported) {
      return const AuthAvailability(AuthAvailabilityStatus.unsupported);
    }
    final response = await _run(
      'check',
      policy: policy,
      timeout: const Duration(seconds: 10),
    );
    return AuthAvailability(
      _enumValue(
        AuthAvailabilityStatus.values,
        response['status'],
        AuthAvailabilityStatus.nativeError,
      ),
      platformCode: response['platformCode'] as String?,
    );
  }

  Future<AuthResult> authenticate({
    required String reason,
    String title = 'Authenticate',
    String cancelButton = 'Cancel',
    AuthPolicy policy = AuthPolicy.biometricsOnly,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    _checkDisposed();
    for (final entry in {
      'reason': reason,
      'title': title,
      'cancelButton': cancelButton,
    }.entries) {
      if (entry.value.trim().isEmpty ||
          entry.value.length > 256 ||
          entry.value.contains('\u0000')) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          'Use 1–256 characters without NUL.',
        );
      }
    }
    if (timeout < const Duration(seconds: 1) ||
        timeout > const Duration(minutes: 5)) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'Use between one second and five minutes.',
      );
    }
    if (_transport == null && !isSupported) {
      return const AuthResult(AuthStatus.unsupported);
    }
    if (_activeId != null) return const AuthResult(AuthStatus.busy);
    final response = await _run(
      'start',
      policy: policy,
      timeout: timeout,
      reason: reason,
      title: title,
      cancelButton: cancelButton,
    );
    return AuthResult(
      _enumValue(AuthStatus.values, response['status'], AuthStatus.nativeError),
      method: _enumValue(
        AuthMethod.values,
        response['method'],
        AuthMethod.unknown,
      ),
      platformCode: response['platformCode'] as String?,
    );
  }

  /// Cancels only the prompt started by this instance. A completed result wins.
  bool cancel() {
    final id = _activeId;
    if (id == null) return false;
    return _backend.request({'op': 'cancel', 'id': id})['cancelled'] == true;
  }

  /// Cancels an active prompt and prevents new operations on this instance.
  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
  }

  void _checkDisposed() {
    if (_disposed) throw StateError('NativeAuth has been disposed.');
  }

  Future<Map<String, Object?>> _run(
    String operation, {
    required AuthPolicy policy,
    required Duration timeout,
    String reason = '',
    String title = '',
    String cancelButton = '',
  }) async {
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    if (operation == 'start') _activeId = id;
    final stopwatch = Stopwatch()..start();
    try {
      var response = _backend.request({
        'op': operation,
        'id': id,
        'policy': policy.name,
        'reason': reason,
        'title': title,
        'cancelButton': cancelButton,
        'timeoutMs': timeout.inMilliseconds,
      });
      while (response['state'] == 'pending') {
        if (stopwatch.elapsed >= timeout) {
          return {'status': 'timeout'};
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (stopwatch.elapsed >= timeout) return {'status': 'timeout'};
        response = _backend.request({'op': 'poll', 'id': id});
      }
      if (response['state'] != 'done') {
        throw const FormatException('Invalid native auth response state.');
      }
      return response;
    } finally {
      try {
        _backend.request({'op': 'release', 'id': id});
      } finally {
        if (_activeId == id) _activeId = null;
      }
    }
  }
}

T _enumValue<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.where((value) => value.name == name).firstOrNull ?? fallback;
