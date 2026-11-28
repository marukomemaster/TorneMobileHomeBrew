/// TV remote key policy for the player controls (plan 147):
/// the matrix that decides what a remote key means, split
/// by whether the controls are up and whether the viewing
/// is live. The widget that carries the decisions out is
/// covered by player_tv_controls_test.dart.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/player_tv_controls_policy.dart';

void main() {
  TvRemoteKeyAction action({
    required bool visible,
    bool live = false,
    required LogicalKeyboardKey key,
  }) => tvRemoteKeyAction(controlsVisible: visible, live: live, key: key);

  group('while the controls are hidden', () {
    test('a D-pad key raises the controls on a recording', () {
      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.select,
        LogicalKeyboardKey.enter,
      ]) {
        expect(
          action(visible: false, key: key),
          TvRemoteKeyAction.showControls,
          reason: '$key',
        );
      }
    });

    test('on live viewing up and down stay with channel zapping', () {
      expect(
        action(visible: false, live: true, key: LogicalKeyboardKey.arrowUp),
        TvRemoteKeyAction.pass,
      );
      expect(
        action(visible: false, live: true, key: LogicalKeyboardKey.arrowDown),
        TvRemoteKeyAction.pass,
      );
      // The other navigation keys still raise the controls.
      expect(
        action(visible: false, live: true, key: LogicalKeyboardKey.arrowLeft),
        TvRemoteKeyAction.showControls,
      );
      expect(
        action(visible: false, live: true, key: LogicalKeyboardKey.select),
        TvRemoteKeyAction.showControls,
      );
    });

    test('the back key passes, so the system back leaves the screen', () {
      expect(
        action(visible: false, key: LogicalKeyboardKey.escape),
        TvRemoteKeyAction.pass,
      );
      expect(
        action(visible: false, key: LogicalKeyboardKey.goBack),
        TvRemoteKeyAction.pass,
      );
    });
  });

  group('while the controls are up', () {
    test('navigation keys only poke the hide timer', () {
      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.select,
        LogicalKeyboardKey.enter,
      ]) {
        expect(
          action(visible: true, key: key),
          TvRemoteKeyAction.poke,
          reason: '$key',
        );
      }
      // On live viewing too: once the bar is up, up and down
      // navigate it instead of zapping.
      expect(
        action(visible: true, live: true, key: LogicalKeyboardKey.arrowDown),
        TvRemoteKeyAction.poke,
      );
    });

    test('the back key hides the controls', () {
      expect(
        action(visible: true, key: LogicalKeyboardKey.escape),
        TvRemoteKeyAction.hideControls,
      );
      expect(
        action(visible: true, key: LogicalKeyboardKey.goBack),
        TvRemoteKeyAction.hideControls,
      );
    });
  });

  group('media keys act in either state', () {
    test('play/pause family', () {
      for (final visible in [false, true]) {
        expect(
          action(visible: visible, key: LogicalKeyboardKey.mediaPlayPause),
          TvRemoteKeyAction.togglePlayPause,
        );
        expect(
          action(visible: visible, key: LogicalKeyboardKey.space),
          TvRemoteKeyAction.togglePlayPause,
        );
        expect(
          action(visible: visible, key: LogicalKeyboardKey.mediaPlay),
          TvRemoteKeyAction.play,
        );
        expect(
          action(visible: visible, key: LogicalKeyboardKey.mediaPause),
          TvRemoteKeyAction.pause,
        );
        expect(
          action(visible: visible, key: LogicalKeyboardKey.mediaFastForward),
          TvRemoteKeyAction.skipForward,
        );
        expect(
          action(visible: visible, key: LogicalKeyboardKey.mediaRewind),
          TvRemoteKeyAction.skipBackward,
        );
      }
    });
  });

  test('unrelated keys pass in either state', () {
    for (final visible in [false, true]) {
      expect(
        action(visible: visible, key: LogicalKeyboardKey.keyA),
        TvRemoteKeyAction.pass,
      );
      expect(
        action(visible: visible, key: LogicalKeyboardKey.channelUp),
        TvRemoteKeyAction.pass,
      );
    }
  });

  test('only the acting actions claim the key event', () {
    for (final a in [
      TvRemoteKeyAction.showControls,
      TvRemoteKeyAction.hideControls,
      TvRemoteKeyAction.togglePlayPause,
      TvRemoteKeyAction.play,
      TvRemoteKeyAction.pause,
      TvRemoteKeyAction.skipForward,
      TvRemoteKeyAction.skipBackward,
    ]) {
      expect(tvRemoteKeyActionClaims(a), isTrue, reason: '$a');
    }
    // Poking must leave the event for the focus system —
    // claiming it would eat the D-pad navigation itself.
    expect(tvRemoteKeyActionClaims(TvRemoteKeyAction.poke), isFalse);
    expect(tvRemoteKeyActionClaims(TvRemoteKeyAction.pass), isFalse);
  });

  group('automatic fullscreen entry (owner request 2026-11-28)', () {
    test('the TV variant enters fullscreen as playback opens', () {
      expect(
        shouldAutoEnterFullscreen(
          tvVariant: true,
          alreadyFullscreen: false,
          alreadyRequested: false,
        ),
        isTrue,
      );
    });

    test('the standard variant never does', () {
      expect(
        shouldAutoEnterFullscreen(
          tvVariant: false,
          alreadyFullscreen: false,
          alreadyRequested: false,
        ),
        isFalse,
      );
    });

    test('already fullscreen, or already asked once, stays out', () {
      expect(
        shouldAutoEnterFullscreen(
          tvVariant: true,
          alreadyFullscreen: true,
          alreadyRequested: false,
        ),
        isFalse,
      );
      expect(
        shouldAutoEnterFullscreen(
          tvVariant: true,
          alreadyFullscreen: false,
          alreadyRequested: true,
        ),
        isFalse,
      );
    });
  });
}
