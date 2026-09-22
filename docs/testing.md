# Testing

Run the Dart API tests from the package directory:

```sh
dart pub get
dart analyze
dart test
```

Build the native libraries and local archives from a Git checkout:

```sh
python3 tools/build_release.py --dn /path/to/dn
```

The script includes the native source needed by DartNative consumers and corrects the generated binary podspec's license to MIT. It does not publish anything.

## Device example

Run `dn pub get` in `example`, then build with `--dart-define=AUTH_TEST_DRIVER=true` to enable its local command driver. Ordinary builds keep the driver disabled.

With the example running on an iOS simulator:

```sh
python3 tools/device_command.py ios SIMULATOR_UDID \
  '{"id":"availability","action":"check"}'
```

For an Android debug build, use `android DEVICE_SERIAL`; `adb` must be on your path, or pass `--adb /path/to/adb`.

Commands support `check`, `start`, and `cancel`. Set `fallback: true` for the combined policy. A `start` command accepts a timeout in seconds. Use `--wait 0` to leave a prompt open while interacting with the device or sending a cancel command. Results are saved as `auth-result-ID.json` in the app's documents directory: `Documents` on iOS and `files` on Android. Use unique IDs for each run.

Test on an enrolled device: success, a rejected scan followed by success, user cancellation, app cancellation, timeout, concurrent requests, backgrounding, and a fresh request after each terminal result. Also test without enrollment and with device-credential fallback.

A successful simulator test verifies the bridge and OS callback handling. Physical-device checks are still needed for hardware behavior and biometric lockout.

See [local verification](verification.md) for the tested environments and remaining device checks.

After creating the GitHub repository and accepting the registry publishing agreement, `python3 tools/publish_release.py` uploads the prepared archives using the configured DartNative publish token. It records an accepted upload and prevents a blind retry.
