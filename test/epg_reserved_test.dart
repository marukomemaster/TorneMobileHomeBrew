/// Reserved marking for the programme guide (plan 120):
/// the desiredMatchingID event-id parse, the reservation
/// index's matching rules, and the guide grid framing a
/// reserved event's tile in red while an unreserved tile
/// stays unframed.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/variant.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/epg_reserved.dart';
import 'package:tmhb/ui/epg_screen.dart';

RecordSchedule _schedule({
  String id = '1',
  required DateTime start,
  int broadcastingType = 2,
  int serviceId = 0x3333,
  String desiredMatchingId = '',
}) => RecordSchedule(
  id: id,
  start: start,
  durationSeconds: 1800,
  conditionId: '1',
  channel: ScheduleChannel(
    broadcastingType: broadcastingType,
    channelType: 2,
    serviceId: serviceId,
  ),
  desiredQualityMode: 100,
  desiredMatchingId: desiredMatchingId,
  reservationCreatorId: '2000',
  priorityFlag: 0,
  recordDestinationId: 'HDD',
);

const _channel = Channel(
  broadcastingType: 2,
  networkId: 0x1111,
  transportStreamId: 0x2222,
  serviceId: 0x3333,
  serviceType: 1,
  channelNumber: 1,
  serviceName: 'テスト局',
);

/// A schedule service backed by a mutable list, for the
/// guide's delete flow: listSchedules replays the list the
/// way the device would after a delete, deleteSchedule
/// records and removes. The remaining operations are not
/// exercised here.
class _FakeSchedules implements ScheduleService {
  _FakeSchedules(this.items);

  final List<RecordSchedule> items;
  final List<String> deletedIds = [];

  @override
  Future<List<RecordSchedule>> listSchedules({
    int startingIndex = 0,
    int requestedCount = 50,
  }) async => [...items];

