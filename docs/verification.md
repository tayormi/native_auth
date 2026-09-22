# Local verification

Verified on September 22, 2026 with DartNative 3.45 prerelease and Dart 3.12 prerelease.

- Dart package: analyzer clean; 25 tests pass. The example's Dart source also analyzes cleanly.
- Native libraries: iOS device arm64 and simulator arm64/x86_64 compile; Android AAR builds for arm64-v8a, armeabi-v7a, x86, and x86_64.
- iPhone 17 Pro simulator, iOS 26.4: unavailable without enrollment, available with enrollment, Face ID success, concurrent-request rejection, app cancellation, timeout, retry after cancellation and timeout, and background cancellation pass. Direct native requests also confirm that cancellation survives a late simulated match and consumed results cannot be reused.
- Pixel 9a emulator, Android API 36: no-enrollment detection, combined-policy availability with a PIN, and successful system PIN authentication pass. The result identifies the method as `deviceCredential`. Enrolled fingerprint success, a rejected scan followed by success, concurrent-request rejection, app cancellation, timeout, and retry pass too. Back and Home dismiss the prompt without authenticating; both returned `userCancelled` on this emulator. Direct native checks confirm concurrent rejection and that a late match cannot overwrite cancellation.
- Release candidate recheck: all 25 Dart tests pass again. A fresh app built from the source archive passes iOS Face ID, timeout, and app cancellation. Android builds and runs in release mode with R8 minification and resource shrinking enabled; system PIN authentication returns `success (deviceCredential)`. The native JNI entry class remains present in the R8 mapping.
- Source archive: includes Swift, Java, JNI, podspec, Gradle files, tests, docs, and the example; excludes build directories, local SDK paths, and generated settings.

These are local build and simulator/emulator results. Physical devices, biometric lockout, iOS passcode fallback, older supported OS versions have not been tested.
