/// Native request transport. Supply an implementation for isolated Dart tests.
abstract interface class AuthTransport {
  Map<String, Object?> request(Map<String, Object?> arguments);
}
