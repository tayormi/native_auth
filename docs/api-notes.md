# API notes

`authenticate` and `checkAvailability` return futures. They do not block the Dart isolate while the system prompt is visible. Native operations run on the platform UI thread; Dart checks request completion while an operation is pending.

## Policies and results

`biometricsOnly` never grants access based on a device passcode. `biometricsOrDeviceCredential` lets the operating system offer its own passcode, PIN, pattern, or password screen. The package does not draw a password form or fall back to an app password.

Android requests `BIOMETRIC_STRONG` in both policies. The first release requires API 30 so the same authenticator mask works for availability checks and prompts.

iOS uses a new `LAContext` for every operation and does not configure a biometric reuse interval. It reports `AuthMethod.biometric` for a successful biometric-only prompt. For the combined policy it reports `unknown`, because LocalAuthentication does not identify which method succeeded. Android reports the method supplied by the system callback.

A mismatched Android biometric scan is nonterminal: the system can offer another attempt. The Dart future completes when the system succeeds, ends the prompt, or the request is cancelled or times out.

`platformCode` contains an OS code or a package diagnostic. Cancellation and unavailable authentication are result values. Invalid Dart options throw `ArgumentError`; missing native bindings and malformed bridge responses throw. Neither case grants access.

## Lifecycle

Calling `cancel` affects only the prompt owned by that `NativeAuth` instance. Native code also rejects concurrent prompts from other instances or isolates. A terminal result cannot be overwritten by a late success callback. Calling cancel after native success does not retroactively change that completed result.

The native side has its own deadline and removes abandoned results. Releasing a Dart operation cancels unfinished native work. Timeout checks use monotonic clocks.

On iOS, backgrounding cancels an active prompt. On Android, destroying the host or detaching the engine cancels it; stopping the host cancels biometric-only prompts. A combined-policy request follows the system lifecycle because Android's credential screen can itself stop the host. Applications must manage their own relocking behavior and should call `cancel()` when abandoning a protected action. The first terminal event wins; for example, pressing Home can return `userCancelled` if Android dismisses the prompt before the host stops.

## Security boundary

A successful result is a local UI authentication decision. It is not a signed assertion for a backend, proof of a specific account identity, or an authentication-bound key operation. For secrets that must remain inaccessible until authentication, a separate Keychain access-control or Android Keystore integration is required.

## Platform references

- [Apple LocalAuthentication](https://developer.apple.com/documentation/localauthentication)
- [Android biometric authentication](https://developer.android.com/identity/sign-in/biometric-auth)
- [Android BiometricPrompt](https://developer.android.com/reference/android/hardware/biometrics/BiometricPrompt)
