# Roko Input · 洛克输入法

[简体中文](README.md) · **English**

A source-only macOS voice input project for personal, non-commercial use. Hold your shortcut to speak, release it to stop, and insert the final transcript at the cursor.

## Apple models only. On-device recognition only.

Roko Input uses **only Apple's built-in Speech framework and on-device speech models**. It does not include a third-party recognition model, cloud ASR API, API key, analytics SDK, or application network client.

Every recognition request sets `requiresOnDeviceRecognition = true`. Before starting, the app checks `supportsOnDeviceRecognition`. If on-device Chinese recognition is unsupported or unavailable, it reports an error and **does not fall back to cloud recognition**. Recognition runs locally without uploading audio or transcripts.

This is an application-level recognition policy, not a claim that macOS as a whole makes no network connections. Apple manages speech resources; downloading or preparing missing system language resources may require connectivity outside this app. Existing resources are required for offline use. On-device availability and accuracy vary by hardware, OS and language. See Apple's [on-device recognition requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition) and [capability check](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition).

**Version 0.4.0 changes the earlier prototype's behavior:** older versions allowed Apple to choose the processing location. Only the new implementation enforces on-device recognition. Previous tests do not establish this version's recognition accuracy or offline reliability.

## Features

- Menu-bar-only startup: settings stay closed until opened from the Roko menu.
- Hold-to-talk, with F5 as the default; release stops audio capture. Holds shorter than 0.5 seconds show a reminder and are discarded without insertion, transcript history or statistics.
- A small nonactivating orange-gradient waveform capsule at the bottom of the screen while recording. Bars reflect microphone RMS level, not recognition progress. Release shows a finalizing indicator; success hides it. It never steals editor focus.
- A shortcut recorder for function keys or combinations containing Command, Option or Control. Preferences persist; registration conflicts retain the previous shortcut.
- Apple's automatic punctuation and intermediate transcript display.
- InputMethodKit integration in the macOS input-source menu. Select Roko Input to insert text; Accessibility permission is not requested or required.
- A statistics window: today's recognized characters, successful dictations, recorded minutes, average first-result time, seven daily rows, and all-time characters.
- Optional daily transcript history, a menu-bar controller, and editable final text.

The app does not contain a Pinyin conversion engine. Ordinary keyboard events pass through. It does not automatically press Return or send a message.

## Requirements and source build

macOS 13+, Apple Silicon or Intel, Xcode Command Line Tools, a microphone, and available Apple on-device Chinese (`zh-CN`) speech resources. Microphone and Speech permissions are required. Accessibility permission is not needed. Select Roko Input before dictating into another app.

**This repository contains source code only. There are no DMG/PKG installers, prebuilt apps, release archives, or installer-generation scripts.** Build locally:

```sh
zsh scripts/test.sh
zsh scripts/build.sh
```

The build script creates a local universal application in `build/Roko Input.app` using system frameworks and an ad-hoc signature. Build output is ignored by Git and is not distributed. There are no third-party package dependencies.

For a local installation, quit the running app, then run:

```sh
zsh scripts/install-local.sh
```

This **source script**, not an installer binary, builds and copies the app to `~/Library/Input Methods/Roko Input.app`. It backs up an existing copy under the app data directory and registers/enables the input source without selecting it. Add Roko Input in System Settings → Keyboard → Text Input → Edit → +. Log out and back in if macOS has not refreshed its input-source list. Local builds are not Developer ID signed or notarized.

## Usage

1. Select Roko Input from the system input-source menu. If another input method is active, the app asks you to switch instead of requesting Accessibility access.
2. Put the cursor in a normal text field. Hold **F5**, speak after recording starts, then release it.
3. The app waits for a final result and inserts it into the original active target. If focus changes, text is retained for manual copying where detectable.
4. Open the Roko menu → settings → **设置快捷键** to record your own shortcut. Esc cancels; **恢复 F5** restores the default. Modifier-only shortcuts are not supported.
5. Use **查看输入统计** in settings or **输入统计** in the menu bar to see statistics.

Some keyboards need Fn+F5 to produce a standard function key. Resolve conflicts with system dictation or other apps yourself; Roko Input does not change those system settings. The window's Start/Stop buttons are for manual dictation; they do not automatically insert into another app. Closing the window keeps the menu-bar app running.

Secure input mode blocks dictation. Do not dictate secrets into ordinary fields. Automatic insertion uses InputMethodKit only; it does not simulate keystrokes or use clipboard paste. The explicit Copy button still writes to the clipboard.

## Permission flow

