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
import 'package:tmhb/app/cs_epg_providers.dart';
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
  late List<_FakeSchedules> twoUnitSchedules;
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

  ProviderContainer makeContainer({EpgGuide? terrestrialGuide, EpgGuide? csGuide}) {
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
        epgGuideProvider.overrideWith(
          (ref, reg) async => terrestrialGuide ?? guide(),
        ),
        bsEpgGuideProvider.overrideWith(
          (ref, reg) async => const EpgGuide(broadcastingType: 3, services: []),
        ),
        csEpgGuideProvider.overrideWith(
          (ref, reg) async =>
              csGuide ?? const EpgGuide(broadcastingType: 4, services: []),
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

  // ---- Two units and one-shot rules (owner request
  // 2026-11-27) ----

  const reg2 = RegisteredNasne(
    host: '192.0.2.11',
    udn: 'uuid:test-2',
    friendlyName: 'nasne 2',
    macAddr: '00:11:22:33:44:66',
  );
  const channel2 = Channel(
    broadcastingType: 2,
    networkId: 1,
    transportStreamId: 2,
    serviceId: 200,
    serviceType: 1,
    channelNumber: 2,
    serviceName: 'テスト放送２',
  );

  /// A guide holding [events] on the two test
  /// channels, grouped per channel.
  EpgGuide guideWith(List<(Channel, DateTime, String, int)> events) {
    final byChannel = <Channel, List<EpgEvent>>{};
    for (final (channel, start, title, eventId) in events) {
      byChannel.putIfAbsent(channel, () => []).add(
        EpgEvent(
          eventId: eventId,
          start: start,
          duration: const Duration(minutes: 60),
          title: title,
        ),
      );
    }
    return EpgGuide(
      broadcastingType: 2,
      services: [
        for (final entry in byChannel.entries)
          EpgServiceGuide(channel: entry.key, events: entry.value),
      ],
    );
  }

  /// A container with two registered units, each with
  /// its own fake schedule service and its own guide.
  ProviderContainer makeTwoUnitContainer({
    required EpgGuide guide1,
    required EpgGuide guide2,
  }) {
    keyValues = InMemoryKeyValueStore();
    final schedules1 = _FakeSchedules();
    final schedules2 = _FakeSchedules();
    twoUnitSchedules = [schedules1, schedules2];
    DeviceServices bundleFor(_FakeSchedules s) => DeviceServices(
      deviceInfo: _StubDeviceInfo(),
      settings: _StubSettings(),
      schedules: s,
      titles: _StubTitles(),
      metadata: _StubMetadata(),
      live: _StubLive(),
      playback: const UnsupportedPlaybackEngine(),
    );
    final bundles = {_reg.host: bundleFor(schedules1), reg2.host: bundleFor(schedules2)};
    final guides = {_reg.host: guide1, reg2.host: guide2};
    return ProviderContainer(
      overrides: [
        registrationStoreProvider.overrideWithValue(
          InMemoryRegistrationStore(const [_reg, reg2]),
        ),
        keyValueStoreProvider.overrideWithValue(keyValues),
        deviceServicesProvider.overrideWith((ref, reg) => bundles[reg.host]!),
        epgGuideProvider.overrideWith((ref, reg) async => guides[reg.host]!),
        bsEpgGuideProvider.overrideWith(
          (ref, reg) async => const EpgGuide(broadcastingType: 3, services: []),
        ),
        csEpgGuideProvider.overrideWith(
          (ref, reg) async => const EpgGuide(broadcastingType: 4, services: []),
        ),
      ],
    );
  }

  test('two units: the same programme is reserved only on the first', () async {
    final start = DateTime.now().add(const Duration(days: 1));
    final guide = guideWith([(_channel, start, 'アニメ番組', 42)]);
    final container = makeTwoUnitContainer(guide1: guide, guide2: guide);
    addTearDown(container.dispose);
    await seedRules();
    final summary = await container.read(autoRecordCheckerProvider).run();
    expect(summary.reserved, 1);
    expect(twoUnitSchedules[0].created, hasLength(1));
    expect(twoUnitSchedules[1].created, isEmpty);
  });

  test('two units: same-time programmes split across the units', () async {
    final start = DateTime.now().add(const Duration(days: 1));
    final guide = guideWith([
      (_channel, start, 'アニメ番組１', 42),
      (channel2, start.add(const Duration(minutes: 30)), 'アニメ番組２', 43),
    ]);
    final container = makeTwoUnitContainer(guide1: guide, guide2: guide);
    addTearDown(container.dispose);
    await seedRules();
    final summary = await container.read(autoRecordCheckerProvider).run();
    // Unit 1 takes the first programme (the second
    // overlaps it there); unit 2 takes the second —
    // the first is a duplicate there, and unit 1's
    // tuner time is not unit 2's conflict.
    expect(summary.reserved, 2);
    expect(twoUnitSchedules[0].created, hasLength(1));
    expect(twoUnitSchedules[0].created.single.channel.serviceId, 100);
    expect(twoUnitSchedules[1].created, hasLength(1));
    expect(twoUnitSchedules[1].created.single.channel.serviceId, 200);
  });

  test('two units: a programme already on unit 1 is not doubled on unit 2', () async {
    final start = DateTime.now().add(const Duration(days: 1));
    final guide = guideWith([(_channel, start, 'アニメ番組', 42)]);
    final container = makeTwoUnitContainer(guide1: guide, guide2: guide);
    addTearDown(container.dispose);
    // Unit 1 already holds the programme (reserved by
    // hand before the check).
    twoUnitSchedules[0].items.add(
      RecordSchedule(
        id: 'manual-1',
        start: start,
        durationSeconds: 3600,
        conditionId: '1',
        channel: const ScheduleChannel(
          broadcastingType: 2,
          channelType: 2,
          serviceId: 100,
        ),
        desiredQualityMode: 100,
        desiredMatchingId: '',
        reservationCreatorId: '2000',
        priorityFlag: 0,
        recordDestinationId: 'HDD',
      ),
    );
    await seedRules();
    final summary = await container.read(autoRecordCheckerProvider).run();
    expect(summary.reserved, 0);
    expect(twoUnitSchedules[0].created, isEmpty);
    expect(twoUnitSchedules[1].created, isEmpty);
  });

  test('a one-shot rule reserves once, switches off, and logs it', () async {
    final start = DateTime.now().add(const Duration(days: 1));
    final container = makeContainer(
      terrestrialGuide: guideWith([
        (_channel, start, 'アニメ番組１', 42),
        (_channel, start.add(const Duration(hours: 2)), 'アニメ番組２', 43),
      ]),
    );
    addTearDown(container.dispose);
    await keyValues.write(
      'auto_record_rules',
      encodeAutoRecordRules(const [
        AutoRecordRule(id: 'once1', keyword: 'アニメ', onceOnly: true),
      ]),
    );
    final summary = await container.read(autoRecordCheckerProvider).run();
    expect(summary.reserved, 1);
    expect(schedules.created, hasLength(1));
    expect(schedules.created.single.start, start);
    final rules = container.read(autoRecordRulesProvider);
    expect(rules.single.enabled, isFalse);
    final log = container.read(autoRecordLogProvider);
    expect(
      log.map((e) => e.kind),
      containsAll(<AutoRecordLogKind>[
        AutoRecordLogKind.reserved,
        AutoRecordLogKind.ruleDisabled,
      ]),
    );
    // A second check with the spent rule reserves
    // nothing more.
    final again = await container.read(autoRecordCheckerProvider).run();
    expect(again.reserved, 0);
    expect(schedules.created, hasLength(1));
  });

  test('two units: a one-shot rule fires on the first unit only', () async {
    final start = DateTime.now().add(const Duration(days: 1));
    final guide = guideWith([(_channel, start, 'アニメ番組', 42)]);
    final container = makeTwoUnitContainer(guide1: guide, guide2: guide);
    addTearDown(container.dispose);
    await keyValues.write(
      'auto_record_rules',
      encodeAutoRecordRules(const [
        AutoRecordRule(id: 'once1', keyword: 'アニメ', onceOnly: true),
      ]),
    );
    final summary = await container.read(autoRecordCheckerProvider).run();
    expect(summary.reserved, 1);
    expect(twoUnitSchedules[0].created, hasLength(1));
    expect(twoUnitSchedules[1].created, isEmpty);
    expect(container.read(autoRecordRulesProvider).single.enabled, isFalse);
  });

  test('a CS guide hit is reserved with its CS channel', () async {
    final start = DateTime.now().add(const Duration(days: 1));
    final container = makeContainer(
      terrestrialGuide: const EpgGuide(broadcastingType: 2, services: []),
      csGuide: EpgGuide(
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
            events: [
              EpgEvent(
                eventId: 77,
                start: start,
                duration: const Duration(minutes: 30),
                title: 'アニメ映画',
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(container.dispose);
    await seedRules();
    final summary = await container.read(autoRecordCheckerProvider).run();
    expect(summary.reserved, 1);
    expect(schedules.created, hasLength(1));
    expect(schedules.created.single.channel.broadcastingType, 4);
    expect(schedules.created.single.channel.serviceId, 240);
  });
}
