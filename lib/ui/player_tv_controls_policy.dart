/// TV player controls policy (plan 147): what a remote
/// control key means for the TV variant's player controls.
///
/// The stock media_kit Material controls — what
/// AdaptiveVideoControls selects on Android — toggle their
/// visibility from pointer events only and hold no key
/// handling at all, so on a TV, where the remote produces
/// nothing but key events, the transport UI never appears
/// and its buttons never enter the tree to take focus. The
/// TV variant therefore carries its own controls
/// (player_tv_controls.dart); this file decides, purely,
/// what each key does to them, so the matrix is testable
/// without a widget tree.
library;

import 'package:flutter/services.dart';

/// How long the TV controls stay up after the last remote
/// key. Longer than the stock controls' pointer hover
/// duration (3 s): D-pad travel across a button row takes
/// several presses with pauses between them, and the timer
/// restarts on every key the controls care about, so only
/// true inactivity hides them.
const Duration tvControlsHideDelay = Duration(seconds: 5);

/// What one remote key asks of the TV player controls.
enum TvRemoteKeyAction {
  /// The controls are hidden: bring them up.
  showControls,

  /// The controls are up: put them away (the remote's back
  /// key). With the controls hidden the same key passes, so
  /// the system back leaves the screen as usual.
  hideControls,

  /// Play/pause media key (or space): toggle playback. The
  /// controls come up with it when hidden, and the hide
  /// timer restarts when they are already up.
  togglePlayPause,

  /// Play media key: start playback (same visibility
  /// handling as [togglePlayPause]).
  play,

  /// Pause media key: pause playback (same visibility
  /// handling as [togglePlayPause]).
  pause,

  /// Fast-forward media key: skip ahead by the recorded
  /// screen's skip step (same visibility handling as
  /// [togglePlayPause]).
  skipForward,

  /// Rewind media key: skip back by the skip step (same
  /// visibility handling as [togglePlayPause]).
  skipBackward,

  /// A navigation key while the controls are up: the focus
  /// system moves within the bar; the controls only restart
  /// their hide timer.
  poke,

  /// Not the controls' business: the zap handler, the
  /// focus system or the system back takes it.
  pass,
}

/// Decides what [key] means for the TV player controls,
/// given whether they are currently [controlsVisible] and
/// whether the viewing is [live].
///
/// On live viewing the up / down keys belong to channel
/// zapping (the player screen's own key handler) while the
/// controls are hidden, so they pass; once the controls
/// are up they are ordinary navigation and only poke.
TvRemoteKeyAction tvRemoteKeyAction({
  required bool controlsVisible,
  required bool live,
  required LogicalKeyboardKey key,
}) {
  if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
    return controlsVisible
        ? TvRemoteKeyAction.hideControls
        : TvRemoteKeyAction.pass;
  }
  if (key == LogicalKeyboardKey.mediaPlayPause ||
      key == LogicalKeyboardKey.space) {
    return TvRemoteKeyAction.togglePlayPause;
  }
  if (key == LogicalKeyboardKey.mediaPlay) return TvRemoteKeyAction.play;
  if (key == LogicalKeyboardKey.mediaPause) return TvRemoteKeyAction.pause;
  if (key == LogicalKeyboardKey.mediaFastForward) {
    return TvRemoteKeyAction.skipForward;
  }
  if (key == LogicalKeyboardKey.mediaRewind) {
    return TvRemoteKeyAction.skipBackward;
  }
  if (key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    if (controlsVisible) return TvRemoteKeyAction.poke;
    if (live &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      return TvRemoteKeyAction.pass;
    }
    return TvRemoteKeyAction.showControls;
  }
  return TvRemoteKeyAction.pass;
}

/// Whether the controls claim the key event for [action],
/// keeping it from the focus system and the platform's
/// default handling (a claimed back key must not also pop
/// the screen). Poking and passing leave the event alone:
/// poking is how D-pad navigation reaches the focused
/// control in the first place.
bool tvRemoteKeyActionClaims(TvRemoteKeyAction action) => switch (action) {
  TvRemoteKeyAction.showControls ||
  TvRemoteKeyAction.hideControls ||
  TvRemoteKeyAction.togglePlayPause ||
  TvRemoteKeyAction.play ||
  TvRemoteKeyAction.pause ||
  TvRemoteKeyAction.skipForward ||
  TvRemoteKeyAction.skipBackward => true,
  TvRemoteKeyAction.poke || TvRemoteKeyAction.pass => false,
};

/// Whether the player screen should put the video into
/// fullscreen on its own as playback opens (owner request
/// 2026-11-28: on the TV, playback should simply start
/// fullscreen — reaching for the bar's fullscreen button
/// first is one step too many). TV variant only, only
/// until it has been asked for once (the viewer who
/// leaves fullscreen by hand is not dragged back), and
/// never when the video is already fullscreen.
bool shouldAutoEnterFullscreen({
  required bool tvVariant,
  required bool alreadyFullscreen,
  required bool alreadyRequested,
}) => tvVariant && !alreadyFullscreen && !alreadyRequested;
