/// Live viewing screen tests (plan 95): the band tabs
/// (Discord request, 2026-11-21) switch which band's channels
/// are listed, and the programme guide's subchannel switch
/// applies to this list too.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/live_screen.dart';

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
        '地デジサブ局',
        networkId: 10,
        transportStreamId: 10,
        serviceId: 101,
      ),
      _channel(
        'DTTB',
        '地デジ他局',
        networkId: 10,
        transportStreamId: 11,
        serviceId: 200,
      ),
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
      _channel(
        'BS',
        'BSサブ局',
        networkId: 4,
        transportStreamId: 1,
        serviceId: 102,
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

Future<void> _pumpLive(
  WidgetTester tester, {
  List<LiveBand>? bands,
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
        liveChannelsProvider.overrideWith((ref, r) async => bands ?? _bands),
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

void main() {
  group('liveBandTabLabel', () {
    test('short labels for the measured bands, device title otherwise', () {
      LiveBand band(String id, String title) =>
          LiveBand(containerId: id, title: title, channels: const []);
      expect(liveBandTabLabel(band('0/video/LiveTuner/DTTB', '地上デジタル')), '地デジ');
      expect(liveBandTabLabel(band('0/video/LiveTuner/BS', 'ＢＳデジタル')), 'BS');
      expect(liveBandTabLabel(band('0/video/LiveTuner/CS', '１１０度ＣＳ')), 'CS');
      expect(
        liveBandTabLabel(band('0/video/LiveTuner/XX', 'その他バンド')),
        'その他バンド',
      );
    });
  });

  group('live screen band tabs', () {
    testWidgets('tabs switch which band is listed', (tester) async {
      await _pumpLive(tester);

      // Terrestrial first; the subchannel is hidden by the
      // default-off switch, the other bands are behind tabs.
      expect(find.text('地デジ本局'), findsOneWidget);
      expect(find.text('地デジ他局'), findsOneWidget);
      expect(find.text('BS本局'), findsNothing);
      expect(find.text('CS局'), findsNothing);

      await tester.tap(find.text('BS'));
      await tester.pump();
      expect(find.text('BS本局'), findsOneWidget);
      expect(find.text('地デジ本局'), findsNothing);

      await tester.tap(find.text('CS'));
      await tester.pump();
      expect(find.text('CS局'), findsOneWidget);
      expect(find.text('BS本局'), findsNothing);
    });

    testWidgets('the subchannel switch applies to the live list', (
      tester,
    ) async {
      await _pumpLive(tester);
      expect(find.text('地デジサブ局'), findsNothing);
      expect(find.text('BSサブ局'), findsNothing);

      final keyValues = InMemoryKeyValueStore();
      await keyValues.write('epg_show_subchannels', 'true');
      await _pumpLive(tester, keyValues: keyValues);
      expect(find.text('地デジサブ局'), findsOneWidget);

      await tester.tap(find.text('BS'));
      await tester.pump();
      expect(find.text('BSサブ局'), findsOneWidget);
    });

    testWidgets('a single band sits next to the pinned tab', (tester) async {
      await _pumpLive(tester, bands: [_bands.first]);
      // The ピン留め tab always heads the tab row, so even a
      // single band is listed under tabs now.
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      expect(find.text('地デジ本局'), findsOneWidget);

      // Nothing pinned yet: the pinned tab shows its guidance.
      await tester.tap(find.text('ピン留め'));
      await tester.pump();
      expect(find.textContaining('ピン留めしたチャンネルがありません'), findsOneWidget);
      expect(find.text('地デジ本局'), findsNothing);
    });
  });
}
