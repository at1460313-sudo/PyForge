# PyForge — the offline Python IDE for Android

A premium, zero-friction Python IDE built with **Flutter** and **Chaquopy** (embedded
CPython). Editor, debugger, terminal, lessons, challenges, snippets and progress
tracking all work **fully offline**. AI features are optional and BYOK
(Bring Your Own Key).

> **What you're holding:** the complete Flutter project — `lib/` (Dart),
> `android/` (Gradle + Kotlin bridge), `android/app/src/main/python/` (the Python
> half of the bridge), `pubspec.yaml` and this README. You compile the APK locally;
> nothing here is a web app.

---

## 1. System architecture

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                              FLUTTER (Dart)                                 │
│                                                                             │
│  ┌──────────┐  ┌───────────┐  ┌────────────┐  ┌──────────────────────────┐  │
│  │  UI      │  │  State    │  │ Services   │  │  Theme Manager           │  │
│  │  - IDE   │  │  (provider│  │  - AI svc  │  │  - Dark / Light / OLED    │  │
│  │  - Learn │  │   models) │  │  - Secure  │  │  - One Dark Pro, Dracula, │  │
│  │  - Pkgs  │  │           │  │    storage │  │    Monokai, Nord, …      │  │
│  │  - Snips │  │           │  │  - Git     │  │  - Syntax mode (custom)   │  │
│  │  - Stats │  │           │  │            │  │                           │  │
│  └────┬─────┘  └─────┬─────┘  └──────┬─────┘  └──────────────────────────┘  │
│       │              │               │                                        │
│  ┌────▼──────────────▼───────────────▼───────────────────────────────────┐  │
│  │ PythonBridge (Dart)   —  MethodChannel 'pyforge/bridge' (commands)      │  │
│  │                       —  MethodChannel 'pyforge/events' (events)       │  │
│  └───────────────────────────────────────┬───────────────────────────────┘  │
└──────────────────────────────────────────┼──────────────────────────────────┘
                                           │ platform channel (JSON)
┌──────────────────────────────────────────▼──────────────────────────────────┐
│  KOTLIN  —  PythonBridge.kt (MainActivity)                                    │
│  • single background worker thread (serialized interpreter access)           │
│  • streams output / debugger pauses / input() requests back to Dart        │
│  • debugger handoff: Python blocks in debugPause() until Step/Continue/Stop  │
└──────────────────────────────────────────┬──────────────────────────────────┘
                                           │ Chaquopy (embedded CPython 3.10)
┌──────────────────────────────────────────▼──────────────────────────────────┐
│  PYTHON  —  pyforge/bridge.py                                                │
│  • run_code: exec with live stdout/stderr streaming + input() + Stop         │
│  • debug_run: sys.settrace tracer (real pause/step/continue)                 │
│  • check_syntax (Error Lens), challenge_check (auto-graded tests)            │
│  • git via dulwich (init/commit/push over HTTPS)                            │
│  • package listing / install attempts                                        │
└─────────────────────────────────────────────────────────────────────────────┘

  External (optional, only when the user triggers an action):
    • AI providers — OpenAI / Anthropic / Gemini / OpenRouter / custom
      (key kept in flutter_secure_storage, sent only to the chosen endpoint)
    • Git remote (HTTPS push), package downloads (build time)
```

**Everything inside the dashed boxes is offline.** The only network calls the app
ever makes are: AI Co-Pilot actions (user-initiated, BYOK), git push (optional),
and runtime package-install attempts.

---

## 2. Prerequisites

| Tool | Version | Check |
|---|---|---|
| Flutter SDK | latest stable (≥ 3.27 recommended) | `flutter --version` |
| Android Studio | latest, with Android SDK | — |
| Java / JDK | 17 (bundled with recent Android Studio) | `java -version` |
| Android SDK | API 35, build-tools, platform-tools | via Android Studio |
| Python (build machine) | any 3.x (used by Chaquopy's build-time pip) | `python3 --version` |

Install Flutter from [flutter.dev/docs/get-started/install](https://docs.flutter.dev/get-started/install)
and run `flutter doctor`. Fix anything it reports before continuing.

> Windows users: also install
> [Git for Windows](https://git-scm.com/download/win) so the `gradlew` wrapper can
> run. Mac users: Xcode is not needed (Android only).

---

## 3. Set up the project

```bash
cd pyforge
flutter create . --platforms=android --project-name pyforge
flutter pub get
```

`flutter create .` only adds the few generated files the project intentionally
omits — including the **Gradle wrapper** (`gradlew`, `gradlew.bat` and
`gradle-wrapper.jar`), which cannot be shipped as plain text. It will not
overwrite the files shipped here; if it asks about existing files, keep ours.

Afterwards, verify the wrapper exists:

```bash
ls android/gradlew android/gradle/wrapper/gradle-wrapper.jar
```

**Verify the Android toolchain picked everything up:**

```bash
flutter doctor
flutter devices          # your phone or emulator should be listed
```

---

## 4. Build & install

### CLI (fastest)

```bash
# Debug build — installs and runs instantly
flutter run                    # device must be connected / emulator running

