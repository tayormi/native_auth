import 'package:native_auth/native_auth.dart';
import 'package:test/test.dart';

class FakeTransport implements AuthTransport {
  final requests = <Map<String, Object?>>[];
  Map<String, Object?> result = {
    'state': 'done',
    'status': 'success',
    'method': 'biometric',
  };
  bool pending = false;
  bool cancelled = false;
  bool failStart = false;
  @override
  Map<String, Object?> request(Map<String, Object?> request) {
    requests.add(request);
    switch (request['op']) {
      case 'start':
      case 'check':
        if (failStart) throw StateError('Bridge failed');
        return pending ? {'state': 'pending'} : result;
      case 'poll':
        if (cancelled) return {'state': 'done', 'status': 'appCancelled'};
        return pending ? {'state': 'pending'} : result;
      case 'cancel':
        cancelled = pending;
        return {'cancelled': cancelled};
      case 'release':
        return {};
      default:
        throw StateError('Unexpected request');
    }
  }
}

void main() {
  late FakeTransport transport;
  late NativeAuth auth;
  setUp(() {
    transport = FakeTransport();
    auth = NativeAuth.withTransport(transport);
  });

  test(
    'defaults to biometrics only and preserves Unicode prompt text',
    () async {
      final result = await auth.authenticate(reason: 'Déverrouiller 🔐');
      expect(result.authenticated, isTrue);
      expect(result.method, AuthMethod.biometric);
      expect(transport.requests.first['policy'], 'biometricsOnly');
      expect(transport.requests.first['reason'], 'Déverrouiller 🔐');
      expect(transport.requests.last['op'], 'release');
    },
  );
  test(
    'credential fallback is explicit and method can remain unknown',
    () async {
      transport.result = {'state': 'done', 'status': 'success'};
      final result = await auth.authenticate(
        reason: 'Unlock',
        policy: AuthPolicy.biometricsOrDeviceCredential,
      );
      expect(
        transport.requests.first['policy'],
        'biometricsOrDeviceCredential',
      );
      expect(result.method, AuthMethod.unknown);
    },
  );
  for (final status in AuthStatus.values.where(
    (s) => s != AuthStatus.success,
  )) {
    test('${status.name} never authenticates', () async {
      transport.result = {
        'state': 'done',
        'status': status.name,
        'platformCode': '-8',
      };
      final result = await auth.authenticate(reason: 'Unlock');
      expect(result.authenticated, isFalse);
      expect(result.status, status);
      expect(result.platformCode, '-8');
    });
  }
  test('an unknown status or boolean does not authenticate', () async {
    transport.result = {
      'state': 'done',
      'status': 'approved',
      'authenticated': true,
    };
    expect(
      (await auth.authenticate(reason: 'Unlock')).status,
      AuthStatus.nativeError,
    );
  });
  test('availability checks never show a prompt', () async {
    transport.result = {'state': 'done', 'status': 'available'};
    expect((await auth.checkAvailability()).canAuthenticate, isTrue);
    expect(transport.requests.first['op'], 'check');
    transport.result = {'state': 'done', 'status': 'notEnrolled'};
    expect((await auth.checkAvailability()).canAuthenticate, isFalse);
  });
  test('concurrent calls do not replace an active request', () async {
    transport.pending = true;
    final first = auth.authenticate(reason: 'First');
    expect((await auth.authenticate(reason: 'Second')).status, AuthStatus.busy);
    expect(transport.requests.where((r) => r['op'] == 'start').length, 1);
    auth.cancel();
    expect((await first).status, AuthStatus.appCancelled);
  });
  test('cancel targets its own request and consumes cancellation', () async {
    expect(auth.cancel(), isFalse);
    transport.pending = true;
    final future = auth.authenticate(reason: 'Unlock');
    final id = transport.requests.first['id'];
    expect(auth.cancel(), isTrue);
    expect((await future).status, AuthStatus.appCancelled);
    expect(
      transport.requests.where((r) => r['op'] == 'cancel').single['id'],
      id,
    );
    expect(auth.cancel(), isFalse);
  });
  test('dispose cancels and prevents reuse', () async {
    transport.pending = true;
    final future = auth.authenticate(reason: 'Unlock');
    auth.dispose();
    auth.dispose();
    expect((await future).status, AuthStatus.appCancelled);
    await expectLater(auth.authenticate(reason: 'Again'), throwsStateError);
    await expectLater(auth.checkAvailability(), throwsStateError);
  });
  test('Dart timeout releases a native operation that never replies', () async {
    transport.pending = true;
    final result = await auth.authenticate(
      reason: 'Unlock',
      timeout: const Duration(seconds: 1),
    );
    expect(result.status, AuthStatus.timeout);
    expect(transport.requests.last['op'], 'release');
    transport.pending = false;
    expect((await auth.authenticate(reason: 'Retry')).authenticated, isTrue);
  });
  test('bridge failure releases request and resets busy state', () async {
    transport.failStart = true;
    await expectLater(auth.authenticate(reason: 'Unlock'), throwsStateError);
    expect(transport.requests.last['op'], 'release');
    transport.failStart = false;
    expect((await auth.authenticate(reason: 'Retry')).authenticated, isTrue);
  });
  test('malformed native response fails closed and releases', () async {
    transport.result = {'status': 'success'};
    await expectLater(
      auth.authenticate(reason: 'Unlock'),
      throwsFormatException,
    );
    expect(transport.requests.last['op'], 'release');
  });
  test(
    'validates empty, oversized, NUL text and timeout before native call',
    () async {
      for (final reason in ['', ' ', '\u0000', List.filled(257, 'a').join()]) {
        await expectLater(
          auth.authenticate(reason: reason),
          throwsArgumentError,
        );
      }
      await expectLater(
        auth.authenticate(reason: 'Unlock', title: ''),
        throwsArgumentError,
      );
      await expectLater(
        auth.authenticate(reason: 'Unlock', cancelButton: ''),
        throwsArgumentError,
      );
      await expectLater(
        auth.authenticate(reason: 'Unlock', timeout: Duration.zero),
        throwsArgumentError,
      );
      await expectLater(
        auth.authenticate(
          reason: 'Unlock',
          timeout: const Duration(minutes: 6),
        ),
        throwsArgumentError,
      );
      expect(transport.requests, isEmpty);
    },
  );
}
