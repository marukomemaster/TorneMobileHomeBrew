/// Video decode mode (plan 139): how much of the video
/// decoding mpv may hand to the device's hardware decoder.
/// The escape hatch answers a Fire TV 4K Max (first
/// generation) field failure — the stream arrived in full
/// but the hardware MPEG-2 path never produced a picture.
/// These tests pin the policy (the stored form, the mpv
/// properties each mode sets, the video controller's
/// hardware acceleration), the notifier's persistence, and
/// the settings wiring, including the picker dialog's TV
/// initial focus (plan 134). The TV variant's unset default
/// is software — full software decoding: plan 139's unit
/// recovered with MPEG-2-only software, but the fork
/// owner's Fire OS 7 unit stayed black there because its
/// H.264 hardware path produces no picture either
/// (measured on the real device, 2026-11-28), so a
/// first-run TV viewer gets the way around without finding
/// the setting first; a stored mode still wins. The design
/// lives in ui/player_hwdec_policy.dart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/variant.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/player_hwdec_policy.dart';
import 'package:tmhb/ui/settings_screen.dart';

/// Lets the notifier's asynchronous restore / write-back settle.
Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

/// Whether the primary focus sits inside the widget [finder]
/// resolves to (the plan-134 test helper's shape).
bool focusIsInside(Finder finder) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final targets = finder.evaluate();
  if (targets.length != 1) return false;
  final target = targets.single;
  var inside = false;
  context.visitAncestorElements((element) {
    if (element == target) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

void main() {
  group('video hwdec policy', () {
    test('the modes are auto, mpeg2Software and software', () {
      expect(VideoHwdecMode.values, [
        VideoHwdecMode.auto,
        VideoHwdecMode.mpeg2Software,
        VideoHwdecMode.software,
      ]);
    });

    test('parse reads the stored enum name', () {
      expect(parseVideoHwdecMode('auto'), VideoHwdecMode.auto);
      expect(
        parseVideoHwdecMode('mpeg2Software'),
        VideoHwdecMode.mpeg2Software,
      );
      expect(parseVideoHwdecMode('software'), VideoHwdecMode.software);
    });

    test('parse falls back to auto for anything unknown', () {
      expect(parseVideoHwdecMode(null), VideoHwdecMode.auto);
      expect(parseVideoHwdecMode(''), VideoHwdecMode.auto);
      // The fork's stored form must not leak into this build:
      // its values were keyed differently and are not names
      // this build writes.
      expect(parseVideoHwdecMode('mpeg2_software'), VideoHwdecMode.auto);
      expect(parseVideoHwdecMode('AUTO'), VideoHwdecMode.auto);
    });

    test('parse honours a caller fallback for anything unknown', () {
      expect(
        parseVideoHwdecMode(null, fallback: VideoHwdecMode.mpeg2Software),
        VideoHwdecMode.mpeg2Software,
      );
      expect(
        parseVideoHwdecMode('junk', fallback: VideoHwdecMode.mpeg2Software),
        VideoHwdecMode.mpeg2Software,
      );
      // A stored name still wins over the fallback.
      expect(
        parseVideoHwdecMode('auto', fallback: VideoHwdecMode.mpeg2Software),
        VideoHwdecMode.auto,
      );
    });

    test('the unset default is auto except on TV', () {
      expect(defaultVideoHwdecMode(isTv: false), VideoHwdecMode.auto);
      // TV: full software — the fork owner's Fire OS 7 unit
      // produces no picture on the H.264 hardware path
      // either (2026-11-28), so MPEG-2-only software is
      // not enough there.
      expect(defaultVideoHwdecMode(isTv: true), VideoHwdecMode.software);
    });

    test('the MPEG-2-only codec list excludes mpeg2video only', () {
      final codecs = mpeg2SoftwareHwdecCodecs.split(',');
      expect(
        codecs,
        containsAll(['h264', 'hevc', 'mpeg4', 'vp8', 'vp9', 'av1']),
      );
      expect(codecs, isNot(contains('mpeg2video')));
      expect(mpeg2SoftwareHwdecCodecs, 'h264,hevc,mpeg4,vp8,vp9,av1');
    });

    test('only the MPEG-2-only mode sets hwdec-codecs', () {
      expect(hwdecCodecsPropertyFor(VideoHwdecMode.auto), isNull);
      expect(
        hwdecCodecsPropertyFor(VideoHwdecMode.mpeg2Software),
        mpeg2SoftwareHwdecCodecs,
      );
      expect(hwdecCodecsPropertyFor(VideoHwdecMode.software), isNull);
    });

    test('only the full software mode pins hwdec off', () {
      expect(hwdecPropertyFor(VideoHwdecMode.auto), isNull);
      expect(hwdecPropertyFor(VideoHwdecMode.mpeg2Software), isNull);
      expect(hwdecPropertyFor(VideoHwdecMode.software), 'no');
    });

    test('only the full software mode drops controller acceleration', () {
      expect(videoControllerHardwareAcceleration(VideoHwdecMode.auto), isTrue);
      expect(
        videoControllerHardwareAcceleration(VideoHwdecMode.mpeg2Software),
        isTrue,
      );
      expect(
        videoControllerHardwareAcceleration(VideoHwdecMode.software),
        isFalse,
      );
    });

    test('every mode has a label and a description', () {
      for (final mode in VideoHwdecMode.values) {
        expect(mode.shortLabel, isNotEmpty);
        expect(mode.description, isNotEmpty);
      }
      expect(VideoHwdecMode.auto.shortLabel, '自動');
      expect(VideoHwdecMode.mpeg2Software.shortLabel, 'MPEG-2 のみソフトウェア');
      expect(VideoHwdecMode.software.shortLabel, 'すべてソフトウェア');
    });
  });

  group('VideoHwdecModeNotifier persistence', () {
    late InMemoryKeyValueStore keyValues;

    setUp(() {
      keyValues = InMemoryKeyValueStore();
    });

    ProviderContainer makeContainer({
      AppVariant variant = AppVariant.standard,
    }) {
      final container = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(keyValues),
          appVariantProvider.overrideWithValue(variant),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('nothing stored means auto', () async {
      final container = makeContainer();
      container.read(videoHwdecModeProvider);
      await flush();
      expect(container.read(videoHwdecModeProvider), VideoHwdecMode.auto);
    });

    test('nothing stored means software on TV', () async {
      final container = makeContainer(variant: AppVariant.tv);
      container.read(videoHwdecModeProvider);
      await flush();
      expect(container.read(videoHwdecModeProvider), VideoHwdecMode.software);
    });

    test('a stored mode still wins on TV', () async {
      await keyValues.write('video_hwdec_mode', 'auto');
      final container = makeContainer(variant: AppVariant.tv);
      container.read(videoHwdecModeProvider);
      await flush();
      expect(container.read(videoHwdecModeProvider), VideoHwdecMode.auto);
    });

    test('an unknown stored value falls back to the TV default on TV', (
      ) async {
      await keyValues.write('video_hwdec_mode', 'everything');
      final container = makeContainer(variant: AppVariant.tv);
      container.read(videoHwdecModeProvider);
      await flush();
      expect(container.read(videoHwdecModeProvider), VideoHwdecMode.software);
    });

    test('a stored mode is restored', () async {
      await keyValues.write('video_hwdec_mode', 'mpeg2Software');
      final container = makeContainer();
      container.read(videoHwdecModeProvider);
      await flush();
      expect(
        container.read(videoHwdecModeProvider),
        VideoHwdecMode.mpeg2Software,
      );
    });

    test('an unknown stored value falls back to auto', () async {
      await keyValues.write('video_hwdec_mode', 'everything');
      final container = makeContainer();
      container.read(videoHwdecModeProvider);
      await flush();
      expect(container.read(videoHwdecModeProvider), VideoHwdecMode.auto);
    });

    test('set writes the mode name through to the store', () async {
      final container = makeContainer();
      final notifier = container.read(videoHwdecModeProvider.notifier);
      await notifier.set(VideoHwdecMode.software);
      expect(container.read(videoHwdecModeProvider), VideoHwdecMode.software);
      expect(await keyValues.read('video_hwdec_mode'), 'software');

      await notifier.set(VideoHwdecMode.auto);
      expect(container.read(videoHwdecModeProvider), VideoHwdecMode.auto);
      expect(await keyValues.read('video_hwdec_mode'), 'auto');
    });
  });

  group('settings screen video hwdec setting', () {
    Future<void> pumpSetting(
      WidgetTester tester,
      InMemoryKeyValueStore keyValues, {
      AppVariant variant = AppVariant.standard,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyValueStoreProvider.overrideWithValue(keyValues),
            appVariantProvider.overrideWithValue(variant),
          ],
          child: const MaterialApp(home: Scaffold(body: VideoHwdecSetting())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('auto is the default shown', (tester) async {
      await pumpSetting(tester, InMemoryKeyValueStore());
      expect(find.text('映像デコード方式'), findsWidgets);
      expect(find.text('自動'), findsOneWidget);
    });

    testWidgets('on TV, full software is the default shown', (tester) async {
      await pumpSetting(
        tester,
        InMemoryKeyValueStore(),
        variant: AppVariant.tv,
      );
      expect(find.text('すべてソフトウェア'), findsOneWidget);
    });

    testWidgets('a saved mode is the one shown', (tester) async {
      final keyValues = InMemoryKeyValueStore();
      await keyValues.write('video_hwdec_mode', 'software');
      await pumpSetting(tester, keyValues);
      await tester.pump();
      expect(find.text('すべてソフトウェア'), findsOneWidget);
    });

    testWidgets('picking a mode in the dialog persists it', (tester) async {
      final keyValues = InMemoryKeyValueStore();
      await pumpSetting(tester, keyValues);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(VideoHwdecSetting)),
      );

      await tester.tap(find.text('自動'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('MPEG-2 のみソフトウェア').last);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        container.read(videoHwdecModeProvider),
        VideoHwdecMode.mpeg2Software,
      );
      expect(await keyValues.read('video_hwdec_mode'), 'mpeg2Software');
      expect(find.text('MPEG-2 のみソフトウェア'), findsOneWidget);
    });

    testWidgets('cancelling the dialog changes nothing', (tester) async {
      final keyValues = InMemoryKeyValueStore();
      await pumpSetting(tester, keyValues);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(VideoHwdecSetting)),
      );

      await tester.tap(find.text('自動'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(container.read(videoHwdecModeProvider), VideoHwdecMode.auto);
      expect(await keyValues.read('video_hwdec_mode'), isNull);
    });

    testWidgets('on TV the picker opens with the current mode focused', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      await pumpSetting(
        tester,
        InMemoryKeyValueStore(),
        variant: AppVariant.tv,
      );

      await tester.tap(find.text('すべてソフトウェア'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // The focused row is the one for the mode in force
      // (software, the TV unset default): its ListTile
      // inside the dialog (plan 134).
      final softwareTile = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ListTile, 'すべてソフトウェア'),
      );
      expect(softwareTile, findsOneWidget);
      expect(focusIsInside(softwareTile), isTrue);
    });

    testWidgets('on the standard variant the picker opens unfocused', (
      tester,
    ) async {
      await pumpSetting(tester, InMemoryKeyValueStore());

      await tester.tap(find.text('自動'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      final autoTile = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ListTile, '自動'),
      );
      expect(focusIsInside(autoTile), isFalse);
    });
  });
}
