/// TV remote operation of the screens the earlier TV
/// passes (plans 121/123/134) had not covered — the auto
/// record screens and the ranking screen (owner report
/// 2026-11-28: some screens answered only to touch). The
/// rule editor's fields are the TV text-field shell, the
/// display-only heads and tails of the two lists hold
/// focus at their edges, and the programme guide's tiles
/// take D-pad focus like every other row in the app.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/bs_epg_providers.dart';
import 'package:tmhb/app/cs_epg_providers.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/app/variant.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/auto_record_screen.dart';
import 'package:tmhb/ui/epg_screen.dart';
import 'package:tmhb/ui/ranking_screen.dart';
import 'package:tmhb/ui/tv_focus.dart';

const _reg = RegisteredNasne(
  host: '192.0.2.1',
  udn: 'uuid:test',
  friendlyName: 'nasne',
  macAddr: '00:11:22:33:44:55',
);

/// Presses the D-pad down key [times] times, letting each
/// focus move settle.
Future<void> _pressDown(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
  }
}

/// Whether [rect] intersects the test viewport.
bool _onScreen(WidgetTester tester, Rect rect) {
  final view = Rect.fromLTWH(
    0,
    0,
    tester.view.physicalSize.width / tester.view.devicePixelRatio,
    tester.view.physicalSize.height / tester.view.devicePixelRatio,
  );
  return rect.overlaps(view);
}

