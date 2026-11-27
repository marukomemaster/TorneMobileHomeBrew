/// Auto pick (user-fork addition, owner request
/// 2026-11-27): the keyword-less companion to the auto
/// record rules. Where a rule claims the programmes
/// its conditions name, the auto pick fills the tuner's
/// idle time with programmes the viewer is likely to
/// want, scored from the viewer's own recording
/// history. The design the owner approved:
///
/// - The rules and the viewer's own reservations are
/// absolute: the auto pick only ever sees the time
/// they leave free (the checker plans it after the
/// rule pass, against the reservations then on the
/// unit — see app/auto_record_providers.dart).
/// - A disk guard: when the unit's free space is
/// under a floor the viewer sets, nothing is picked.
/// Unknown free space reads as under the floor —
/// the side that never records unasked.
/// - A per-check cap keeps one check from filling the
/// guide: a handful of programmes, never a flood.
/// - Nothing is ever deleted to make room, and an
/// auto reservation is marked as one (the checker
/// keeps the marks; see app/auto_pick_providers.dart).
///
/// This file is the pure half: the tendency profile
/// aggregated from recorded titles and reservations,
/// the scoring of one programme against it, and the
/// plan that walks the scored guide into the free
/// slots. The ranking screen (ui/ranking_screen.dart)
/// renders the same three computations, so what the
/// screen promises is what the checker does.
library;

import '../core/core.dart';
import 'auto_record_policy.dart';
import 'epg_genre.dart';
import 'epg_search.dart';
import 'format.dart';

/// The channel identity the tendency profile counts
/// by: broadcasting type + service id — the pair a
/// reservation and a guide event share (the same pair
/// [autoRecordProgrammeKey] keys programmes by).
String autoPickChannelKey({
  required int broadcastingType,
  required int serviceId,
}) => '$broadcastingType:$serviceId';

/// The series identity of one programme title: the
/// title itself, trimmed. A series' episodes share
/// the programme title in the guide and in the title
/// list alike (episode detail lives in the outline),
/// so the exact title is the series key; no episode
/// suffix is guessed at or stripped.
String autoPickSeriesKey(String title) => title.trim();

/// The ARIB genre level-1 value a recorded title's
/// DIDL genre text names, or null when it names none
/// this app labels.
///
/// The device writes the DIDL genre with a fullwidth
/// slash where the app's genre table (epg_genre.dart)
/// writes an interpunct — the measured fixture values
/// are ニュース／報道, ドキュメンタリー／教養, 趣味／教育,
/// 福祉 — so the separator is normalised before the
/// match. A text that still matches no label counts
/// for nothing here: the title still feeds the
/// channel and series counts, which need no mapping.
int? autoPickGenreLevel1OfDidlGenre(String? didlGenre) {
  if (didlGenre == null) return null;
  final normalised = didlGenre.trim().replaceAll('／', '・');
  if (normalised.isEmpty) return null;
  for (final value in epgGenreLevel1Values) {
    if (epgGenreLabel(value) == normalised) return value;
  }
  return null;
}

/// One piece of recording-history evidence: a
/// recorded title or a reservation, reduced to what
/// the profile counts.
class TendencySample {
  const TendencySample({
    this.genreLevel1,
    required this.broadcastingType,
    required this.serviceId,
    required this.channelName,
    required this.title,
  });

  /// ARIB genre level-1, when the source names one
  /// (a title's DIDL genre, or the guide event a
  /// reservation resolves to); null when it does not.
  final int? genreLevel1;
  final int broadcastingType;
  final int serviceId;

  /// Display name of the channel, for the ranking.
  final String channelName;

  /// Programme title (the series key's source).
  final String title;

  String get channelKey => autoPickChannelKey(
    broadcastingType: broadcastingType,
    serviceId: serviceId,
  );
}

