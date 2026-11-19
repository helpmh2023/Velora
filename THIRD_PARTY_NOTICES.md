# Third-party notices

Velora itself is released under the [MIT License](LICENSE). It is built on, and
its release builds bundle, the open-source components below. Each keeps its own
license. This list covers what ships in the app; transitive Dart/Flutter
packages carry their own licenses (run `flutter pub deps` or see
`pubspec.lock`, and the app's built-in license page).

## Bundled in release builds

| Component | Used for | License |
|---|---|---|
| [Flutter](https://flutter.dev) engine and framework | UI | BSD-3-Clause |
| [media_kit](https://github.com/media-kit/media-kit), `media_kit_video`, `media_kit_libs_windows_video` | Video playback bindings | MIT |
| [libmpv](https://mpv.io) + [FFmpeg](https://ffmpeg.org) (`libmpv-2.dll`, from the media-kit [libmpv-win32-video-build](https://github.com/media-kit/libmpv-win32-video-build)) | Video decoding and rendering | LGPL-3.0-or-later (this build is configured with `--disable-gpl`) |
| [ANGLE](https://github.com/google/angle) (`libEGL.dll`, `libGLESv2.dll`) | OpenGL ES on Windows | BSD-3-Clause |
| [anacrolix/torrent](https://github.com/anacrolix/torrent) and its dependencies (compiled into `velora_engine.exe`) | Torrent streaming engine | MPL-2.0 (library); dependencies under MIT / BSD / Apache-2.0 |
| [provider](https://pub.dev/packages/provider), [http](https://pub.dev/packages/http), [window_manager](https://pub.dev/packages/window_manager), [flutter_shaders](https://pub.dev/packages/flutter_shaders), [flutter_animate](https://pub.dev/packages/flutter_animate), [hive_ce](https://pub.dev/packages/hive_ce), [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage), [path_provider](https://pub.dev/packages/path_provider), [url_launcher](https://pub.dev/packages/url_launcher), [crypto](https://pub.dev/packages/crypto) | App functionality | MIT / BSD-3-Clause |
| Microsoft Visual C++ runtime (`vcruntime140*.dll`, `msvcp140.dll`) | C++ runtime for the Windows app | Microsoft redistributable terms |

### About libmpv (LGPL)

`libmpv-2.dll` ships as a separate library next to `velora.exe`, so you can
replace it with your own build of libmpv. Its source is available from the
[mpv](https://github.com/mpv-player/mpv) and
[FFmpeg](https://git.ffmpeg.org/ffmpeg.git) projects and from the build
scripts linked above.

### About the torrent engine (MPL-2.0)

The engine in `native/velora_engine/` is Velora's own code (MIT) that uses the
MPL-2.0 licensed `anacrolix/torrent` library. The library's source is
available at <https://github.com/anacrolix/torrent>. The exact versions used
are pinned in `native/velora_engine/go.mod` and `go.sum`.

## Services Velora talks to

These are separate services with their own terms. Velora is not affiliated with
or endorsed by any of them.

- **Cinemeta** (`v3-cinemeta.strem.io`) – movie and series metadata.
- **Torrentio** (`torrentio.strem.fun`) – lists torrent sources for a title.
- **Trakt** (`api.trakt.tv`) – optional account sync. Trakt's API terms
  restrict use with apps that promote copyright infringement; see the README.
- **ipify** (`api.ipify.org`) – only when you press "Check what peers see" in
  Settings, to show the public address.

## Fonts and trademarks

- The interface is designed for the **SF Pro Display** typeface, which is **not
  included** in this repository or its releases (Apple's license does not allow
  redistribution). Without it the app falls back to Segoe UI.
- Names such as Stremio, Trakt, Torrentio and Cinemeta belong to their owners.
