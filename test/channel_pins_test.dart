/// Pinned channels tests (owner request 2026-11-26): the
/// pin filter flattens the pinned channels across bands in
/// band order, a channel without a broadcast identity is
/// never pinned, a hidden channel stays out of the pinned
/// list, the notifier persists the choice in the key-value
/// store, and the TV視聴 screen's ピン留め tab — its row
/// toggles, its cross-band listing and its empty guidance —
/// works end to end.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/channel_pins.dart';
import 'package:tmhb/ui/channel_visibility.dart';
import 'package:tmhb/ui/live_screen.dart';

/// Lets the notifier's asynchronous restore / write-back settle.
Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

const _reg = RegisteredNasne(
  host: '192.0.2.1',
  udn: 'uuid:test',
  friendlyName: 'nasne',
  macAddr: '00:11:22:33:44:55',
);

LiveChannel _channel(
  String band,
  String name, {
  int? networkId,
  int? transportStreamId,
  int? serviceId,
}) => LiveChannel(
  id: '0/video/LiveTuner/$band/ch?name=$name',
  bandId: '0/video/LiveTuner/$band',
  networkId: networkId,
  transportStreamId: transportStreamId,
  serviceId: serviceId,
  channelName: name,
  programTitle: '$name の番組',
);

final _bands = [
  LiveBand(
    containerId: '0/video/LiveTuner/DTTB',
    title: '地上デジタル',
    channels: [
      _channel(
        'DTTB',
        '地デジ本局',
        networkId: 10,
        transportStreamId: 10,
        serviceId: 100,
      ),
      _channel(
        'DTTB',
        '地デジ他局',
        networkId: 10,
        transportStreamId: 11,
        serviceId: 200,
      ),
      _channel('DTTB', '匿名局'),
    ],
  ),
  LiveBand(
    containerId: '0/video/LiveTuner/BS',
    title: 'ＢＳデジタル',
    channels: [
      _channel(
        'BS',
        'BS本局',
        networkId: 4,
        transportStreamId: 1,
        serviceId: 101,
      ),
    ],
  ),
  LiveBand(
    containerId: '0/video/LiveTuner/CS',
    title: '１１０度ＣＳ',
    channels: [
      _channel('CS', 'CS局', networkId: 6, transportStreamId: 1, serviceId: 300),
    ],
  ),
];