/// The samples of a recorded-title list: genre from
/// the DIDL genre text (see
/// [autoPickGenreLevel1OfDidlGenre]), channel from
/// the title's scheduled channel, series from the
/// title. Titles without a channel still count for
/// genre and series.
List<TendencySample> autoPickSamplesFromTitles(List<RecordedTitle> titles) => [
  for (final title in titles)
    TendencySample(
      genreLevel1: autoPickGenreLevel1OfDidlGenre(title.genre),
      broadcastingType: title.channel?.broadcastingType ?? -1,
      serviceId: title.channel?.serviceId ?? -1,
      channelName: title.channelName ?? '',
      title: title.title,
    ),
];

/// The samples of a reservation list. A reservation
/// names no genre of its own, so the genre comes from
/// the held guide: [guideHits] resolves a reservation
/// to its event by programme key, and the event's
/// genre is the sample's. A reservation the guide no
/// longer holds counts for channel and series only.
List<TendencySample> autoPickSamplesFromSchedules(
  List<RecordSchedule> schedules,
  List<EpgSearchHit> guideHits,
) {
  final genreByKey = <String, int>{};
  for (final hit in guideHits) {
    final genre = hit.event.genreLevel1;
    if (genre == null) continue;
    genreByKey[autoRecordProgrammeKey(
          broadcastingType: hit.channel.broadcastingType,
          serviceId: hit.channel.serviceId,
          start: hit.event.start,
        )] =
        genre;
  }
  return [
    for (final schedule in schedules)
      TendencySample(
        genreLevel1:
            genreByKey[autoRecordProgrammeKey(
              broadcastingType: schedule.channel.broadcastingType,
              serviceId: schedule.channel.serviceId,
              start: schedule.start,
            )],
        broadcastingType: schedule.channel.broadcastingType,
        serviceId: schedule.channel.serviceId,
        channelName: '',
        title: schedule.title ?? '',
      ),
  ];
}

/// The viewer's recording tendency, aggregated from
/// samples: how often each genre, channel and series
/// appears in what they record. The score reads the
/// counts relative to the strongest count of each
/// kind, so the profile needs no tuning as the
/// library grows.
class TendencyProfile {
  const TendencyProfile({
    required this.sampleCount,
    required this.genreCounts,
    required this.channelCounts,
    required this.channelNames,
    required this.seriesCounts,
  });

  factory TendencyProfile.aggregate(Iterable<TendencySample> samples) {
    final genreCounts = <int, int>{};
    final channelCounts = <String, int>{};
    final channelNames = <String, String>{};
    final seriesCounts = <String, int>{};
    var count = 0;
    for (final sample in samples) {
      count++;
      final genre = sample.genreLevel1;
      if (genre != null) {
        genreCounts[genre] = (genreCounts[genre] ?? 0) + 1;
      }
      // A sample without a real channel (a title whose
      // scheduled channel is unknown) counts for
      // neither the channel counts nor the names.
      if (sample.broadcastingType >= 0 && sample.serviceId >= 0) {
        channelCounts[sample.channelKey] =
            (channelCounts[sample.channelKey] ?? 0) + 1;
        if (sample.channelName.isNotEmpty) {
          channelNames.putIfAbsent(sample.channelKey, () => sample.channelName);
        }
      }
      final series = autoPickSeriesKey(sample.title);
      if (series.isNotEmpty) {
        seriesCounts[series] = (seriesCounts[series] ?? 0) + 1;
      }
    }
    return TendencyProfile(
      sampleCount: count,
      genreCounts: genreCounts,
      channelCounts: channelCounts,
      channelNames: channelNames,
      seriesCounts: seriesCounts,
    );
  }

  static const empty = TendencyProfile(
    sampleCount: 0,
    genreCounts: {},
    channelCounts: {},
    channelNames: {},
    seriesCounts: {},
  );

  final int sampleCount;
  final Map<int, int> genreCounts;
  final Map<String, int> channelCounts;

  /// Channel key → display name (first name a sample
  /// offered; samples from reservations offer none,
  /// so a channel counted only from reservations has
  /// no name here — the ranking falls back to the key).
  final Map<String, String> channelNames;
  final Map<String, int> seriesCounts;