# Release APK
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
flutter install                # installs the release APK on your device
```

### Android Studio

1. **File → Open** → select the `pyforge` folder (the one containing `pubspec.yaml`).
2. Wait for Gradle sync (first sync downloads ~1 GB of dependencies — this is normal).
3. Select your device in the toolbar and press **Run ▶**.

### No toolchain at all: build in the cloud (GitHub Actions)

The project ships with `.github/workflows/build-apk.yml`. Push the repo to
GitHub and the workflow builds the release APK on every push to `main` —
download it from the **Actions** tab → latest run → artifact `pyforge-release-apk`.
It also runs the Python bridge host tests on every build. First run takes
roughly 15–25 minutes. The APK is signed with the debug keystore (fine for
sideloading; see section 7 for store signing).

First build takes several minutes: Chaquopy downloads a CPython build and compiles
`numpy` wheels for every Android ABI. Subsequent builds are much faster.

### Run on a real phone

Enable **Developer options → USB debugging** on the phone, connect it, accept the
fingerprint dialog, then `flutter run` (or press ▶ in Android Studio). Wi-Fi
debugging also works: pair with `adb pair`, then the device appears in `flutter devices`.

---

## 5. First steps in the app

1. The IDE opens with `hello.py` — tap the green **▶** button. Output streams into
   the terminal panel at the bottom.
2. Introduce a syntax error — the red **Error Lens** banner appears above the
   editor with a **Fix it** button (needs an AI key) after ~0.5 s.
3. Tap the **bug icon** button in the toolbar to debug: execution pauses at line 1
   with the variable explorer; use **Step / Continue / Stop**.
4. Set breakpoints with the **bookmark icon** (toggles a breakpoint on the cursor line).
5. Explore **Learn** for lessons and auto-graded challenges, **Snippets** for
   boilerplate, **Progress** for your streak.

---

## 6. Feature guide

### Editor
- **IntelliSense**: keywords, builtins with parameter hints, and every symbol defined
  in the open document — tap a suggestion to insert. Triggered while typing.
- **Error Lens**: debounced syntax check after each pause in typing; the banner shows
  `Ln <line>: <message>` with a one-tap AI fix.
- **Bracket colorizer**: `()` `[]` `{}` each get their own color (rainbow-by-type).
- **TODO/FIXME**: highlighted inside comments.
- **Keyboard bar**: Tab, arrows, brackets, `=`/`==`, `#`, undo/redo — appears when
  the editor has focus.
- **Focus mode**: the fullscreen icon hides all chrome; the exit button stays
  top-right.

### Runner & debugger
- Streamed stdout/stderr, `input()` support (a field appears when the program asks),
  and a working **Stop** button: normal runs are line-traced (a small performance
  cost) so even `while True: pass` can be interrupted. Note that a tight loop inside
  a C extension (e.g. a huge numpy computation) can still only finish on its own —
  that is a platform limit of any embedded interpreter.
- The debugger is a **real** step-through: the Python worker thread blocks at each
  pause until you press Step/Continue/Stop. The variable explorer shows the live
  `repr` of every local at that line.

### Packages
Chaquopy compiles Python packages **into the APK at build time**; a full pip
runtime is not guaranteed on-device (Chaquopy's supported model is build-time
bundling). PyForge handles this honestly:
- **Installed tab** lists everything bundled (numpy and requests are included).
- **Install** tries a runtime pip; if the build doesn't include pip, you get the
  exact `install("name")` line to paste into `android/app/build.gradle`, then rebuild:

```groovy
chaquopy {
    defaultConfig {
        pip {
            install("numpy")
            install("requests")
            install("pandas")        // ← add what you need, then rebuild
        }
    }
}
```

