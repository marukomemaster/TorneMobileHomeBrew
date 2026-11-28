/// Player controls for the TV variant (plan 147).
///
/// The stock media_kit Material controls — what
/// AdaptiveVideoControls selects on Android — show and hide
/// from pointer events only: their visibility toggles in a
/// pointer-down listener, they hold no key handling at all
/// (the keyboard shortcuts live in the desktop controls
/// only), and the seek bar and button bars exist in the
/// tree only while the controls are mounted as visible. A
/// remote control produces nothing but key events, so on a
/// TV the transport UI never appears and focus can never
/// reach it — the Fire TV field report behind this plan:
/// no seek bar, no ±10 s skip buttons, no fullscreen
/// button, and §140's adb key events could not raise the
/// bar either, for the same reason.
///
/// The TV variant therefore builds its own controls here,
/// remote-first:
///
///  * While hidden, a hardware key handler (the same shape
///    as the player screen's zap handler) watches for
///    remote keys and brings the controls up; what each key
///    means is player_tv_controls_policy's decision.
///  * The bar that comes up is a focus scope of ordinary
///    buttons: the play/pause button takes focus first
///    (the primary action, as dialogs do on TV — plan 134),
///    the D-pad walks the row, and the seek bar, when
///    focused, seeks with left / right. A parking focus
///    node holds focus while the controls are hidden, so
///    focus never wanders onto the app bar behind them.
///  * The controls hide again after [tvControlsHideDelay]
///    with no key press, or at once on the back key; the
///    hide returns focus to the parking node. A system back
///    that arrives as a pop instead of a key event is
///    caught by the [PopScope] guard and hides the
///    controls first, the way TV players treat back.
///  * Media keys (play / pause / fast-forward / rewind)
///    act directly, with the controls coming up alongside.
///  * In fullscreen, the heading rides at the top of the
///    picture while the controls are up: fullscreen has
///    no app bar to show what is playing, so the OK key
///    that raises the controls raises the title with
///    them (owner request 2026-11-28).
///
/// The standard variant never builds this widget: it keeps
/// the stock adaptive controls exactly as before.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'player_record_policy.dart';
import 'player_seek_policy.dart';
import 'player_tv_controls_policy.dart';

/// The video controls the TV variant shows over the video:
/// a bottom transport bar raised and driven by the remote
/// (see the library comment). Everything playback-shaped is
/// handed in as streams and callbacks by the player screen,
/// so the widget itself holds only presentation state —
/// visibility, the hide timer, and the latest stream
/// values it displays.
class TvVideoControls extends StatefulWidget {
  const TvVideoControls({
    super.key,
    required this.playingStream,
    required this.positionStream,
    required this.durationStream,
    required this.initialPlaying,
    required this.initialPosition,
    required this.initialDuration,
    required this.seekable,
    required this.live,
    required this.chapters,
    required this.onTogglePlayPause,
    required this.onPlay,
    required this.onPause,
    required this.onSkip,
    required this.onChapterSeek,
    required this.onSeek,
    required this.onToggleFullscreen,
    required this.isFullscreen,
    required this.title,
    this.onProgrammeAction,
    this.programmeState = LiveProgrammeReservationState.none,
  });

  /// The player's playing / position / duration streams,
  /// with the matching state values at build time (the
  /// streams report changes, not a starting value).
  final Stream<bool> playingStream;
  final Stream<Duration> positionStream;
  final Stream<Duration> durationStream;
  final bool initialPlaying;
  final Duration initialPosition;
  final Duration initialDuration;

  /// The seekable signal the skip buttons and the seek bar
  /// follow, exactly as the stock rows' buttons do: while
  /// it is false they stay disabled.
  final ValueListenable<bool> seekable;

  /// Live viewing: no seek bar, no skip or chapter buttons,
  /// and the up / down keys stay with channel zapping while
  /// the controls are hidden (see the policy).
  final bool live;

  /// The recording's chapter points: the chapter buttons
  /// join the row and the seek bar draws a tick per point.
  /// Empty keeps both out.
  final List<Duration> chapters;

  /// Play/pause toggle for the centre button and the
  /// play/pause media key.
  final VoidCallback onTogglePlayPause;

  /// The play and pause media keys.
  final VoidCallback onPlay;
  final VoidCallback onPause;

  /// A ±10 s skip (the buttons and the fast-forward /
  /// rewind media keys), by offset from the position.
  final void Function(Duration offset) onSkip;

