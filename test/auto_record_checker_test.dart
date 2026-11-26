/// Auto record checker tests (user-fork addition): the
/// checker end to end against fake services — a match
/// becomes a reservation on the unit, and the
/// reservation list the 予約 screen reads
/// (schedulesProvider) shows it without a manual
/// refresh. The startup ordering is covered too: the
/// startup check fires before the persisted rules have
/// been read back, and must still see them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/auto_record_providers.dart';
import 'package:tmhb/app/bs_epg_providers.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/auto_record_policy.dart';

const _reg = RegisteredNasne(
  host: '192.0.2.10',
  udn: 'uuid:test',
  friendlyName: 'nasne',
  macAddr: '00:11:22:33:44:55',
);

const _channel = Channel(
  broadcastingType: 2,
  networkId: 1,
  transportStreamId: 1,
  serviceId: 100,
  serviceType: 1,
  channelNumber: 1,
  serviceName: 'テスト放送',
);

class _FakeSchedules implements ScheduleService {
  final List<RecordSchedule> items = [];
  final List<NewRecordSchedule> created = [];
  int _nextId = 200;

  @override
  Future<List<RecordSchedule>> listSchedules({
    int startingIndex = 0,
    int requestedCount = 50,
  }) async => [...items];

  @override
  Future<String> createSchedule(NewRecordSchedule schedule) async {
    created.add(schedule);
    final id = '${_nextId++}';
    items.add(
      RecordSchedule(
        id: id,
        start: schedule.start,
        durationSeconds: schedule.durationSeconds,
        conditionId: '1',
        channel: schedule.channel,
        desiredQualityMode: schedule.desiredQualityMode,
        desiredMatchingId: schedule.desiredMatchingId,
        reservationCreatorId: schedule.reservationCreatorId,
        priorityFlag: schedule.priorityFlag,
        recordDestinationId: schedule.recordDestinationId,
        title: 'アニメ番組',
      ),
    );
    return id;
  }

  @override
  Future<void> updateSchedule(ScheduleUpdate update) async {}

  @override
  Future<void> deleteSchedule(String id) async {
    items.removeWhere((s) => s.id == id);
  }

  @override
  Future<List<RecordSchedule>> checkConflicts(
    NewRecordSchedule candidate,
  ) async => const [];
}

/// A service the checker never calls; any call is a
/// test bug, so it throws.
class _Unused {
  static Never call(Invocation invocation) =>
      throw UnimplementedError('unused fake: $invocation');
}

class _StubDeviceInfo implements DeviceInfoService {
  @override
  dynamic noSuchMethod(Invocation invocation) => _Unused.call(invocation);
}

class _StubSettings implements SettingsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => _Unused.call(invocation);
}

class _StubTitles implements TitleCatalogService {
  @override
  dynamic noSuchMethod(Invocation invocation) => _Unused.call(invocation);
}

class _StubMetadata implements MetadataService {
  @override
  dynamic noSuchMethod(Invocation invocation) => _Unused.call(invocation);
}

class _StubLive implements LiveCatalogService {
  @override
  dynamic noSuchMethod(Invocation invocation) => _Unused.call(invocation);
}

void main() {
  const rule = AutoRecordRule(id: 'r1', keyword: 'アニメ');

  late _FakeSchedules schedules;
  late InMemoryKeyValueStore keyValues;

  EpgGuide guide() {
    final start = DateTime.now().add(const Duration(days: 1));
    return EpgGuide(
      broadcastingType: 2,
      services: [
        EpgServiceGuide(
          channel: _channel,
          events: [
            EpgEvent(
              eventId: 42,
              start: start,
              duration: const Duration(minutes: 30),
              title: 'アニメ番組',
            ),
          ],
        ),
      ],
    );
  }

  ProviderContainer makeContainer() {
    schedules = _FakeSchedules();
    keyValues = InMemoryKeyValueStore();
    final bundle = DeviceServices(
      deviceInfo: _StubDeviceInfo(),
      settings: _StubSettings(),
      schedules: schedules,
      titles: _StubTitles(),
      metadata: _StubMetadata(),
      live: _StubLive(),
      playback: const UnsupportedPlaybackEngine(),
    );
    return ProviderContainer(
      overrides: [
        registrationStoreProvider.overrideWithValue(
          InMemoryRegistrationStore(const [_reg]),
        ),
        keyValueStoreProvider.overrideWithValue(keyValues),
        deviceServicesProvider.overrideWith((ref, reg) => bundle),
        epgGuideProvider.overrideWith((ref, reg) async => guide()),
        bsEpgGuideProvider.overrideWith(
          (ref, reg) async => const EpgGuide(broadcastingType: 3, services: []),
        ),
      ],
    );
  }

  Future<void> seedRules() =>
      keyValues.write('auto_record_rules', encodeAutoRecordRules([rule]));

  test('a startup-order check still reserves, and the list shows it', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await seedRules();
    // Nothing has read the rules provider yet: this is
    // the order the app shell's startup check runs in.
    final summary = await container.read(autoRecordCheckerProvider).run();
    expect(summary.reserved, 1);
    expect(schedules.created.length, 1);
  });

  test('a check refreshes the reservation list the UI watches', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await seedRules();
    final reg = (await container.read(registrationsProvider.future)).single;
    // Let the persisted rules land, as they have by the
    // time the viewer opens the rules screen.
    container.read(autoRecordRulesProvider);
    for (
      var i = 0;
      i < 50 && container.read(autoRecordRulesProvider).isEmpty;
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(autoRecordRulesProvider), isNotEmpty);

    // The 予約 screen's view: subscribed before the check.
    final seen = <List<RecordSchedule>>[];
    final sub = container.listen(
      schedulesProvider(reg),
      (_, next) => next.whenData(seen.add),
    );
    addTearDown(sub.close);
    expect(await container.read(schedulesProvider(reg).future), isEmpty);

    final summary = await container.read(autoRecordCheckerProvider).run();
    expect(summary.reserved, 1);

    // No manual invalidate: the list the screen holds
    // must arrive at the created reservation by itself.
    expect(await container.read(schedulesProvider(reg).future), hasLength(1));
    expect(seen.last, hasLength(1));
  });
}
