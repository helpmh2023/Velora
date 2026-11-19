# Contributing to Velora

Thanks for wanting to help. Velora is a personal project, so the process is
light.

## Ways to help

- **Report a bug** – open an issue with what you did, what you expected, what
  happened, and your Windows version. Screenshots help. If a title would not
  play, include which source you picked (quality and provider), not just the
  title.
- **Suggest a feature** – open an issue first so we can agree on the idea before
  you spend time on code.
- **Send a pull request** – fixes are always welcome. For larger changes, open
  an issue first.

## Setting up

See "Build from source" in the [README](README.md). In short:

```powershell
flutter pub get
powershell -File scripts/build_engine.ps1   # needs Go
flutter run -d windows
```

## Before you open a pull request

```powershell
dart format lib test
flutter analyze        # must report no issues
flutter test           # must pass
```

- Add or update tests for behaviour you change. The `test/` folder has
  examples for providers, parsing and widgets, with mocked network calls (tests
  never hit the real Cinemeta, Torrentio or Trakt).
- Keep changes focused; one topic per pull request.
- Don't commit secrets, tokens, personal paths, or built binaries
  (`build/`, `dist/`, `*.exe`).
- Match the existing style: small widgets, logic in providers and services,
  comments that explain *why*.

## Code layout

```
lib/
  core/        platform helpers, theme bits, smooth scrolling, storage, benchmark
  models/      plain data classes (MetaItem, StreamSource, WatchProgress ...)
  services/    network + engine clients (Cinemeta, Torrentio, Trakt, engine)
  providers/   app state (ChangeNotifier)
  screens/     one folder per screen
  widgets/     reusable glass UI pieces
native/velora_engine/   Go torrent-streaming engine
shaders/                GLSL aurora background
installer/, scripts/    Windows packaging
```

## License

By contributing you agree that your contribution is licensed under the
project's [MIT License](LICENSE).