  /// A chapter skip, forward or back.
  final void Function(bool forward) onChapterSeek;

  /// An absolute seek (the seek bar's left / right steps,
  /// already clamped by player_seek_policy).
  final void Function(Duration target) onSeek;

  /// The fullscreen button.
  final VoidCallback onToggleFullscreen;

  /// Whether the video is currently fullscreen, read at
  /// build time for the fullscreen button's icon.
  final bool Function() isFullscreen;

  /// The heading the player screen's app bar shows — a
  /// recording's title, or the channel being watched.
  /// While the controls are up in fullscreen it is shown
  /// again at the top of the picture (owner request
  /// 2026-11-28): fullscreen has no app bar, so the OK
  /// key raising the controls is also how the viewer
  /// asks what is playing. Outside fullscreen the app
  /// bar already carries it, so the overlay stays out.
  final String title;

  /// Works on the programme now on air (live viewing
  /// only; user-fork addition, 2026-11-26): the player
  /// screen's programme action for the channel being
  /// watched — recording it, or stopping it, following
  /// [programmeState]. Null — recordings, and live
  /// viewing whose channel carries no programme actions
  /// — keeps the button out of the row. A press while a
  /// record or stop is already in flight is held back by
  /// the screen's own gate, so the button itself never
  /// disables.
  final VoidCallback? onProgrammeAction;

  /// The reservation state of the programme being
  /// watched, read at build time for the programme
  /// button's label and icon (see player_record_policy):
  /// the screen refreshes it as the state is reported,
  /// and these controls rebuild with the screen.
  final LiveProgrammeReservationState programmeState;

  @override
  State<TvVideoControls> createState() => _TvVideoControlsState();
}

class _TvVideoControlsState extends State<TvVideoControls> {
  bool _visible = false;
  Timer? _hideTimer;
  late bool _playing = widget.initialPlaying;
  late Duration _position = widget.initialPosition;
  late Duration _duration = widget.initialDuration;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Where focus rests while the controls are hidden: an
  /// inert node that only holds the place, skipped by
  /// traversal, so the D-pad cannot wander from it onto
  /// the app bar behind the video.
  final FocusNode _parkingFocusNode = FocusNode(
    debugLabel: 'TvControlsParking',
    skipTraversal: true,
  );

  /// The play/pause button's node: showing the controls
  /// asks it for focus, putting the remote on the primary
  /// action (plan 134's dialog rule, applied to the bar).
  final FocusNode _playFocusNode = FocusNode(debugLabel: 'TvControlsPlay');

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _subscriptions.add(
      widget.playingStream.listen((playing) {
        if (mounted && playing != _playing) {
          setState(() => _playing = playing);
        }
      }),
    );
    _subscriptions.add(
      widget.positionStream.listen((position) {
        if (mounted) setState(() => _position = position);
      }),
    );
    _subscriptions.add(
      widget.durationStream.listen((duration) {
        if (mounted) setState(() => _duration = duration);
      }),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _hideTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _parkingFocusNode.dispose();
    _playFocusNode.dispose();
    super.dispose();
  }

