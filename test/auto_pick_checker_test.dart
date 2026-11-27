/// Auto pick checker tests (user-fork addition): the
/// keyword-less auto recording end to end against
/// fake services — with no rules at all, a check
/// fills the free time from the viewer's own library
/// tendency, marks what it made, and stops at the
/// disk guard and the per-check cap.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/auto_pick_providers.dart';
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
        title: 'ドラマ甲',
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

class _FakeDeviceInfo implements DeviceInfoService {
  _FakeDeviceInfo({required this.freeBytes, this.fail = false});

  final int freeBytes;
  final bool fail;

  @override
  Future<List<HddEntry>> listHdds() async {
    if (fail) {
      throw const NasneError(
        category: NasneErrorCategory.unreachable,
        source: 'fake',
        messageKey: 'fake',
      );
    }
    return const [
      HddEntry(id: 0, internal: false, mounted: true, registered: true),
    ];
  }

  @override
  Future<HddInfo> getHddInfo(int id) async => HddInfo(
    id: id,
    internal: false,
    format: 'xfs',
    name: 'HDD',
    usedBytes: 0,
    freeBytes: freeBytes,
    totalBytes: freeBytes,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused fake: $invocation');
}

class _FakeTitles implements TitleCatalogService {
  _FakeTitles(this.items);

  final List<RecordedTitle> items;

  @override
  Future<List<RecordedTitle>> listTitles({bool withMetadata = true}) async =>
      items;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused fake: $invocation');
}

class _StubSettings implements SettingsService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused fake: $invocation');
}

class _StubMetadata implements MetadataService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused fake: $invocation');
}

class _StubLive implements LiveCatalogService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused fake: $invocation');
}

void main() {
  late _FakeSchedules schedules;
  late InMemoryKeyValueStore keyValues;

  /// Two future episodes of the followed series.
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
              duration: const Duration(minutes: 60),
              title: 'ドラマ甲',
              genreLevel1: 3,
            ),
            EpgEvent(
              eventId: 43,
              start: start.add(const Duration(hours: 2)),
              duration: const Duration(minutes: 60),
              title: 'ドラマ甲',
              genreLevel1: 3,
            ),
          ],
        ),
      ],
    );
  }

  List<RecordedTitle> library() => const [
    RecordedTitle(
      id: 't1',
      title: 'ドラマ甲',
      channel: ScheduleChannel(
        broadcastingType: 2,
        channelType: 2,
        serviceId: 100,
      ),
      genre: 'ドラマ',
      channelName: 'テスト放送',
    ),
  ];

  ProviderContainer makeContainer({
    int freeBytes = 100 << 30,
    bool hddFails = false,
  }) {
    schedules = _FakeSchedules();
    keyValues = InMemoryKeyValueStore();
    final bundle = DeviceServices(
      deviceInfo: _FakeDeviceInfo(freeBytes: freeBytes, fail: hddFails),
      settings: _StubSettings(),
      schedules: schedules,
      titles: _FakeTitles(library()),
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
        csEpgGuideProvider.overrideWith(
          (ref, reg) async => const EpgGuide(broadcastingType: 4, services: []),
        ),
      ],
    );
  }

  Future<void> seedSettings(AutoPickSettings settings) =>
      keyValues.write('auto_pick_settings', encodeAutoPickSettings(settings));

  test('with no rules, the auto pick fills free time and marks it', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await seedSettings(const AutoPickSettings(enabled: true));
    final summary = await container.read(autoRecordCheckerProvider).run();
    expect(summary.auto, 2);
    expect(summary.reserved, 0);
    expect(schedules.created, hasLength(2));
    final marks = container
        .read(autoPickMarksProvider.notifier)
        .keysFor(_reg.host);
    expect(marks, hasLength(2));
    final log = container.read(autoRecordLogProvider);
    expect(log.where((e) => e.kind == AutoRecordLogKind.auto), hasLength(2));
  });

  test('the disk guard stops the auto pick under the floor', () async {
    final container = makeContainer(freeBytes: 1 << 30);
    addTearDown(container.dispose);
    await seedSettings(const AutoPickSettings(enabled: true));
    final summary = await container.read(autoRecordCheckerProvider).run();
    expect(summary.auto, 0);
    expect(schedules.created, isEmpty);
  });

  test('unknown free space stops the auto pick too', () async {
    final container = makeContainer(hddFails: true);
    addTearDown(container.dispose);
    await seedSettings(const AutoPickSettings(enabled: true));
    final summary = await container.read(autoRecordCheckerProvider).run();
    expect(summary.auto, 0);
    expect(schedules.created, isEmpty);
  });

  test('the per-check cap bounds one check', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await seedSettings(const AutoPickSettings(enabled: true, maxPerCheck: 1));
    final summary = await container.read(autoRecordCheckerProvider).run();
    expect(summary.auto, 1);
    expect(schedules.created, hasLength(1));
  });

  test('a rule programme is the rule’s, never the auto pick’s too', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await seedSettings(const AutoPickSettings(enabled: true));
    await keyValues.write(
      'auto_record_rules',
      encodeAutoRecordRules(const [
        AutoRecordRule(id: 'r1', keyword: 'ドラマ甲', onceOnly: true),
      ]),
    );
    final summary = await container.read(autoRecordCheckerProvider).run();
    // The one-shot rule takes the first episode; the
    // auto pick takes only the second.
    expect(summary.reserved, 1);
    expect(summary.auto, 1);
    expect(schedules.created, hasLength(2));
    final marks = container
        .read(autoPickMarksProvider.notifier)
        .keysFor(_reg.host);
    expect(marks, hasLength(1));
  });

  test('off (the default), the auto pick never runs', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final summary = await container.read(autoRecordCheckerProvider).run();
    expect(summary.auto, 0);
    expect(schedules.created, isEmpty);
  });
}