void main() {
  group('auto record rule editor on the TV variant', () {
    testWidgets('the fields are TV shells: no editable field, OK opens '
        'the editor, back closes it', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVariantProvider.overrideWithValue(AppVariant.tv),
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const []),
            ),
          ],
          child: const MaterialApp(home: AutoRecordRuleEditScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // No plain text field anywhere in the form: a plain
      // field would open the software keyboard on focus
      // and trap the remote (plan 123).
      expect(find.byType(AppTextField), findsNWidgets(2));
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditableText), findsNothing);

      // Focus the keyword shell and press OK: its edit
      // dialog opens, the way the remote drives it.
      final shell = find.descendant(
        of: find.byType(AppTextField).first,
        matching: find.byType(FocusableActionDetector),
      );
      final shellFocus = tester
          .widgetList<Focus>(
            find.descendant(of: shell, matching: find.byType(Focus)),
          )
          .map((widget) => widget.focusNode)
          .whereType<FocusNode>()
          .first;
      shellFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Back closes the dialog without applying anything.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      // OK again, type, confirm: the value lands in the
      // field and the dialog closes.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ドラマ');
      await tester.tap(find.text('決定'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('ドラマ'), findsOneWidget);
    });
  });

  group('auto record screen on the TV variant', () {
    testWidgets('D-pad traversal scrolls the list to its tail',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVariantProvider.overrideWithValue(AppVariant.tv),
          ],
          child: const MaterialApp(home: AutoRecordScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final tail = find.text('まだ履歴はありません。');
      // The log tail starts below the fold — so far down
      // the list has not even built it yet.
      expect(tail, findsNothing);

      await _pressDown(tester, 15);
      await tester.pumpAndSettle();

      // …and D-pad traversal brings it on screen: the
      // tail's anchor holds focus at the list's end.
      expect(tail, findsOneWidget);
      expect(_onScreen(tester, tester.getRect(tail)), isTrue);
    });
  });

  group('ranking screen on the TV variant', () {
    testWidgets('D-pad traversal scrolls the tendency list to its '
        'last section', (tester) async {
      tester.view.physicalSize = const Size(1280, 260);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVariantProvider.overrideWithValue(AppVariant.tv),
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const [_reg]),
            ),
            titlesProvider.overrideWith2(
              (reg) => _StaticTitlesNotifier(reg, [
                for (var i = 1; i <= 12; i++)
                  RecordedTitle(
                    id: '$i',
                    title: '番組$i',
                    channelName: 'テスト放送$i',
                    channel: ScheduleChannel(
                      broadcastingType: 2,
                      channelType: 0,
                      serviceId: i,
                    ),
                    genre: 'ニュース',
                  ),
              ]),
            ),
            schedulesProvider.overrideWith(
              (ref, reg) async => const <RecordSchedule>[],
            ),
            epgGuideProvider.overrideWith(
              (ref, reg) async =>
                  const EpgGuide(broadcastingType: 2, services: []),
            ),
            bsEpgGuideProvider.overrideWith(
              (ref, reg) async =>
                  const EpgGuide(broadcastingType: 3, services: []),
            ),
            csEpgGuideProvider.overrideWith(
              (ref, reg) async =>
                  const EpgGuide(broadcastingType: 4, services: []),
            ),
          ],
          child: const MaterialApp(home: RankingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // The screen opens on the 放送中 tab (added
      // 2026-11-28); switch to the tendency view first.
      await tester.tap(find.text('傾向'));
      await tester.pumpAndSettle();

      final lastSection = find.text('シリーズ別');
      // Below the fold: the list has not built it yet.
      expect(lastSection, findsNothing);

      await _pressDown(tester, 25);
      await tester.pumpAndSettle();

      // The rows are display-only; the row anchors are
      // what carry traversal (and the scroll) to the end.
      expect(lastSection, findsOneWidget);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      // Traversal walked the list to (within a row of)
      // its very end.
      expect(
        position.pixels,
        greaterThan(position.maxScrollExtent - 60),
      );
    });

    testWidgets('the on-air tab opens the screen: cards for the top '
        'three, a row for the fourth, and a card opens the detail', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      EpgGuide guideWith(int serviceId, String title) => EpgGuide(
        broadcastingType: 2,
        services: [
          EpgServiceGuide(
            channel: Channel(
              broadcastingType: 2,
              networkId: 1,
              transportStreamId: 1,
              serviceId: serviceId,
              serviceType: 1,
              channelNumber: serviceId,
              serviceName: 'テスト放送$serviceId',
            ),
            events: [
              EpgEvent(
                eventId: serviceId,
                start: now.subtract(const Duration(minutes: 10)),
                duration: const Duration(minutes: 60),
                title: title,
              ),
            ],
          ),
        ],
      );
      // Four channels on air at once; the recorded
      // series match puts 一位の番組 first whatever the
      // wall clock says about prime time.
      final guide = EpgGuide(
        broadcastingType: 2,
        services: [
          for (final (serviceId, title) in [
            (1, '一位の番組'),
            (2, '二位の番組'),
            (3, '三位の番組'),
            (4, '四位の番組'),
          ])
            guideWith(serviceId, title).services.single,
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVariantProvider.overrideWithValue(AppVariant.tv),
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const [_reg]),
            ),
            titlesProvider.overrideWith2(
              (reg) => _StaticTitlesNotifier(reg, [
                RecordedTitle(
                  id: '1',
                  title: '一位の番組',
                  channelName: 'テスト放送1',
                  channel: ScheduleChannel(
                    broadcastingType: 2,
                    channelType: 0,
                    serviceId: 1,
                  ),
                  genre: 'ニュース',
                ),
              ]),
            ),
            schedulesProvider.overrideWith(
              (ref, reg) async => const <RecordSchedule>[],
            ),
            epgGuideProvider.overrideWith((ref, reg) async => guide),
            bsEpgGuideProvider.overrideWith(
              (ref, reg) async =>
                  const EpgGuide(broadcastingType: 3, services: []),
            ),
            csEpgGuideProvider.overrideWith(
              (ref, reg) async =>
                  const EpgGuide(broadcastingType: 4, services: []),
            ),
            channelLogosProvider.overrideWith(
              (ref, reg) async => const <int, List<int>>{},
            ),
            bsChannelLogosProvider.overrideWith(
              (ref, reg) async => const <int, List<int>>{},
            ),
            deviceServicesProvider.overrideWith((ref, r) => _stubServices()),
          ],
          child: const MaterialApp(home: RankingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // The opening view is the on-air ranking: the
      // series match leads, the top three carry the
      // 放送中 badge, and the fourth is a compact row.
      expect(find.text('一位の番組'), findsOneWidget);
      expect(find.text('放送中', skipOffstage: false), findsNWidgets(4));
      expect(find.text('四位の番組', skipOffstage: false), findsOneWidget);

      await tester.tap(find.text('一位の番組'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('programme guide on the TV variant', () {
    testWidgets('D-pad focus reaches a tile and OK opens its detail; '
        'back closes the detail', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final start = DateTime.now().add(const Duration(minutes: 30));
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
                title: 'これからの番組',
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVariantProvider.overrideWithValue(AppVariant.tv),
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const [_reg]),
            ),
            epgGuideProvider.overrideWith((ref, r) async => guide),
            channelLogosProvider.overrideWith(
              (ref, r) async => const <int, List<int>>{},
            ),
            deviceServicesProvider.overrideWith(
              (ref, r) => _stubServices(),
            ),
          ],
          child: const MaterialApp(home: EpgScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final tileText = find.text('これからの番組');
      expect(tileText, findsOneWidget);
      final tileRect = tester.getRect(
        find.ancestor(of: tileText, matching: find.byType(InkWell)),
      );

      // Walk the D-pad down until the focused widget sits
      // on the tile.
      var focused = false;
      for (var i = 0; i < 20 && !focused; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        final focusContext = FocusManager.instance.primaryFocus?.context;
        final box = focusContext?.findRenderObject();
        if (box is RenderBox && box.hasSize) {
          final centre = box.localToGlobal(box.size.center(Offset.zero));
          focused = tileRect.contains(centre);
        }
      }
      expect(focused, isTrue, reason: 'the tile never took D-pad focus');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      // The detail dialog the tap opens, with its
      // reservation action.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('録画予約'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}

const _channel = Channel(
  broadcastingType: 2,
  networkId: 0x1111,
  transportStreamId: 0x2222,
  serviceId: 0x3333,
  serviceType: 1,
  serviceName: 'テスト局',
  channelNumber: 1,
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

DeviceServices _stubServices() => DeviceServices(
  deviceInfo: _StubDeviceInfo(),
  settings: _StubSettings(),
  schedules: _StubSchedules(),
  titles: _StubTitles(),
  metadata: _StubMetadata(),
  live: _StubLive(),
  playback: const UnsupportedPlaybackEngine(),
);

/// A service the guide never calls in these tests; any
/// call is a test bug, so it throws.
class _Unused {
  static Never call(Invocation invocation) =>
      throw UnimplementedError('unused stub: $invocation');
}

class _StubSchedules implements ScheduleService {
  @override
  Future<List<RecordSchedule>> listSchedules({
    int startingIndex = 0,
    int requestedCount = 50,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => _Unused.call(invocation);
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