  /// The remote's keys while this screen is the current
  /// route. The decision is the policy's; this handler
  /// only carries it out and reports whether the key was
  /// claimed (see tvRemoteKeyActionClaims).
  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final action = tvRemoteKeyAction(
      controlsVisible: _visible,
      live: widget.live,
      key: event.logicalKey,
    );
    switch (action) {
      case TvRemoteKeyAction.showControls:
        _show();
      case TvRemoteKeyAction.hideControls:
        _hide();
      case TvRemoteKeyAction.togglePlayPause:
        widget.onTogglePlayPause();
        _showOrPoke();
      case TvRemoteKeyAction.play:
        widget.onPlay();
        _showOrPoke();
      case TvRemoteKeyAction.pause:
        widget.onPause();
        _showOrPoke();
      case TvRemoteKeyAction.skipForward:
        widget.onSkip(skipSeekStep);
        _showOrPoke();
      case TvRemoteKeyAction.skipBackward:
        widget.onSkip(-skipSeekStep);
        _showOrPoke();
      case TvRemoteKeyAction.poke:
        _restartHideTimer();
      case TvRemoteKeyAction.pass:
        break;
    }
    return tvRemoteKeyActionClaims(action);
  }

  /// Brings the controls up and puts the remote on the
  /// play/pause button once the bar has mounted.
  void _show() {
    _restartHideTimer();
    if (_visible) return;
    setState(() => _visible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visible) _playFocusNode.requestFocus();
    });
  }

  /// A media key acted while the controls were up or down:
  /// up stays up with a fresh timer, down comes up.
  void _showOrPoke() {
    if (_visible) {
      _restartHideTimer();
    } else {
      _show();
    }
  }

  /// Puts the controls away and returns focus to the
  /// parking node once the bar has unmounted.
  void _hide() {
    _hideTimer?.cancel();
    if (!_visible) return;
    setState(() => _visible = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_visible) _parkingFocusNode.requestFocus();
    });
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(tvControlsHideDelay, () {
      if (mounted) _hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_visible,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _hide();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The parking place for focus while the controls
          // are hidden (see _parkingFocusNode). It draws
          // nothing and takes no pointer input; the remote
          // reaches the controls through the key handler.
          Focus(
            focusNode: _parkingFocusNode,
            autofocus: true,
            child: const SizedBox.expand(),
          ),
          // The title at the top of the picture, up and
          // down with the controls — in fullscreen only,
          // where no app bar shows it (see [title]).
          if (_visible && widget.isFullscreen())
            Positioned(left: 0, right: 0, top: 0, child: _buildTitleBar()),
          if (_visible)
            Positioned(left: 0, right: 0, bottom: 0, child: _buildBar()),
        ],
      ),
    );
  }

  /// The title bar at the top of the picture: the heading
  /// on a scrim that fades into the video, the mirror of
  /// the transport bar's. Display only — it takes no
  /// focus and no pointer input, so D-pad traversal in
  /// the bar below is exactly as before.
  Widget _buildTitleBar() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 20, 32, 36),
        child: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// The transport bar: the seek row over the button row,
  /// on a scrim that fades into the video. A focus scope
  /// keeps D-pad traversal inside the bar while it is up.
  Widget _buildBar() {
    return FocusScope(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 36, 32, 20),
          child: ValueListenableBuilder<bool>(
            valueListenable: widget.seekable,
            builder: (context, seekable, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.live) _buildSeekRow(seekable),
                _buildButtonRow(seekable),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Position, the seek bar, and the duration. The bar is
  /// focusable only while the stream is seekable and its
  /// length is known; otherwise it still draws the
  /// position, like the disabled skip buttons draw theirs.
  Widget _buildSeekRow(bool seekable) {
    const textStyle = TextStyle(color: Colors.white, fontSize: 14);
    return Row(
      children: [
        Text(_clock(_position), style: textStyle),
        const SizedBox(width: 12),
        Expanded(
          child: _TvSeekBar(
            position: _position,
            duration: _duration,
            enabled: seekable && _duration > Duration.zero,
            chapters: widget.chapters,
            onSeek: widget.onSeek,
          ),
        ),
        const SizedBox(width: 12),
        Text(_clock(_duration), style: textStyle),
      ],
    );
  }

  /// The button row: chapter and ±10 s skips flanking
  /// play/pause for recordings (the stock Material row's
  /// arrangement); for live, the programme button beside
  /// play/pause while the viewing offers one; and the
  /// fullscreen button at the right end in both. Skips
  /// follow the seekable signal, disabled and dimmed
  /// while the stream is not seekable.
  Widget _buildButtonRow(bool seekable) {
    return Row(
      children: [
        if (!widget.live && widget.chapters.isNotEmpty)
          IconButton(
            tooltip: '前のチャプター',
            iconSize: 36,
            color: Colors.white,
            onPressed: seekable ? () => widget.onChapterSeek(false) : null,
            icon: const Icon(Icons.fast_rewind),
          ),
        if (!widget.live)
          IconButton(
            tooltip: '10秒戻し',
            iconSize: 36,
            color: Colors.white,
            onPressed: seekable ? () => widget.onSkip(-skipSeekStep) : null,
            icon: const Icon(Icons.replay_10),
          ),
        IconButton(
          focusNode: _playFocusNode,
          tooltip: _playing ? '一時停止' : '再生',
          iconSize: 40,
          color: Colors.white,
          onPressed: widget.onTogglePlayPause,
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
        ),
        if (widget.live && widget.onProgrammeAction != null)
          IconButton(
            tooltip: liveProgrammeActionLabel(widget.programmeState),
            iconSize: 36,
            color: Colors.white,
            onPressed: widget.onProgrammeAction,
            icon: Icon(liveProgrammeActionIcon(widget.programmeState)),
          ),
        if (!widget.live)
          IconButton(
            tooltip: '10秒スキップ',
            iconSize: 36,
            color: Colors.white,
            onPressed: seekable ? () => widget.onSkip(skipSeekStep) : null,
            icon: const Icon(Icons.forward_10),
          ),
        if (!widget.live && widget.chapters.isNotEmpty)
          IconButton(
            tooltip: '次のチャプター',
            iconSize: 36,
            color: Colors.white,
            onPressed: seekable ? () => widget.onChapterSeek(true) : null,
            icon: const Icon(Icons.fast_forward),
          ),
        const Spacer(),
        IconButton(
          tooltip: widget.isFullscreen() ? '全画面を終了' : '全画面',
          iconSize: 32,
          color: Colors.white,
          onPressed: widget.onToggleFullscreen,
          icon: Icon(
            widget.isFullscreen() ? Icons.fullscreen_exit : Icons.fullscreen,
          ),
        ),
      ],
    );
  }
}

/// The TV seek bar: a progress line with a thumb and one
/// tick per chapter point, drawn over the same dimensions
/// the stock bar uses (a 48 px tall target, a 4 px line, a
/// 16 px thumb — see the player screen's seek bar
/// dimensions). Pointer input is not its way: while it
/// holds focus, left / right seek by the skip step from
/// the current position (holding the key repeats, so a
/// hold scrubs), and focus shows as a thicker line in the
/// theme's primary colour with a larger thumb.
class _TvSeekBar extends StatefulWidget {
  const _TvSeekBar({
    required this.position,
    required this.duration,
    required this.enabled,
    required this.chapters,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;

  /// Focusable and key-driven only while true (the stream
  /// is seekable and its length is known).
  final bool enabled;

  /// Chapter points, drawn as ticks at their fractions.
  final List<Duration> chapters;

  /// An absolute seek to an already-clamped target.
  final void Function(Duration target) onSeek;

  @override
  State<_TvSeekBar> createState() => _TvSeekBarState();
}

class _TvSeekBarState extends State<_TvSeekBar> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'TvSeekBar');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted && _focusNode.hasFocus != _focused) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _step(-skipSeekStep);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _step(skipSeekStep);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _step(Duration offset) {
    widget.onSeek(
      skipSeekTarget(
        position: widget.position,
        offset: offset,
        duration: widget.duration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fraction = widget.duration > Duration.zero
        ? (widget.position.inMicroseconds / widget.duration.inMicroseconds)
              .clamp(0.0, 1.0)
        : 0.0;
    final lineHeight = _focused ? 6.0 : 4.0;
    final thumbSize = _focused ? 20.0 : 16.0;
    final activeColor = _focused
        ? Theme.of(context).colorScheme.primary
        : Colors.white;
    return Focus(
      focusNode: _focusNode,
      canRequestFocus: widget.enabled,
      skipTraversal: !widget.enabled,
      onKeyEvent: _onKeyEvent,
      child: SizedBox(
        height: 48,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: (48 - lineHeight) / 2,
                  child: Container(
                    height: lineHeight,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(lineHeight / 2),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: (48 - lineHeight) / 2,
                  child: Container(
                    width: width * fraction,
                    height: lineHeight,
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: BorderRadius.circular(lineHeight / 2),
                    ),
                  ),
                ),
                if (widget.duration > Duration.zero)
                  for (final chapter in widget.chapters)
                    Positioned(
                      left:
                          width *
                              (chapter.inMicroseconds /
                                  widget.duration.inMicroseconds) -
                          1,
                      top: (48 - 12) / 2,
                      child: Container(
                        width: 2,
                        height: 12,
                        color: Colors.white70,
                      ),
                    ),
                Positioned(
                  left: (width * fraction - thumbSize / 2).clamp(
                    0.0,
                    width - thumbSize,
                  ),
                  top: (48 - thumbSize) / 2,
                  child: Container(
                    width: thumbSize,
                    height: thumbSize,
                    decoration: BoxDecoration(
                      color: activeColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A position or duration as `m:ss`, or `h:mm:ss` past an
/// hour — the shape the stock controls' position indicator
/// uses.
String _clock(Duration value) {
  final total = value.isNegative ? Duration.zero : value;
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  final seconds = total.inSeconds.remainder(60);
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}
