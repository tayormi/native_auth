# native_auth

Biometric authentication and optional device-passcode fallback for DartNative.

- **iOS 15+:** Face ID, Touch ID, and device passcode through LocalAuthentication.
- **Android 11+:** Class 3 (strong) biometrics and device PIN, pattern, or password through BiometricPrompt.

## Install

Add the package to your DartNative app:

```yaml
dependencies:
  native_auth:
    hosted: https://dartpub.dev
    version: ^0.1.0
```

Run `dn pub get`, then rebuild the app. Your generated plugin registrant loads the native bindings.

For iOS, set the deployment target to 15 or newer and add this to `ios/Runner/Info.plist`:

```xml
<key>NSFaceIDUsageDescription</key>
<string>Use Face ID to unlock your private content.</string>
```

For Android, set `minSdk = 30`. The package declares `USE_BIOMETRIC`; no change to your main activity is needed. Your DartNative SDK may require a newer OS than this package.

## Authenticate

```dart
import 'package:native_auth/native_auth.dart';

final auth = NativeAuth();
final result = await auth.authenticate(
  reason: 'Unlock your private content',
  policy: AuthPolicy.biometricsOrDeviceCredential,
);

if (result.authenticated) {
  // Show the protected screen.
}
```

The default policy is `biometricsOnly`. Passcode fallback must be selected explicitly. The system collects credentials; your app never receives them.

## Check and cancel

```dart
final availability = await auth.checkAvailability();
if (!availability.canAuthenticate) {
  print(availability.status); // For example: notEnrolled or lockedOut.
}

auth.cancel();  // Cancel this instance's active prompt.
auth.dispose(); // Cancel and prevent this instance from starting more work.
```

Use the same policy when checking availability and authenticating. Availability can change before a prompt starts, so always check the authentication result too.

Results distinguish success, user cancellation, app cancellation, system cancellation, timeout, lockout, and unavailable authentication. Only `AuthStatus.success` sets `authenticated` to `true`.

One prompt can run at a time across the process. A second request returns `busy`. The default timeout is 60 seconds and can be set between one second and five minutes.

This package authenticates the device user. It does not perform server sign-in, unlock a Keychain item, or authorize a cryptographic operation. Your app owns its unlocked state and must relock when appropriate, including after backgrounding.

See the [example app](example/README.md), [API notes](docs/api-notes.md), and [testing guide](docs/testing.md).

MIT license.
