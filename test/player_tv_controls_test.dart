/// TV player controls (plan 147), driven the way a remote
/// control drives them: key events only, no taps. The stock
/// media_kit Material controls answer pointer events only,
/// so the TV variant's own bar is pinned here instead —
/// raising it with the D-pad, walking its buttons, seeking
/// from the focused seek bar, the auto-hide, and the back
/// key putting the bar away before it leaves the screen.
/// The live programme button (user-fork addition,
/// 2026-11-26) is pinned here too: beside play/pause while
/// the viewing offers the programme actions, its face
/// following the programme's reservation state.
///
/// Playback itself is faked with stream controllers and
/// callback counters; nothing here opens a real player.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/ui/player_record_policy.dart';
import 'package:tmhb/ui/player_tv_controls.dart';
import 'package:tmhb/ui/player_tv_controls_policy.dart';

class _Fake {
  final playing = StreamController<bool>.broadcast();
  final position = StreamController<Duration>.broadcast();
  final duration = StreamController<Duration>.broadcast();
  final seekable = ValueNotifier<bool>(true);
  int toggles = 0;
  int plays = 0;
  int pauses = 0;
  int fullscreenToggles = 0;
  int programmeActions = 0;
  bool fullscreen = false;
  final List<Duration> skips = [];
  final List<bool> chapterSeeks = [];
  final List<Duration> seeks = [];

  Widget build({
    bool live = false,
    List<Duration> chapters = const [],
    bool withProgrammeAction = false,
    LiveProgrammeReservationState programmeState =
        LiveProgrammeReservationState.none,
    String title = 'テスト番組',
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TvVideoControls(
          playingStream: playing.stream,
          positionStream: position.stream,
          durationStream: duration.stream,
          initialPlaying: false,
          initialPosition: const Duration(seconds: 100),
          initialDuration: const Duration(seconds: 600),
          seekable: seekable,
          live: live,
          chapters: chapters,
          onTogglePlayPause: () => toggles++,
          onPlay: () => plays++,
          onPause: () => pauses++,
          onSkip: skips.add,
          onChapterSeek: chapterSeeks.add,
          onSeek: seeks.add,
          onToggleFullscreen: () => fullscreenToggles++,
          isFullscreen: () => fullscreen,
          title: title,
          onProgrammeAction: withProgrammeAction
              ? () => programmeActions++
              : null,
          programmeState: programmeState,
        ),
      ),
    );
  }
}

/// The IconButton a tooltip belongs to (the finder for a
/// tooltip lands on the Tooltip the button builds inside
/// itself, so the button is its ancestor).
IconButton buttonByTooltip(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );

