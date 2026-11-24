import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../../core/glass.dart';
import '../../core/platform.dart';
import '../../core/smooth_scroll.dart';
import '../../providers/settings_provider.dart';
import '../../providers/trakt_provider.dart';
import '../../services/engine_service.dart';
import '../../widgets/glass_button.dart';
import '../../widgets/glass_panel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Upload limit choices in KB/s (1 is the minimum).
const _uploadSteps = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048];

class _SettingsScreenState extends State<SettingsScreen> {
  final _scroll = SmoothScrollController();
  final _urlCtl = TextEditingController();
  String? _urlMessage; // result of Test
  bool _urlOk = false;
  bool _testing = false;
  bool _applying = false;
  int? _cacheBytes;

  @override
  void initState() {
    super.initState();
    _urlCtl.text = context.read<SettingsProvider>().remoteUrl ?? '';
    _refreshCache();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _urlCtl.dispose();
    super.dispose();
  }

  static String _fmtBytes(int b) {
    const gb = 1 << 30, mb = 1 << 20;
    return b >= gb
        ? '${(b / gb).toStringAsFixed(2)} GB'
        : '${(b / mb).toStringAsFixed(0)} MB';
  }

  Future<void> _refreshCache() async {
    final n = await context.read<EngineService>().cacheBytes();
    if (mounted) setState(() => _cacheBytes = n);
  }

