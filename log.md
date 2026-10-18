# Intel Mac development log

This is the working log for the public [`mayas18/parrot-intel-mac`](https://github.com/mayas18/parrot-intel-mac) fork. It records changes and checks on the target Mac; source changes alone do not establish that dictation works.

## 2026-10-18 — Target and scope

- Target: Intel Core i5 MacBook Pro (`x86_64`), macOS 14.6.1.
- Starting state: no installed Parrot.app or `parrot` command; upstream's app build and public download served Apple Silicon.
- Goal: install and call `parrot`, acquire a local model, dictate with the microphone and hotkey, and deliver text into the focused app. Preserve Apple Silicon support and prepare a universal release build.
- Public `perroquet.xyz` downloads still serve upstream releases. This fork has no published Intel DMG.

## Backend decision

- The original Intel Core ML approach compiled and downloaded a 143 MB model, but inference crashed in Argmax WhisperKit's `MLMultiArray` initialization on this x86_64 host (exit 139). The crash report was retained locally and is not part of this repository.
- Intel now uses a bundled, CPU-only `whisper.cpp` CLI and separate GGML weights; Apple Silicon keeps WhisperKit. The helper build pins `whisper.cpp` v1.9.5 at commit `d1be6fde11ac6e0407606b4e42fe72d34add8037`.
- Audio is passed in a private temporary WAV that is removed after decoding. The transcript is read from the helper's stdout and is not written to a transcript file.

## Build and install verified

- Built the `x86_64` Parrot executable and whisper.cpp helper, assembled `build/Parrot.app`, and passed `codesign --verify --deep --strict` with a local ad-hoc signature. Both executable and helper are `x86_64`.
- Installed to `~/Applications/Parrot.app` with `~/.local/bin/parrot` linked to it. `parrot --version` reports `0.2.3-intel-dev`.
- `parrot models download whisper-base.en` completed. The GGML `base.en` model is cached under `~/Library/Application Support/parrot/models/whisper-cpp/` (141 MB; SHA-256 `a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002`).
- The target Command Line Tools installation has mismatched SwiftPM interfaces and a duplicate Swift bridging module map. A temporary wrapper, module cache, and VFS overlay under `/tmp` enabled the local build without changing system toolchain files. SwiftPM also needed `--disable-keychain` to avoid a stalled dependency lookup. Full Xcode/XCTest is unavailable, so the Swift unit suite has not run on this machine.

## Inference and live run verified

- Direct `whisper-cli` inference on a 16 kHz mono speech fixture returned the exact reference: “The quick brown fox jumps over the lazy dog.”
- The final Swift `parrot-bench` path on the same 2.6 s fixture returned 0 word errors out of 9, 100% first-word accuracy, and 1.174 s repeat inference. An earlier benchmark using the installed app's helper also passed at 0/9 word errors.
- The installed menu bar app launched, received Microphone and Accessibility grants, and reported `listening on fn hold`. Its runtime log then recorded a real Fn hold, 2.96 s of microphone audio, a 32-character transcription, and completed text delivery in 1.402 s after release. Logs omit spoken and transcribed text by design, so this does not independently prove the characters appeared in the intended field or that the clipboard was restored; visual confirmation remains useful.

## Remaining release work

1. Visually confirm a dictated phrase in the target text field and clipboard restoration on this Mac.
2. Build and inspect both slices of a universal app on a suitable release host. The current host check covers `x86_64` only.
3. Run Swift unit tests where a working XCTest toolchain is available. The new GGML model naming and WAV encoding tests have compiled only as source review here.
4. Publish a signed and notarized Intel-capable release only when Developer ID signing and notarization credentials are available. There is no such credential on the test Mac; this repository currently provides source builds.

## Public source release

- Published this fork as source with upstream history and the Humanitas Labs MIT license. The bundle build now includes both the Parrot and whisper.cpp/ggml MIT notices.
- The helper build targets macOS 14.0; the repackaged helper reports `minos 14.0`. The assembled app passed strict signature verification, and the bundled helper achieved 0% word error rate on the speech fixture.
- Automatic updates are disabled until this fork has its own signed release feed. There is no signed or notarized Intel DMG yet.
- Linked the fork in [upstream issue #48](https://github.com/humanitas-labs/parrot/issues/48#issuecomment-6246258580), which invites links to maintained ports.
