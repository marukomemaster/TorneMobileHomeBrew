/// Ranking screen (user-fork addition, owner
/// request 2026-11-27): four views over the same
/// computations the auto pick runs on, for the
/// selected nasne.
///
/// - 放送中 (on air, added 2026-11-28): the programmes
///   on air now, ranked by the same score — the
///   SideView-style home the owner asked for, minus
///   the popularity counts no local data can supply
///   (see onair_ranking_policy.dart). The first tab
///   and the opening view.
/// - 傾向 (tendency): what the viewer records,
///   counted by genre, channel and series — the
///   profile the auto pick scores against.
/// - おすすめ (recommendations): the held guide's
///   future programmes ranked by that score, each
///   row opening the programme's usual detail, so a
///   recommendation is one tap from a reservation.
/// - 自動候補 (auto candidates): what the next auto
///   pick check would actually do — the plan itself,
///   with the disk guard and the per-check cap
///   applied, and the programmes the auto pick
///   already reserved marked as its own.
///
/// Nothing here computes a second, private version
/// of the ranking: every score comes from
/// auto_pick_policy.dart, so the screen cannot
/// promise what the checker would not do.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/auto_pick_providers.dart';
import '../app/bs_epg_providers.dart';
import '../app/cs_epg_providers.dart';
import '../app/state.dart';
import '../core/core.dart';
import 'auto_pick_policy.dart';
import 'auto_record_policy.dart';
import 'epg_genre.dart';
import 'epg_reserved.dart';
import 'epg_screen.dart';
import 'onair_ranking_policy.dart';
import 'epg_search.dart';
import 'format.dart';
import 'live_screen.dart';
import 'tv_focus.dart';

class RankingScreen extends ConsumerStatefulWidget {
  const RankingScreen({super.key});

  @override
  ConsumerState<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends ConsumerState<RankingScreen> {
  // The opening view is 放送中: the screen opens on
  // what is on now, the way the compared app's home
  // does. Its segment leads the row but keeps value 3,
  // so the three original views keep their values.
  int _view = 3;

  @override
  Widget build(BuildContext context) {
    final reg = ref.watch(selectedRegistrationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('ランキング')),
      body: reg == null
          ? const Center(child: Text('nasne が登録されていません'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 3, label: Text('放送中')),
                      ButtonSegment(value: 0, label: Text('傾向')),
                      ButtonSegment(value: 1, label: Text('おすすめ')),
                      ButtonSegment(value: 2, label: Text('自動候補')),
                    ],
                    selected: {_view},
                    onSelectionChanged: (selection) =>
                        setState(() => _view = selection.single),
                  ),
                ),
                Expanded(
                  child: switch (_view) {
                    0 => _TendencyView(reg: reg),
                    1 => _RecommendView(reg: reg),
                    2 => _CandidatesView(reg: reg),
                    _ => _OnAirView(reg: reg),
                  },
                ),
              ],
            ),
    );
  }
}

/// The data every view shares, gathered from the
/// providers the rest of the app reads: the three
/// guides' hits, the unit's reservations and titles,
/// and the tendency profile over them.
class _RankingData {
  _RankingData(this.hits, this.schedules, this.profile);

  final List<EpgSearchHit> hits;
  final List<RecordSchedule> schedules;
  final TendencyProfile profile;
}

_RankingData _rankingData(WidgetRef ref, RegisteredNasne reg) {
  final hits = <EpgSearchHit>[];
  for (final provider in [
    epgGuideProvider(reg),
    bsEpgGuideProvider(reg),
    csEpgGuideProvider(reg),
  ]) {
    final guide = ref.watch(provider).value;
    if (guide == null) continue;
    for (final service in guide.services) {
      for (final event in service.events) {
        hits.add(EpgSearchHit(service: service, event: event));
      }
    }
  }
  final schedules =
      ref.watch(schedulesProvider(reg)).value ?? const <RecordSchedule>[];
  final titles =
      ref.watch(titlesProvider(reg)).value?.titles ?? const <RecordedTitle>[];
  return _RankingData(
    hits,
    schedules,
    autoPickProfileFor(titles: titles, schedules: schedules, guideHits: hits),
  );
}

/// A list of display-only rows, each wrapped in a
/// TvFocusAnchor: on the TV variant nothing else in such
/// a list can take focus, and a lazily built list only
/// builds what traversal has scrolled into view — edge
/// anchors alone would leave the tail unbuilt and
/// unreachable, so every row is a traversal stop that
/// scrolls the next rows in (plan 123's rule). On the
/// standard variant the anchors are the identity and
/// the list is unchanged.
Widget _tvTraversableList(List<Widget> rows) {
  return ListView(
    children: [for (final row in rows) TvFocusAnchor(child: row)],
  );
}

