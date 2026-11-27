/// Auto pick policy tests (user-fork addition): the
/// tendency aggregation, the scoring and the plan —
/// the three computations the checker and the ranking
/// screen share, so what the screen promises is what
/// the checker does.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/auto_pick_policy.dart';
import 'package:tmhb/ui/epg_search.dart';
import 'package:tmhb/ui/format.dart';

/// An instant whose JST wall clock reads as the
/// given fields (the test host runs in UTC).
DateTime jst(int month, int day, int hour, [int minute = 0]) =>
    instantFromJstWall(DateTime(2026, month, day, hour, minute));

Channel channel(int serviceId, {int type = 2, String name = 'テスト放送'}) =>
    Channel(
      broadcastingType: type,
      networkId: 1,
      transportStreamId: 1,
      serviceId: serviceId,
      serviceType: 1,
      channelNumber: serviceId,
      serviceName: name,
    );

EpgEvent event({
  required DateTime start,
  String? title,
  String? shortText,
  int? genre,
  int minutes = 60,
  int eventId = 1,
}) => EpgEvent(
  eventId: eventId,
  start: start,
  duration: Duration(minutes: minutes),
  title: title,
  shortText: shortText,
  genreLevel1: genre,
);

EpgSearchHit hit(Channel ch, EpgEvent e) => EpgSearchHit(
  service: EpgServiceGuide(channel: ch, events: [e]),
  event: e,
);

RecordSchedule schedule({
  required DateTime start,
  int serviceId = 100,
  int type = 2,
  int minutes = 60,
  String id = 's1',
}) => RecordSchedule(
  id: id,
  start: start,
  durationSeconds: minutes * 60,
  conditionId: '1',
  channel: ScheduleChannel(
    broadcastingType: type,
    channelType: type,
    serviceId: serviceId,
  ),
  desiredQualityMode: 100,
  desiredMatchingId: '',
  reservationCreatorId: '2000',
  priorityFlag: 0,
  recordDestinationId: 'HDD',
);