void main() {
  group('channelIsPinned', () {
    test('a null key is never pinned, a stored key is', () {
      expect(channelIsPinned(null, {'10:10:100'}), isFalse);
      expect(channelIsPinned('10:10:100', {'10:10:100'}), isTrue);
      expect(channelIsPinned('10:11:200', {'10:10:100'}), isFalse);
    });
  });

  group('pinnedLiveChannels', () {
    test('an empty choice pins nothing', () {
      expect(pinnedLiveChannels(_bands, const {}), isEmpty);
    });

    test('flattens across bands in band order, then list order', () {
      // Pinned out of order on purpose: the listing follows
      // the bands and their rows, not the stored set.
      final pinned = pinnedLiveChannels(_bands, {
        '6:1:300',
        '10:11:200',
        '4:1:101',
        '10:10:100',
      });
      expect(pinned.map((c) => c.channelName), [
        '地デジ本局',
        '地デジ他局',
        'BS本局',
        'CS局',
      ]);
    });

    test('a channel without identity is never listed', () {
      final pinned = pinnedLiveChannels(_bands, {
        '10:10:100',
        '10:11:200',
        '4:1:101',
        '6:1:300',
      });
      expect(pinned.map((c) => c.channelName), isNot(contains('匿名局')));
    });

    test('a hidden channel stays out even while pinned', () {
      // The composition the live list applies: the
      // not-watched filter runs first, the pin filter reads
      // what is left.
      final visible = liveBandsWithHiddenChannels(_bands, {'10:10:100'});
      final pinned = pinnedLiveChannels(visible, {'10:10:100', '4:1:101'});
      expect(pinned.map((c) => c.channelName), ['BS本局']);
    });
  });

  group('PinnedChannelsNotifier persistence', () {
    late InMemoryKeyValueStore keyValues;

    setUp(() {
      keyValues = InMemoryKeyValueStore();
    });

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(keyValues)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('decode keeps only three-part numeric triples', () {
      expect(PinnedChannelsNotifier.decode(null), isEmpty);
      expect(PinnedChannelsNotifier.decode(''), isEmpty);
      expect(PinnedChannelsNotifier.decode('10:10:100,4:1:101'), {
        '10:10:100',
        '4:1:101',
      });
      expect(PinnedChannelsNotifier.decode('x, 10:10 ,1:2:3:4,,'), isEmpty);
      expect(PinnedChannelsNotifier.decode(' 10:10:100 '), {'10:10:100'});
    });

    test('setPinned writes the sorted comma-separated form', () async {
      final container = makeContainer();
      final notifier = container.read(pinnedChannelsProvider.notifier);
      await notifier.setPinned('4:1:101', true);
      await notifier.setPinned('10:10:100', true);
      expect(container.read(pinnedChannelsProvider), {'10:10:100', '4:1:101'});
      expect(await keyValues.read('pinned_channels'), '10:10:100,4:1:101');

      await notifier.setPinned('4:1:101', false);
      expect(container.read(pinnedChannelsProvider), {'10:10:100'});
      expect(await keyValues.read('pinned_channels'), '10:10:100');
    });

    test('a fresh container restores the stored set', () async {
      await keyValues.write('pinned_channels', '10:10:100');
      final container = makeContainer();
      container.read(pinnedChannelsProvider);
      await flush();
      expect(container.read(pinnedChannelsProvider), {'10:10:100'});
    });
  });

  group('pinned tab in the live screen', () {
    Future<void> pumpLive(
      WidgetTester tester, {
      InMemoryKeyValueStore? keyValues,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const [_reg]),
            ),
            liveChannelsProvider.overrideWith((ref, r) async => _bands),
            keyValueStoreProvider.overrideWithValue(
              keyValues ?? InMemoryKeyValueStore(),
            ),
          ],
          child: const MaterialApp(home: LiveScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
    }

    Finder pinToggleOf(String channelName) => find.descendant(
      of: find.widgetWithText(ListTile, channelName),
      matching: find.byType(IconButton),
    );

    testWidgets('the pinned tab starts empty, with its guidance', (
      tester,
    ) async {
      await pumpLive(tester);
      await tester.tap(find.text('ピン留め'));
      await tester.pump();
      expect(find.textContaining('ピン留めしたチャンネルがありません'), findsOneWidget);
      expect(find.text('地デジ本局'), findsNothing);
    });

    testWidgets('pinning rows lists them across bands in band order', (
      tester,
    ) async {
      await pumpLive(tester);

      // Pin a CS channel first, then a terrestrial one: the
      // pinned tab still lists terrestrial before CS.
      await tester.tap(find.text('CS'));
      await tester.pump();
      await tester.tap(pinToggleOf('CS局'));
      await tester.pump();
      await tester.tap(find.text('地デジ'));
      await tester.pump();
      await tester.tap(pinToggleOf('地デジ本局'));
      await tester.pump();

      await tester.tap(find.text('ピン留め'));
      await tester.pump();
      expect(find.text('地デジ本局'), findsOneWidget);
      expect(find.text('CS局'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('地デジ本局')).dy,
        lessThan(tester.getTopLeft(find.text('CS局')).dy),
      );
      // The pinned rows carry the filled pin; unpinning from
      // the pinned tab drops the row at once.
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, '地デジ本局'),
          matching: find.byIcon(Icons.push_pin),
        ),
        findsOneWidget,
      );
      await tester.tap(pinToggleOf('地デジ本局'));
      await tester.pump();
      expect(find.text('地デジ本局'), findsNothing);
      expect(find.text('CS局'), findsOneWidget);
    });

    testWidgets('a channel without identity shows a disabled pin toggle', (
      tester,
    ) async {
      await pumpLive(tester);
      final toggle = tester.widget<IconButton>(pinToggleOf('匿名局'));
      expect(toggle.onPressed, isNull);
    });

    testWidgets('a hidden channel stays out of the pinned tab', (tester) async {
      final keyValues = InMemoryKeyValueStore();
      await keyValues.write('pinned_channels', '10:10:100');
      await keyValues.write('hidden_channels', '10:10:100');
      await pumpLive(tester, keyValues: keyValues);

      await tester.tap(find.text('ピン留め'));
      await tester.pump();
      expect(find.textContaining('ピン留めしたチャンネルがありません'), findsOneWidget);
      expect(find.text('地デジ本局'), findsNothing);
    });
  });
}