/// One scored programme row: rank, title, where and
/// when, the score and what earned it.
Widget _scoredRow({
  required int rank,
  required EpgSearchHit hit,
  required AutoPickScore score,
  String? trailingText,
  VoidCallback? onTap,
}) {
  final event = hit.event;
  final breakdown = score.parts
      .map((part) => '${part.label} +${part.points}')
      .join(' ・ ');
  return ListTile(
    leading: Text(
      '$rank',
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    ),
    title: Text(
      event.title ?? '（タイトルなし）',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(
      '${hit.channelName} ・ ${formatDateTimeWithWeekdayJst(event.start)}\n'
      'スコア ${score.total}${breakdown.isEmpty ? '' : '（$breakdown）'}',
    ),
    isThreeLine: true,
    trailing: trailingText == null
        ? null
        : Chip(label: Text(trailingText), visualDensity: VisualDensity.compact),
    onTap: onTap,
  );
}

/// 傾向: the viewer's recording tendency, counted.
class _TendencyView extends ConsumerWidget {
  const _TendencyView({required this.reg});

  final RegisteredNasne reg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = _rankingData(ref, reg).profile;
    if (profile.sampleCount == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '録画済みタイトルや予約がまだありません。録画がたまると、よく録るジャンルやチャンネルの傾向がここに出ます。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    Widget section(String title, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ...rows,
      ],
    );
    // TV: every ranking row is wrapped in a
    // TvFocusAnchor (below) — the rows are display-only,
    // and a lazily built list only builds what traversal
    // has scrolled into view, so each row must be a
    // traversal stop for the D-pad to walk the list.
    Widget rankRow(int rank, String label, int count) => TvFocusAnchor(
      child: ListTile(
        leading: Text(
          '$rank',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        title: Text(label),
        trailing: Text('$count 件'),
        dense: true,
      ),
    );
    final sections = [
      section('ジャンル別', [
        for (final (i, entry) in profile.genreRanking.take(10).indexed)
          rankRow(
            i + 1,
            epgGenreLabel(entry.genreLevel1) ?? 'ジャンル ${entry.genreLevel1}',
            entry.count,
          ),
      ]),
      section('チャンネル別', [
        for (final (i, entry) in profile.channelRanking.take(10).indexed)
          rankRow(i + 1, entry.name, entry.count),
      ]),
      section('シリーズ別', [
        for (final (i, entry) in profile.seriesRanking.take(10).indexed)
          rankRow(i + 1, entry.title, entry.count),
      ]),
    ];
    return ListView(children: [...sections, const SizedBox(height: 24)]);
  }
}

/// おすすめ: the guide's future programmes, ranked by
/// the auto pick score. A row opens the programme's
/// detail — the same dialog the guide and the search
/// open — so reserving from here is the usual flow.
class _RecommendView extends ConsumerWidget {
  const _RecommendView({required this.reg});

  final RegisteredNasne reg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = _rankingData(ref, reg);
    final now = DateTime.now();
    final scored = <({EpgSearchHit hit, AutoPickScore score})>[];
    for (final hit in data.hits) {
      if (!hit.event.start.isAfter(now)) continue;
      final score = scoreAutoPickCandidate(
        event: hit.event,
        channel: hit.channel,
        profile: data.profile,
      );
      if (score.total > 0) scored.add((hit: hit, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.total.compareTo(a.score.total);
      return byScore != 0
          ? byScore
          : a.hit.event.start.compareTo(b.hit.event.start);
    });
    if (scored.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'おすすめできる番組がまだありません。録画がたまると傾向が出て、番組表からおすすめが並びます。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final reservedIndex = EpgReservedIndex.fromSchedules(data.schedules);
    return ListView.builder(
      itemCount: scored.take(30).length,
      itemBuilder: (context, index) {
        final entry = scored[index];
        final hit = entry.hit;
        return _scoredRow(
          rank: index + 1,
          hit: hit,
          score: entry.score,
          onTap: () => showEpgEventDetail(
            context,
            reg: reg,
            channel: hit.channel,
            channelName: hit.channelName,
            event: hit.event,
            reservedSchedule: reservedIndex.scheduleFor(hit.channel, hit.event),
            onDeleteReserved: (schedule) =>
                deleteScheduleAndInvalidate(ref, reg, schedule),
            onWatch: () => openLiveChannelForEpg(
              context,
              ref,
              reg: reg,
              channel: hit.channel,
            ),
          ),
        );
      },
    );
  }
}

/// 自動候補: the plan the next check would run, as
/// the checker computes it — disk guard, per-check
/// cap and all — with each candidate's outcome in
/// words and the auto pick's own reservations marked.
class _CandidatesView extends ConsumerWidget {
  const _CandidatesView({required this.reg});

