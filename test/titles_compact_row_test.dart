/// The recorded-titles list's compact rows (owner request
/// 2026-11-28, the official app's shape): a title that
/// would wrap over many lines is held to two, the
/// when-and-where line to one, and the row stays dense —
/// a long title must not stretch its row over its
/// neighbours.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/titles_screen.dart';

const _reg = RegisteredNasne(
  host: '192.0.2.1',
  udn: 'uuid:test',
  friendlyName: 'nasne',
  macAddr: '00:11:22:33:44:55',
);

/// A titles notifier serving one fixed, complete stage —
/// the override stand-in for the device-backed load.
class _StaticTitlesNotifier extends TitlesNotifier {
  _StaticTitlesNotifier(super.reg, this.titles);

  final List<RecordedTitle> titles;

  @override
  Stream<TitleListProgress> build() =>
      Stream.value(TitleListProgress(titles, complete: true));
}

Future<void> _pumpTitles(
  WidgetTester tester,
  List<RecordedTitle> titles,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        registrationStoreProvider.overrideWithValue(
          InMemoryRegistrationStore(const [_reg]),
        ),
        titlesProvider.overrideWith2(
          (reg) => _StaticTitlesNotifier(reg, titles),
        ),
        titleCountsProvider.overrideWith(
          (ref, reg) async => TitleCounts(titles.length, 3000),
        ),
        channelsProvider.overrideWith((ref, reg) async => <Channel>[]),
        titleThumbnailProvider.overrideWith((ref, key) async => null),
        credentialSummaryProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: TitlesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a long title stays within two lines and the row stays '
      'compact', (tester) async {
    final start = DateTime.parse('2026-11-28T09:29:00+09:00');
    await _pumpTitles(tester, [
      RecordedTitle(
        id: '1',
        title: 'ドキュメント72時間 都会の格闘技ジムで[解][字][再] '
            '選「格闘技とわたし」特別拡大版ディレクターズカット',
        scheduledStart: start,
        scheduledDurationSeconds: 30 * 60,
        channelName: 'NHK総合1・札幌',
        newFlag: true,
        copyCountRemaining: 10,
      ),
      RecordedTitle(
        id: '2',
        title: '短い番組',
        scheduledStart: start,
        scheduledDurationSeconds: 30 * 60,
        channelName: 'NHK総合1・札幌',
      ),
    ]);

    final rows = find.byType(ListTile);
    expect(rows, findsNWidgets(2));
    final longRow = tester.getSize(rows.at(0));
    final shortRow = tester.getSize(rows.at(1));

    // The long title's row is at most one extra title line
    // taller than the short title's — not the half-dozen
    // lines the unwrapped title used to take. The badges
    // (NEW, remaining copies) still ride along.
    expect(longRow.height, lessThanOrEqualTo(shortRow.height + 26));
    expect(longRow.height, lessThanOrEqualTo(84));
    expect(find.text('残り 10 回'), findsOneWidget);
  });
}
