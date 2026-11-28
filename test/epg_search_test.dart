/// Programme search tests (plan 86, plan 85 item 8): the
/// pure search over the held EPG dataset, and the search
/// screen (keyword entry, genre filter, result -> detail
/// dialog, and the guide screen's entry point).
library;

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/bs_epg_providers.dart';
import 'package:tmhb/app/cs_epg_providers.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/epg_screen.dart';
import 'package:tmhb/ui/epg_search.dart';
import 'package:tmhb/ui/epg_search_screen.dart';

const _reg = RegisteredNasne(
  host: '192.0.2.1',
  udn: 'uuid:test',
  friendlyName: 'nasne',
  macAddr: '00:11:22:33:44:55',
);

Channel _channel(int serviceId, String name) => Channel(
  broadcastingType: 2,
  networkId: 1,
  transportStreamId: 1,
  serviceId: serviceId,
  serviceType: 1,
  channelNumber: serviceId,
  serviceName: name,
);

EpgEvent _event(
  int id,
  DateTime start, {
  String? title,
  String? shortText,
  String? description,
  String? cast,
  int? genre,
}) => EpgEvent(
  eventId: id,
  start: start,
  duration: const Duration(minutes: 30),
  title: title,
  shortText: shortText,
  description: description,
  cast: cast,
  genreLevel1: genre,
);

final _t0 = DateTime.utc(2026, 11, 21, 1); // 10:00 JST

EpgGuide _guide() => EpgGuide(
  broadcastingType: 2,
  services: [
    EpgServiceGuide(
      channel: _channel(1, 'テスト局'),
      events: [
        _event(1, _t0, title: '朝のニュース', genre: 0),
        _event(
          2,
          _t0.add(const Duration(hours: 1)),
          title: '連続ドラマ「海」',
          description: '海辺の町の物語',
          cast: '山田花子',
          genre: 3,
        ),
        _event(3, _t0.add(const Duration(hours: 2)), title: 'News English'),
      ],
    ),
    EpgServiceGuide(
      channel: _channel(2, '映画チャンネル'),
      events: [
        _event(
          4,
          _t0.add(const Duration(minutes: 30)),
          title: '名画座',
          shortText: '海が舞台の名作',
          genre: 6,
        ),
      ],
    ),
  ],
);

List<int> _ids(List<EpgSearchHit> hits) => [
  for (final hit in hits) hit.event.eventId,
];

/// The schedules service behind the result row menu tests:
/// records what the shared create was asked to make, and
/// answers the conflict check with [conflicts].
class _MenuFakeSchedules implements ScheduleService {
  final List<RecordSchedule> items = [];
  final List<NewRecordSchedule> created = [];
  final List<String> deleted = [];
  List<RecordSchedule> conflicts = const [];

  @override
  Future<List<RecordSchedule>> listSchedules({
    int startingIndex = 0,
    int requestedCount = 50,
  }) async => [...items];

  @override
  Future<String> createSchedule(NewRecordSchedule schedule) async {
    created.add(schedule);
    return '900';
  }

  @override
  Future<void> updateSchedule(ScheduleUpdate update) async {}

  @override
  Future<void> deleteSchedule(String id) async {
    deleted.add(id);
  }

  @override
  Future<List<RecordSchedule>> checkConflicts(
    NewRecordSchedule candidate,
  ) async => conflicts;
}

/// A service the row menu never calls; any call is a test
/// bug, so it throws.
class _MenuUnused {
  static Never call(Invocation invocation) =>
      throw UnimplementedError('unused fake: $invocation');
}

class _MenuStubDeviceInfo implements DeviceInfoService {
  @override
  dynamic noSuchMethod(Invocation invocation) => _MenuUnused.call(invocation);
}

class _MenuStubSettings implements SettingsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => _MenuUnused.call(invocation);
}

class _MenuStubTitles implements TitleCatalogService {
  @override
  dynamic noSuchMethod(Invocation invocation) => _MenuUnused.call(invocation);
}