  @override
  Future<void> deleteSchedule(String id) async {
    deletedIds.add(id);
    items.removeWhere((s) => s.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by this test');
}

/// The rest of the device bundle is never touched by the
/// guide screen in these tests.
class _Unused {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by this test');
}

class _UnusedDeviceInfo extends _Unused implements DeviceInfoService {}

class _UnusedSettings extends _Unused implements SettingsService {}

class _UnusedTitles extends _Unused implements TitleCatalogService {}

class _UnusedMetadata extends _Unused implements MetadataService {}

class _UnusedLive extends _Unused implements LiveCatalogService {}

void main() {
  group('desiredMatchingEventId', () {
    test('reads the event id of the server-normalised list form', () {
      expect(desiredMatchingEventId('0x7880,0x7880,0xDE00,0x1234'), 0x1234);
      expect(desiredMatchingEventId('0x1111,0x2222,0x3333,0x0007'), 7);
    });

    test('reads the event id of the create form', () {
      expect(desiredMatchingEventId(',,0x1111,0x00AB'), 0xAB);
    });

    test('a manual reservation carries event id 0', () {
      expect(desiredMatchingEventId('0x7880,0x7880,0xDE00,0x0000'), 0);
    });

    test('unparseable values give null', () {
      expect(desiredMatchingEventId(''), isNull);
      expect(desiredMatchingEventId('0x7880,0x7880,0xDE00'), isNull);
      expect(desiredMatchingEventId('0x7880,0x7880,0xDE00,'), isNull);
      expect(desiredMatchingEventId('0x7880,0x7880,0xDE00,0xZZZZ'), isNull);
    });
  });

  group('EpgReservedIndex', () {
    final start = DateTime.utc(2026, 11, 23, 12, 0);
    final event = EpgEvent(
      eventId: 7,
      start: start,
      duration: const Duration(minutes: 30),
      title: '番組',
    );

    test('an event reservation matches by event id, whatever its start', () {
      final index = EpgReservedIndex.fromSchedules([
        _schedule(
          start: start.add(const Duration(minutes: 3)),
          desiredMatchingId: '0x1111,0x2222,0x3333,0x0007',
        ),
      ]);
      expect(index.isReserved(_channel, event), isTrue);
    });

    test('a manual reservation matches by start instant', () {
      final index = EpgReservedIndex.fromSchedules([
        _schedule(
          start: start,
          desiredMatchingId: '0x1111,0x2222,0x3333,0x0000',
        ),
      ]);
      expect(index.isReserved(_channel, event), isTrue);
    });

    test('a manual reservation starting a minute off does not match', () {
      final index = EpgReservedIndex.fromSchedules([
        _schedule(
          start: start.add(const Duration(minutes: 1)),
          desiredMatchingId: '0x1111,0x2222,0x3333,0x0000',
        ),
      ]);
      expect(index.isReserved(_channel, event), isFalse);
    });

    test('another service or band does not match', () {
      final byService = EpgReservedIndex.fromSchedules([
        _schedule(
          start: start,
          serviceId: 0x4444,
          desiredMatchingId: '0x1111,0x2222,0x4444,0x0007',
        ),
      ]);
      expect(byService.isReserved(_channel, event), isFalse);
      final byBand = EpgReservedIndex.fromSchedules([
        _schedule(
          start: start,
          broadcastingType: 3,
          desiredMatchingId: '0x1111,0x2222,0x3333,0x0007',
        ),
      ]);
      expect(byBand.isReserved(_channel, event), isFalse);
    });

    test('scheduleFor returns the event reservation that matched', () {
      final reservation = _schedule(
        id: '42',
        start: start.add(const Duration(minutes: 3)),
        desiredMatchingId: '0x1111,0x2222,0x3333,0x0007',
      );
      final index = EpgReservedIndex.fromSchedules([reservation]);
      expect(index.scheduleFor(_channel, event), same(reservation));
    });

    test('scheduleFor returns a manual reservation matched by start', () {
      final reservation = _schedule(
        id: '43',
        start: start,
        desiredMatchingId: '0x1111,0x2222,0x3333,0x0000',
      );
      final index = EpgReservedIndex.fromSchedules([reservation]);
      expect(index.scheduleFor(_channel, event), same(reservation));
    });

    test('scheduleFor prefers the event match over a start match', () {
      final byEvent = _schedule(
        id: '44',
        start: start.add(const Duration(minutes: 3)),
        desiredMatchingId: '0x1111,0x2222,0x3333,0x0007',
      );
      final byStart = _schedule(
        id: '45',
        start: start,
        desiredMatchingId: '0x1111,0x2222,0x3333,0x0000',
      );
      final index = EpgReservedIndex.fromSchedules([byStart, byEvent]);
      expect(index.scheduleFor(_channel, event), same(byEvent));
    });

    test('scheduleFor is null when nothing matches', () {
      final index = EpgReservedIndex.fromSchedules([
        _schedule(
          start: start,
          serviceId: 0x4444,
          desiredMatchingId: '0x1111,0x2222,0x4444,0x0007',
        ),
      ]);
      expect(index.scheduleFor(_channel, event), isNull);
      expect(
        EpgReservedIndex.fromSchedules(const []).scheduleFor(_channel, event),
        isNull,
      );
    });

    test('no reservations, no marking', () {
      final index = EpgReservedIndex.fromSchedules(const []);
      expect(index.isEmpty, isTrue);
      expect(index.isReserved(_channel, event), isFalse);
    });
  });

  group('epgReservedFrame', () {
    test('a reserved tile gets the red frame; others get none', () {
      final frame = epgReservedFrame(true);
      expect(frame, isNotNull);
      final border = frame!.border as Border;
      expect(border.top.color, epgReservedFrameColor);
      expect(border.top.width, epgReservedFrameWidth);
      expect(epgReservedFrame(false), isNull);
    });
  });

  group('guide grid', () {
    testWidgets('a reserved event tile is framed; an unreserved one is not', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const reg = RegisteredNasne(
        host: '192.0.2.1',
        udn: 'uuid:test',
        friendlyName: 'nasne',
        macAddr: '00:11:22:33:44:55',
      );
      final now = DateTime.now().toUtc();
      final guide = EpgGuide(
        broadcastingType: 2,
        services: [
          EpgServiceGuide(
            channel: _channel,
            events: [
              EpgEvent(
                eventId: 1,
                start: now,
                duration: const Duration(minutes: 30),
                title: '予約済み番組',
                genreLevel1: 3,
              ),
              EpgEvent(
                eventId: 2,
                start: now.add(const Duration(hours: 1)),
                duration: const Duration(minutes: 30),
                title: '通常番組',
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const [reg]),
            ),
            epgGuideProvider.overrideWith((ref, r) async => guide),
            channelLogosProvider.overrideWith(
              (ref, r) async => const <int, List<int>>{},
            ),
            schedulesProvider.overrideWith(
              (ref, r) async => [
                _schedule(
                  start: now,
                  desiredMatchingId: '0x1111,0x2222,0x3333,0x0001',
                ),
              ],
            ),
          ],
          child: const MaterialApp(home: EpgScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      Container frameOf(String title) => tester.widget<Container>(
        find
            .ancestor(of: find.text(title), matching: find.byType(Container))
            .first,
      );
      final reserved = frameOf('予約済み番組');
      expect(reserved.foregroundDecoration, isNotNull);
      final decoration = reserved.foregroundDecoration! as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.color, epgReservedFrameColor);
      expect(frameOf('通常番組').foregroundDecoration, isNull);
    });
  });

  group('event detail delete action (plan 124)', () {
    final futureEvent = EpgEvent(
      eventId: 7,
      start: DateTime.now().add(const Duration(hours: 2)),
      duration: const Duration(minutes: 30),
      title: '予約済み番組',
    );

    testWidgets('a reserved detail offers delete instead of reserve', (
      tester,
    ) async {
      var deleteCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpgEventDetailDialog(
              event: futureEvent,
              channelName: 'テスト局',
              onReserve: () {},
              onDeleteReservation: () => deleteCalls++,
            ),
          ),
        ),
      );
      expect(find.text('予約を削除'), findsOneWidget);
      expect(find.text('録画予約'), findsNothing);
      await tester.tap(find.text('予約を削除'));
      expect(deleteCalls, 1);
    });

    testWidgets('an unreserved detail keeps the reserve action', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpgEventDetailDialog(
              event: futureEvent,
              channelName: 'テスト局',
              onReserve: () {},
            ),
          ),
        ),
      );
      expect(find.text('録画予約'), findsOneWidget);
      expect(find.text('予約を削除'), findsNothing);
    });

    bool focusIsInside(Finder finder) {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) return false;
      final targets = finder.evaluate();
      if (targets.length != 1) return false;
      final target = targets.single;
      var inside = false;
      context.visitAncestorElements((element) {
        if (element == target) {
          inside = true;
          return false;
        }
        return true;
      });
      return inside;
    }

    Finder actionButton(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(FilledButton),
    );

    testWidgets('on TV a reserved detail focuses the delete action', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appVariantProvider.overrideWithValue(AppVariant.tv)],
          child: MaterialApp(
            home: Scaffold(
              body: EpgEventDetailDialog(
                event: futureEvent,
                channelName: 'テスト局',
                onReserve: () {},
                onDeleteReservation: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(focusIsInside(actionButton('予約を削除')), isTrue);
    });

    testWidgets('on TV an unreserved detail focuses the reserve action', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appVariantProvider.overrideWithValue(AppVariant.tv)],
          child: MaterialApp(
            home: Scaffold(
              body: EpgEventDetailDialog(
                event: futureEvent,
                channelName: 'テスト局',
                onReserve: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(focusIsInside(actionButton('録画予約')), isTrue);
    });

    Widget host({
      required RecordSchedule? reservedSchedule,
      required Future<void> Function(RecordSchedule) onDeleteReserved,
    }) {
      const reg = RegisteredNasne(
        host: '192.0.2.1',
        udn: 'uuid:test',
        friendlyName: 'nasne',
        macAddr: '00:11:22:33:44:55',
      );
      return MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showEpgEventDetail(
                  context,
                  reg: reg,
                  channel: _channel,
                  channelName: 'テスト局',
                  event: futureEvent,
                  reservedSchedule: reservedSchedule,
                  onDeleteReserved: onDeleteReserved,
                ),
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('confirming deletes the matched reservation and closes', (
      tester,
    ) async {
      final deleted = <RecordSchedule>[];
      final reservation = _schedule(
        id: '42',
        start: futureEvent.start,
        desiredMatchingId: '0x1111,0x2222,0x3333,0x0007',
      );
      await tester.pumpWidget(
        host(
          reservedSchedule: reservation,
          onDeleteReserved: (s) async => deleted.add(s),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EpgEventDetailDialog), findsOneWidget);
      await tester.tap(find.text('予約を削除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The confirmation is up; nothing deleted yet.
      expect(find.textContaining('の予約を削除しますか？'), findsOneWidget);
      expect(deleted, isEmpty);
      await tester.tap(find.text('削除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(deleted, [same(reservation)]);
      expect(find.byType(EpgEventDetailDialog), findsNothing);
      expect(find.text('予約を削除しました'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation deletes nothing', (tester) async {
      final deleted = <RecordSchedule>[];
      final reservation = _schedule(
        id: '42',
        start: futureEvent.start,
        desiredMatchingId: '0x1111,0x2222,0x3333,0x0007',
      );
      await tester.pumpWidget(
        host(
          reservedSchedule: reservation,
          onDeleteReserved: (s) async => deleted.add(s),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('予約を削除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('キャンセル'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(deleted, isEmpty);
      expect(find.byType(EpgEventDetailDialog), findsOneWidget);
    });
  });

  group('guide grid delete flow (plan 124)', () {
    testWidgets('deleting from the detail clears the red frame', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const reg = RegisteredNasne(
        host: '192.0.2.1',
        udn: 'uuid:test',
        friendlyName: 'nasne',
        macAddr: '00:11:22:33:44:55',
      );
      // The event sits in the future: this test is about
      // the reserved frame alone, and an event on air
      // would keep the on-air frame after the deletion
      // (epg_onair_policy).
      final start = DateTime.now().toUtc().add(const Duration(hours: 1));
      final guide = EpgGuide(
        broadcastingType: 2,
        services: [
          EpgServiceGuide(
            channel: _channel,
            events: [
              EpgEvent(
                eventId: 1,
                start: start,
                duration: const Duration(minutes: 30),
                title: '予約済み番組',
                genreLevel1: 3,
              ),
            ],
          ),
        ],
      );
      final schedules = _FakeSchedules([
        _schedule(
          id: '42',
          start: start,
          desiredMatchingId: '0x1111,0x2222,0x3333,0x0001',
        ),
      ]);
      final bundle = DeviceServices(
        deviceInfo: _UnusedDeviceInfo(),
        settings: _UnusedSettings(),
        schedules: schedules,
        titles: _UnusedTitles(),
        metadata: _UnusedMetadata(),
        live: _UnusedLive(),
        playback: const UnsupportedPlaybackEngine(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const [reg]),
            ),
            epgGuideProvider.overrideWith((ref, r) async => guide),
            channelLogosProvider.overrideWith(
              (ref, r) async => const <int, List<int>>{},
            ),
            deviceServicesProvider.overrideWith((ref, r) => bundle),
          ],
          child: const MaterialApp(home: EpgScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      Container frameOf() => tester.widget<Container>(
        find
            .ancestor(of: find.text('予約済み番組'), matching: find.byType(Container))
            .first,
      );
      expect(frameOf().foregroundDecoration, isNotNull);

      await tester.tap(find.text('予約済み番組'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EpgEventDetailDialog), findsOneWidget);
      expect(find.text('予約を削除'), findsOneWidget);
      expect(find.text('録画予約'), findsNothing);

      await tester.tap(find.text('予約を削除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('削除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(schedules.deletedIds, ['42']);
      expect(find.byType(EpgEventDetailDialog), findsNothing);
      expect(frameOf().foregroundDecoration, isNull);
    });
  });
}