void main() {
  group('DIDL genre mapping', () {
    test('the measured fixture texts resolve to their genres', () {
      expect(autoPickGenreLevel1OfDidlGenre('ニュース／報道'), 0);
      expect(autoPickGenreLevel1OfDidlGenre('ドキュメンタリー／教養'), 8);
      expect(autoPickGenreLevel1OfDidlGenre('趣味／教育'), 10);
      expect(autoPickGenreLevel1OfDidlGenre('福祉'), 11);
      expect(autoPickGenreLevel1OfDidlGenre('ドラマ'), 3);
    });

    test('unknown or empty texts resolve to nothing', () {
      expect(autoPickGenreLevel1OfDidlGenre(null), isNull);
      expect(autoPickGenreLevel1OfDidlGenre(''), isNull);
      expect(autoPickGenreLevel1OfDidlGenre('謎のジャンル'), isNull);
    });
  });

  group('tendency aggregation', () {
    RecordedTitle title({
      required String name,
      String? genre,
      int serviceId = 100,
      String channelName = 'テスト放送',
    }) => RecordedTitle(
      id: 't-$name-$serviceId',
      title: name,
      channel: ScheduleChannel(
        broadcastingType: 2,
        channelType: 2,
        serviceId: serviceId,
      ),
      genre: genre,
      channelName: channelName,
    );

    test('titles feed genre, channel and series counts', () {
      final profile = TendencyProfile.aggregate(
        autoPickSamplesFromTitles([
          title(name: 'ドラマ甲', genre: 'ドラマ'),
          title(name: 'ドラマ甲', genre: 'ドラマ'),
          title(name: 'アニメ乙', genre: 'アニメ・特撮', serviceId: 200),
        ]),
      );
      expect(profile.sampleCount, 3);
      expect(profile.genreCounts, {3: 2, 7: 1});
      expect(profile.channelCounts, {'2:100': 2, '2:200': 1});
      expect(profile.seriesCounts, {'ドラマ甲': 2, 'アニメ乙': 1});
      expect(profile.genreRanking.first.genreLevel1, 3);
      expect(profile.channelRanking.first.name, 'テスト放送');
      expect(profile.seriesRanking.first.title, 'ドラマ甲');
    });

    test('a schedule takes its genre from the guide event', () {
      final start = jst(12, 1, 21);
      final profile = TendencyProfile.aggregate(
        autoPickSamplesFromSchedules(
          [schedule(start: start)],
          [hit(channel(100), event(start: start, title: '映画', genre: 6))],
        ),
      );
      expect(profile.genreCounts, {6: 1});
      expect(profile.channelCounts, {'2:100': 1});
    });

    test('a schedule the guide no longer holds counts without a genre', () {
      final profile = TendencyProfile.aggregate(
        autoPickSamplesFromSchedules([
          schedule(start: jst(12, 1, 21)),
        ], const []),
      );
      expect(profile.genreCounts, isEmpty);
      expect(profile.sampleCount, 1);
    });
  });

  group('scoring', () {
    final primeTime = jst(12, 5, 21); // 21:00 JST
    TendencyProfile profile() => TendencyProfile.aggregate(const [
      TendencySample(
        genreLevel1: 3,
        broadcastingType: 2,
        serviceId: 100,
        channelName: 'テスト放送',
        title: 'ドラマ甲',
      ),
      TendencySample(
        genreLevel1: 3,
        broadcastingType: 2,
        serviceId: 100,
        channelName: 'テスト放送',
        title: 'ドラマ甲',
      ),
      TendencySample(
        genreLevel1: 7,
        broadcastingType: 2,
        serviceId: 200,
        channelName: '別放送',
        title: 'アニメ乙',
      ),
    ]);

    test('a followed series on the favourite channel scores highest', () {
      final score = scoreAutoPickCandidate(
        event: event(start: primeTime, title: 'ドラマ甲', genre: 3),
        channel: channel(100),
        profile: profile(),
      );
      // series 30 + genre 25 (top genre) + channel 15 (top
      // channel) + prime time 10.
      expect(score.total, 80);
      expect(
        score.parts.map((p) => p.label),
        containsAll(['よく録るシリーズ', 'よく録るジャンル', 'よく録るチャンネル', 'プライムタイム']),
      );
    });

    test('genre and channel points scale against the strongest count', () {
      final score = scoreAutoPickCandidate(
        event: event(start: jst(12, 5, 13), title: 'アニメ乙', genre: 7),
        channel: channel(200),
        profile: profile(),
      );
      // series 30 + genre round(25 * 1/2) = 13 + channel
      // round(15 * 1/2) = 8; no prime time at 13:00 JST.
      expect(score.total, 30 + 13 + 8);
    });

    test('first-episode markers and films earn their own points', () {
      final first = scoreAutoPickCandidate(
        event: event(
          start: jst(12, 5, 13),
          title: '新ドラマ',
          shortText: '第1話',
          genre: 3,
        ),
        channel: channel(999),
        profile: TendencyProfile.empty,
      );
      expect(first.total, 15);
      final film = scoreAutoPickCandidate(
        event: event(start: jst(12, 5, 13), title: '映画', genre: 6),
        channel: channel(999),
        profile: TendencyProfile.empty,
      );
      expect(film.total, 10);
    });

    test('prime time is the JST 19:00–23:00 window', () {
      // Host time is UTC in the test environment; the
      // judgement is on the JST wall clock.
      expect(autoPickStartsInPrimeTime(jst(12, 5, 19)), isTrue); // 19:00 JST
      expect(
        autoPickStartsInPrimeTime(jst(12, 5, 18, 59)),
        isFalse,
      ); // 18:59 JST
      expect(
        autoPickStartsInPrimeTime(jst(12, 5, 22, 59)),
        isTrue,
      ); // 22:59 JST
      expect(autoPickStartsInPrimeTime(jst(12, 5, 23)), isFalse); // 23:00 JST
    });

    test('no signal scores zero', () {
      final score = scoreAutoPickCandidate(
        event: event(start: jst(12, 5, 13), title: '無関係', genre: 0),
        channel: channel(999),
        profile: profile(),
      );
      expect(score.total, 0);
      expect(score.parts, isEmpty);
    });
  });

  group('planning', () {
    final now = jst(12, 1, 12);
    DateTime at(int day, int hour) => jst(12, day, hour);

    TendencyProfile dramaProfile() => TendencyProfile.aggregate(const [
      TendencySample(
        genreLevel1: 3,
        broadcastingType: 2,
        serviceId: 100,
        channelName: 'テスト放送',
        title: 'ドラマ甲',
      ),
    ]);

    List<EpgSearchHit> guide() => [
      hit(
        channel(100),
        event(start: at(2, 21), title: 'ドラマ甲', genre: 3, eventId: 1),
      ),
      hit(
        channel(100),
        event(start: at(2, 22), title: 'ドラマ甲', genre: 3, eventId: 2),
      ),
      hit(
        channel(100),
        event(start: at(3, 21), title: 'ドラマ甲', genre: 3, eventId: 3),
      ),
    ];

    AutoPickPlan plan({
      List<EpgSearchHit>? hits,
      List<RecordSchedule> existing = const [],
      int maxPicks = 3,
      int? freeBytes = 100 << 30,
      int minFreeBytes = 20 << 30,
      Set<String> external = const {},
      Set<String> auto = const {},
    }) => planAutoPick(
      hits: hits ?? guide(),
      profile: dramaProfile(),
      existing: existing,
      now: now,
      maxPicks: maxPicks,
      freeBytes: freeBytes,
      minFreeBytes: minFreeBytes,
      externalReservedKeys: external,
      autoReservedKeys: auto,
    );

    test('free slots are filled in score order up to the cap', () {
      final result = plan(maxPicks: 2);
      expect(result.picks, hasLength(2));
      expect(result.candidates.map((c) => c.disposition), [
        AutoPickDisposition.picked,
        AutoPickDisposition.picked,
        AutoPickDisposition.overLimit,
      ]);
    });

    test('an existing reservation conflicts and is not doubled', () {
      final result = plan(existing: [schedule(start: at(2, 21), minutes: 90)]);
      final byStart = {
        for (final c in result.candidates) c.hit.event.start: c.disposition,
      };
      expect(byStart[at(2, 21)], AutoPickDisposition.alreadyReserved);
      // The 22:00 programme overlaps the reservation's
      // hour, so it conflicts; the next day is picked.
      expect(byStart[at(2, 22)], AutoPickDisposition.conflict);
      expect(byStart[at(3, 21)], AutoPickDisposition.picked);
    });

    test('picks conflict with each other', () {
      final overlapping = [
        hit(
          channel(100),
          event(
            start: at(2, 21),
            title: 'ドラマ甲',
            genre: 3,
            minutes: 120,
            eventId: 1,
          ),
        ),
        hit(
          channel(200),
          event(start: at(2, 22), title: 'ドラマ甲', genre: 3, eventId: 2),
        ),
      ];
      final result = plan(hits: overlapping);
      expect(result.candidates[0].disposition, AutoPickDisposition.picked);
      expect(result.candidates[1].disposition, AutoPickDisposition.conflict);
    });

    test('the disk guard blocks every pick under the floor', () {
      final result = plan(freeBytes: 10 << 30);
      expect(result.picks, isEmpty);
      expect(result.candidates.map((c) => c.disposition).toSet(), {
        AutoPickDisposition.capacityBlocked,
      });
    });

    test('unknown free space blocks too (never records unasked)', () {
      final result = plan(freeBytes: null);
      expect(result.picks, isEmpty);
    });

    test('free space exactly at the floor still picks', () {
      final result = plan(freeBytes: 20 << 30);
      expect(result.picks, isNotEmpty);
    });

    test('an other-unit programme is a duplicate, not a conflict', () {
      final key = '2:100:${at(2, 21).toIso8601String()}';
      final result = plan(external: {key});
      final byStart = {
        for (final c in result.candidates) c.hit.event.start: c.disposition,
      };
      expect(byStart[at(2, 21)], AutoPickDisposition.reservedOnOtherUnit);
      // The other unit's tuner time is not this unit's:
      // the overlapping 22:00 programme is still picked.
      expect(byStart[at(2, 22)], AutoPickDisposition.picked);
    });

    test('a marked programme reads as auto-reserved, not merely reserved', () {
      final key = '2:100:${at(2, 21).toIso8601String()}';
      final result = plan(
        existing: [schedule(start: at(2, 21))],
        auto: {key},
      );
      final byStart = {
        for (final c in result.candidates) c.hit.event.start: c.disposition,
      };
      expect(byStart[at(2, 21)], AutoPickDisposition.alreadyAutoReserved);
    });

    test('past programmes and zero-score programmes are not candidates', () {
      final hits = [
        hit(
          channel(100),
          event(start: at(1, 10), title: 'ドラマ甲', genre: 3, eventId: 9),
        ),
        hit(
          channel(999),
          event(start: at(2, 13), title: '無関係', genre: 0, eventId: 10),
        ),
        ...guide(),
      ];
      final result = plan(hits: hits);
      expect(result.candidates, hasLength(3));
    });
  });
}
