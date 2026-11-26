/// CS (broadcastingType 4) EPG coverage (plan 137): the
/// fixed-stride version table, the EPGGet request it feeds,
/// and guide parsing for a band whose events arrive mostly
/// as other-TS sections.
///
/// The version-table and channel-list fixtures are the real
/// responses of the measured unit (FW 2.60, 2026-11-26): a
/// 4,572-byte table (57 records of 80 bytes) and the 57-entry
/// channel list (54 video services, networkIds 6 and 7).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/cs_epg_providers.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/epg_screen.dart';

Map<String, dynamic> _fixtureJson(String name) {
  final file = File('test/fixtures/webapi/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

List<int> _fixtureBytes(String name) =>
    File('test/fixtures/webapi/$name').readAsBytesSync();

/// The measured CS channel list, parsed the way the device
/// info service parses it.
List<Channel> csChannels() {
  final json = _fixtureJson('status_channelListGet_broadcastingType4.json');
  return [
    for (final e in json['channel'] as List)
      Channel.fromJson(
        (e as Map).cast<String, dynamic>(),
        broadcastingType: 4,
      ),
  ];
}

const _csChannel = Channel(
  broadcastingType: 4,
  networkId: 7,
  transportStreamId: 28960,
  serviceId: 240,
  serviceType: 1,
  channelNumber: 240,
  serviceName: 'ムービープラス',
);

/// One EIT section for [_csChannel] in the shape of
/// bs_epg_other_ts_and_title_test.dart's builder: a titled
/// event (テレビ) with a genre descriptor (映画).
Uint8List csSection(int tableId) {
  const bytes = [0x1b, 0x7c, 0xc6, 0xec, 0xd3]; // テレビ
  final descriptor = [
    0x4d, 10, 0x6a, 0x70, 0x6e, 5, ...bytes, 0,
    0x54, 2, 0x60, 0x00, // content: level1 6 (映画), level2 0
  ];
  final event = [
    0, 42, 0xef, 0xb0,
    0x09, 0x55, 0, 0, 0x30, 0,
    0xf0, descriptor.length,
    ...descriptor,
  ];
  final size = 11 + event.length + 4;
  final data = [
    tableId, 0xb0 | ((size >> 8) & 0x0f), size & 255,
    0, 240, 0xc1, 0, 0,
    0x71, 0x20, 0, 7, 0, tableId,
    ...event,
  ];
  final crc = crc32Mpeg(data);
  return Uint8List.fromList([
    ...data,
    (crc >> 24) & 255, (crc >> 16) & 255, (crc >> 8) & 255, crc & 255,
  ]);
}

void main() {
  group('CS version table (measured fixture)', () {
    test('the channel fixture is the measured CS lineup', () {
      final channels = csChannels();
      expect(channels, hasLength(57));
      expect(
        channels.where((c) => c.serviceType == 1),
        hasLength(54),
      );
      expect(
        channels.map((c) => c.networkId).toSet(),
        {6, 7},
      );
      expect(
        channels.every((c) => c.broadcastingType == 4),
        isTrue,
      );
    });

    test('all 54 video services are enumerated, both sides carried', () {
      final table = _fixtureBytes('status_EPGVersionInfoGet_broadcastingType4.bin');
      expect(table, hasLength(4572));
      final channels = csChannels();
      final services = parseCsEpgVersionServices(table, channels);
      expect(services, hasLength(54));
      // The enumerated set is exactly the video channels' set.
      expect(
        {for (final s in services) (s.networkId, s.transportStreamId, s.serviceId)},
        {
          for (final c in channels)
            if (c.serviceType == 1)
              (c.networkId, c.transportStreamId, c.serviceId),
        },
      );
      // Both segment bitmaps are requested for every CS
      // service (the measured capture's request shape).
      expect(
        services.every((s) => s.hasBasic && s.hasExtended),
        isTrue,
      );
      // A known CS service: ムービープラス.
      expect(services, contains(const EpgServiceRef(7, 28960, 240)));
    });

    test('the request body matches the measured capture byte count', () {
      final table = _fixtureBytes('status_EPGVersionInfoGet_broadcastingType4.bin');
      final services = parseCsEpgVersionServices(table, csChannels());
      final body = buildEpgGetBody(services);
      // The measured capture's EPGGet request for the same
      // table was 1,304 bytes: 8 + 24 * 54.
      expect(body.length, 1304);
      expect(body.sublist(4, 6), [0, 54]);
      // First record: triple, then both bitmaps all set.
      final first = services.first;
      expect(body.sublist(8, 14), [
        first.networkId >> 8, first.networkId & 0xff,
        first.transportStreamId >> 8, first.transportStreamId & 0xff,
        first.serviceId >> 8, first.serviceId & 0xff,
      ]);
      expect(body.sublist(8 + 8, 8 + 24), List.filled(16, 0xff));
    });

    test('the flags-derived walk cannot read the CS table', () {
      // Why a dedicated walk exists: the CS flags (0xa000)
      // carry the 0x2000 bit, which the terrestrial / satellite
      // walk treats as unknown and stops on, at the very first
      // record. Their behaviour is unchanged.
      final table = _fixtureBytes('status_EPGVersionInfoGet_broadcastingType4.bin');
      expect(parseEpgVersionServices(table), isEmpty);
      expect(parseSatelliteEpgVersionServices(table, csChannels()), isEmpty);
    });

    test('a truncated CS table enumerates only whole records', () {
      final table = _fixtureBytes('status_EPGVersionInfoGet_broadcastingType4.bin');
      // Header + 2 whole records + a partial third. The first
      // record is a data service (filtered out), the second is
      // ショップチャンネル; the partial record adds nothing.
      final cut = table.sublist(0, 12 + 80 * 2 + 40);
      final services = parseCsEpgVersionServices(cut, csChannels());
      expect(services, const [EpgServiceRef(6, 24704, 55)]);
    });
  });

  group('CS guide parsing', () {
    test('other-TS sections yield titled, genred events', () {
      final guide = parseEpgGuide(
        csSection(0x60),
        const [_csChannel],
        broadcastingType: 4,
      );
      final event = guide.services.single.events.single;
      expect(event.title, 'テレビ');
      expect(event.genreLevel1, 6);
      expect(event.genreLevel2, 0);
    });

    test('basic sections yield events as for the other bands', () {
      final guide = parseEpgGuide(
        csSection(0x50),
        const [_csChannel],
        broadcastingType: 4,
      );
      expect(guide.services.single.events.single.title, 'テレビ');
    });

    test('completion adds empty columns for video channels only', () {
      const noEvents = Channel(
        broadcastingType: 4,
        networkId: 6,
        transportStreamId: 24704,
        serviceId: 55,
        serviceType: 1,
        channelNumber: 55,
        serviceName: 'ショップチャンネル',
      );
      const dataService = Channel(
        broadcastingType: 4,
        networkId: 6,
        transportStreamId: 24608,
        serviceId: 1,
        serviceType: 165,
        channelNumber: 1,
        serviceName: '-',
      );
      final parsed = parseEpgGuide(
        csSection(0x60),
        const [_csChannel],
        broadcastingType: 4,
      );
      final completed = completeSatelliteEpgGuide(
        parsed,
        const [_csChannel, noEvents, dataService],
      );
      expect(completed.services, hasLength(2));
      expect(completed.services[0].channel, _csChannel);
      expect(completed.services[0].events, hasLength(1));
      expect(completed.services[1].channel, noEvents);
      expect(completed.services[1].events, isEmpty);
    });

    test('completion leaves a terrestrial guide untouched', () {
      const terrestrial = EpgGuide(broadcastingType: 2, services: []);
      expect(
        identical(completeSatelliteEpgGuide(terrestrial, const []), terrestrial),
        isTrue,
      );
    });
  });

  group('CS acquisition (service boundary)', () {
    test('verinfo -> EPGGet request -> completed CS guide', () async {
      final versionTable =
          _fixtureBytes('status_EPGVersionInfoGet_broadcastingType4.bin');
      late http.Request epgRequest;
      final client = MockClient((request) async {
        if (request.url.path == '/status/EPGVersionInfoGet') {
          return http.Response.bytes(versionTable, 200);
        }
        if (request.url.path == '/chEpg/EPGGet') {
          epgRequest = request;
          // One other-TS section for ムービープラス, wrapped the
          // way the device wraps it (zlib, then XOR).
          final zipped = ZLibEncoder().convert(csSection(0x60));
          return http.Response.bytes(
            zipped.map((b) => b ^ epgXorKey).toList(),
            200,
          );
        }
        return http.Response('', 404);
      });
      final service = WebApiEpgService(
        plain: WebApiTransport('192.0.2.1', client: client),
        authed: WebApiTransport(
          '192.0.2.1',
          client: client,
          tokenProvider: const TokenProvider('58daf0'),
        ),
      );

      final guide = await service.getProgrammeGuide(4, csChannels());
      expect(guide.broadcastingType, 4);
      // The request asks for every segment of all 54 video
      // services, both bitmaps set (the measured shape).
      expect(epgRequest.bodyBytes.length, 1304);
      expect(epgRequest.bodyBytes.sublist(4, 6), [0, 54]);
      // Completion: every video channel is a column, the one
      // with a section carries its event.
      expect(guide.services, hasLength(54));
      final moviePlus = guide.services.singleWhere(
        (s) => s.channel.serviceId == 240,
      );
      expect(moviePlus.events.single.title, 'テレビ');
      expect(
        guide.services.where((s) => s.events.isEmpty),
        hasLength(53),
      );
    });
  });

  group('programme guide screen', () {
    testWidgets('the CS segment shows the CS guide', (tester) async {
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
      final csGuide = EpgGuide(
        broadcastingType: 4,
        services: [
          EpgServiceGuide(
            channel: _csChannel,
            events: [
              EpgEvent(
                eventId: 1,
                start: now,
                duration: const Duration(minutes: 30),
                title: 'CS番組',
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
            epgGuideProvider.overrideWith(
              (ref, r) async =>
                  const EpgGuide(broadcastingType: 2, services: []),
            ),
            csEpgGuideProvider.overrideWith((ref, r) async => csGuide),
            channelLogosProvider.overrideWith(
              (ref, r) async => const <int, List<int>>{},
            ),
          ],
          child: const MaterialApp(home: EpgScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Terrestrial is selected first: no CS column yet.
      expect(find.text('ムービープラス'), findsNothing);
      await tester.tap(find.text('CS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('ムービープラス'), findsOneWidget);
      expect(find.text('CS番組'), findsOneWidget);
    });
  });
}
