/// Auto record policy tests (user-fork addition):
/// rule matching, the stored form, and planning —
/// priority order, duplicates against the unit's
/// reservations, and single-tuner conflicts.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/auto_record_policy.dart';
import 'package:tmhb/ui/epg_search.dart';

void main() {
  const channel = Channel(
    broadcastingType: 2,
    networkId: 1,
    transportStreamId: 1,
    serviceId: 100,
    serviceType: 1,
    channelNumber: 1,
    serviceName: 'テスト放送',
  );
  const otherChannel = Channel(
    broadcastingType: 2,
    networkId: 1,
    transportStreamId: 2,
    serviceId: 200,
    serviceType: 1,
    channelNumber: 2,
    serviceName: 'テスト放送２',
  );

  EpgSearchHit hit(
    DateTime start,
    int minutes, {
    String? title,
    String? description,
    int? genre,
    Channel on = channel,
    int eventId = 1,
  }) {
    return EpgSearchHit(
      service: EpgServiceGuide(channel: on, events: const []),
      event: EpgEvent(
        eventId: eventId,
        start: start,
        duration: Duration(minutes: minutes),
        title: title,
        description: description,
        genreLevel1: genre,
      ),
    );
  }

  RecordSchedule existing(DateTime start, int minutes, {int serviceId = 100}) {
    return RecordSchedule(
      id: 'existing-$serviceId-${start.toIso8601String()}',
      start: start,
      durationSeconds: minutes * 60,
      conditionId: '1',
      channel: ScheduleChannel(
        broadcastingType: 2,
        channelType: 2,
        serviceId: serviceId,
      ),
      desiredQualityMode: 100,
      desiredMatchingId: '',
      reservationCreatorId: '2000',
      priorityFlag: 0,
      recordDestinationId: 'HDD',
    );
  }

  final now = DateTime(2026, 11, 26, 12);
  DateTime at(int day, int hour, [int minute = 0]) =>
      DateTime(2026, 11, day, hour, minute);

  EpgEvent event({
    String? title,
    int? genre,
    String? shortText,
    String? description,
    String? cast,
    String? extendedText,
    List<EpgExtendedItem> extendedItems = const [],
  }) => EpgEvent(
    eventId: 1,
    start: at(27, 20),
    duration: const Duration(minutes: 30),
    title: title,
    shortText: shortText,
    description: description,
    cast: cast,
    extendedText: extendedText,
    extendedItems: extendedItems,
    genreLevel1: genre,
  );

  group('autoRecordRuleMatches', () {
    test('keyword matches the title, case-insensitively', () {
      const rule = AutoRecordRule(id: 'a', keyword: 'news');
      expect(autoRecordRuleMatches(rule, event(title: 'News ABC')), isTrue);
      expect(autoRecordRuleMatches(rule, event(title: 'ドラマ')), isFalse);
    });

    test('keyword matches the outline and the description too', () {
      const rule = AutoRecordRule(id: 'a', keyword: '宇宙');
      expect(
        autoRecordRuleMatches(
          rule,
          event(title: 'ドキュメント', shortText: '宇宙の謎に迫る'),
        ),
        isTrue,
      );
      expect(
        autoRecordRuleMatches(
          rule,
          event(title: 'ドキュメント', description: '宇宙ステーションの記録'),
        ),
        isTrue,
      );
      expect(
        autoRecordRuleMatches(
          rule,
          event(title: 'ドキュメント', shortText: '海の謎に迫る'),
        ),
        isFalse,
      );
    });

    test('keyword matches the cast and the extended text too', () {
      const rule = AutoRecordRule(id: 'a', keyword: '山田');
      expect(
        autoRecordRuleMatches(rule, event(title: 'ドラマ', cast: '山田太郎')),
        isTrue,
      );
      expect(
        autoRecordRuleMatches(
          rule,
          event(title: 'ドラマ', extendedText: '出演は山田太郎'),
        ),
        isTrue,
      );
      expect(
        autoRecordRuleMatches(
          rule,
          event(
            title: 'ドラマ',
            extendedItems: const [
              EpgExtendedItem(label: '解説', value: '山田太郎が解説'),
            ],
          ),
        ),
        isTrue,
      );
      expect(
        autoRecordRuleMatches(rule, event(title: 'ドラマ', cast: '佐藤花')),
        isFalse,
      );
    });

    test('a keyword in the description claims an untitled event', () {
      const rule = AutoRecordRule(id: 'a', keyword: '宇宙');
      expect(autoRecordRuleMatches(rule, event(description: '宇宙の番組')), isTrue);
    });

    test('the genre still gates a keyword hit in the description', () {
      const rule = AutoRecordRule(id: 'a', keyword: '宇宙', genreLevel1: 7);
      expect(
        autoRecordRuleMatches(rule, event(description: '宇宙の番組', genre: 7)),
        isTrue,
      );
      expect(
        autoRecordRuleMatches(rule, event(description: '宇宙の番組', genre: 3)),
        isFalse,
      );
    });

    test('genre must be the event genre', () {
      const rule = AutoRecordRule(id: 'a', genreLevel1: 7);
      expect(autoRecordRuleMatches(rule, event(genre: 7)), isTrue);
      expect(autoRecordRuleMatches(rule, event(genre: 3)), isFalse);
      expect(autoRecordRuleMatches(rule, event()), isFalse);
    });

    test('keyword and genre are both required when both are set', () {
      const rule = AutoRecordRule(id: 'a', keyword: '劇場版', genreLevel1: 7);
      expect(
        autoRecordRuleMatches(rule, event(title: '劇場版アニメ', genre: 7)),
        isTrue,
      );
      expect(
        autoRecordRuleMatches(rule, event(title: '劇場版アニメ', genre: 3)),
        isFalse,
      );
      expect(
        autoRecordRuleMatches(rule, event(title: 'アニメ', genre: 7)),
        isFalse,
      );
    });

    test('an unconfigured rule matches nothing', () {
      const rule = AutoRecordRule(id: 'a');
      expect(
        autoRecordRuleMatches(rule, event(title: '何か', genre: 7)),
        isFalse,
      );
    });

    test('a keyword rule cannot claim an untitled event', () {
      const rule = AutoRecordRule(id: 'a', keyword: 'x');
      expect(autoRecordRuleMatches(rule, event(genre: 7)), isFalse);
    });

    test('a genre rule can claim an untitled event', () {
      const rule = AutoRecordRule(id: 'a', genreLevel1: 7);
      expect(autoRecordRuleMatches(rule, event(genre: 7)), isTrue);
    });
  });

  group('rule JSON form', () {
    test('round trip keeps the rules', () {
      const rules = [
        AutoRecordRule(id: 'a', keyword: 'アニメ', genreLevel1: 7),
        AutoRecordRule(id: 'b', keyword: 'ニュース', enabled: false),
      ];
      final decoded = decodeAutoRecordRules(encodeAutoRecordRules(rules));
      expect(decoded.length, 2);
      expect(decoded[0].keyword, 'アニメ');
      expect(decoded[0].genreLevel1, 7);
      expect(decoded[0].enabled, isTrue);
      expect(decoded[1].enabled, isFalse);
    });

    test('an unreadable store reads as no rules', () {
      expect(decodeAutoRecordRules(null), isEmpty);
      expect(decodeAutoRecordRules('not json'), isEmpty);
      expect(decodeAutoRecordRules('{"x":1}'), isEmpty);
    });

    test('a broken entry is dropped, the rest survive', () {
      final decoded = decodeAutoRecordRules(
        '[{"keyword":"id無し"},{"id":"b","keyword":"保持"}]',
      );
      expect(decoded.length, 1);
      expect(decoded.single.id, 'b');
    });
  });

  group('planAutoRecord', () {
    const animeRule = AutoRecordRule(id: 'a', keyword: 'アニメ');
    const dramaRule = AutoRecordRule(id: 'd', genreLevel1: 3);

    test('a future match with a free tuner is reserved', () {
      final plan = planAutoRecord(
        rules: const [animeRule],
        hits: [hit(at(27, 20), 30, title: 'アニメ番組')],
        existing: const [],
        now: now,
      );
      expect(plan.reservations.length, 1);
      expect(plan.skips, isEmpty);
    });

    test('a keyword found only in the description is planned', () {
      final plan = planAutoRecord(
        rules: const [AutoRecordRule(id: 's', keyword: '宇宙')],
        hits: [hit(at(27, 20), 30, title: 'ドキュメント', description: '宇宙の記録')],
        existing: const [],
        now: now,
      );
      expect(plan.reservations.length, 1);
      expect(plan.skips, isEmpty);
    });

    test('a programme that already started is not a candidate', () {
      final plan = planAutoRecord(
        rules: const [animeRule],
        hits: [hit(at(26, 11), 30, title: 'アニメ番組')],
        existing: const [],
        now: now,
      );
      expect(plan.reservations, isEmpty);
      expect(plan.skips, isEmpty);
    });

    test('a programme already on the unit is a duplicate skip', () {
      final plan = planAutoRecord(
        rules: const [animeRule],
        hits: [hit(at(27, 20), 30, title: 'アニメ番組')],
        existing: [existing(at(27, 20), 30)],
        now: now,
      );
      expect(plan.reservations, isEmpty);
      expect(plan.skips.single.reason, AutoRecordSkipReason.alreadyReserved);
    });

    test('an overlap with an existing reservation is a conflict skip', () {
      final plan = planAutoRecord(
        rules: const [animeRule],
        hits: [hit(at(27, 20), 30, title: 'アニメ番組')],
        existing: [existing(at(27, 20, 15), 30, serviceId: 200)],
        now: now,
      );
      expect(plan.reservations, isEmpty);
      expect(plan.skips.single.reason, AutoRecordSkipReason.conflict);
    });

    test('back-to-back programmes do not conflict', () {
      final plan = planAutoRecord(
        rules: const [animeRule],
        hits: [hit(at(27, 20), 30, title: 'アニメ番組')],
        existing: [existing(at(27, 19, 30), 30, serviceId: 200)],
        now: now,
      );
      expect(plan.reservations.length, 1);
    });

    test('the stronger rule wins an overlap in the same check', () {
      final plan = planAutoRecord(
        rules: const [animeRule, dramaRule],
        hits: [
          hit(at(27, 20), 60, title: 'アニメ番組'),
          hit(at(27, 20, 30), 60, title: 'ドラマ', genre: 3, on: otherChannel),
        ],
        existing: const [],
        now: now,
      );
      expect(plan.reservations.length, 1);
      expect(plan.reservations.single.ruleIndex, 0);
      expect(plan.skips.single.reason, AutoRecordSkipReason.conflict);
      expect(plan.skips.single.ruleIndex, 1);
    });

    test('a programme matched by two rules is claimed by the stronger', () {
      final plan = planAutoRecord(
        rules: const [
          animeRule,
          AutoRecordRule(id: 'b', genreLevel1: 7),
        ],
        hits: [hit(at(27, 20), 30, title: 'アニメ番組', genre: 7)],
        existing: const [],
        now: now,
      );
      expect(plan.reservations.length, 1);
      expect(plan.reservations.single.ruleIndex, 0);
    });

    test('a disabled rule plans nothing', () {
      final plan = planAutoRecord(
        rules: const [AutoRecordRule(id: 'a', keyword: 'アニメ', enabled: false)],
        hits: [hit(at(27, 20), 30, title: 'アニメ番組')],
        existing: const [],
        now: now,
      );
      expect(plan.reservations, isEmpty);
      expect(plan.skips, isEmpty);
    });

    test('two free programmes under one rule are both reserved', () {
      final plan = planAutoRecord(
        rules: const [animeRule],
        hits: [
          hit(at(27, 22), 30, title: 'アニメ番組２', eventId: 2),
          hit(at(27, 20), 30, title: 'アニメ番組１', eventId: 1),
        ],
        existing: const [],
        now: now,
      );
      expect(plan.reservations.length, 2);
      expect(plan.reservations.first.hit.event.start, at(27, 20));
    });
  });
}