  Future<void> _testUrl() async {
    setState(() {
      _testing = true;
      _urlMessage = null;
    });
    final err = await EngineService.checkRemote(_urlCtl.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _urlOk = err == null;
      _urlMessage = err ?? 'Connected - this is a Velora engine.';
    });
  }

  void _saveUrl() {
    final settings = context.read<SettingsProvider>();
    settings.remoteUrl = _urlCtl.text.trim().replaceAll(RegExp(r'/+$'), '');
    _urlCtl.text = settings.remoteUrl ?? '';
  }

  Future<void> _apply({bool clear = false}) async {
    final s = context.read<SettingsProvider>();
    setState(() => _applying = true);
    try {
      await context.read<EngineService>().restartWith(
        maxCacheGb: s.maxCacheGb,
        uploadKbps: s.uploadKbps,
        noUpload: !s.allowUpload,
        keepCache: s.keepCache,
        bindIp: s.bindIp,
        remoteBaseUrl: s.remoteUrl,
        clearCache: clear,
      );
    } catch (_) {
      // The engine card shows the error.
    }
    if (!mounted) return;
    setState(() => _applying = false);
    _refreshCache();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final engine = context.watch<EngineService>();
    final pending = !engine.matches(
      maxCacheGb: s.maxCacheGb,
      uploadKbps: s.uploadKbps,
      noUpload: !s.allowUpload,
      keepCache: s.keepCache,
      bindIp: s.bindIp,
      remoteBaseUrl: s.remoteUrl,
    );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
          children: [
            const Text(
              'Settings',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 20),
            _EngineCard(engine: engine, cacheBytes: _cacheBytes),
            const SizedBox(height: 18),
            _Section(
              title: 'Streaming',
              children: [
                _Row(
                  title: 'Play next episode automatically',
                  subtitle:
                      'Near the end of an episode, an "Up next" card appears and starts the '
                      'next episode after 10 seconds, picking a source that matches the one '
                      'you were watching. You can always press Cancel. Turn off to be asked '
                      'instead.',
                  trailing: Switch(
                    value: s.autoplayNext,
                    onChanged: (v) => s.autoplayNext = v,
                  ),
                ),
                _Row(
                  title: 'Cache size',
                  subtitle:
                      'Most disk space downloaded video may use. Oldest titles are removed first.',
                  trailing: Text(
                    '${s.maxCacheGb.toStringAsFixed(0)} GB',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  below: _slider(
                    value: s.maxCacheGb,
                    min: 1,
                    max: 32,
                    divisions: 31,
                    onChanged: (v) => s.maxCacheGb = v.roundToDouble(),
                  ),
                ),
                _Row(
                  title: 'Keep downloads between sessions',
                  subtitle:
                      'Video you already downloaded (even partly) stays on disk, so watching it '
                      'again, or resuming, does not download it again, and cached titles even '
                      'start without internet. Turn off to wipe it each time Velora starts.',
                  trailing: Switch(
                    value: s.keepCache,
                    onChanged: (v) => s.keepCache = v,
                  ),
                ),
                _Row(
                  title: 'Pre-buffer next episodes while watching',
                  subtitle:
                      'Quietly downloads the next episodes of a series in the background, '
                      'so they start with no wait. Needs free space within the cache size above.',
                  trailing: Text(
                    s.prebufferAhead == 0
                        ? 'Off'
                        : '${s.prebufferAhead} episode${s.prebufferAhead == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  below: _slider(
                    value: s.prebufferAhead.toDouble(),
                    min: 0,
                    max: 3,
                    divisions: 3,
                    onChanged: (v) => s.prebufferAhead = v.round(),
                  ),
                ),
                _Row(
                  title: 'Pre-buffer only the start',
                  subtitle:
                      'Download just the first part of an episode (about 7 minutes) instead '
                      'of all of it. Uses far less disk; the rest streams in as you watch.',
                  trailing: Switch(
                    value: s.prebufferStartOnly,
                    onChanged: (v) => s.prebufferStartOnly = v,
                  ),
                ),
                _Row(
                  title: 'Allow uploading',
                  subtitle:
                      'Torrents work by sharing pieces back. Turn off to leech only (some peers may throttle you).',
                  trailing: Switch(
                    value: s.allowUpload,
                    onChanged: (v) => s.allowUpload = v,
                  ),
                ),
                if (s.allowUpload)
                  _Row(
                    title: 'Upload limit',
                    subtitle:
                        'Set to the minimum (1 KB/s) by default. Torrents need a trickle of '
                        'upload to stay on good terms with peers; "Allow uploading" off '
                        'is the absolute minimum but can slow some downloads.',
                    trailing: Text(
                      '${s.uploadKbps} KB/s',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    below: _slider(
                      value: _uploadSteps
                          .indexOf(
                            _uploadSteps.reduce(
                              (a, b) =>
                                  (a - s.uploadKbps).abs() <=
                                      (b - s.uploadKbps).abs()
                                  ? a
                                  : b,
                            ),
                          )
                          .toDouble(),
                      min: 0,
                      max: (_uploadSteps.length - 1).toDouble(),
                      divisions: _uploadSteps.length - 1,
                      onChanged: (v) => s.uploadKbps = _uploadSteps[v.round()],
                    ),
                  ),
                if (isMobile)
                  _Row(
                    title: 'Wi-Fi only',
                    subtitle:
                        'Never stream over mobile data. (Takes effect once the on-device engine ships.)',
                    trailing: Switch(
                      value: s.wifiOnly,
                      onChanged: (v) => s.wifiOnly = v,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const _TraktSection(),
            const SizedBox(height: 18),
            const _PrivacySection(),
            const SizedBox(height: 18),
            _Section(
              title: 'Remote engine',
              children: [
                _Row(
                  title: 'Engine address',
                  subtitle:
                      'Optional. Run velora_engine on an always-on machine and enter its address '
                      '(e.g. http://100.64.0.5:11470, reached over Tailscale). '
                      'Leave empty to run the engine on this device.',
                  below: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _urlCtl,
                        onChanged: (_) => setState(() => _urlMessage = null),
                        decoration: InputDecoration(
                          hintText: 'http://host:port',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.07),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          GlassButton(
                            label: _testing ? 'Testing...' : 'Test',
                            icon: Icons.network_check_rounded,
                            onTap: _testing ? () {} : _testUrl,
                          ),
                          GlassButton(
                            label: 'Save',
                            icon: Icons.check_rounded,
                            primary: true,
                            onTap: _saveUrl,
                          ),
                          if (_urlMessage != null)
                            Text(
                              _urlMessage!,
                              style: TextStyle(
                                color: _urlOk
                                    ? const Color(0xFF69F0AE)
                                    : const Color(0xFFFF8A65),
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _Section(
              title: 'Appearance',
              children: [
                _Row(
                  title: 'Animated background',
                  subtitle:
                      'The moving aurora uses your graphics card. Smooth runs it at 30 fps '
                      '(looks the same, half the work); Off shows a still frame. '
                      'It always pauses by itself during playback and on detail pages.',
                  below: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final q in AuroraQuality.values)
                        GlassButton(
                          label: q.label,
                          primary: s.auroraQualityValue == q,
                          onTap: () => s.auroraQualityValue = q,
                        ),
                    ],
                  ),
                ),
                _Row(
                  title: 'Reduce glass effects',
                  subtitle:
                      'Turns off the frosted blur. Use this if animation feels choppy on weaker graphics.',
                  trailing: Switch(
                    value: s.reduceGlassEnabled,
                    onChanged: (v) => s.reduceGlassEnabled = v,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (pending)
              GlassPanel(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Icon(Icons.restart_alt_rounded),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Engine settings changed. Apply them to restart the engine '
                        '(this stops anything playing; your downloaded cache is kept).',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GlassButton(
                      label: _applying ? 'Applying...' : 'Apply',
                      primary: true,
                      onTap: _applying ? () {} : _apply,
                    ),
                  ],
                ),
              ),
            if (!pending && s.remoteUrl == null)
              Align(
                alignment: Alignment.centerLeft,
                child: GlassButton(
                  label: _applying
                      ? 'Clearing...'
                      : 'Clear cache${_cacheBytes == null ? '' : '  (${_fmtBytes(_cacheBytes!)})'}',
                  icon: Icons.delete_sweep_rounded,
                  onTap: _applying ? () {} : () => _apply(clear: true),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _slider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) => SliderTheme(
    data: SliderTheme.of(context).copyWith(
      trackHeight: 4,
      activeTrackColor: const Color(0xFF00E5FF),
      inactiveTrackColor: Colors.white24,
      thumbColor: Colors.white,
      overlayColor: const Color(0xFF00E5FF).withValues(alpha: 0.18),
    ),
    child: Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: Color(0xFF00E5FF),
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, this.trailing, this.below});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Colors.white60,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 16), trailing!],
          ],
        ),
        if (below != null) ...[const SizedBox(height: 6), below!],
      ],
    ),
  );
}

class _EngineCard extends StatelessWidget {
  const _EngineCard({required this.engine, required this.cacheBytes});

  final EngineService engine;
  final int? cacheBytes;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (engine.state) {
      EngineState.ready => (const Color(0xFF69F0AE), 'Running'),
      EngineState.starting => (const Color(0xFFFFD54F), 'Starting...'),
      EngineState.failed => (const Color(0xFFFF8A65), 'Not running'),
      EngineState.stopped => (Colors.white38, 'Stopped'),
    };
    final remote = engine.remoteBaseUrl != null;
    final detail = [
      remote ? 'Remote: ${engine.remoteBaseUrl}' : 'On this device',
      if (!remote && cacheBytes != null) 'cache ${_size(cacheBytes!)}',
    ].join('  -  ');

    return GlassPanel(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 10),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Streaming engine - $label',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  engine.state == EngineState.failed && engine.error != null
                      ? engine.error!
                      : detail,
                  style: const TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _size(int bytes) {
    const gb = 1 << 30, mb = 1 << 20;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }
}

/// Network adapter binding + "what do peers see?" check.
class _PrivacySection extends StatefulWidget {
  const _PrivacySection();

  @override
  State<_PrivacySection> createState() => _PrivacySectionState();
}

class _PrivacySectionState extends State<_PrivacySection> {
  List<NetAdapter>? _adapters;
  bool _checking = false;
  String? _appIp;
  String? _engineIp;
  String? _checkError;

  @override
  void initState() {
    super.initState();
    _loadAdapters();
  }

  Future<void> _loadAdapters() async {
    final a = await EngineService.adapters();
    if (mounted) setState(() => _adapters = a);
  }

  Future<void> _check() async {
    final engine = context.read<EngineService>();
    setState(() {
      _checking = true;
      _checkError = null;
      _appIp = null;
      _engineIp = null;
    });
    String? appIp;
    try {
      final r = await http
          .get(Uri.parse('https://api.ipify.org'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) appIp = r.body.trim();
    } catch (_) {}
    final engineIp = await engine.publicIp();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _appIp = appIp;
      _engineIp = engineIp;
      if (engineIp == null) {
        _checkError =
            'The engine is not running, or could not reach the internet '
            '(if you bound it to an adapter, that adapter may have no connection).';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final adapters = _adapters ?? const <NetAdapter>[];
    final selected = s.bindIp;
    final missing =
        selected != null && !adapters.any((a) => a.address == selected);

    final masked = _engineIp != null && _appIp != null && _engineIp != _appIp;

    return _Section(
      title: 'Privacy',
      children: [
        const _Row(
          title: 'About hiding your IP',
          subtitle:
              'Torrenting works by connecting to other people, so peers always see '
              'the address your traffic leaves from. Velora cannot hide that by itself. '
              'The way to mask it is a VPN: connect one, then bind Velora to its adapter '
              'below. If the VPN drops, the engine stops instead of falling back to '
              'your real connection. (Another option: run the engine on a remote '
              'machine - see "Remote engine".)',
        ),
        _Row(
          title: 'Network adapter',
          subtitle:
              'Automatic uses whatever your system chooses. Pick your VPN adapter to '
              'force all torrent traffic through it. Changes apply after you restart '
              'the engine.',
          below: DropdownButtonFormField<String?>(
            initialValue: selected,
            isExpanded: true,
            dropdownColor: const Color(0xF2141826),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.07),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Automatic (system default)'),
              ),
              if (missing)
                DropdownMenuItem<String?>(
                  value: selected,
                  child: Text(
                    '${s.bindName ?? 'Adapter'} - $selected  (not connected)',
                    style: const TextStyle(color: Color(0xFFFF8A65)),
                  ),
                ),
              for (final a in adapters)
                DropdownMenuItem<String?>(
                  value: a.address,
                  child: Text(
                    '${a.name} - ${a.address}${a.vpnLikely ? '   (looks like a VPN)' : ''}',
                  ),
                ),
            ],
            onChanged: (ip) {
              final name = adapters
                  .where((a) => a.address == ip)
                  .map((a) => a.name)
                  .firstOrNull;
              s.setBinding(ip, name);
            },
          ),
        ),
        if (missing)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'The selected adapter is not connected, so the engine will not start. '
              'Reconnect your VPN (then press Apply), or switch back to Automatic.',
              style: TextStyle(color: Color(0xFFFF8A65), fontSize: 12.5),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassButton(
              label: 'Refresh adapters',
              icon: Icons.refresh_rounded,
              onTap: _loadAdapters,
            ),
          ),
        ),
        _Row(
          title: 'Check what peers see',
          subtitle:
              'Compares the address this app uses with the one the torrent engine '
              'uses. Asks api.ipify.org (a public "what is my IP" service) twice.',
          below: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassButton(
                label: _checking ? 'Checking...' : 'Check now',
                icon: Icons.shield_outlined,
                primary: true,
                onTap: _checking ? () {} : _check,
              ),
              if (_checkError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _checkError!,
                  style: const TextStyle(
                    color: Color(0xFFFF8A65),
                    fontSize: 13,
                  ),
                ),
              ] else if (_engineIp != null) ...[
                const SizedBox(height: 12),
                Text(
                  'This app:  ${_appIp ?? 'unknown'}',
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  'Torrent engine (what peers see):  $_engineIp',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  masked
                      ? 'Masked: peers see a different address from your normal one.'
                      : 'Not masked: peers can see your normal IP address. '
                            'Connect a VPN and bind to its adapter above.',
                  style: TextStyle(
                    color: masked
                        ? const Color(0xFF69F0AE)
                        : const Color(0xFFFFD54F),
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _open(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

InputDecoration _fieldDecoration(String hint) => InputDecoration(
  hintText: hint,
  isDense: true,
  filled: true,
  fillColor: Colors.white.withValues(alpha: 0.07),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
  ),
);

/// Trakt.tv: API keys, device-code login, sync and scrobble switches.
class _TraktSection extends StatefulWidget {
  const _TraktSection();

  @override
  State<_TraktSection> createState() => _TraktSectionState();
}

class _TraktSectionState extends State<_TraktSection> {
  final _id = TextEditingController();
  final _secret = TextEditingController();

  @override
  void initState() {
    super.initState();
    _id.text = context.read<TraktProvider>().clientId ?? '';
  }

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TraktProvider>();
    final s = context.watch<SettingsProvider>();

    final children = <Widget>[];
    switch (t.state) {
      case TraktState.notConfigured:
        children.add(
          _Row(
            title: 'Connect your Trakt account',
            subtitle:
                'Trakt keeps your watch history and watchlist in sync across devices. '
                'It needs a free "API app" that only you own:\n'
                '1. Open trakt.tv/oauth/applications and create a new app (Trakt asks for a verified GitHub account).\n'
                '2. Name: Velora.  Redirect URI: ${TraktProvider.redirectUriHint}\n'
                '3. Copy the Client ID into the box below. New Trakt apps have no Client Secret, '
                'so leave that box empty (only fill it if your app shows one).\n'
                'Keys are kept in your system\'s secure storage, never in a plain file.',
            below: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    GlassButton(
                      label: 'Open Trakt apps page',
                      icon: Icons.open_in_new_rounded,
                      onTap: () => _open('https://trakt.tv/oauth/applications'),
                    ),
                    GlassButton(
                      label: 'Copy redirect URI',
                      icon: Icons.copy_rounded,
                      onTap: () => Clipboard.setData(
                        const ClipboardData(
                          text: TraktProvider.redirectUriHint,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _id,
                  decoration: _fieldDecoration('Client ID'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _secret,
                  obscureText: true,
                  decoration: _fieldDecoration(
                    'Client Secret (optional - leave empty for new apps)',
                  ),
                ),
                const SizedBox(height: 14),
                GlassButton(
                  label: 'Save',
                  icon: Icons.check_rounded,
                  primary: true,
                  onTap: () async {
                    await t.saveCredentials(_id.text, _secret.text);
                    _secret.clear();
                  },
                ),
              ],
            ),
          ),
        );
      case TraktState.disconnected:
        children.add(
          _Row(
            title: 'Not connected',
            subtitle: t.usesBrowserLogin
                ? 'Your Trakt app is saved. Connect opens trakt.tv in your browser '
                      'to approve Velora. Your password is never typed into Velora.'
                : 'Your Trakt API keys are saved. Connect to sign in: you will get a '
                      'short code to enter on trakt.tv. Your password is never typed '
                      'into Velora.',
            below: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                GlassButton(
                  label: 'Connect Trakt',
                  icon: Icons.link_rounded,
                  primary: true,
                  onTap: t.startLogin,
                ),
                GlassButton(
                  label: 'Change API keys',
                  onTap: () {
                    _id.text = t.clientId ?? '';
                    t.forgetCredentials();
                  },
                ),
              ],
            ),
          ),
        );
      case TraktState.awaitingApproval:
        final code = t.deviceCode;
        if (code == null) {
          // Browser (PKCE) sign-in.
          children.add(
            _Row(
              title: 'Approve Velora in your browser',
              subtitle:
                  'A trakt.tv page should have opened. Sign in there and press '
                  'Yes. This page updates by itself (waits up to 5 minutes).',
              below: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  GlassButton(
                    label: 'Open it again',
                    icon: Icons.open_in_new_rounded,
                    primary: true,
                    onTap: () {
                      final u = t.authUrl;
                      if (u != null) _open(u.toString());
                    },
                  ),
                  GlassButton(label: 'Cancel', onTap: t.cancelLogin),
                ],
              ),
            ),
          );
        } else {
          children.add(
            _Row(
              title: 'Enter this code on trakt.tv',
              subtitle:
                  'Waiting for you to approve... this page updates by itself.',
              below: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    code.userCode,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      GlassButton(
                        label: 'Open trakt.tv/activate',
                        icon: Icons.open_in_new_rounded,
                        primary: true,
                        onTap: () => _open(code.verificationUrl),
                      ),
                      GlassButton(label: 'Cancel', onTap: t.cancelLogin),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
      case TraktState.connected:
        final last = s.traktLastSync;
        children.addAll([
          _Row(
            title: 'Connected${t.username == null ? '' : ' as ${t.username}'}',
            subtitle: t.syncing
                ? 'Syncing...'
                : (last == null
                      ? 'Not synced yet.'
                      : 'Last synced ${_ago(last)}.'),
            below: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                GlassButton(
                  label: t.syncing ? 'Syncing...' : 'Sync now',
                  icon: Icons.sync_rounded,
                  primary: true,
                  onTap: t.syncing ? () {} : () => t.sync(),
                ),
                GlassButton(label: 'Disconnect', onTap: t.logout),
              ],
            ),
          ),
          _Row(
            title: 'Scrobble while watching',
            subtitle:
                'Tells Trakt what you are playing; finishing a title adds it to your history.',
            trailing: Switch(
              value: s.traktScrobble,
              onChanged: (v) => s.traktScrobble = v,
            ),
          ),
          _Row(
            title: 'Sync watchlist with My List',
            subtitle:
                'Titles added to My List appear on your Trakt watchlist, and the other way round.',
            trailing: Switch(
              value: s.traktWatchlist,
              onChanged: (v) {
                s.traktWatchlist = v;
                if (v) t.sync(quiet: true);
              },
            ),
          ),
        ]);
    }

    if (t.message != null) {
      final bad =
          t.message!.toLowerCase().contains('problem') ||
          t.message!.toLowerCase().contains('expire') ||
          t.message!.toLowerCase().contains('denied') ||
          t.message!.toLowerCase().contains('rejected') ||
          t.message!.toLowerCase().contains('could not') ||
          t.message!.toLowerCase().contains('enter both');
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            t.message!,
            style: TextStyle(
              fontSize: 13,
              color: bad ? const Color(0xFFFF8A65) : const Color(0xFF69F0AE),
            ),
          ),
        ),
      );
    }

    return _Section(title: 'Trakt', children: children);
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}
