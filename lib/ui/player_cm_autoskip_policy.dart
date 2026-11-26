/// Player CM auto skip policy (user-fork addition; not
/// part of the upstream plans): while a recording plays
/// with the setting on, move past the chapter segments
/// that look like commercial breaks without the viewer
/// pressing the chapter buttons (plan 112) each time.
///
/// What counts as a commercial break here is a
/// heuristic, not a fact the unit serves: the chapter
/// points are the unit's silence cuts (see the core
/// chapter parsing), so a break shows up as a run of
/// short segments between long ones — spots are cut
/// at 15 / 30 / 60 s, programme segments run for
/// minutes. A segment of at most [cmSegmentMaxDuration]
/// is therefore treated as part of a break, and a run
/// of such segments is skipped as one break. Short
/// programme pieces (a mini corner, a weather spot)
/// match the same shape and will be skipped too; that
/// misjudgement is the known cost of the feature, and
/// why it defaults off and why the manual chapter
/// buttons stay.
///
/// Safety rails, all decided here so the screen only
/// wires them:
/// - The first segment (the opening) and the last
///   segment (the ending / credits) are never part of
///   a skipped run, however short they are.
/// - A run the viewer seeked into by hand is left
///   alone for the rest of that playback: the screen
///   passes its start as [suppressedRunStart], found
///   with [cmRunStartAt] at the seek's landing point.
/// - No points, an unknown duration, or a position
///   outside the segments means no skip, never an
///   error: auto skip decorates playback exactly the
///   way chapters do and must not break it.
library;

/// The longest single chapter segment still treated
/// as part of a commercial break. Spots are cut at
/// 15 / 30 / 60 s; 65 s leaves a small margin over a
/// 60 s spot without reaching the shortest real
/// programme segments this was reasoned against
/// (news items and corners run minutes, not seconds).
const Duration cmSegmentMaxDuration = Duration(seconds: 65);

/// The chapter segments of a recording of [duration]:
/// the spans between consecutive boundary points,
/// where the boundaries are the start, every chapter
/// point strictly inside the recording, and the end.
/// Points outside the recording or duplicated collapse
/// away, so the segments are never empty or negative.
List<({Duration start, Duration end})> _segments({
  required List<Duration> chapters,
  required Duration duration,
}) {
  final points = <Duration>{
    Duration.zero,
    for (final point in chapters)
      if (point > Duration.zero && point < duration) point,
    duration,
  }.toList()..sort();
  return [
    for (var i = 0; i + 1 < points.length; i++)
      (start: points[i], end: points[i + 1]),
  ];
}

bool _isShort(({Duration start, Duration end}) segment) =>
    segment.end - segment.start <= cmSegmentMaxDuration;

/// The index of the segment holding [position], or
/// null when the position is at or past the end (a
/// position before the start cannot occur: the first
/// segment starts at zero).
int? _segmentIndexAt(
  List<({Duration start, Duration end})> segments,
  Duration position,
) {
  for (var i = 0; i < segments.length; i++) {
    if (position < segments[i].end) return i;
  }
  return null;
}

/// The bounds of the skippable run holding segment
/// [index]: the first and last segment indexes of the
/// run of short segments around it, or null when the
/// segment is not in a run — it is long itself, or it
/// is the first or the last segment, which are never
/// skipped. A run stops before the last segment even
/// when that segment is short, so a skip lands on the
/// last segment's start at the furthest.
({int first, int last})? _runBounds(
  List<({Duration start, Duration end})> segments,
  int index,
) {
  if (index <= 0 || index >= segments.length - 1) return null;
  if (!_isShort(segments[index])) return null;
  var first = index;
  while (first - 1 > 0 && _isShort(segments[first - 1])) {
    first--;
  }
  var last = index;
  while (last + 1 < segments.length - 1 && _isShort(segments[last + 1])) {
    last++;
  }
  return (first: first, last: last);
}

/// Where auto skip seeks to from [position]: the end
/// of the commercial-break run the position is in —
/// the start of the first segment after the run — or
/// null when the position is not in a skippable run
/// (a long segment, the opening, the ending, a run
/// suppressed by a manual seek, or no usable points).
Duration? cmAutoSkipTarget({
  required List<Duration> chapters,
  required Duration position,
  required Duration duration,
  Duration? suppressedRunStart,
}) {
  if (chapters.isEmpty || duration <= Duration.zero) return null;
  final segments = _segments(chapters: chapters, duration: duration);
  final index = _segmentIndexAt(segments, position);
  if (index == null) return null;
  final run = _runBounds(segments, index);
  if (run == null) return null;
  if (suppressedRunStart != null &&
      segments[run.first].start == suppressedRunStart) {
    return null;
  }
  return segments[run.last].end;
}

/// The start of the commercial-break run holding
/// [position], or null when the position is not in a
/// skippable run. The screen records this when a
/// manual seek lands inside a run, and passes it back
/// to [cmAutoSkipTarget] as the suppressed run.
Duration? cmRunStartAt({
  required List<Duration> chapters,
  required Duration position,
  required Duration duration,
}) {
  if (chapters.isEmpty || duration <= Duration.zero) return null;
  final segments = _segments(chapters: chapters, duration: duration);
  final index = _segmentIndexAt(segments, position);
  if (index == null) return null;
  final run = _runBounds(segments, index);
  if (run == null) return null;
  return segments[run.first].start;
}