void main() {
  testWidgets('hidden until a remote key raises the bar onto play/pause', (
    tester,
  ) async {
    final fake = _Fake();
    await tester.pumpWidget(fake.build());
    await tester.pump();

    expect(find.byTooltip('再生'), findsNothing);
    expect(find.byTooltip('10秒スキップ'), findsNothing);
    expect(find.byTooltip('全画面'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('再生'), findsOneWidget);
    expect(find.byTooltip('10秒戻し'), findsOneWidget);
    expect(find.byTooltip('10秒スキップ'), findsOneWidget);
    expect(find.byTooltip('全画面'), findsOneWidget);
    // The primary action holds focus (plan 134's rule): the
    // OK key presses it.
    final playButton = buttonByTooltip(tester, '再生');
    expect(playButton.focusNode?.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fake.toggles, 1);
  });

  testWidgets('the D-pad walks the row and OK works the skip buttons', (
    tester,
  ) async {
    final fake = _Fake();
    await tester.pumpWidget(fake.build());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();

    // Right from play/pause lands on +10 s.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fake.skips, [const Duration(seconds: 10)]);
    expect(fake.toggles, 0);

    // Left twice from +10 s crosses play/pause to -10 s.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fake.skips, [
      const Duration(seconds: 10),
      const Duration(seconds: -10),
    ]);
  });

  testWidgets('chapter buttons flank the skips when the title has points', (
    tester,
  ) async {
    final fake = _Fake();
    await tester.pumpWidget(
      fake.build(
        chapters: const [Duration(seconds: 60), Duration(seconds: 120)],
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('前のチャプター'), findsOneWidget);
    expect(find.byTooltip('次のチャプター'), findsOneWidget);

    // Left from play/pause crosses -10 s to the previous
    // chapter button.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fake.chapterSeeks, [false]);
    expect(fake.skips, isEmpty);
  });

  testWidgets('the focused seek bar seeks with left and right', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(fake.build());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();

    // Up from the button row reaches the seek bar.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    // From the position the screen handed in (100 s), by
    // the skip step, through the clamping policy.
    expect(fake.seeks, [
      const Duration(seconds: 110),
      const Duration(seconds: 90),
    ]);
    expect(fake.skips, isEmpty);
  });

  testWidgets('the bar hides after the delay and a key raises it again', (
    tester,
  ) async {
    final fake = _Fake();
    await tester.pumpWidget(fake.build());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('再生'), findsOneWidget);

    await tester.pump(tvControlsHideDelay);
    await tester.pump();
    expect(find.byTooltip('再生'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('再生'), findsOneWidget);
  });

  testWidgets('the back key puts the bar away instead of leaving', (
    tester,
  ) async {
    final fake = _Fake();
    await tester.pumpWidget(fake.build());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('再生'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byTooltip('再生'), findsNothing);
    expect(find.byType(TvVideoControls), findsOneWidget);
  });

  testWidgets('media keys act directly and raise the bar with them', (
    tester,
  ) async {
    final fake = _Fake();
    await tester.pumpWidget(fake.build());
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    await tester.pump();
    expect(fake.toggles, 1);
    // The bar came up; the icon still shows play because
    // the fake's playing stream has not reported a change.
    expect(find.byTooltip('再生'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.pump();
    expect(fake.skips, [const Duration(seconds: 10)]);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaRewind);
    await tester.pump();
    expect(fake.skips, [
      const Duration(seconds: 10),
      const Duration(seconds: -10),
    ]);
  });

  testWidgets('live: no seek row or skips, and up/down stay with zapping', (
    tester,
  ) async {
    final fake = _Fake();
    await tester.pumpWidget(fake.build(live: true));
    await tester.pump();

    // Down is the zap handler's key on live: the bar stays
    // down (the zap itself is the player screen's business
    // and not faked here).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byTooltip('再生'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('再生'), findsOneWidget);
    expect(find.byTooltip('全画面'), findsOneWidget);
    expect(find.byTooltip('10秒スキップ'), findsNothing);
    // No seek row: the position readout is part of it.
    expect(find.text('1:40'), findsNothing);
  });

  testWidgets('while the stream is not seekable the seek paths stay off', (
    tester,
  ) async {
    final fake = _Fake()..seekable.value = false;
    await tester.pumpWidget(fake.build());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();

    final skipButton = buttonByTooltip(tester, '10秒スキップ');
    expect(skipButton.onPressed, isNull);

    // The seek bar takes no focus: up from play/pause goes
    // nowhere, and right crosses the disabled skips to the
    // fullscreen button.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fake.seeks, isEmpty);
    expect(fake.skips, isEmpty);
    expect(fake.fullscreenToggles, 1);
  });

  testWidgets('the playing stream drives the play/pause icon', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(fake.build());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('再生'), findsOneWidget);

    fake.playing.add(true);
    await tester.pump();
    expect(find.byTooltip('一時停止'), findsOneWidget);
    expect(find.byTooltip('再生'), findsNothing);
  });

  testWidgets('live: the programme button beside play/pause records', (
    tester,
  ) async {
    final fake = _Fake();
    await tester.pumpWidget(fake.build(live: true, withProgrammeAction: true));
    // Left raises the bar on live (down belongs to zapping).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('録画'), findsOneWidget);

    // Right from play/pause lands on the programme button.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fake.programmeActions, 1);
    expect(fake.toggles, 0);
  });

  testWidgets('live: the programme button follows the reservation state', (
    tester,
  ) async {
    final recording = _Fake();
    await tester.pumpWidget(
      recording.build(
        live: true,
        withProgrammeAction: true,
        programmeState: LiveProgrammeReservationState.recording,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('録画停止'), findsOneWidget);
    expect(find.byTooltip('録画'), findsNothing);

    final reserved = _Fake();
    await tester.pumpWidget(
      reserved.build(
        live: true,
        withProgrammeAction: true,
        programmeState: LiveProgrammeReservationState.reserved,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('予約を取り消し'), findsOneWidget);
  });

  testWidgets('no programme button without an action, or on a recording', (
    tester,
  ) async {
    final liveNoAction = _Fake();
    await tester.pumpWidget(liveNoAction.build(live: true));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('全画面'), findsOneWidget);
    expect(find.byTooltip('録画'), findsNothing);

    final recording = _Fake();
    await tester.pumpWidget(recording.build(withProgrammeAction: true));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('全画面'), findsOneWidget);
    expect(find.byTooltip('録画'), findsNothing);
  });

  group('the title at the top of the picture (owner request 2026-11-28)', () {
    testWidgets('in fullscreen the OK key raises the title with the bar', (
      tester,
    ) async {
      final fake = _Fake()..fullscreen = true;
      await tester.pumpWidget(fake.build());
      await tester.pump();

      // The title is hidden with the controls.
      expect(find.text('テスト番組'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump();

      // The title rides at the top of the picture; the
      // transport bar at the bottom is as before.
      final title = find.text('テスト番組');
      expect(title, findsOneWidget);
      expect(tester.getRect(title).top, lessThan(80));
      expect(find.byTooltip('再生'), findsOneWidget);
      expect(find.byTooltip('全画面を終了'), findsOneWidget);
    });

    testWidgets('outside fullscreen the overlay stays out — the app bar '
        'already shows the title', (tester) async {
      final fake = _Fake();
      await tester.pumpWidget(fake.build());
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump();

      expect(find.text('テスト番組'), findsNothing);
      expect(find.byTooltip('再生'), findsOneWidget);
    });
  });
}