Only pure-Python packages and packages with wheels for Android (Chaquopy's
[package repo](https://chaquo.com/pypi-13.1/) list) can be bundled; `pandas` etc.
work, but heavy compiled libraries may not — check Chaquopy's supported list.

### AI Co-Pilot (BYOK)
Settings → AI Co-Pilot: choose provider (OpenAI, OpenRouter, Anthropic, Gemini, or
any OpenAI-compatible endpoint), pick/type a model, paste your key, **Test
connection**. The key is stored with `flutter_secure_storage` (Android Keystore
encrypted) and only sent to the provider you chose, only when you trigger an action.
Features: **Explain this code**, **Fix my bug** (renders a real diff — Apply or
Discard, applied edits are undoable with ↺), **Quiz me** (interactive, graded
in-app), and the **Explain / Fix it** buttons on crashed runs, which translate the
traceback to plain English.

### Version control
- **Init** creates a Git repository (dulwich) inside your workspace; **Commit**
  stages and commits everything; **Push** sends to an HTTPS remote using the token
  kept in secure storage (credentials are injected into an in-memory URL only and
  never written to the repo).
- Remove the `install("dulwich==0.22.1")` line from `android/app/build.gradle` if
  you don't want version control — everything else keeps working.

### Curriculum & progress
Six lessons, six auto-graded challenges (tests run on-device in an isolated
namespace), five cheat sheets, and a dashboard with day-streaks, challenges,
lessons read, lines written and programs run.

---

## 7. Release signing (Play Store)

Debug builds use the debug keystore automatically. For a store release:

```bash
keytool -genkey -v -keystore ~/pyforge-release.keystore -alias pyforge \
  -keyalg RSA -keysize 2048 -validity 10000
```

Create `android/key.properties`:

```properties
storePassword=<your password>
keyPassword=<your password>
keyAlias=pyforge
storeFile=<absolute path to pyforge-release.keystore>
```

Then `flutter build apk --release` (the build.gradle here picks it up
automatically). Never commit `key.properties` or the keystore.

---

## 8. Troubleshooting

| Problem | Fix |
|---|---|
| `flutter doctor` shows no devices | Enable USB debugging; `adb devices` should list it |
| First Gradle sync fails with a Python error | Install Python 3 on your machine (Chaquopy's build-time pip needs it); then `flutter clean` and retry |
| `CardThemeData` / `withValues` errors in `flutter analyze` | Your Flutter is older than 3.27 — run `flutter upgrade` |
| `re_highlight` style name error (e.g. `draculaTheme`) | Names were verified against the published source; if your resolved version differs, open the imported style file and match the export name (one-line fix) |
| Build fails on `dulwich` | Remove `install("dulwich==0.22.1")` from `android/app/build.gradle` |
| Build fails on `numpy` | Your machine needs the Python + build tools Chaquopy requires; see [Chaquopy docs](https://chaquo.com/chaquopy/doc/current/android.html). You can also remove the numpy line — the app still runs |
| Chaquopy plugin not found | Ensure `mavenCentral()` is in the `pluginManagement` repositories in `android/settings.gradle` (already included) |
| App runs but Python features do nothing | Check Logcat for `python.stdout` / `python.stderr` and `com.chaquo.python` errors |
| AI "Test connection" 401/404 | Wrong key or model name; also check the base URL for OpenRouter/custom providers |
| Push fails | Only HTTPS remotes are supported; check that the token has push access to the repo |

---

## 9. Verification matrix (honest status)

What was actually verified while building this project:

| Component | Status |
|---|---|
| Python bridge logic (`run_code`, `debug_run` tracer, `check_syntax`, `challenge_check`, cancellation, input()) | **Tested on host CPython 3** — 21 checks in `tools/host_test_bridge.py`, including a genuine blocking verification that the debugger pauses until a command arrives: run it yourself with `python3 tools/host_test_bridge.py` |
| Dart code | Written against verified APIs of re_editor 0.10 / re_highlight (fetched from source); unit tests included for the pure-Dart helpers (`test/ai_parsing_test.dart`). Not compiled here (no Flutter SDK on the build machine) — run `flutter analyze` locally |
| Kotlin bridge | Written against Chaquopy 17.1 / Flutter embedding docs; compiled only on your machine |
| On-device behavior | Awaits your first `flutter run` — if anything misbehaves, the Logcat tags in section 8 will pinpoint it |

Known platform limits (documented above): runtime pip is best-effort; C-extension
loops cannot be force-killed; bracket colors are per-type rather than per-depth.

---

## 10. Project layout

```
pyforge/
├── pubspec.yaml
├── tools/host_test_bridge.py  ← host tests for the Python bridge
├── lib/
│   ├── main.dart
│   ├── theme/            app + syntax themes
│   ├── editor/           python grammar, autocomplete
│   ├── services/         python bridge, AI, secure storage
│   ├── state/             provider models (workspace, run, debugger…)
│   ├── ui/                screens (IDE, learn, packages, settings…)
│   ├── data/              snippets, curriculum
│   └── utils/             AI response parsing + diff
├── test/                  pure-Dart unit tests
└── android/
    ├── settings.gradle, build.gradle, gradle.properties
    └── app/
        ├── build.gradle   ← Chaquopy plugin + pip block
        └── src/main/
            ├── AndroidManifest.xml
            ├── kotlin/com/pyforge/ide/
            │   ├── PyForgeApp.kt        (starts Python)
            │   ├── MainActivity.kt
            │   └── PythonBridge.kt      (channels + debugger handoff)
            ├── python/pyforge/bridge.py (the Python half)
            └── res/                      (themes, adaptive icon)
```

MIT-licensed dependencies throughout. Built with Flutter, re_editor, re_highlight,
provider, flutter_secure_storage, http, shared_preferences, path_provider,
share_plus, Chaquopy, dulwich.
