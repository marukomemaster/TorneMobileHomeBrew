/// On-air ranking (user-fork addition, owner request
/// 2026-11-28): the ranking screen's 放送中 tab, modelled
/// on the home screen of the app the owner compared
/// against — what is on now, biggest first, in a list
/// that reads at a glance.
///
/// The ordering is the viewer's own tendency, not a
/// popularity chart: the numbers a popularity ranking
/// would need (everyone's viewing and reservation
/// counts) live on a server this app has no access to,
/// and none are shown. Each on-air programme is scored
/// by the same tendency scoring the auto pick uses
/// (auto_pick_policy.dart), so the tab cannot promise
/// an order the rest of the app would not compute.
///
/// Two deliberate differences from the おすすめ tab,
/// which ranks the future:
///
/// - Every programme on air is listed, score zero
///   included. おすすめ is a filter (a future programme
///   with no signal is not a recommendation), but this
///   tab answers "what is on now" — a programme the
///   viewer has no history with is still on, and still
///   belongs in the answer, at the bottom.
/// - The order is fully deterministic: score, then
///   start, then the programme key — the same tie-break
///   chain the auto pick plan sorts by, so two builds
///   of the list can never disagree.
library;

import 'auto_pick_policy.dart';
import 'auto_record_policy.dart';
import 'epg_onair_policy.dart';
import 'epg_search.dart';

/// One programme of the on-air ranking: the guide hit
/// and its tendency score.
class OnAirRankedProgramme {
  const OnAirRankedProgramme({required this.hit, required this.score});

  final EpgSearchHit hit;
  final AutoPickScore score;
}

/// The programmes on air at [now] in [hits] (the held
/// guides of every band), ranked by tendency score.
///
/// A programme the guide holds twice under one key
/// (the same event listed by two bands' datasets)
/// appears once — the first listing wins, as the auto
/// pick plan dedupes. Programmes that have not started
/// or have already ended are not on air and never
/// appear (epg_onair_policy's half-open interval).
List<OnAirRankedProgramme> rankOnAirProgrammes({
  required List<EpgSearchHit> hits,
  required TendencyProfile profile,
  required DateTime now,
}) {
  final seenKeys = <String>{};
  final entries = <({EpgSearchHit hit, AutoPickScore score, String key})>[];
  for (final hit in hits) {
    final event = hit.event;
    if (!epgEventIsOnAir(start: event.start, end: event.end, now: now)) {
      continue;
    }
    final key = autoRecordProgrammeKey(
      broadcastingType: hit.channel.broadcastingType,
      serviceId: hit.channel.serviceId,
      start: event.start,
    );
    if (!seenKeys.add(key)) continue;
    entries.add((
      hit: hit,
      score: scoreAutoPickCandidate(
        event: event,
        channel: hit.channel,
        profile: profile,
      ),
      key: key,
    ));
  }
  entries.sort((a, b) {
    final byScore = b.score.total.compareTo(a.score.total);
    if (byScore != 0) return byScore;
    final byStart = a.hit.event.start.compareTo(b.hit.event.start);
    if (byStart != 0) return byStart;
    return a.key.compareTo(b.key);
  });
  return [
    for (final entry in entries)
      OnAirRankedProgramme(hit: entry.hit, score: entry.score),
  ];
}
