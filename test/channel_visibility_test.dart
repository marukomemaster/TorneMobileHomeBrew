/// Not-watched channels tests (owner request 2026-11-26):
/// the channel key is the broadcast identity triple, the
/// filter drops hidden channels from the programme guide
/// and the live bands (identity-less live channels stay),
/// the notifier persists the choice in the key-value store
/// and resets it, and the settings flow — the 見ない
/// チャンネル page's switches and reset, and the live list
/// honouring the choice — works end to end.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/channel_visibility.dart';
import 'package:tmhb/ui/live_screen.dart';
import 'package:tmhb/ui/settings_screen.dart';

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

Channel _guideChannel(int nid, int tsid, int sid, String name) => Channel(
  broadcastingType: 2,
  networkId: nid,
  transportStreamId: tsid,
  serviceId: sid,
  serviceType: 1,
  channelNumber: 1,
  serviceName: name,
);

LiveChannel _liveChannel(
  String name, {
  int? networkId,
  int? transportStreamId,
  int? serviceId,
}) => LiveChannel(
  id: '0/video/LiveTuner/DTTB/ch?name=$name',
  bandId: '0/video/LiveTuner/DTTB',
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
      _liveChannel('地デジ本局', networkId: 10, transportStreamId: 10, serviceId: 100),
      _liveChannel('地デジ他局', networkId: 10, transportStreamId: 11, serviceId: 200),
    ],
  ),
];

void main() {
  group('channel keys', () {
    test('the key is the decimal identity triple', () {
      expect(
        channelVisibilityKey(
          networkId: 7880,
          transportStreamId: 7880,
          serviceId: 56832,
        ),
        '7880:7880:56832',
      );
      expect(channelKeyOf(_guideChannel(10, 11, 200, 'x')), '10:11:200');
      expect(
        liveChannelKeyOf(
          _liveChannel('x', networkId: 4, transportStreamId: 1, serviceId: 101),
        ),
        '4:1:101',
      );
    });

    test('a live channel without identity has no key and is never hidden', () {
      final anonymous = _liveChannel('x');
      expect(liveChannelKeyOf(anonymous), isNull);
      expect(channelIsHidden(null, {'10:11:200'}), isFalse);
      expect(channelIsHidden('10:11:200', {'10:11:200'}), isTrue);
      expect(channelIsHidden('10:11:201', {'10:11:200'}), isFalse);
    });
  });

  group('guideWithHiddenChannels', () {
    final guide = EpgGuide(
      broadcastingType: 2,
      services: [
        EpgServiceGuide(channel: _guideChannel(10, 10, 100, '本局'), events: const []),
        EpgServiceGuide(channel: _guideChannel(10, 11, 200, '他局'), events: const []),
      ],
    );

    test('an empty choice returns the guide unchanged', () {
      expect(identical(guideWithHiddenChannels(guide, const {}), guide), isTrue);
    });

    test('a hidden service drops out, the rest stay', () {
      final filtered = guideWithHiddenChannels(guide, {'10:11:200'});
      expect(filtered.services.map((s) => s.channel.serviceName), ['本局']);
      expect(filtered.broadcastingType, 2);
    });

    test('a choice matching nothing returns the guide unchanged', () {
      expect(
        identical(guideWithHiddenChannels(guide, {'1:2:3'}), guide),
        isTrue,
      );
    });
  });

  group('liveBandsWithHiddenChannels', () {
    test('an empty choice returns the bands unchanged', () {
      expect(
        identical(liveBandsWithHiddenChannels(_bands, const {}), _bands),
        isTrue,
      );
    });

    test('a hidden channel drops out of its band', () {
      final filtered = liveBandsWithHiddenChannels(_bands, {'10:11:200'});
      expect(filtered.single.channels.map((c) => c.channelName), ['地デジ本局']);
    });

    test('a channel without identity stays visible', () {
      final bands = [
        LiveBand(
          containerId: '0/video/LiveTuner/DTTB',
          title: '地上デジタル',
          channels: [
            _liveChannel('匿名局'),
            _liveChannel('他局', networkId: 10, transportStreamId: 11, serviceId: 200),
          ],
        ),
      ];
      final filtered = liveBandsWithHiddenChannels(bands, {'10:11:200'});
      expect(filtered.single.channels.map((c) => c.channelName), ['匿名局']);
    });
  });

  group('HiddenChannelsNotifier persistence', () {
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
      expect(HiddenChannelsNotifier.decode(null), isEmpty);
      expect(HiddenChannelsNotifier.decode(''), isEmpty);
      expect(HiddenChannelsNotifier.decode('10:11:200,4:1:101'), {
        '10:11:200',
        '4:1:101',
      });
      expect(HiddenChannelsNotifier.decode('x, 10:11 ,1:2:3:4,,'), isEmpty);
      expect(HiddenChannelsNotifier.decode(' 10:11:200 '), {'10:11:200'});
    });

    test('setHidden writes the sorted comma-separated form', () async {
      final container = makeContainer();
      final notifier = container.read(hiddenChannelsProvider.notifier);
      await notifier.setHidden('4:1:101', true);
      await notifier.setHidden('10:11:200', true);
      expect(container.read(hiddenChannelsProvider), {'10:11:200', '4:1:101'});
      expect(await keyValues.read('hidden_channels'), '10:11:200,4:1:101');

      await notifier.setHidden('4:1:101', false);
      expect(container.read(hiddenChannelsProvider), {'10:11:200'});
      expect(await keyValues.read('hidden_channels'), '10:11:200');
    });

    test('reset shows every channel again and clears the store', () async {
      final container = makeContainer();
      final notifier = container.read(hiddenChannelsProvider.notifier);
      await notifier.setHidden('10:11:200', true);
      await notifier.reset();
      expect(container.read(hiddenChannelsProvider), isEmpty);
      expect(await keyValues.read('hidden_channels'), '');
    });

    test('a fresh container restores the stored set', () async {
      await keyValues.write('hidden_channels', '10:11:200');
      final container = makeContainer();
      container.read(hiddenChannelsProvider);
      await flush();
      expect(container.read(hiddenChannelsProvider), {'10:11:200'});
    });
  });

  group('hidden channels in the UI', () {
    Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final keyValues = InMemoryKeyValueStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const [_reg]),
            ),
            liveChannelsProvider.overrideWith((ref, r) async => _bands),
            keyValueStoreProvider.overrideWithValue(keyValues),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      return container;
    }

    testWidgets('the settings page toggles persist through the notifier', (
      tester,
    ) async {
      final container = await pumpSettings(tester);

      final tile = find.widgetWithText(ListTile, '見ないチャンネル');
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(SwitchListTile, '地デジ他局'), findsOneWidget);
      await tester.tap(find.widgetWithText(SwitchListTile, '地デジ他局'));
      await tester.pump();
      expect(container.read(hiddenChannelsProvider), {'10:11:200'});

      // The reset restores every channel after a confirmation.
      await tester.tap(find.widgetWithText(ListTile, 'すべて表示する'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(FilledButton, 'リセット'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(hiddenChannelsProvider), isEmpty);
    });

    testWidgets('the live list honours the stored choice', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final keyValues = InMemoryKeyValueStore();
      await keyValues.write('hidden_channels', '10:11:200');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const [_reg]),
            ),
            liveChannelsProvider.overrideWith((ref, r) async => _bands),
            keyValueStoreProvider.overrideWithValue(keyValues),
          ],
          child: const MaterialApp(home: LiveScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('地デジ本局'), findsOneWidget);
      expect(find.text('地デジ他局'), findsNothing);
    });
  });
}
