<p align="center">
  <img src="assets/icon/velora_logo.png" alt="Velora logo" width="120">
</p>

<h1 align="center">VELORA</h1>

<p align="center">
  A glass-and-aurora desktop streaming client, built with Flutter.<br>
  Browse, search, pick a source and watch, with a torrent engine built in.
</p>

<p align="center">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="Platform: Windows" src="https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6">
  <img alt="Built with Flutter" src="https://img.shields.io/badge/built%20with-Flutter-02569B">
  <a href="https://github.com/helpmh2023/Velora/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/helpmh2023/Velora"></a>
</p>

---

## Download

**[Get the latest release](https://github.com/helpmh2023/Velora/releases/latest)**

| File | What it is |
|---|---|
| `Velora-Setup-<version>.exe` | **Installer (recommended).** Installs for your user, no admin rights needed, adds a Start menu entry. |
| `Velora-<version>-windows-x64.zip` | Portable. Unzip the whole folder anywhere and run `velora.exe`. |

Requires **Windows 10 or 11 (64-bit)** and an internet connection.

> **Windows may warn "Unknown publisher" (SmartScreen).** The builds are not
> code-signed, because that needs a paid certificate. Choose **More info -> Run
> anyway**. Some antivirus tools also flag torrent software by default; the
> source for everything is in this repository, and you can build it yourself
> (see below). Each release lists SHA-256 checksums.

## Features

**Look and feel ("Aurora Glass")**
- Live GPU aurora background (a GLSL fragment shader) that swells with the breathing logo in the intro.
- Frosted-glass panels; cards stay dim until hovered or focused, then grow with a soft glow.
- Frameless window with custom controls, smooth mouse-wheel scrolling, full keyboard navigation.
- Quality controls: full, 30 fps or still aurora, and a "reduce glass" switch. The aurora pauses itself while the player or a details page covers it.

**Watching**
- Home with a rotating hero banner and rows of trending, top and genre lists (from Cinemeta).
- **Movies** and **Series** tabs: Popular / Featured / By year, genre filters, endless scrolling.
- Search across movies and series; details pages with cast, seasons and episodes.
- Source picker (from Torrentio) grouped by quality (4K / 1080p / 720p / 480p), with seeder counts, a "most seeds" marker and a one-click best-seeded button.
- Built-in **torrent streaming engine**: starts playing while it downloads; no separate torrent app. Cache size cap, upload limit (1 KB/s by default), optional remote engine.
- Player (libmpv): glass controls, audio and subtitle track menus, seek bar with buffering, resume where you left off.

**Your library**
- My List (favourites), Continue Watching with automatic resume, watched ticks on episodes. Everything is stored locally.
- Optional **Trakt** sync: scrobbling, watch history and watchlist both ways.

**Privacy**
- No accounts, analytics or telemetry. Velora only contacts Cinemeta, Torrentio, Trakt (if you connect it) and a public IP-check service (only when you press the button).
- Bind the torrent engine to your **VPN adapter** with leak protection: if the VPN drops, the engine stops instead of using your real connection. A built-in check shows what peers see.
- Keys and tokens live in Windows secure storage, never in plain files.

## Keyboard shortcuts (player)

| Key | Action |
|---|---|
| `Space` / `K` | Play / pause |
| `Left` / `Right` | Back / forward 10 s (hold `Shift` for 30 s) |
| `Up` / `Down` | Volume |
| `M` | Mute |
| `F` / `F11` / double-click | Fullscreen |
| `Esc` | Leave fullscreen, then go back |

## Getting started

1. Install and open Velora. Browse or search, open a title, press **Watch**.
2. Pick a source. The one with the most seeders usually starts fastest.
3. Playback can take 5 to 20 seconds to start while the engine finds peers.

**Optional: Trakt.** In **Settings -> Trakt**, create a free API app at
[trakt.tv/oauth/applications](https://trakt.tv/oauth/applications) with the
redirect URI `http://localhost:8765/callback`, paste its **Client ID**, and
press Connect. Keys are stored in secure storage. Please read the note on
Trakt's terms in the [disclaimer](#legal-and-disclaimer) first.

**Optional: hide your IP.** Torrent peers always see the address your traffic
leaves from. Connect a VPN, then in **Settings -> Privacy** pick its network
adapter and press **Apply**. Use "Check what peers see" to verify.

Your data (library, settings, progress) is in
`%APPDATA%\Velora\Velora\data`. Uninstalling keeps it on purpose.

Downloaded video is cached in `%LOCALAPPDATA%\Velora\Velora\engine` (up to the
cache size set in Settings), so watching or resuming a title again does not
download it again. **Settings -> Streaming -> Clear cache** frees the space.

## Build from source

You need:

- **Flutter** 3.50 or newer (stable) with Windows desktop enabled. Older versions can be capped at about 30 fps on recent Windows 11 builds
- **Visual Studio 2022** (or Build Tools) with *Desktop development with C++*
  **and** the *C++ ATL for latest v143 build tools (x86 & x64)* component
- **Go** 1.27 or newer (for the torrent engine)
- *Optional:* [Inno Setup 6](https://jrsoftware.org/isinfo.php) to build the installer

```powershell
git clone https://github.com/helpmh2023/Velora.git
cd Velora

flutter pub get
powershell -File scripts/build_engine.ps1   # builds native/velora_engine/velora_engine.exe
flutter run -d windows                      # run in debug
```

Run the checks:

```powershell
flutter analyze
flutter test
```

Make release packages (zip, plus the installer if Inno Setup is installed):

```powershell
powershell -File scripts/package_windows.ps1
# -> dist/Velora-<version>-windows-x64.zip and dist/Velora-Setup-<version>.exe
```

> The interface is designed for **SF Pro Display**, which can't be
> redistributed. To use it, add the font files to `assets/fonts/` and
> uncomment the `fonts:` block in `pubspec.yaml`. Without it the app uses
> Segoe UI.

## How it works

```
 Cinemeta (catalogs, metadata)        Torrentio (sources for a title)
            \                                  /
             +----------- Velora (Flutter) ---+
                              |
                  http://127.0.0.1:<port>/stream/<hash>/<file>
                              |
                  velora_engine (Go, anacrolix/torrent)
                              |
                      torrent peers (optionally via your VPN adapter)
```

The player never talks to torrents; it plays an ordinary local HTTP URL that the
engine fills in on demand. That keeps the player simple and lets the same
engine run locally, on another machine, or (in future) inside a mobile app.

```
lib/            Flutter app (core, models, services, providers, screens, widgets)
native/velora_engine/   Go torrent-streaming engine
shaders/        aurora.frag (GLSL)
installer/      Inno Setup script
scripts/        build_engine.ps1, package_windows.ps1
test/           unit and widget tests (network is mocked)
```

## Roadmap

- [x] Windows desktop app, installer and portable build
- [ ] Android (phone and tablet layouts, touch player, engine built into the app)
- [ ] iOS / iPadOS (sideloaded; engine built into the app)
- [ ] Code-signed Windows builds

## Legal and disclaimer

Velora is a **client application**. It does **not** host, store, index or
distribute any video content, and it ships with no content. The titles and
sources it shows come from third-party services (Cinemeta, Torrentio) that are
not part of this project.

- **You are responsible for what you watch and download.** Only access content
  you have the legal right to. Laws about copyright and file sharing differ by
  country, and downloading or sharing copyrighted material without permission
  may be illegal where you live.
- Torrenting exposes your IP address to other peers, and may expose you to
  notices from your internet provider. See "Optional: hide your IP" above.
- **Trakt:** Trakt's API terms say its data may not be used in apps or websites
  that promote copyright infringement or piracy. Connecting Velora to Trakt is
  optional and at your own risk; Trakt may revoke API access.
- Velora is not affiliated with, endorsed by, or sponsored by Stremio, Trakt,
  Torrentio, Cinemeta, Apple or any other third party. All trademarks belong to
  their owners.
- The software is provided "as is", without warranty of any kind (see the
  [license](LICENSE)).

## Contributing

Bug reports, ideas and pull requests are welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

Velora is released under the [MIT License](LICENSE). Bundled third-party
components keep their own licenses: see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Acknowledgements

[Flutter](https://flutter.dev) · [media_kit](https://github.com/media-kit/media-kit)
and [mpv](https://mpv.io) · [anacrolix/torrent](https://github.com/anacrolix/torrent) ·
[Cinemeta](https://github.com/Stremio/cinemeta) and the Stremio addon protocol ·
[Torrentio](https://github.com/TheBeastLT/torrentio-scraper) ·
[Trakt](https://trakt.tv)
