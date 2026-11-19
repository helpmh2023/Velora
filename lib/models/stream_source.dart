enum Quality {
  uhd('4K'),
  fhd('1080p'),
  hd('720p'),
  sd('480p'),
  other('Other');

  const Quality(this.label);
  final String label;
}

/// One playable source from Torrentio: a torrent + which file in it.
class StreamSource {
  const StreamSource({
    required this.infoHash,
    required this.fileIdx,
    required this.release,
    required this.quality,
    required this.tags,
    required this.seeders,
    required this.sizeLabel,
    required this.sizeBytes,
    required this.provider,
    required this.languages,
    required this.trackers,
    this.filename,
  });

  final String infoHash;
  final int? fileIdx;

  /// Release name, e.g. "The.Matrix.1999.1080p.BluRay.x264".
  final String release;
  final Quality quality;

  /// HDR / DV / 10bit etc. from Torrentio's label.
  final List<String> tags;
  final int seeders;
  final String sizeLabel;
  final int sizeBytes;
  final String provider;

  /// Flag emoji string Torrentio appends for multi-language releases.
  final String languages;
  final List<String> trackers;
  final String? filename;

  Map<String, dynamic> toJson() => {
    'infoHash': infoHash,
    'fileIdx': fileIdx,
    'release': release,
    'quality': quality.name,
    'tags': tags,
    'seeders': seeders,
    'sizeLabel': sizeLabel,
    'sizeBytes': sizeBytes,
    'provider': provider,
    'languages': languages,
    'trackers': trackers,
    'filename': filename,
  };

  /// Inverse of [toJson] (not Torrentio's wire format).
  factory StreamSource.fromStored(Map<String, dynamic> j) => StreamSource(
    infoHash: '${j['infoHash']}',
    fileIdx: (j['fileIdx'] as num?)?.toInt(),
    release: '${j['release']}',
    quality: Quality.values.firstWhere(
      (q) => q.name == j['quality'],
      orElse: () => Quality.other,
    ),
    tags: ((j['tags'] as List?) ?? const []).map((e) => '$e').toList(),
    seeders: (j['seeders'] as num?)?.toInt() ?? 0,
    sizeLabel: '${j['sizeLabel'] ?? ''}',
    sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
    provider: '${j['provider'] ?? ''}',
    languages: '${j['languages'] ?? ''}',
    trackers: ((j['trackers'] as List?) ?? const []).map((e) => '$e').toList(),
    filename: j['filename'] as String?,
  );

  static const _defaultTrackers = [
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://tracker.openbittorrent.com:6969/announce',
    'udp://open.demonii.com:1337/announce',
  ];

  static Quality _quality(String label) {
    final l = label.toLowerCase();
    if (l.contains('4k') || l.contains('2160')) return Quality.uhd;
    if (l.contains('1080')) return Quality.fhd;
    if (l.contains('720')) return Quality.hd;
    if (l.contains('480') || l.contains('360')) return Quality.sd;
    return Quality.other;
  }

  static int _bytes(String text) {
    final m = RegExp(
      r'([\d.]+)\s*([KMGT]?B)',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return 0;
    final n = double.tryParse(m.group(1)!) ?? 0;
    const mult = {
      'B': 1,
      'KB': 1 << 10,
      'MB': 1 << 20,
      'GB': 1 << 30,
      'TB': 1 << 40,
    };
    return (n * (mult[m.group(2)!.toUpperCase()] ?? 1)).round();
  }

  /// Torrentio packs everything into two strings. `name` is "Torrentio" plus a
  /// quality line such as "4k DV | HDR". `title` is the release name, then a
  /// stats line (seeders, size, provider), then optional language flags.
  factory StreamSource.fromJson(Map<String, dynamic> j) {
    final nameLines = '${j['name'] ?? ''}'.split('\n');
    final label = nameLines.length > 1 ? nameLines.sublist(1).join(' ') : '';
    final tags = label
        .split(RegExp(r'[|\s]+'))
        .where((t) => t.isNotEmpty)
        .where((t) => _quality(t) == Quality.other)
        .toList();

    final lines = '${j['title'] ?? ''}'.split('\n');
    final statIdx = lines.indexWhere((l) => l.contains('\u{1F464}'));
    final release = (statIdx > 0 ? lines.sublist(0, statIdx) : [lines.first])
        .join(' ')
        .trim();
    final stats = statIdx >= 0 ? lines[statIdx] : '';
    final langs = (statIdx >= 0 && statIdx + 1 < lines.length)
        ? lines[statIdx + 1].trim()
        : '';

    final seeders =
        int.tryParse(
          RegExp(
                r'\u{1F464}\s*(\d+)',
                unicode: true,
              ).firstMatch(stats)?.group(1) ??
              '',
        ) ??
        0;
    final size =
        RegExp(
          r'\u{1F4BE}\s*([\d.]+\s*[KMGT]?B)',
          unicode: true,
        ).firstMatch(stats)?.group(1) ??
        '';
    final provider =
        RegExp(r'⚙️?\s*(.+)$').firstMatch(stats)?.group(1)?.trim() ?? '';

    final sources = (j['sources'] as List?)?.cast<String>() ?? const [];
    final trackers = [
      for (final s in sources)
        if (s.startsWith('tracker:')) s.substring(8),
    ];

    final hints = j['behaviorHints'];
    return StreamSource(
      infoHash: '${j['infoHash']}'.toLowerCase(),
      fileIdx: (j['fileIdx'] as num?)?.toInt(),
      release: release.isEmpty ? '${j['infoHash']}' : release,
      quality: _quality(label),
      tags: tags,
      seeders: seeders,
      sizeLabel: size,
      sizeBytes: _bytes(size),
      provider: provider,
      languages: langs,
      trackers: trackers.isEmpty ? _defaultTrackers : trackers,
      filename: hints is Map ? hints['filename'] as String? : null,
    );
  }
}
