import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'transport.dart';

/// Resolves the native ABI. Normally initialized by the generated registrant.
final class NativeAuthBindings implements AuthTransport {
  NativeAuthBindings._() {
    final library = Platform.isAndroid
        ? DynamicLibrary.open('libnative_auth.so')
        : DynamicLibrary.process();
    _call = library
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)
        >('DnauthRequest');
    _free = library
        .lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)
        >('DnauthFree');
  }
  static NativeAuthBindings? _instance;
  static bool get isSupported => Platform.isIOS || Platform.isAndroid;
  static NativeAuthBindings get instance {
    if (!isSupported) {
      throw UnsupportedError('native_auth supports iOS and Android.');
    }
    return _instance ??= NativeAuthBindings._();
  }

  static void loadSymbols() {
    if (isSupported) instance;
  }

  late final Pointer<Utf8> Function(Pointer<Utf8>) _call;
  late final void Function(Pointer<Utf8>) _free;

  @override
  Map<String, Object?> request(Map<String, Object?> arguments) {
    final input = jsonEncode(arguments).toNativeUtf8();
    Pointer<Utf8> output = nullptr;
    try {
      output = _call(input);
      if (output == nullptr) {
        throw StateError('native_auth could not allocate a response.');
      }
      final decoded = jsonDecode(output.toDartString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid native auth response.');
      }
      return decoded;
    } finally {
      calloc.free(input);
      if (output != nullptr) _free(output);
    }
  }
}
