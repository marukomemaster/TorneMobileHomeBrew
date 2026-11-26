/// Auto record policy tests (user-fork addition):
/// rule matching, the stored form, and planning —
/// priority order, duplicates against the unit's
/// reservations, and single-tuner conflicts.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/auto_record_policy.dart';
import 'package:tmhb/ui/epg_search.dart';
import 'package:tmhb/ui/format.dart';

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

  group('channel pin', () {
    const pin = AutoRecordChannel(
      networkId: 1,
      transportStreamId: 1,
      serviceId: 100,
      name: 'テスト放送',
    );
    const rule = AutoRecordRule(id: 'a', keyword: 'アニメ', channel: pin);

    test('a pinned rule matches only on its channel', () {
      expect(
        autoRecordRuleMatches(rule, event(title: 'アニメ番組'), channel: channel),
        isTrue,
      );
      expect(
        autoRecordRuleMatches(
          rule,
          event(title: 'アニメ番組'),
          channel: otherChannel,
        ),
        isFalse,
      );
    });

    test('a pinned rule never matches without a channel', () {
      expect(autoRecordRuleMatches(rule, event(title: 'アニメ番組')), isFalse);
    });

    test('the channel is an AND with the keyword and genre', () {
      const both = AutoRecordRule(
        id: 'a',
        keyword: 'アニメ',
        genreLevel1: 7,
        channel: pin,
      );
      expect(
        autoRecordRuleMatches(
          both,
          event(title: 'アニメ番組', genre: 3),
          channel: channel,
        ),
        isFalse,
      );
      expect(
        autoRecordRuleMatches(
          both,
          event(title: 'ドラマ', genre: 7),
          channel: channel,
        ),
        isFalse,
      );
      expect(
        autoRecordRuleMatches(
          both,
          event(title: 'アニメ番組', genre: 7),
          channel: channel,
        ),
        isTrue,
      );
    });

    test('a channel alone does not configure a rule', () {
      const channelOnly = AutoRecordRule(id: 'a', channel: pin);
      expect(channelOnly.isConfigured, isFalse);
      expect(
        autoRecordRuleMatches(
          channelOnly,
          event(title: 'アニメ番組'),
          channel: channel,
        ),
        isFalse,
      );
    });

    test('planning respects the pin', () {
      final plan = planAutoRecord(
        rules: const [rule],
        hits: [
          hit(at(27, 20), 30, title: 'アニメ番組', on: otherChannel, eventId: 1),
          hit(at(27, 22), 30, title: 'アニメ番組', eventId: 2),
        ],
        existing: const [],
        now: now,
      );
      expect(plan.reservations.length, 1);
      expect(plan.reservations.single.hit.channel.serviceId, 100);
    });

    test('the JSON form round-trips the channel', () {
      const rules = [rule];
      final decoded = decodeAutoRecordRules(encodeAutoRecordRules(rules));
      expect(decoded.single.channel, pin);
      expect(decoded.single.channel!.name, 'テスト放送');
    });

    test('a rule stored before channels reads as unpinned', () {
      final decoded = decodeAutoRecordRules('[{"id":"a","keyword":"アニメ"}]');
      expect(decoded.single.channel, isNull);
    });
  });

  group('exclusion keywords', () {
    test('an exclusion word in the title vetoes a keyword match', () {
      const rule = AutoRecordRule(
        id: 'a',
        keyword: 'アニメ',
        excludeKeywords: ['再放送'],
      );
      expect(
        autoRecordRuleMatches(rule, event(title: 'アニメ番組（再放送）')),
        isFalse,
      );
      expect(autoRecordRuleMatches(rule, event(title: 'アニメ番組')), isTrue);
    });

    test('an exclusion word in the description vetoes too', () {
      const rule = AutoRecordRule(
        id: 'a',
        keyword: 'アニメ',
        excludeKeywords: ['総集編'],
      );
      expect(
        autoRecordRuleMatches(
          rule,
          event(title: 'アニメ番組', description: '今週は総集編'),
        ),
        isFalse,
      );
    });

    test('a genre-only rule is vetoed by an exclusion word', () {
      const rule = AutoRecordRule(
        id: 'a',
        genreLevel1: 7,
        excludeKeywords: ['劇場版'],
      );
      expect(
        autoRecordRuleMatches(rule, event(title: '劇場版アニメ', genre: 7)),
        isFalse,
      );
      expect(
        autoRecordRuleMatches(rule, event(title: 'アニメ', genre: 7)),
        isTrue,
      );
    });

    test('any one of several exclusion words vetoes', () {
      const rule = AutoRecordRule(
        id: 'a',
        keyword: 'アニメ',
        excludeKeywords: ['再放送', '総集編', '特番'],
      );
      expect(
        autoRecordRuleMatches(rule, event(title: 'アニメ総集編')),
        isFalse,
      );
      expect(
        autoRecordRuleMatches(rule, event(title: 'アニメ特番')),
        isFalse,
      );
      expect(autoRecordRuleMatches(rule, event(title: 'アニメ')), isTrue);
    });

    test('exclusion matching is case-insensitive and ignores blanks', () {
      const rule = AutoRecordRule(
        id: 'a',
        keyword: 'news',
        excludeKeywords: [' ', 'SPORTS'],
      );
      expect(
        autoRecordRuleMatches(rule, event(title: 'News sports special')),
        isFalse,
      );
      expect(autoRecordRuleMatches(rule, event(title: 'News ABC')), isTrue);
    });

    test('the JSON form round-trips the exclusions', () {
      const rules = [
        AutoRecordRule(id: 'a', keyword: 'アニメ', excludeKeywords: ['再放送', '総集編']),
      ];
      final decoded = decodeAutoRecordRules(encodeAutoRecordRules(rules));
      expect(decoded.single.excludeKeywords, ['再放送', '総集編']);
    });

    test('a rule stored before exclusions reads as none', () {
      final decoded = decodeAutoRecordRules('[{"id":"a","keyword":"アニメ"}]');
      expect(decoded.single.excludeKeywords, isEmpty);
    });

    test('planning drops a vetoed programme', () {
      final plan = planAutoRecord(
        rules: const [
          AutoRecordRule(id: 'a', keyword: 'アニメ', excludeKeywords: ['再放送']),
        ],
        hits: [
          hit(at(27, 20), 30, title: 'アニメ番組（再放送）', eventId: 1),
          hit(at(27, 22), 30, title: 'アニメ番組', eventId: 2),
        ],
        existing: const [],
        now: now,
      );
      expect(plan.reservations.length, 1);
      expect(plan.reservations.single.hit.event.start, at(27, 22));
    });
  });

  group('time-of-day range', () {
    // Starts are built as JST wall times so the tests
    // read the same in any host timezone.
    DateTime jst(int day, int hour, [int minute = 0]) =>
        instantFromJstWall(DateTime(2026, 11, day, hour, minute));

    EpgEvent atJst(int day, int hour, [int minute = 0]) => EpgEvent(
      eventId: 1,
      start: jst(day, hour, minute),
      duration: const Duration(minutes: 30),
      title: 'アニメ番組',
    );

    const morning = AutoRecordRule(
      id: 'a',
      keyword: 'アニメ',
      startMinuteOfDay: 9 * 60,
      endMinuteOfDay: 12 * 60,
    );

    test('a start inside the range matches, outside does not', () {
      expect(autoRecordRuleMatches(morning, atJst(27, 10)), isTrue);
      expect(autoRecordRuleMatches(morning, atJst(27, 13)), isFalse);
      expect(autoRecordRuleMatches(morning, atJst(27, 8)), isFalse);
    });

    test('the start bound is in, the end bound is out', () {
      expect(autoRecordRuleMatches(morning, atJst(27, 9)), isTrue);
      expect(autoRecordRuleMatches(morning, atJst(27, 11, 59)), isTrue);
      expect(autoRecordRuleMatches(morning, atJst(27, 12)), isFalse);
      expect(autoRecordRuleMatches(morning, atJst(27, 8, 59)), isFalse);
    });

    const lateNight = AutoRecordRule(
      id: 'a',
      keyword: 'アニメ',
      startMinuteOfDay: 23 * 60,
      endMinuteOfDay: 2 * 60,
    );

    test('a range past midnight wraps', () {
      expect(autoRecordRuleMatches(lateNight, atJst(27, 23)), isTrue);
      expect(autoRecordRuleMatches(lateNight, atJst(27, 23, 59)), isTrue);
      expect(autoRecordRuleMatches(lateNight, atJst(28, 0)), isTrue);
      expect(autoRecordRuleMatches(lateNight, atJst(28, 1, 59)), isTrue);
      expect(autoRecordRuleMatches(lateNight, atJst(28, 2)), isFalse);
      expect(autoRecordRuleMatches(lateNight, atJst(27, 22, 59)), isFalse);
      expect(autoRecordRuleMatches(lateNight, atJst(27, 12)), isFalse);
    });

    test('equal bounds are an empty range', () {
      expect(autoRecordStartInTimeRange(jst(27, 10), 600, 600), isFalse);
      const empty = AutoRecordRule(
        id: 'a',
        keyword: 'アニメ',
        startMinuteOfDay: 600,
        endMinuteOfDay: 600,
      );
      expect(autoRecordRuleMatches(empty, atJst(27, 10)), isFalse);
    });

    test('the range is an AND with the other conditions', () {
      expect(autoRecordRuleMatches(morning, atJst(27, 10)), isTrue);
      const drama = AutoRecordRule(
        id: 'a',
        keyword: 'ドラマ',
        startMinuteOfDay: 9 * 60,
        endMinuteOfDay: 12 * 60,
      );
      expect(autoRecordRuleMatches(drama, atJst(27, 10)), isFalse);
    });

    test('the JSON form round-trips the range', () {
      const rules = [lateNight];
      final decoded = decodeAutoRecordRules(encodeAutoRecordRules(rules));
      expect(decoded.single.startMinuteOfDay, 23 * 60);
      expect(decoded.single.endMinuteOfDay, 2 * 60);
      expect(decoded.single.hasTimeRange, isTrue);
    });

    test('a rule stored before ranges reads as the whole day', () {
      final decoded = decodeAutoRecordRules('[{"id":"a","keyword":"アニメ"}]');
      expect(decoded.single.hasTimeRange, isFalse);
      expect(autoRecordRuleMatches(decoded.single, atJst(27, 3)), isTrue);
    });

    test('a half-stored range reads as no range', () {
      final decoded = decodeAutoRecordRules(
        '[{"id":"a","keyword":"アニメ","startMinute":540}]',
      );
      expect(decoded.single.hasTimeRange, isFalse);
    });
  });

  group('one-shot rules', () {
    const onceRule = AutoRecordRule(id: 'a', keyword: 'アニメ', onceOnly: true);

    test('only the earliest match of a check is planned', () {
      final plan = planAutoRecord(
        rules: const [onceRule],
        hits: [
          hit(at(27, 22), 30, title: 'アニメ番組２', eventId: 2),
          hit(at(27, 20), 30, title: 'アニメ番組１', eventId: 1),
          hit(at(28, 20), 30, title: 'アニメ番組３', eventId: 3),
        ],
        existing: const [],
        now: now,
      );
      expect(plan.reservations.length, 1);
      expect(plan.reservations.single.hit.event.start, at(27, 20));
      // The later programmes are left alone, not
      // recorded as skips.
      expect(plan.skips, isEmpty);
    });

    test('a conflicting first match leaves the next one to be planned', () {
      final plan = planAutoRecord(
        rules: const [onceRule],
        hits: [
          hit(at(27, 20), 30, title: 'アニメ番組１', eventId: 1),
          hit(at(27, 22), 30, title: 'アニメ番組２', eventId: 2),
        ],
        existing: [existing(at(27, 20, 15), 30, serviceId: 200)],
        now: now,
      );
      expect(plan.skips.single.reason, AutoRecordSkipReason.conflict);
      expect(plan.reservations.length, 1);
      expect(plan.reservations.single.hit.event.start, at(27, 22));
    });

    test('a duplicate first match leaves the next one to be planned', () {
      final plan = planAutoRecord(
        rules: const [onceRule],
        hits: [
          hit(at(27, 20), 30, title: 'アニメ番組１', eventId: 1),
          hit(at(27, 22), 30, title: 'アニメ番組２', eventId: 2),
        ],
        existing: [existing(at(27, 20), 30)],
        now: now,
      );
      expect(plan.skips.single.reason, AutoRecordSkipReason.alreadyReserved);
      expect(plan.reservations.length, 1);
      expect(plan.reservations.single.hit.event.start, at(27, 22));
    });

    test('an overflow programme does not block a weaker rule', () {
      final plan = planAutoRecord(
        rules: const [
          onceRule,
          AutoRecordRule(id: 'b', keyword: 'ドラマ'),
        ],
        hits: [
          hit(at(27, 20), 30, title: 'アニメ番組１', eventId: 1),
          hit(at(27, 22), 60, title: 'アニメ番組２', eventId: 2),
          hit(
            at(27, 22, 15),
            30,
            title: 'ドラマ',
            on: otherChannel,
            eventId: 3,
          ),
        ],
        existing: const [],
        now: now,
      );
      // The one-shot rule reserves only the 20:00
      // programme. Its 22:00 overflow is not reserved,
      // so it never occupies the tuner: the weaker
      // rule's overlapping 22:15 programme is still
      // reserved.
      expect(plan.reservations.length, 2);
      expect(plan.reservations[0].ruleIndex, 0);
      expect(plan.reservations[1].ruleIndex, 1);
      expect(plan.skips, isEmpty);
    });

    test('the JSON form round-trips one-shot mode', () {
      const rules = [onceRule];
      final decoded = decodeAutoRecordRules(encodeAutoRecordRules(rules));
      expect(decoded.single.onceOnly, isTrue);
    });

    test('a rule stored before one-shot mode reads as standing', () {
      final decoded = decodeAutoRecordRules('[{"id":"a","keyword":"アニメ"}]');
      expect(decoded.single.onceOnly, isFalse);
    });

    test('the JSON form round-trips the quality mode', () {
      const rules = [AutoRecordRule(id: 'a', keyword: 'アニメ', qualityMode: 230)];
      final decoded = decodeAutoRecordRules(encodeAutoRecordRules(rules));
      expect(decoded.single.qualityMode, 230);
    });

    test('a rule stored before the quality choice reads as '
        'no specification', () {
      final decoded = decodeAutoRecordRules('[{"id":"a","keyword":"アニメ"}]');
      expect(decoded.single.qualityMode, isNull);
    });
  });

  group('two-unit coordination', () {
    String keyOf(EpgSearchHit h) => autoRecordProgrammeKey(
      broadcastingType: h.channel.broadcastingType,
      serviceId: h.channel.serviceId,
      start: h.event.start,
    );

    test('a programme reserved on the other unit is a duplicate here', () {
      final target = hit(at(27, 20), 30, title: 'アニメ番組');
      final plan = planAutoRecord(
        rules: const [AutoRecordRule(id: 'a', keyword: 'アニメ')],
        hits: [target],
        existing: const [],
        now: now,
        externalReservedKeys: {keyOf(target)},
      );
      expect(plan.reservations, isEmpty);
      expect(plan.skips.single.reason, AutoRecordSkipReason.alreadyReserved);
    });

    test('an external duplicate does not occupy this tuner', () {
      final taken = hit(at(27, 20), 60, title: 'アニメ番組１', eventId: 1);
      final other = hit(
        at(27, 20, 30),
        60,
        title: 'アニメ番組２',
        on: otherChannel,
        eventId: 2,
      );
      final plan = planAutoRecord(
        rules: const [AutoRecordRule(id: 'a', keyword: 'アニメ')],
        hits: [taken, other],
        existing: const [],
        now: now,
        externalReservedKeys: {keyOf(taken)},
      );
      // The overlapping second programme is still
      // reserved on this unit: the first unit's
      // reservation is not this unit's conflict.
      expect(plan.reservations.length, 1);
      expect(plan.reservations.single.hit.event.start, at(27, 20, 30));
      expect(plan.skips.single.reason, AutoRecordSkipReason.alreadyReserved);
    });

    test('an empty external set is the single-unit plan, unchanged', () {
      final plan = planAutoRecord(
        rules: const [AutoRecordRule(id: 'a', keyword: 'アニメ')],
        hits: [hit(at(27, 20), 30, title: 'アニメ番組')],
        existing: const [],
        now: now,
        externalReservedKeys: const {},
      );
      expect(plan.reservations.length, 1);
      expect(plan.skips, isEmpty);
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