  final RegisteredNasne reg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = _rankingData(ref, reg);
    final settings = ref.watch(autoPickSettingsProvider);
    final marks = ref.watch(autoPickMarksProvider)[reg.host] ?? const <String>{};
    // Other units' reservations, for the duplicate
    // judgement (reserved once across the household).
    final externalKeys = <String>{};
    final registrations =
        ref.watch(registrationsProvider).value ?? const <RegisteredNasne>[];
    for (final other in registrations) {
      if (other.host == reg.host) continue;
      final schedules =
          ref.watch(schedulesProvider(other)).value ?? const <RecordSchedule>[];
      for (final s in schedules) {
        externalKeys.add(
          autoRecordProgrammeKey(
            broadcastingType: s.channel.broadcastingType,
            serviceId: s.channel.serviceId,
            start: s.start,
          ),
        );
      }
    }
    // The unit's free space, summed over the drives
    // the home screen shows a detail for; not loaded
    // (or failed) reads as unknown, which blocks.
    int? freeBytes;
    final hdd = ref.watch(hddDetailsProvider(reg)).value;
    if (hdd != null) {
      var sum = 0;
      var readAny = false;
      for (final detail in hdd) {
        final info = detail.info;
        if (info == null) continue;
        sum += info.freeBytes;
        readAny = true;
      }
      if (readAny) freeBytes = sum;
    }
    final plan = planAutoPick(
      hits: data.hits,
      profile: data.profile,
      existing: data.schedules,
      now: DateTime.now(),
      maxPicks: settings.maxPerCheck,
      freeBytes: freeBytes,
      minFreeBytes: settings.minFreeBytes,
      externalReservedKeys: externalKeys,
      autoReservedKeys: marks,
    );
    final guardText = freeBytes == null
        ? '空き容量が分からないため、自動録画は止まっています'
        : '空き容量 ${formatBytes(freeBytes)}'
              '（下限 ${settings.minFreeGb} GB ・ 1回の上限 ${settings.maxPerCheck} 件）';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            settings.enabled
                ? '次回のチェックで自動録画が拾う候補です。$guardText'
                : 'おまかせ自動録画はオフです。オンにすると、次回のチェックでこの候補から予約します。$guardText',
          ),
        ),
        Expanded(
          child: plan.candidates.isEmpty
              ? const Center(child: Text('候補はまだありません。'))
              : _tvTraversableList([
                  for (final (index, candidate)
                      in plan.candidates.take(30).indexed)
                    _scoredRow(
                      rank: index + 1,
                      hit: candidate.hit,
                      score: candidate.score,
                      trailingText: switch (candidate.disposition) {
                        AutoPickDisposition.picked => '次回予約',
                        AutoPickDisposition.alreadyAutoReserved => '自動で予約済み',
                        AutoPickDisposition.alreadyReserved => '予約済み',
                        AutoPickDisposition.reservedOnOtherUnit =>
                          '他の nasne で予約済み',
                        AutoPickDisposition.conflict => '時間帯が埋まっています',
                        AutoPickDisposition.overLimit => '上限のため対象外',
                        AutoPickDisposition.capacityBlocked => '容量ガードで停止中',
                      },
                    ),
                ]),
        ),
      ],
    );
  }
}

/// The channel logo bytes for one hit, from the logo
/// maps the guide screen reads: terrestrial and BS
/// fetch logos; CS fetches none (plan 137), so a CS
/// programme's card falls back to its genre block.
List<int>? _onAirLogoFor(
  EpgSearchHit hit,
  Map<int, List<int>> terrestrialLogos,
  Map<int, List<int>> bsLogos,
) {
  final logos = switch (hit.channel.broadcastingType) {
    2 => terrestrialLogos,
    3 => bsLogos,
    _ => const <int, List<int>>{},
  };
  return logos[hit.channel.serviceId];
}

/// The 放送中 badge: the official wording in the red
/// the official apps mark live programmes with (the
/// same red family as the guide's reserved frame).
Widget _onAirBadge() => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  decoration: BoxDecoration(
    color: const Color(0xFFD32F2F),
    borderRadius: BorderRadius.circular(4),
  ),
  child: const Text(
    '放送中',
    style: TextStyle(
      color: Colors.white,
      fontSize: 11,
      fontWeight: FontWeight.bold,
    ),
  ),
);

/// The medal colours of the top three ranks, the
/// compared app's crown chips read as: gold, silver,
/// bronze.
Color _onAirRankColor(int rank) => switch (rank) {
  1 => const Color(0xFFFFC107),
  2 => const Color(0xFFB0BEC5),
  _ => const Color(0xFFBC7A45),
};

