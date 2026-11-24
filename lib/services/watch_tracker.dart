/// Works out where someone is in a video from how much of the file they have
/// downloaded, for players that cannot tell us (VLC on an iPad). The video is
/// streamed from this PC, so how far into the file the player has read is a
/// good guide to how far into the film it is.
///
/// Accuracy is roughly a minute: the player reads a little ahead of what it
/// shows, and a file's bytes are not spread perfectly evenly over its length.
/// A fixed [rewind] is taken off so resuming never skips something unseen.
class WatchTracker {
  WatchTracker({
    this.mainStreamMinBytes = 512 * 1024,
    this.rewind = const Duration(seconds: 30),
  });

  /// A connection only counts as "the video" once it has delivered this much:
  /// players also open short connections to read the file's header and index.
  final int mainStreamMinBytes;

  /// Taken off the estimate (see above).
  final Duration rewind;

  final _delivered = <int, int>{};
  int? _main;
  int? _pos;
  int? _total;
  DateTime? _lastSeen;
  DateTime? _lastReport;
  int? _reportedPos;
  var _nextConn = 0;

  /// Call when a new connection for this video starts; returns its id.
  int open() => _nextConn++;

  /// Bytes of the file delivered so far on connection [conn], which began at
  /// byte [start]; [total] is the whole file's size.
  void bytes(int conn, int start, int delivered, int total, {DateTime? now}) {
    _lastSeen = now ?? DateTime.now();
    _total = total;
    _delivered[conn] = delivered;
    if (delivered >= mainStreamMinBytes) _main = conn;
    if (_main == conn) _pos = start + delivered;
  }

  bool get hasData => _pos != null && _total != null && _total! > 0;
  DateTime? get lastSeen => _lastSeen;

  /// Estimated playback position, or null if there is not enough to say.
  Duration? estimate(Duration videoLength) {
    if (!hasData) return null;
    final f = (_pos! / _total!).clamp(0.0, 1.0);
    final ms = (videoLength.inMilliseconds * f).round() - rewind.inMilliseconds;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  /// True when it is time to report: it has been quiet for [idle] (they
  /// stopped), or it is still playing and [every] has passed since the last
  /// report, and the position actually moved.
  bool shouldReport({
    required DateTime now,
    required Duration idle,
    required Duration every,
  }) {
    if (!hasData || _lastSeen == null) return false;
    if (_pos == _reportedPos) return false; // nothing new
    final quiet = now.difference(_lastSeen!) >= idle;
    final due = _lastReport == null || now.difference(_lastReport!) >= every;
    return quiet || due;
  }

  void reported({DateTime? now}) {
    _lastReport = now ?? DateTime.now();
    _reportedPos = _pos;
  }
}
