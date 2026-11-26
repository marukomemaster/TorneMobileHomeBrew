/// Regression coverage for BS EPG service version tables with
/// variable-length records and for missing EIT.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

Channel bs(int sid, {int tsid = 0x4422, int serviceType = 1}) => Channel(
  broadcastingType: 3,
  networkId: 4,
  transportStreamId: tsid,
  serviceId: sid,
  serviceType: serviceType,
  channelNumber: sid,
  serviceName: 'BS $sid',
);

/// Lays out (serviceId, flags) records back to back at their
/// flags-derived lengths (plan 136), with the shared network / TS
/// ids of [bs] and the header count set to the record count.
List<int> packedTable(List<(int, int)> records, {int tsid = 0x4422}) {
  final out = <int>[];
  final header = List.filled(12, 0);
  header[8] = records.length >> 8;
  header[9] = records.length & 0xff;
  out.addAll(header);
  for (final (sid, flags) in records) {
    out.addAll([
      0, 4,
      tsid >> 8, tsid & 0xff,
      sid >> 8, sid & 0xff,
      flags >> 8, flags & 0xff,
    ]);
    final blocks =
        (flags & 0x8000 != 0 ? 1 : 0) + (flags & 0x4000 != 0 ? 1 : 0);
    out.addAll(List.filled(68 * blocks, 0));
  }
  return out;
}

void main() {
  test('BS scanner walks variable-length records to later video services',
      () {
    // A block-less record and a basic-only record sit between
    // video services; the walk steps over them at their own
    // lengths instead of at fixed 144-byte strides.
    final table = packedTable(const [
      (193, 0xc000),
      (700, 0x0000), // no EPG; not a channel either
      (244, 0x8000),
      (999, 0xc000), // not in channelListGet
      (191, 0xc000),
    ]);
    final channels = [bs(191), bs(193), bs(244), bs(245)];
    expect(parseSatelliteEpgVersionServices(table, channels), const [
      EpgServiceRef(4, 0x4422, 193),
      EpgServiceRef(4, 0x4422, 244, hasExtended: false),
      EpgServiceRef(4, 0x4422, 191),
    ]);
    // The terrestrial enumeration reads every record with a block,
    // including the one that is not a channel here.
    expect(parseEpgVersionServices(table), const [
      EpgServiceRef(4, 0x4422, 193),
      EpgServiceRef(4, 0x4422, 244, hasExtended: false),
      EpgServiceRef(4, 0x4422, 999),
      EpgServiceRef(4, 0x4422, 191),
    ]);
    expect(
        buildEpgGetBody(parseSatelliteEpgVersionServices(table, channels))
            .length,
        8 + 24 * 3);
  });

  test('BS scanner stops at a record with unknown flag bits', () {
    // Measured satellite tables carry only 0x0000 / 0x8000 /
    // 0xc000 flags. A record whose length cannot be derived ends
    // the walk rather than misaligning it (plan 136).
    final table = packedTable(const [
      (193, 0xc000),
      (244, 0xa000), // 0x2000 is not understood
      (191, 0xc000),
    ]);
    expect(
        parseSatelliteEpgVersionServices(table, [bs(191), bs(193), bs(244)]),
        const [EpgServiceRef(4, 0x4422, 193)]);
  });

  test('BS scanner on the measured Sony satellite layout finds all 39',
      () {
    // Flags sequence of the captured 6,672-byte satellite tables
    // (plan 116): 42 full records, then a tail of block-less and
    // basic-only records and two more full records. All 39 video
    // services sit in the leading full records.
    final flagsSeq = <int>[
      for (var i = 0; i < 42; i++) 0xc000,
      for (var i = 0; i < 7; i++) 0x0000,
      0x8000,
      for (var i = 0; i < 5; i++) 0x0000,
      0x8000, 0x8000,
      0xc000, 0xc000,
    ];
    final records = <(int, int)>[];
    var video = 0;
    for (var i = 0; i < flagsSeq.length; i++) {
      final flags = flagsSeq[i];
      final sid =
          (flags != 0 && video < 39 && i < 42) ? 101 + video++ : 700 + i;
      records.add((sid, flags));
    }
    final table = packedTable(records);
    expect(table.length, 6672);
    final channels = [for (var s = 101; s < 140; s++) bs(s)];
    final result = parseSatelliteEpgVersionServices(table, channels);
    expect(result.map((r) => r.serviceId),
        [for (var s = 101; s < 140; s++) s]);
    // The terrestrial enumeration sees all 47 records with blocks.
    expect(parseEpgVersionServices(table).length, 47);
  });

  test('BS all channel columns stay visible, but missing EIT remains empty', () {
    final channels = [bs(191), bs(192), bs(193), bs(244)];
    final original = EpgGuide(broadcastingType: 3, services: [
      EpgServiceGuide(channel: channels.first, events: const []),
    ]);
    final completed = completeSatelliteEpgGuide(original, channels);
    expect(completed.services.map((s) => s.channel.serviceId),
        [191, 192, 193, 244]);
    expect(completed.eventCount, 0);
    expect(completed.services[2].events, isEmpty);
    expect(completed.services[3].events, isEmpty);
  });

  test('terrestrial guide is unchanged by the BS coverage helper', () {
    final original = EpgGuide(broadcastingType: 2, services: const []);
    expect(identical(completeSatelliteEpgGuide(original, [bs(193)]), original), isTrue);
  });

  test('BS scanner ignores bogus triples and non-video channels', () {
    final table = packedTable(const [
      (193, 0xc000),
      (244, 0x8000),
    ]);
    final result = parseSatelliteEpgVersionServices(
        table, [bs(193, serviceType: 192), bs(244)]);
    expect(result, const [
      EpgServiceRef(4, 0x4422, 244, hasExtended: false),
    ]);
  });
}