Already-authorized microphone and Speech access go straight to recording. The app requests access only while the corresponding status is not determined. Initial permission setup does not start a dictation: completion asks you to hold the shortcut again. Denied/restricted access is explained without repeatedly requesting it. A changed development signing identity may cause macOS to require authorization again after an update; source checks cannot override system identity decisions.

Recognition snapshots with non-overlapping audio timestamps preserve earlier utterances; overlapping snapshots revise the same utterance. Untimed hypotheses are not blindly appended. This mitigates client-side replacement but cannot recover audio that Apple never recognized or guarantee complete long dictation. Diagnostic system logs contain counts/timing availability, not transcript text.

## Troubleshooting

`kLSRErrorDomain / 201` means Siri and Dictation are disabled. Enable **System Settings → Keyboard → Dictation**, review Apple's system privacy notice yourself, and retry. This system prerequisite is separate from Roko's on-device-only request policy; Roko does not enable it automatically. Error 102 indicates missing local speech resources. Error 1110 means no speech was recognized.

## Statistics: what is counted?

Only **nonempty final recognition results completed since this feature was added** contribute to statistics, once per dictation. They measure recognized text, not confirmed delivery to an editor. Manual dictations count too. Failed/interrupted partial results do not count. A dictation is currently limited to 55 seconds; a visible reminder asks you to release and start a new hold when that limit is reached. Speech after that limit is not captured. Editing or copying text afterwards does not add counts.

Characters are Swift grapheme clusters containing a letter or decimal digit. Chinese characters and Latin letters/digits count individually; punctuation, whitespace and emoji do not. This is a character count, not an English word count. Days follow the system's local calendar/time zone. Recording time excludes finalization. First-result time is measured from request setup, not detected speech onset.

Aggregates live at:

```text
~/Library/Application Support/Roko Input/statistics.json
```

They contain dates and numeric totals, **no transcript text**. They remain enabled when transcript history is disabled. Earlier logs are not silently imported. A malformed statistics file is reported, not overwritten. Quit the app and delete this file to reset statistics.

## Transcript history and privacy

```text
~/Library/Application Support/Roko Input/History/YYYY-MM-DD.jsonl
```

History is enabled by default as requested. Each nonempty dictation is one JSONL record, even when it contains multiple sentences; intermediate results are not duplicated. Interrupted text is explicitly marked `final: false`. New records identify the backend as Apple on-device Speech. No raw audio is saved.

Use **打开文字日志目录** to open the folder. Turn off **保存每次转写的文字历史** to stop future text records. This does not erase existing files or disable numeric statistics. Delete individual date files in Finder to remove history. These plaintext files have no automatic expiration; OS backups or other software under your account may read them. The History directory uses mode 0700 and record files/statistics use mode 0600. Logs and statistics are excluded from Git. Never attach private transcripts to a public issue.

## Repository and verification

`Sources/` contains recognition, shortcut registration, text insertion, local history and statistics. `Resources/` contains input-source metadata/localization. `Tests/` covers hold/release state, history encoding/permissions, statistics aggregation/counting/corruption handling and shortcut serialization. `scripts/` contains source build, local install, tests and icon generation only.

Unit checks and compilation do not establish live recognition, global-key delivery, network traffic, or compatibility with every editor. Test those on your device after granting permissions, including with network access unavailable. Apple model availability is a runtime prerequisite; unsupported devices intentionally cannot dictate. Do not substitute a cloud fallback.

## License — personal use only, no commercial use

This project is **source-available for personal, non-commercial use only**, under the custom [Roko Input Personal Non-Commercial License](LICENSE). It is not MIT-licensed and is not an unrestricted open-source license. Commercial use, business or organizational use, paid services, resale and commercial integration are prohibited. Keep the license and attribution with permitted copies and modifications. Apple's models/frameworks are not relicensed by this project.

### Settings workspace

Open **macOS input menu → 洛克输入法设置…** to access the four settings pages:

- **Voice input:** a three-step tutorial, the orange F5 keyboard illustration, live microphone/Speech permission status, and a manual dictation preview. If you change the talk shortcut, its current value is shown beside the tutorial.
- **Shortcuts:** record separate global shortcuts for hold-to-talk and switching directly to Roko Input. The switch shortcut is optional and does not record audio. Duplicate or occupied shortcuts preserve the previous setting. Roko must already be added to macOS input sources.
- **Statistics:** today's characters, sessions, speaking time, average first-result latency, lifetime characters, and a seven-day chart. Counts describe recognized text, not confirmed delivery to another app.
- **Input history:** enable or disable new transcript logging, browse one day at a time, search that day's text, copy entries, or open the local folder in Finder. Existing history stays available when logging is disabled. No audio is stored.

The keyboard illustration is bundled locally; the settings interface requires no network connection.