class _MenuStubMetadata implements MetadataService {
  @override
  dynamic noSuchMethod(Invocation invocation) => _MenuUnused.call(invocation);
}

class _MenuStubLive implements LiveCatalogService {
  @override
  dynamic noSuchMethod(Invocation invocation) => _MenuUnused.call(invocation);
}

/// A reservation as the unit lists it, for seeding the
/// already-reserved and conflict answers.
RecordSchedule _listedReservation({
  required DateTime start,
  int eventId = 1,
}) => RecordSchedule(
  id: '100',
  start: start,
  durationSeconds: 30 * 60,
  conditionId: '1',
  channel: const ScheduleChannel(
    broadcastingType: 2,
    channelType: 2,
    serviceId: 1,
  ),
  desiredQualityMode: 100,
  desiredMatchingId:
      ',,0x0001,0x${eventId.toRadixString(16).padLeft(4, '0')}',
  reservationCreatorId: '2000',
  priorityFlag: 0,
  recordDestinationId: 'HDD',
);

void main() {
  group('searchEpgProgrammes', () {
    test('matches the title', () {
      expect(_ids(searchEpgProgrammes(guides: [_guide()], query: 'ニュース')), [1]);
    });

    test('matches description, cast and short text', () {
      expect(_ids(searchEpgProgrammes(guides: [_guide()], query: '物語')), [2]);
      expect(_ids(searchEpgProgrammes(guides: [_guide()], query: '山田')), [2]);
      expect(_ids(searchEpgProgrammes(guides: [_guide()], query: '名作')), [4]);
    });

    test('matches the channel name', () {
      expect(_ids(searchEpgProgrammes(guides: [_guide()], query: '映画チャンネル')), [
        4,
      ]);
    });

    test('is case-insensitive', () {
      expect(_ids(searchEpgProgrammes(guides: [_guide()], query: 'news')), [3]);
      expect(_ids(searchEpgProgrammes(guides: [_guide()], query: 'NEWS')), [3]);
    });

    test('returns hits in start order across channels', () {
      expect(_ids(searchEpgProgrammes(guides: [_guide()], query: '海')), [4, 2]);
    });

    test('genre filter alone, and combined with a keyword', () {
      expect(_ids(searchEpgProgrammes(guides: [_guide()], genreLevel1: 0)), [
        1,
      ]);
      expect(
        _ids(
          searchEpgProgrammes(guides: [_guide()], query: '海', genreLevel1: 3),
        ),
        [2],
      );
      expect(
        _ids(
          searchEpgProgrammes(guides: [_guide()], query: '海', genreLevel1: 6),
        ),
        [4],
      );
    });

    test('empty query without a genre returns everything in order', () {
      expect(_ids(searchEpgProgrammes(guides: [_guide()])), [1, 4, 2, 3]);
    });

    test('no match returns an empty list', () {
      expect(searchEpgProgrammes(guides: [_guide()], query: '存在しない'), isEmpty);
    });
  });

  group('EpgSearchIndex (plan 98)', () {
    test('agrees with the direct search on every case', () {
      final guides = [_guide()];
      final index = EpgSearchIndex.fromGuides(guides);
      for (final (query, genre) in <(String, int?)>[
        ('ニュース', null),
        ('物語', null),
        ('山田', null),
        ('名作', null),
        ('映画チャンネル', null),
        ('news', null),
        ('NEWS', null),
        ('海', null),
        ('海', 3),
        ('海', 6),
        ('', 0),
        ('', null),
        ('存在しない', null),
      ]) {
        expect(
          _ids(index.search(query: query, genreLevel1: genre)),
          _ids(
            searchEpgProgrammes(
              guides: guides,
              query: query,
              genreLevel1: genre,
            ),
          ),
          reason: 'query=$query genre=$genre',
        );
      }
    });

    test('collects the genre values and the event count once', () {
      final index = EpgSearchIndex.fromGuides([_guide()]);
      expect(index.genreValues, [0, 3, 6]);
      expect(index.eventCount, 4);
    });
  });

  group('epgSearchGenreValues / epgSearchGenreLabel', () {
    test('values are the genres present, ascending and unique', () {
      expect(epgSearchGenreValues([_guide()]), [0, 3, 6]);
    });

    test('labels name the ARIB level-1 genres', () {
      expect(epgSearchGenreLabel(0), 'ニュース・報道');
      expect(epgSearchGenreLabel(3), 'ドラマ');
      expect(epgSearchGenreLabel(15), 'その他');
      expect(epgSearchGenreLabel(99), 'ジャンル 99');
    });
  });

  group('EpgSearchScreen', () {
    EpgGuide futureGuide() {
      final start = DateTime.now().toUtc().add(const Duration(days: 1));
      return EpgGuide(
        broadcastingType: 2,
        services: [
          EpgServiceGuide(
            channel: _channel(1, 'テスト局'),
            events: [
              _event(1, start, title: '明日のドラマ', genre: 3),
              _event(
                2,
                start.add(const Duration(hours: 1)),
                title: '明日の映画',
                genre: 6,
              ),
            ],
          ),
        ],
      );
    }

    Widget host(Widget child, {EpgGuide? guide, EpgGuide? csGuide}) {
      return ProviderScope(
        overrides: [
          epgGuideProvider.overrideWith((ref, r) async => guide ?? _guide()),
          bsEpgGuideProvider.overrideWith(
            (ref, r) async => const EpgGuide(broadcastingType: 3, services: []),
          ),
          csEpgGuideProvider.overrideWith(
            (ref, r) async =>
                csGuide ??
                const EpgGuide(broadcastingType: 4, services: []),
          ),
        ],
        child: MaterialApp(home: child),
      );
    }

    testWidgets('shows the hint before any input', (tester) async {
      await tester.pumpWidget(host(const EpgSearchScreen(reg: _reg)));
      await tester.pump();
      expect(find.textContaining('キーワードを入力するか'), findsOneWidget);
    });

    testWidgets('search also covers the CS guide', (tester) async {
      final start = DateTime.now().add(const Duration(days: 1));
      final csGuide = EpgGuide(
        broadcastingType: 4,
        services: [
          EpgServiceGuide(
            channel: const Channel(
              broadcastingType: 4,
              networkId: 7,
              transportStreamId: 28960,
              serviceId: 240,
              serviceType: 1,
              channelNumber: 240,
              serviceName: 'ムービープラス',
            ),
            events: [_event(9, start, title: 'CSの名画', genre: 6)],
          ),
        ],
      );
      await tester.pumpWidget(
        host(const EpgSearchScreen(reg: _reg), csGuide: csGuide),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'CSの名画');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      // The result row (the search field itself also holds
      // the query text, so match the row, not any text).
      expect(find.widgetWithText(ListTile, 'CSの名画'), findsOneWidget);
    });

    testWidgets('keyword search lists hits and opens the detail dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const EpgSearchScreen(reg: _reg), guide: futureGuide()),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'ドラマ');
      // The query applies after the debounce settles (plan 98).
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('明日のドラマ'), findsOneWidget);
      expect(find.text('明日の映画'), findsNothing);
      await tester.tap(find.text('明日のドラマ'));
      await tester.pumpAndSettle();
      // The shared detail dialog, with the reservation action
      // for an event that has not ended.
      expect(find.text('録画予約'), findsOneWidget);
    });

    testWidgets('typing is debounced before it searches (plan 98)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const EpgSearchScreen(reg: _reg), guide: futureGuide()),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'ドラマ');
      await tester.pump();
      // The keystroke alone has not applied a search yet.
      expect(find.text('明日のドラマ'), findsNothing);
      expect(find.textContaining('キーワードを入力するか'), findsOneWidget);
      // Once typing settles, the search runs.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('明日のドラマ'), findsOneWidget);
    });

    testWidgets('genre dropdown filters the results', (tester) async {
      await tester.pumpWidget(
        host(const EpgSearchScreen(reg: _reg), guide: futureGuide()),
      );
      await tester.pump();
      await tester.tap(find.byType(DropdownButton<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('映画').last);
      await tester.pumpAndSettle();
      expect(find.text('明日の映画'), findsOneWidget);
      expect(find.text('明日のドラマ'), findsNothing);
    });

    testWidgets('the guide screen has a search entry point', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const [_reg]),
            ),
            epgGuideProvider.overrideWith((ref, r) async => futureGuide()),
            bsEpgGuideProvider.overrideWith(
              (ref, r) async =>
                  const EpgGuide(broadcastingType: 3, services: []),
            ),
            csEpgGuideProvider.overrideWith(
              (ref, r) async =>
                  const EpgGuide(broadcastingType: 4, services: []),
            ),
            channelLogosProvider.overrideWith(
              (ref, r) async => const <int, List<int>>{},
            ),
          ],
          child: const MaterialApp(home: EpgScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      expect(find.byType(EpgSearchScreen), findsOneWidget);
    });
  });

  group('EpgSearchScreen result row menu (owner request 2026-11-26)', () {
    EpgGuide menuGuide(DateTime start) => EpgGuide(
      broadcastingType: 2,
      services: [
        EpgServiceGuide(
          channel: _channel(1, 'テスト局'),
          events: [
            _event(1, start, title: '明日のドラマ', genre: 3),
            _event(
              2,
              start.add(const Duration(hours: 1)),
              title: '明日の映画',
              genre: 6,
            ),
          ],
        ),
      ],
    );

    Widget menuHost(_MenuFakeSchedules schedules, {EpgGuide? guide}) {
      final bundle = DeviceServices(
        deviceInfo: _MenuStubDeviceInfo(),
        settings: _MenuStubSettings(),
        schedules: schedules,
        titles: _MenuStubTitles(),
        metadata: _MenuStubMetadata(),
        live: _MenuStubLive(),
        playback: const UnsupportedPlaybackEngine(),
      );
      return ProviderScope(
        overrides: [
          epgGuideProvider.overrideWith(
            (ref, r) async =>
                guide ?? menuGuide(DateTime.now().add(const Duration(days: 1))),
          ),
          bsEpgGuideProvider.overrideWith(
            (ref, r) async => const EpgGuide(broadcastingType: 3, services: []),
          ),
          csEpgGuideProvider.overrideWith(
            (ref, r) async => const EpgGuide(broadcastingType: 4, services: []),
          ),
          deviceServicesProvider.overrideWith((ref, reg) => bundle),
        ],
        child: const MaterialApp(home: EpgSearchScreen(reg: _reg)),
      );
    }

    Future<void> searchFor(WidgetTester tester, String keyword) async {
      await tester.enterText(find.byType(TextField), keyword);
      // The query applies after the debounce settles (plan 98).
      await tester.pump(const Duration(milliseconds: 250));
    }

    testWidgets('a long press on a result opens its menu, and 録画 '
        'reserves the programme through the shared create', (tester) async {
      final schedules = _MenuFakeSchedules();
      await tester.pumpWidget(menuHost(schedules));
      await tester.pump();
      await searchFor(tester, 'ドラマ');
      expect(find.text('明日のドラマ'), findsOneWidget);

      await tester.longPress(find.widgetWithText(ListTile, '明日のドラマ'));
      await tester.pumpAndSettle();

      // The menu alone: the hold neither opened the detail
      // dialog (its tap is swallowed) nor reserved yet.
      expect(find.text('録画'), findsOneWidget);
      expect(find.text('録画予約'), findsNothing);
      expect(schedules.created, isEmpty);

      await tester.tap(find.text('録画'));
      await tester.pumpAndSettle();

      // The candidate the guide's own creation path builds:
      // the event's start, length and id, on its channel.
      expect(schedules.created, hasLength(1));
      final created = schedules.created.single;
      expect(created.eventId, 1);
      expect(created.channel.serviceId, 1);
      expect(created.durationSeconds, 30 * 60);
      expect(find.text('予約を作成しました'), findsOneWidget);
    });

    testWidgets('a right click on a result opens its menu', (tester) async {
      final schedules = _MenuFakeSchedules();
      await tester.pumpWidget(menuHost(schedules));
      await tester.pump();
      await searchFor(tester, 'ドラマ');

      final row = find.widgetWithText(ListTile, '明日のドラマ');
      final gesture = await tester.startGesture(
        tester.getCenter(row),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('録画'), findsOneWidget);
      // A right click is not a tap: no detail dialog.
      expect(find.text('録画予約'), findsNothing);

      await tester.tap(find.text('録画'));
      await tester.pumpAndSettle();
      expect(schedules.created, hasLength(1));
      expect(find.text('予約を作成しました'), findsOneWidget);
    });

    testWidgets('a programme already reserved offers 録画解除, not '
        '録画, and deleting runs the one confirmation', (tester) async {
      final start = DateTime.now().add(const Duration(days: 1));
      final schedules = _MenuFakeSchedules()
        ..items.add(_listedReservation(start: start));
      await tester.pumpWidget(menuHost(schedules, guide: menuGuide(start)));
      await tester.pump();
      await searchFor(tester, 'ドラマ');

      await tester.longPress(find.widgetWithText(ListTile, '明日のドラマ'));
      await tester.pumpAndSettle();

      // The guide tile menu's stance (owner request
      // 2026-11-28): a reserved programme is un-reserved
      // from here, never reserved twice.
      expect(find.text('録画解除'), findsOneWidget);
      expect(find.text('録画'), findsNothing);

      await tester.tap(find.text('録画解除'));
      await tester.pumpAndSettle();

      // The detail dialog's own confirmation stands between
      // the menu and the device: nothing is deleted yet.
      expect(find.text('予約を削除'), findsOneWidget);
      expect(schedules.deleted, isEmpty);

      await tester.tap(find.text('削除'));
      await tester.pumpAndSettle();

      expect(schedules.created, isEmpty);
      expect(schedules.deleted, ['100']);
      expect(find.text('予約を削除しました'), findsOneWidget);
    });

    testWidgets('a conflicting programme is reported and not created', (
      tester,
    ) async {
      final start = DateTime.now().add(const Duration(days: 1));
      final schedules = _MenuFakeSchedules()
        ..conflicts = [_listedReservation(start: start, eventId: 7)];
      await tester.pumpWidget(menuHost(schedules, guide: menuGuide(start)));
      await tester.pump();
      await searchFor(tester, 'ドラマ');

      await tester.longPress(find.widgetWithText(ListTile, '明日のドラマ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('録画'));
      await tester.pumpAndSettle();

      expect(schedules.created, isEmpty);
      expect(find.text('競合する予約があるため予約できませんでした'), findsOneWidget);
    });

    testWidgets('a programme that has ended offers no menu; the hold '
        'goes on to the detail, which offers it no reservation', (
      tester,
    ) async {
      final schedules = _MenuFakeSchedules();
      final ended = menuGuide(
        DateTime.now().subtract(const Duration(hours: 2)),
      );
      await tester.pumpWidget(menuHost(schedules, guide: ended));
      await tester.pump();
      await searchFor(tester, 'ドラマ');
      expect(find.text('明日のドラマ'), findsOneWidget);

      await tester.longPress(find.widgetWithText(ListTile, '明日のドラマ'));
      await tester.pumpAndSettle();

      // No menu item anywhere, and nothing reserved; the
      // hold's tap tail opened the detail dialog, whose
      // only action for an ended programme is closing.
      expect(find.text('録画'), findsNothing);
      expect(find.text('録画予約'), findsNothing);
      expect(find.text('閉じる'), findsOneWidget);
      expect(schedules.created, isEmpty);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
    });
  });
}
