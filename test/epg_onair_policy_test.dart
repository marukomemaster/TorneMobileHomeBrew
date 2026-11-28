/// On-air emphasis policy tests (user-fork addition):
/// the interval test the guide grid and the ranking
/// screen's 放送中 tab share, the deepened tile colour,
/// and the frame composition with the reserved frame.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/epg_genre.dart';
import 'package:tmhb/ui/epg_onair_policy.dart';
import 'package:tmhb/ui/epg_reserved.dart';
import 'package:tmhb/ui/epg_screen.dart';

void main() {
  group('epgEventIsOnAir', () {
    final start = DateTime(2026, 11, 28, 19, 0);
    final end = DateTime(2026, 11, 28, 20, 0);

    test('inside the span is on air', () {
      expect(
        epgEventIsOnAir(start: start, end: end, now: DateTime(2026, 11, 28, 19, 30)),
        isTrue,
      );
    });

    test('the start instant itself is on air', () {
      expect(epgEventIsOnAir(start: start, end: end, now: start), isTrue);
    });

    test('the end instant is no longer on air', () {
      expect(epgEventIsOnAir(start: start, end: end, now: end), isFalse);
    });

    test('before the start and after the end are not on air', () {
      expect(
        epgEventIsOnAir(
          start: start,
          end: end,
          now: start.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(
        epgEventIsOnAir(
          start: start,
          end: end,
          now: end.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });
  });

  group('epgOnAirTileColor', () {
    const surface = Color(0xFFFFFFFF);
    const fallback = Color(0xFFE8E8E8);
    const accent = Color(0xFF0055CC);

    test('a genred tile is its genre tint, deepened past the resting tint', () {
      final onAir = epgOnAirTileColor(
        genreLevel1: 3,
        surface: surface,
        fallback: fallback,
        accent: accent,
      );
      final resting = epgGenreTileColor(
        genreLevel1: 3,
        surface: surface,
        fallback: fallback,
      );
      expect(onAir, isNot(resting));
      // The exact blend the policy documents.
      expect(
        onAir,
        Color.alphaBlend(
          epgGenreColor(3)!.withAlpha((epgOnAirTintStrength * 255).round()),
          surface,
        ),
      );
    });

    test('an ungenred tile takes the accent blend over the fallback', () {
      final onAir = epgOnAirTileColor(
        genreLevel1: null,
        surface: surface,
        fallback: fallback,
        accent: accent,
      );
      expect(
        onAir,
        Color.alphaBlend(
          accent.withAlpha((epgOnAirAccentTintStrength * 255).round()),
          fallback,
        ),
      );
      expect(onAir, isNot(fallback));
    });

    test('a genre without a colour takes the accent blend too', () {
      expect(
        epgOnAirTileColor(
          genreLevel1: 12,
          surface: surface,
          fallback: fallback,
          accent: accent,
        ),
        epgOnAirTileColor(
          genreLevel1: null,
          surface: surface,
          fallback: fallback,
          accent: accent,
        ),
      );
    });
  });

  group('epgTileFrame', () {
    const accent = Color(0xFF0055CC);

    test('neither reserved nor on air: no frame, as tiles have always '
        'painted', () {
      expect(
        epgTileFrame(reserved: false, onAir: false, onAirColor: accent),
        isNull,
      );
    });

    test('on air alone: the accent frame at the reserved width', () {
      final frame = epgTileFrame(
        reserved: false,
        onAir: true,
        onAirColor: accent,
      )!;
      final border = frame.border as Border;
      expect(border.top.color, accent);
      expect(border.top.width, epgReservedFrameWidth);
    });

    test('reserved alone: the reserved frame itself', () {
      expect(
        epgTileFrame(reserved: true, onAir: false, onAirColor: accent),
        epgReservedFrame(true),
      );
    });

    test('reserved and on air: the reserved frame wins', () {
      expect(
        epgTileFrame(reserved: true, onAir: true, onAirColor: accent),
        epgReservedFrame(true),
      );
    });
  });

  group('guide grid wiring', () {
    testWidgets('the on-air tile paints the deepened tint and the accent '
        'frame; a future tile of the same genre paints neither', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const reg = RegisteredNasne(
        host: '192.0.2.1',
        udn: 'uuid:test',
        friendlyName: 'nasne',
        macAddr: '00:11:22:33:44:55',
      );
      const channel = Channel(
        broadcastingType: 2,
        networkId: 0x1111,
        transportStreamId: 0x2222,
        serviceId: 0x3333,
        serviceType: 1,
        channelNumber: 1,
        serviceName: 'テスト局',
      );
      final now = DateTime.now().toUtc();
      final guide = EpgGuide(
        broadcastingType: 2,
        services: [
          EpgServiceGuide(
            channel: channel,
            events: [
              EpgEvent(
                eventId: 1,
                start: now.subtract(const Duration(minutes: 10)),
                duration: const Duration(minutes: 60),
                title: '放送中の番組',
                genreLevel1: 3,
              ),
              EpgEvent(
                eventId: 2,
                start: now.add(const Duration(hours: 2)),
                duration: const Duration(minutes: 60),
                title: 'これからの番組',
                genreLevel1: 3,
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
            epgGuideProvider.overrideWith((ref, r) async => guide),
            channelLogosProvider.overrideWith(
              (ref, r) async => const <int, List<int>>{},
            ),
          ],
          child: const MaterialApp(home: EpgScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      Material tileOf(String title) => tester.widget<Material>(
        find
            .ancestor(of: find.text(title), matching: find.byType(Material))
            .first,
      );
      BoxDecoration? frameOf(String title) {
        for (final element
            in find
                .ancestor(of: find.text(title), matching: find.byType(Container))
                .evaluate()) {
          final widget = element.widget as Container;
          if (widget.foregroundDecoration is BoxDecoration) {
            return widget.foregroundDecoration as BoxDecoration;
          }
        }
        return null;
      }

      final scheme = Theme.of(tester.element(find.text('放送中の番組'))).colorScheme;
      expect(
        tileOf('放送中の番組').color,
        epgOnAirTileColor(
          genreLevel1: 3,
          surface: scheme.surface,
          fallback: scheme.surfaceContainerHighest,
          accent: scheme.primary,
        ),
      );
      expect(
        tileOf('これからの番組').color,
        epgGenreTileColor(
          genreLevel1: 3,
          surface: scheme.surface,
          fallback: scheme.surfaceContainerHighest,
        ),
      );
      final onAirFrame = frameOf('放送中の番組');
      expect(onAirFrame, isNotNull);
      expect((onAirFrame!.border as Border).top.color, scheme.primary);
      expect(frameOf('これからの番組'), isNull);
    });
  });
}
