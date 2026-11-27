/// Ranking screen (user-fork addition, owner
/// request 2026-11-27): three views over the same
/// computations the auto pick runs on, for the
/// selected nasne.
///
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
/// of the ranking: every number comes from
/// auto_pick_policy.dart, so the screen cannot
/// promise what the checker would not do.
library;

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
import 'epg_search.dart';
import 'format.dart';
import 'live_screen.dart';

class RankingScreen extends ConsumerStatefulWidget {
  const RankingScreen({super.key});

  @override
  ConsumerState<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends ConsumerState<RankingScreen> {
  int _view = 0;

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
                    _ => _CandidatesView(reg: reg),
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
    Widget rankRow(int rank, String label, int count) => ListTile(
      leading: Text(
        '$rank',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      title: Text(label),
      trailing: Text('$count 件'),
      dense: true,
    );
    return ListView(
      children: [
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
        const SizedBox(height: 24),
      ],
    );
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
              : ListView.builder(
                  itemCount: plan.candidates.take(30).length,
                  itemBuilder: (context, index) {
                    final candidate = plan.candidates[index];
                    return _scoredRow(
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
                    );
                  },
                ),
        ),
      ],
    );
  }
}