  int get maxGenreCount => genreCounts.values.fold(0, (a, b) => a > b ? a : b);
  int get maxChannelCount =>
      channelCounts.values.fold(0, (a, b) => a > b ? a : b);

  /// The genre ranking for display: count order,
  /// strongest first, ARIB order breaking ties.
  List<({int genreLevel1, int count})> get genreRanking {
    final entries =
        [
          for (final entry in genreCounts.entries)
            (genreLevel1: entry.key, count: entry.value),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0
              ? byCount
              : a.genreLevel1.compareTo(b.genreLevel1);
        });
    return entries;
  }

  /// The channel ranking for display: count order,
  /// strongest first, channel key breaking ties.
  List<({String key, String name, int count})> get channelRanking {
    final entries =
        [
          for (final entry in channelCounts.entries)
            (
              key: entry.key,
              name: channelNames[entry.key] ?? entry.key,
              count: entry.value,
            ),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0 ? byCount : a.key.compareTo(b.key);
        });
    return entries;
  }

  /// The series ranking for display: count order,
  /// strongest first, title breaking ties.
  List<({String title, int count})> get seriesRanking {
    final entries =
        [
          for (final entry in seriesCounts.entries)
            (title: entry.key, count: entry.value),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0 ? byCount : a.title.compareTo(b.title);
        });
    return entries;
  }
}

/// One line of a score's breakdown: what earned the
/// points, in the words the ranking screen shows.
class AutoPickScorePart {
  const AutoPickScorePart({required this.label, required this.points});

  final String label;
  final int points;
}

/// A programme's auto pick score: the total the
/// ranking sorts by, and the parts that earned it —
/// the screen shows the parts, so a pick never has
/// to be taken on faith.
class AutoPickScore {
  const AutoPickScore({required this.total, required this.parts});

  final int total;
  final List<AutoPickScorePart> parts;
}

/// Whether the programme carries a first-episode
/// marker in its title or outline: 第1話, a
/// bracketed-新 new-series marker (fullwidth or
/// halfwidth brackets), 新番組, or 初回. The EPG
/// model carries no first-run flag of its own, so the
/// marker is read from the programme's own text —
/// the fields a viewer reads it from.
bool autoPickHasFirstEpisodeMarker(EpgEvent event) {
  const markers = ['第1話', '\u{3010}新\u{3011}', '[新]', '新番組', '初回'];
  for (final text in [event.title, event.shortText]) {
    if (text == null) continue;
    for (final marker in markers) {
      if (text.contains(marker)) return true;
    }
  }
  return false;
}

/// Whether the programme starts in prime time: the
/// JST wall clock's 19:00–23:00, the hours the
/// evening's main programmes run.
bool autoPickStartsInPrimeTime(DateTime start) {
  final hour = jstWallClock(start).hour;
  return hour >= 19 && hour < 23;
}

/// Scores one programme against the viewer's
/// tendency profile. The weights, strongest first:
///
/// - the same series as something already recorded
/// or reserved: +30 (the single strongest signal —
/// the viewer demonstrably follows this programme);
/// - the genre tendency: up to +25, scaled by how
/// the programme's genre count stands against the
/// viewer's most-recorded genre;
/// - the channel tendency: up to +15, scaled the
/// same way against the most-recorded channel;
/// - a first-episode marker: +15 (a series caught
/// from its start can still be followed);
/// - a film (genre level-1 6): +10 (a one-off worth
/// catching whole, the way the genre tendency
/// cannot express);
/// - a prime-time start: +10.
///
/// A programme with no signal at all scores 0 and is
/// never a candidate: the auto pick fills time with
/// likely programmes, not with arbitrary ones.
AutoPickScore scoreAutoPickCandidate({
  required EpgEvent event,
  required Channel channel,
  required TendencyProfile profile,
}) {
  final parts = <AutoPickScorePart>[];
  void add(String label, int points) {
    if (points > 0) parts.add(AutoPickScorePart(label: label, points: points));
  }

  final series = autoPickSeriesKey(event.title ?? '');
  if (series.isNotEmpty && (profile.seriesCounts[series] ?? 0) > 0) {
    add('よく録るシリーズ', 30);
  }
  final genre = event.genreLevel1;
  if (genre != null && profile.maxGenreCount > 0) {
    final count = profile.genreCounts[genre] ?? 0;
    add('よく録るジャンル', (25 * count / profile.maxGenreCount).round());
  }
  if (profile.maxChannelCount > 0) {
    final key = autoPickChannelKey(
      broadcastingType: channel.broadcastingType,
      serviceId: channel.serviceId,
    );
    final count = profile.channelCounts[key] ?? 0;
    add('よく録るチャンネル', (15 * count / profile.maxChannelCount).round());
  }
  if (autoPickHasFirstEpisodeMarker(event)) add('第1話・新番組', 15);
  if (genre == 6) add('映画', 10);
  if (autoPickStartsInPrimeTime(event.start)) add('プライムタイム', 10);

  return AutoPickScore(
    total: parts.fold(0, (sum, part) => sum + part.points),
    parts: parts,
  );
}

