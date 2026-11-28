/// On-air ranking policy tests (user-fork addition):
/// the 放送中 tab's list — only programmes on air, in
/// tendency-score order with a deterministic tie-break,
/// zero scores included, duplicates listed once.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/auto_pick_policy.dart';
import 'package:tmhb/ui/epg_search.dart';
import 'package:tmhb/ui/onair_ranking_policy.dart';

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
  int? genre,
  int minutes = 60,
  int eventId = 1,
}) => EpgEvent(
  eventId: eventId,
  start: start,
  duration: Duration(minutes: minutes),
  title: title,
  genreLevel1: genre,
);

EpgSearchHit hit(Channel ch, EpgEvent e) => EpgSearchHit(
  service: EpgServiceGuide(channel: ch, events: [e]),
  event: e,
);

void main() {
  // 2026-11-28 20:15 — prime time, so an on-air
  // programme with no other signal still scores the
  // prime-time points; the zero-score case below runs
  // outside it.
  final now = DateTime(2026, 11, 28, 20, 15);

  TendencyProfile profileWithSeries(String title) =>
      TendencyProfile.aggregate([
        TendencySample(
          broadcastingType: 2,
          serviceId: 100,
          channelName: 'テスト放送',
          title: title,
        ),
      ]);

  group('rankOnAirProgrammes', () {
    test('only programmes on air are listed: past and future are out, '
        'the starting instant is in, the ending instant is out', () {
      final ch = channel(100);
      final ranked = rankOnAirProgrammes(
        hits: [
          hit(ch, event(start: now.subtract(const Duration(hours: 2)), title: '終わった番組')),
          hit(ch, event(start: now.add(const Duration(hours: 1)), title: 'これからの番組')),
          hit(ch, event(start: now, title: '今始まる番組')),
          hit(
            ch,
            event(start: now.subtract(const Duration(hours: 1)), title: '今終わる番組'),
          ),
          hit(ch, event(start: now.subtract(const Duration(minutes: 30)), title: '放送中')),
        ],
        profile: TendencyProfile.empty,
        now: now,
      );
      expect(
        ranked.map((e) => e.hit.event.title),
        unorderedEquals(['今始まる番組', '放送中']),
      );
    });

    test('a series the viewer records outranks a programme with no '
        'history', () {
      final ch = channel(100);
      final ranked = rankOnAirProgrammes(
        hits: [
          hit(ch, event(start: now.subtract(const Duration(minutes: 5)), title: '無名の番組')),
          hit(ch, event(start: now.subtract(const Duration(minutes: 40)), title: 'いつもの番組')),
        ],
        profile: profileWithSeries('いつもの番組'),
        now: now,
      );
      expect(ranked.first.hit.event.title, 'いつもの番組');
      expect(ranked.first.score.total, greaterThan(ranked.last.score.total));
    });

    test('equal scores order by start, then by programme key', () {
      final early = channel(100);
      final late = channel(200);
      final ranked = rankOnAirProgrammes(
        hits: [
          hit(late, event(start: now.subtract(const Duration(minutes: 5)), title: '遅い開始')),
          hit(early, event(start: now.subtract(const Duration(minutes: 5)), title: '同じ開始')),
          hit(early, event(start: now.subtract(const Duration(minutes: 45)), title: '早い開始', eventId: 2)),
        ],
        profile: TendencyProfile.empty,
        now: now,
      );
      // All three carry only the prime-time points, so
      // the order is start order; the two sharing a
      // start fall to the programme key (service 100
      // before 200).
      expect(
        ranked.map((e) => e.hit.event.title),
        ['早い開始', '同じ開始', '遅い開始'],
      );
    });

    test('a zero-score programme is still listed, at the bottom', () {
      final midday = DateTime(2026, 11, 28, 14, 15);
      final ch = channel(100);
      final ranked = rankOnAirProgrammes(
        hits: [
          hit(ch, event(start: midday.subtract(const Duration(minutes: 10)), title: '無信号の番組')),
          hit(
            ch,
            event(
              start: midday.subtract(const Duration(minutes: 20)),
              title: '映画番組',
              genre: 6,
            ),
          ),
        ],
        profile: TendencyProfile.empty,
        now: midday,
      );
      expect(ranked, hasLength(2));
      expect(ranked.last.hit.event.title, '無信号の番組');
      expect(ranked.last.score.total, 0);
    });

    test('the same programme listed twice appears once', () {
      final ch = channel(100);
      final e = event(start: now.subtract(const Duration(minutes: 10)), title: '放送中');
      final ranked = rankOnAirProgrammes(
        hits: [hit(ch, e), hit(ch, e)],
        profile: TendencyProfile.empty,
        now: now,
      );
      expect(ranked, hasLength(1));
    });

    test('no programmes on air: an empty ranking', () {
      final ch = channel(100);
      expect(
        rankOnAirProgrammes(
          hits: [hit(ch, event(start: now.add(const Duration(hours: 1)), title: '未来'))],
          profile: TendencyProfile.empty,
          now: now,
        ),
        isEmpty,
      );
    });
  });
}
