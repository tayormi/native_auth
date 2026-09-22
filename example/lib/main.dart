import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartnative/dartnative.dart';
import 'package:dartnative_path_provider/dartnative_path_provider.dart';
import 'package:native_auth/native_auth.dart';
import 'dartnative_plugin_registrant.dart';

void main() {
  DartNativePluginRegistrant.registerAll();
  runApp(const AuthExample());
}

class AuthExample extends StatefulWidget {
  const AuthExample({super.key});
  @override
  State<AuthExample> createState() => _AuthExampleState();
}

class _AuthExampleState extends State<AuthExample> {
  final auth = NativeAuth();
  String message = 'Choose an authentication policy.';
  Timer? driver;

  @override
  void initState() {
    super.initState();
    if (const bool.fromEnvironment('AUTH_TEST_DRIVER')) {
      driver = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => runCommand(),
      );
    }
  }

  Future<void> authenticate(AuthPolicy policy) async {
    setState(() => message = 'Waiting for authentication…');
    try {
      final result = await auth.authenticate(
        reason: 'Unlock the example 🔐',
        policy: policy,
      );
      if (mounted) {
        setState(
          () => message = '${result.status.name} (${result.method.name})',
        );
      }
    } catch (error) {
      if (mounted) setState(() => message = 'Could not authenticate: $error');
    }
  }

  Future<void> check() async {
    final result = await auth.checkAvailability();
    if (mounted) setState(() => message = 'Biometrics: ${result.status.name}');
  }

  // Disabled in normal builds. A local file driver makes device QA repeatable.
  Future<void> runCommand() async {
    final docs = getApplicationDocumentsDirectory();
    final command = File('$docs/auth-command.json');
    if (!command.existsSync()) return;
    Map<String, dynamic> args;
    try {
      args = jsonDecode(command.readAsStringSync()) as Map<String, dynamic>;
      command.deleteSync();
    } catch (_) {
      return;
    }
    final result = <String, Object?>{'id': args['id']};
    try {
      final policy = args['fallback'] == true
          ? AuthPolicy.biometricsOrDeviceCredential
          : AuthPolicy.biometricsOnly;
      if (args['action'] == 'check') {
        final value = await auth.checkAvailability(policy: policy);
        result.addAll({
          'status': value.status.name,
          'canAuthenticate': value.canAuthenticate,
          'code': value.platformCode,
        });
      } else if (args['action'] == 'cancel') {
        result['cancelled'] = auth.cancel();
      } else if (args['action'] == 'raw') {
        result.addAll(
          NativeAuthBindings.instance.request(
            Map<String, Object?>.from(args['arguments'] as Map),
          ),
        );
      } else {
        final value = await auth.authenticate(
          reason: 'Verify the example 🔐',
          policy: policy,
          timeout: Duration(seconds: args['timeout'] as int? ?? 30),
        );
        result.addAll({
          'status': value.status.name,
          'authenticated': value.authenticated,
          'method': value.method.name,
          'code': value.platformCode,
        });
      }
    } catch (error) {
      result['error'] = '$error';
    }
    File(
      '$docs/auth-result-${args['id']}.json',
    ).writeAsStringSync(jsonEncode(result));
    if (mounted) setState(() => message = jsonEncode(result));
  }

  @override
  void dispose() {
    driver?.cancel();
    auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Native Auth')),
    backgroundColor: const Color(0xFFFFFFFF),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Button(onPressed: check, child: const Text('Check biometrics')),
            const SizedBox(height: 12),
            Button(
              onPressed: () => authenticate(AuthPolicy.biometricsOnly),
              child: const Text('Use biometrics'),
            ),
            const SizedBox(height: 12),
            Button(
              onPressed: () =>
                  authenticate(AuthPolicy.biometricsOrDeviceCredential),
              child: const Text('Allow passcode fallback'),
            ),
            const SizedBox(height: 12),
            Button(
              onPressed: () {
                auth.cancel();
              },
              child: const Text('Cancel prompt'),
            ),
          ],
        ),
      ),
    ),
  );
}