/// Why the plan leaves a candidate alone (or takes
/// it). The ranking screen words each of these; the
/// checker acts on [AutoPickDisposition.picked].
enum AutoPickDisposition {
  /// The next check reserves this programme.
  picked,

  /// Already reserved on this unit — by hand, by a
  /// rule, or by torne.
  alreadyReserved,

  /// Already reserved on this unit by an earlier
  /// auto pick (the mark store names it).
  alreadyAutoReserved,

  /// Already reserved on another unit: reserved once
  /// across the household is enough.
  reservedOnOtherUnit,

  /// The tuner is taken at that time — by a
  /// reservation, or by a stronger candidate in the
  /// same plan.
  conflict,

  /// The per-check cap was already filled by
  /// stronger candidates.
  overLimit,

  /// The disk guard stopped the plan: the unit's
  /// free space is under the floor (or unknown).
  capacityBlocked,
}

/// One candidate of an auto pick plan: the programme,
/// its score, and what the plan does with it.
class AutoPickCandidate {
  const AutoPickCandidate({
    required this.hit,
    required this.score,
    required this.disposition,
  });

  final EpgSearchHit hit;
  final AutoPickScore score;
  final AutoPickDisposition disposition;
}

/// The outcome of one auto pick planning pass: every
/// candidate considered, in score order, and the
/// ones the plan picks.
class AutoPickPlan {
  const AutoPickPlan({required this.candidates});

  final List<AutoPickCandidate> candidates;

  List<AutoPickCandidate> get picks => [
    for (final candidate in candidates)
      if (candidate.disposition == AutoPickDisposition.picked) candidate,
  ];
}

bool _overlaps(
  DateTime aStart,
  DateTime aEnd,
  DateTime bStart,
  DateTime bEnd,
) => aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

