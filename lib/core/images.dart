/// Cinemeta hands out small thumbnails; upgrade them to sharp ones.
/// Backdrops: metahub `medium` -> `large` (and TMDB-style /w500/ -> /original/).
String? upscaleBackground(String? url) => url
    ?.replaceFirst('/background/medium/', '/background/large/')
    .replaceFirst('/background/small/', '/background/large/')
    .replaceFirst('/w500/', '/original/')
    .replaceFirst('/w780/', '/original/');

/// Posters: metahub `small` -> `medium`.
String? upscalePoster(String? url) => url
    ?.replaceFirst('/poster/small/', '/poster/medium/')
    .replaceFirst('/w185/', '/w500/');

/// Logos (title treatments): metahub `medium` is plenty.
String? upscaleLogo(String? url) => url;