/// One of the top three on-air programmes, as a large
/// card: a header band carrying the channel logo (or,
/// without one, the genre colour block with the genre
/// named), then the title, channel, time span and the
/// 放送中 badge. No still image is shown: the unit
/// serves no programme stills for guide events.
class _OnAirCard extends StatelessWidget {
  const _OnAirCard({
    required this.rank,
    required this.entry,
    required this.logo,
    required this.onTap,
  });

  final int rank;
  final OnAirRankedProgramme entry;
  final List<int>? logo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = entry.hit.event;
    final genreColor = epgGenreColor(event.genreLevel1);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 96,
              color:
                  genreColor?.withAlpha(217) ??
                  theme.colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: logo != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Image.memory(
                        Uint8List.fromList(logo!),
                        height: 44,
                        fit: BoxFit.contain,
                      ),
                    )
                  : Text(
                      epgGenreLabel(event.genreLevel1) ?? entry.hit.channelName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _onAirRankColor(rank),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$rank位',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _onAirBadge(),
                      const Spacer(),
                      Text(
                        'スコア ${entry.score.total}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.title ?? '（タイトルなし）',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.hit.channelName} ・ '
                    '${formatTimeJst(event.start)}–${formatTimeJst(event.end)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One on-air programme below the top three: a compact
/// row with a small channel logo (or, without one, a
/// genre colour block), the title, where and when, and
/// the rank.
class _OnAirRow extends StatelessWidget {
  const _OnAirRow({
    required this.rank,
    required this.entry,
    required this.logo,
    required this.onTap,
  });

  final int rank;
  final OnAirRankedProgramme entry;
  final List<int>? logo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final event = entry.hit.event;
    return ListTile(
      leading: SizedBox(
        width: 56,
        height: 32,
        child: logo != null
            ? Image.memory(Uint8List.fromList(logo!), fit: BoxFit.contain)
            : DecoratedBox(
                decoration: BoxDecoration(
                  color:
                      epgGenreColor(event.genreLevel1)?.withAlpha(160) ??
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
      ),
      title: Text(
        event.title ?? '（タイトルなし）',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${entry.hit.channelName} ・ '
        '${formatTimeJst(event.start)}–${formatTimeJst(event.end)} ・ '
        'スコア ${entry.score.total}',
      ),
      trailing: Text(
        '$rank',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      onTap: onTap,
    );
  }
}

/// 放送中: the programmes on air now, ranked by the
/// tendency score (onair_ranking_policy.dart). The top
/// three are large cards; the rest are compact rows
/// with a small channel logo (or genre block). A tap
/// opens the programme's usual detail — the same
/// dialog the guide, the search and おすすめ open —
/// so watching and reserving take the existing paths.
class _OnAirView extends ConsumerWidget {
  const _OnAirView({required this.reg});

  final RegisteredNasne reg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = _rankingData(ref, reg);
    final ranked = rankOnAirProgrammes(
      hits: data.hits,
      profile: data.profile,
      now: DateTime.now(),
    );
    if (ranked.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '放送中の番組がまだありません。番組表が読み込まれると、今放送している番組がここに並びます。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final terrestrialLogos =
        ref.watch(channelLogosProvider(reg)).value ?? const <int, List<int>>{};
    final bsLogos =
        ref.watch(bsChannelLogosProvider(reg)).value ?? const <int, List<int>>{};
    final reservedIndex = EpgReservedIndex.fromSchedules(data.schedules);
    void openDetail(OnAirRankedProgramme entry) {
      final hit = entry.hit;
      showEpgEventDetail(
        context,
        reg: reg,
        channel: hit.channel,
        channelName: hit.channelName,
        event: hit.event,
        reservedSchedule: reservedIndex.scheduleFor(hit.channel, hit.event),
        onDeleteReserved: (schedule) =>
            deleteScheduleAndInvalidate(ref, reg, schedule),
        onWatch: () =>
            openLiveChannelForEpg(context, ref, reg: reg, channel: hit.channel),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        for (final (index, entry) in ranked.indexed)
          TvFocusAnchor(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: index < 3
                  ? _OnAirCard(
                      rank: index + 1,
                      entry: entry,
                      logo: _onAirLogoFor(
                        entry.hit,
                        terrestrialLogos,
                        bsLogos,
                      ),
                      onTap: () => openDetail(entry),
                    )
                  : _OnAirRow(
                      rank: index + 1,
                      entry: entry,
                      logo: _onAirLogoFor(
                        entry.hit,
                        terrestrialLogos,
                        bsLogos,
                      ),
                      onTap: () => openDetail(entry),
                    ),
            ),
          ),
      ],
    );
  }
}
