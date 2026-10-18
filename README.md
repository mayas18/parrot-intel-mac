<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/icon-dark.png">
    <img src="docs/assets/icon.png" width="96" alt="parrot">
  </picture>
</p>

# parrot

Hold `fn`, speak, release. Your words appear at the cursor. On-device dictation for macOS.

This fork adds **Intel Mac support** to [Parrot by Humanitas Labs](https://github.com/humanitas-labs/parrot). Intel transcription uses a bundled whisper.cpp helper. Install this fork from source using the instructions below; no DMG or automatic update feed has been published for it. This fork is intended for Intel Macs; **Apple Silicon users should install [upstream Parrot](https://github.com/humanitas-labs/parrot)**. Current verification notes are in [log.md](log.md).

## 1. Install

### Intel Mac from this fork

Requires macOS 14 or later, Git, Swift 5.10 or later, [CMake](https://cmake.org/download/), and a working macOS Command Line Tools or Xcode installation. The first build downloads dependencies and compiles the Intel helper. On an Intel Mac, run:

```sh
git clone https://github.com/mayas18/parrot-intel-mac.git
cd parrot-intel-mac
PARROT_INSTALL_DIR="$HOME/Applications" PARROT_LINK_DIR="$HOME/.local/bin" scripts/dev-install.sh
export PATH="$HOME/.local/bin:$PATH"
parrot --version
parrot models download whisper-base.en
parrot doctor
```

The source installer replaces `Parrot.app` in the chosen directory and retains upstream's app name and bundle identifier. Quit any existing Parrot before installing this fork.

Open `~/Applications/Parrot.app`, grant Microphone and Accessibility when prompted, and use the menu bar app. Run `parrot doctor` again after granting permissions. To run from a terminal instead, quit the menu bar app first, then run `parrot`. Add `~/.local/bin` to your shell startup file if it is not already on your `PATH`. The first model download is about 150 MB. This local build is ad-hoc signed unless you have a Developer ID certificate; macOS may require permission grants again after rebuilding.

The website and terminal installer are prepared for future fork releases, but source installation is currently required. Upstream downloads and the `perroquet.xyz` installer do not contain this Intel backend. Automatic updates are disabled until this fork has its own signed release feed.

## 2. Usage

1. Click into any text field.
2. Hold `fn` and speak. A small pill at the bottom of the screen shows the mic is live. On a keyboard where `fn` does nothing (Logitech and most third-party keyboards), choose another key under **Hotkey** in **Settings…**: left or right Option, Command, Control, or Shift. The change applies from the next press.
3. Release. The transcript is pasted at the cursor, and your clipboard is restored. Processing time varies with the Mac, model, and length of speech; Intel Macs may take longer than Apple Silicon Macs.

Choose **Launch at login** in **Settings…** to start Parrot with your Mac. A tap shorter than 0.3 s, or a hold with another modifier, is ignored, so shortcuts on the hotkey still work. If `fn` is mapped to input source or emoji, `parrot doctor` shows how to fix it.

To dictate in another language, choose a multilingual model in Settings (⌘, from the menu), then choose a Language or Automatic. On Apple Silicon, Automatic chooses among the configured **Languages**. On Intel, whisper.cpp Automatic can detect any supported language and currently ignores that list; choose an explicit Language when you need a fixed language or a language-specific dictionary prompt. English `whisper-base.en` always decodes English.

## 3. Dictionary

Add your names and technical terms to `~/.config/parrot/dictionary`, a plain-text table of each word and what the model writes instead, and Parrot spells them your way. **Open Dictionary File** in Settings opens it. Edits apply on the next dictation. See [docs/dictionary.md](docs/dictionary.md).

## 4. CLI

| Command | What it does |
|---|---|
| `parrot` | Run in the foreground (^C to quit) |
| `parrot setup` | One-time setup: permissions and model download |
| `parrot doctor` | Check permissions, and the `fn` key setting when the hotkey is `fn` |
| `parrot install --launch-at-login` | Start Parrot at login |
| `parrot install --cli` | Link `/usr/local/bin/parrot` to Parrot.app |
| `parrot install --uninstall` | Stop launching at login and remove logs |
| `parrot models list` | List available models |
| `parrot --model whisper-large-v3-turbo` | Larger, multilingual model |
| `parrot --hotkey right-option` | Use another key for this run only; Settings… changes the saved key |
| `parrot --no-overlay` | Hide the recording pill |
| `parrot --inject-mode type-unicode` | Type instead of paste (leaves the clipboard alone) |

## 5. How it works

On Apple Silicon, WhisperKit runs Whisper through Core ML and can use the Apple Neural Engine. On Intel, a bundled, CPU-based `whisper.cpp` helper runs a separate GGML model. AVAudioEngine captures the mic, a CGEventTap watches the hotkey, and a synthesized ⌘V pastes the result. Nothing leaves your Mac, and logs never contain what you said. See [docs/architecture.md](docs/architecture.md).

## 6. Build from source

```sh
PARROT_INSTALL_DIR="$HOME/Applications" PARROT_LINK_DIR="$HOME/.local/bin" scripts/dev-install.sh
swift test # Requires full Xcode
```

`scripts/dev-install.sh` builds the app for this Mac, builds the pinned Intel `whisper.cpp` helper with CMake, signs and installs Parrot.app, and links the CLI. A plain `swift build` compiles the current architecture but does not bundle the Intel helper. The release script can target a universal `arm64`/`x86_64` app, but this fork is verified on Intel; Apple Silicon users should use upstream. Full Xcode is required to run the XCTest suite; Command Line Tools alone can build the app. Use a consistent toolchain and SDK. A Developer ID signing identity is needed for permissions to survive local rebuilds. See [log.md](log.md) for the tested Intel machine and a workaround for its mixed Command Line Tools installation.

Intel model downloads use separate GGML weights under `~/Library/Application Support/parrot/models/whisper-cpp/`; existing Core ML downloads are not reused. All four listed models have GGML downloads. `whisper-base.en` is the tested default; larger models require more memory and their speed depends on the Mac. The Intel helper loads its model for each dictation. A synthetic speech fixture benchmark achieved 0% word error rate; microphone capture and pasting still require local permission grants and user verification.

## 7. Attribution and license

Parrot is [MIT licensed](LICENSE), copyright Humanitas Labs. This fork retains the original license and attribution.

Intel inference uses [whisper.cpp v1.9.5](https://github.com/ggml-org/whisper.cpp/tree/v1.9.5) and its bundled ggml, distributed under the [MIT license](https://github.com/ggml-org/whisper.cpp/blob/v1.9.5/LICENSE). Their license notice is included in `Parrot.app/Contents/Resources/Licenses/` alongside Parrot's. Whisper models originate from [OpenAI Whisper](https://github.com/openai/whisper), distributed under the MIT license; Intel GGML conversions are downloaded from [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp). Apple Silicon uses [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift).