/// Plans the auto pick for one unit: scores the
/// guide's future programmes against [profile] and
/// walks them, strongest first, into the time the
/// unit's reservations leave free.
///
/// - Only programmes starting after [now] and
/// scoring above zero are candidates at all.
/// - [existing] is the unit's reservation list as the
/// plan sees it — the checker passes the list with
/// the rule pass's creations already in, so a
/// rule's programme is a conflict here, never a
/// second pick. [externalReservedKeys] are the
/// programme keys other units hold (the two-nasne
/// rule: reserved once is enough); they duplicate
/// a programme without taking this unit's tuner.
/// - [autoReservedKeys] are the programme keys the
/// mark store holds for this unit: a candidate
/// among them is reported as already auto-reserved
/// rather than merely reserved, so the screen can
/// tell the viewer the app itself put it there.
/// - The disk guard: [freeBytes] under
/// [minFreeBytes] — or null, unknown — blocks every
/// pick. The guard is read once per check from the
/// unit's own report; the per-check cap bounds how
/// much one check can add on top of it.
/// - At most [maxPicks] programmes are picked.
/// - [evaluateLimit] bounds how far down the score
/// order the plan walks (the screen's list and the
/// checker's work both stay finite); picks can
/// only come from within it.
AutoPickPlan planAutoPick({
  required List<EpgSearchHit> hits,
  required TendencyProfile profile,
  required List<RecordSchedule> existing,
  required DateTime now,
  required int maxPicks,
  required int? freeBytes,
  required int minFreeBytes,
  Set<String> externalReservedKeys = const {},
  Set<String> autoReservedKeys = const {},
  int evaluateLimit = 50,
}) {
  final reservedKeys = <String>{
    for (final s in existing)
      autoRecordProgrammeKey(
        broadcastingType: s.channel.broadcastingType,
        serviceId: s.channel.serviceId,
        start: s.start,
      ),
  };
  final busy = <({DateTime start, DateTime end})>[
    for (final s in existing) (start: s.start, end: s.end),
  ];
  final capacityBlocked = freeBytes == null || freeBytes < minFreeBytes;

  final scored = <({EpgSearchHit hit, AutoPickScore score, String key})>[];
  final seenKeys = <String>{};
  for (final hit in hits) {
    final event = hit.event;
    if (!event.start.isAfter(now)) continue;
    final key = autoRecordProgrammeKey(
      broadcastingType: hit.channel.broadcastingType,
      serviceId: hit.channel.serviceId,
      start: event.start,
    );
    if (!seenKeys.add(key)) continue;
    final score = scoreAutoPickCandidate(
      event: event,
      channel: hit.channel,
      profile: profile,
    );
    // A programme already auto-reserved stays listed
    // (the screen marks it) even though its score is
    // recomputed each time and may have fallen to
    // zero; everything else needs a signal.
    if (score.total <= 0 && !autoReservedKeys.contains(key)) continue;
    scored.add((hit: hit, score: score, key: key));
  }
  scored.sort((a, b) {
    final byScore = b.score.total.compareTo(a.score.total);
    if (byScore != 0) return byScore;
    final byStart = a.hit.event.start.compareTo(b.hit.event.start);
    if (byStart != 0) return byStart;
    return a.key.compareTo(b.key);
  });

  final candidates = <AutoPickCandidate>[];
  var picks = 0;
  for (final entry in scored.take(evaluateLimit)) {
    final AutoPickDisposition disposition;
    if (autoReservedKeys.contains(entry.key) &&
        reservedKeys.contains(entry.key)) {
      disposition = AutoPickDisposition.alreadyAutoReserved;
    } else if (reservedKeys.contains(entry.key)) {
      disposition = AutoPickDisposition.alreadyReserved;
    } else if (externalReservedKeys.contains(entry.key)) {
      disposition = AutoPickDisposition.reservedOnOtherUnit;
    } else if (capacityBlocked) {
      disposition = AutoPickDisposition.capacityBlocked;
    } else if (busy.any(
      (span) => _overlaps(
        entry.hit.event.start,
        entry.hit.event.end,
        span.start,
        span.end,
      ),
    )) {
      disposition = AutoPickDisposition.conflict;
    } else if (picks >= maxPicks) {
      disposition = AutoPickDisposition.overLimit;
    } else {
      disposition = AutoPickDisposition.picked;
      picks++;
      busy.add((start: entry.hit.event.start, end: entry.hit.event.end));
      reservedKeys.add(entry.key);
    }
    candidates.add(
      AutoPickCandidate(
        hit: entry.hit,
        score: entry.score,
        disposition: disposition,
      ),
    );
  }
  return AutoPickPlan(candidates: candidates);
}

/// The tendency profile of one unit's library: its
/// recorded titles and its reservations, aggregated
/// (see [autoPickSamplesFromTitles] and
/// [autoPickSamplesFromSchedules]). The checker and
/// the ranking screen build it the same way, from
/// the same unit's data.
TendencyProfile autoPickProfileFor({
  required List<RecordedTitle> titles,
  required List<RecordSchedule> schedules,
  required List<EpgSearchHit> guideHits,
}) => TendencyProfile.aggregate([
  ...autoPickSamplesFromTitles(titles),
  ...autoPickSamplesFromSchedules(schedules, guideHits),
]);
