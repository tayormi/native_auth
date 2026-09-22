# Native Auth example

Run from this directory:

```sh
dn pub get
dn run
```

Choose an enrolled iOS or Android device to test successful authentication. The app includes Face ID usage text and targets iOS 15+ and Android 11+. Select your own Apple development team when running on an iPhone.

The buttons check biometric availability, open a biometric-only prompt, open a prompt that allows device-passcode fallback, and cancel an active request.

For automated device checks, build with `--dart-define=AUTH_TEST_DRIVER=true`. This enables a local file driver in the example app only. It is disabled in ordinary builds.
