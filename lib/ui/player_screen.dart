/// Playback screen (Phase 5, plan 26): plays the decrypted TS
/// stream from the DTCP-IP session's loopback proxy via media_kit
/// (mpv). AVPlayer cannot decode MPEG-2 TS on iOS, hence media_kit.
///
/// Plan 29: the player's state streams are mirrored into the
/// playback diagnostics category (playing / buffering transitions
/// and mpv errors), mpv errors are surfaced on screen instead of
/// an eternal spinner, and a start watchdog turns "nothing ever
/// plays" into a classified timeout error.
///
/// Plan 30: mpv's network timeout is raised from its 5 s default
/// to 30 s before opening. In the build-8 field test the player
/// failed with "Failed to open" about 5 s after the content GET
/// while the (then packet-at-a-time) proxy had not delivered a
/// single byte yet; the proxy now streams and prefetches, and the
/// longer timeout keeps a slow path from tripping mpv first.
///
/// Plan 32: while the player reports playing, a wakelock keeps
/// the device from idle-sleeping (the build-10 iPad field test
/// had the device try to sleep about five minutes into playback).
/// The lock follows the playing stream exactly and is released
/// on pause, stop, error and when this screen is disposed.
///
/// Plan 35: the screen no longer owns a private controller — it
/// opens a session on the app-wide [PlaybackWakelock], so two
/// overlapping player screens cannot drop the OS lock from under
/// each other (build-13 field log).
///
/// Plan 39: live viewing reuses this screen unchanged. Nothing
/// here seeks, resumes, or assumes a stream length (recordings
/// also arrive as an unbounded chunked stream), so an endless
/// broadcast needs no special case; leaving the screen stops
/// the session in dispose, which is what a channel switch is.
/// The wakelock follows the playing stream exactly as it does
/// for recordings.
///
/// Plan 42: for live viewing, mpv's "Cannot seek in this
/// stream." complaint no longer fails the start. mpv queues an
/// initial seek for streams whose timestamps do not start at
/// zero (observed with DR broadcasts on Android) and reports
/// the refusal at error level even though playback itself is
/// unaffected; the live stream is unseekable by design, so the
/// complaint is logged and ignored (see player_error_policy).
/// Recorded playback keeps the previous behaviour.
///
/// Plan 53: subtitle (caption) and sub-audio controls. Every
/// stream kind carries its ARIB caption as a separate subtitle
/// track (measured; see player_track_policy), so the caption
/// toggle is mpv's subtitle track selection — and because mpv
/// may auto-select a caption track matching the device
/// language, the default-off state is forced (sid=no before
/// open, re-applied when the track list settles) until the
/// user turns captions on. Dual-audio programmes carry a
/// second audio track; when two or more audio tracks exist an
/// audio switcher （主音声 / 副音声） is offered. Both selections
/// live only in this screen's state and nothing is persisted —
/// unlike the quality choice, which the detail screens keep
/// in the saved playback quality.
///
/// Plan 54 corrections, driven by the owner's build-20 device
/// log and desktop-mpv measurements on the same streams:
/// (1) media_kit's synthetic 'auto'/'no' list entries are no
/// longer counted as tracks — plan 53's menu sent "副音声" on
/// a single-audio stream to aid=no (silence). Real tracks
/// only; see player_track_policy.
/// (2) mpv's demuxer cache stalls audio track switching on
/// unseekable streams indefinitely (measured: still no audio
/// decode 30 s after a switch; the same switch from a file
/// settles in ~0.15 s, and with cache=no in ~2 s), so the
/// player disables mpv's cache before open. Jitter buffering
/// is the proxy prefetch queue's job, not mpv's cache.
/// (3) The caption toggle's selection is correct, but the
/// bundled ffmpeg builds carry no ARIB caption decoder
/// (plan 54; see player_track_policy), so captions cannot
/// render until the libmpv builds gain one.
///
/// Plan 86: a recording can open at the resume position the
/// nasne holds for it ([PlayerScreen.initialStart]); the title
/// detail asks whether to continue from there or start over.
/// Before this the position was fetched and displayed but never
/// used, so every viewing of a long programme restarted at the
/// beginning (plan 85 item 1).
///
/// Plan 102: the other half of that pair — leaving this screen
/// reports where the viewing stopped ([PlayerScreen
/// .onResumePosition]), because the unit does not learn a
/// position from being streamed to: its points stayed zero
/// through every HB playback until this write existed, so
/// "continue" could never be offered for them. The terms of
/// the report (nothing when playback never started, zero —
/// a cleared point — when it ran to the end) are
/// player_resume_policy's.
///
/// Plan 104: leaving the screen could fail to stop the
/// audio. The plan-102 report ran first in dispose and read
/// the diagnostics log through ref; Riverpod 3 forbids ref
/// once the widget is deactivating, so the read threw a
/// StateError that aborted dispose before the player was
/// disposed and the session stopped — the screen went back
/// to the list and mpv kept playing (field report). Live
/// viewing escaped only because it has no report to send.
/// Dispose now decides the report from the state's own
/// fields, reads no provider (the log is captured in a
/// field at initState), and runs every teardown step —
/// player stop and dispose, session stop, the report last —
/// unconditionally through player_teardown_policy, each
/// guarded so one failure cannot starve the rest.
///
/// Plan 86 (plan 85 item 7): recorded playback gains a speed
/// control in the app bar (1.0 / 1.25 / 1.5 / 2.0, applied via
/// mpv's rate with pitch-corrected audio). Live viewing is
/// excluded — a live stream has nothing to catch up from
/// (see player_speed_policy).
///
/// Plan 86 (plan 85 item 9): the start-failure view leads
/// with a plain explanation and what to do next; the raw
/// player error moves into a collapsed detail section,
/// matching the playback error dialog (playback_launcher).
///
/// Plan 80: the seek-freeze fixes. Recorded playback now
/// runs with mpv's cache on (see player_cache_policy) so
/// the demuxer's re-reads stop round-tripping the proxy.
/// And a playback that had started and then dies mid-stream
/// — a fatal error after the start, or the silent stall of
/// plan 78, where mpv stopped on the last frame with no
/// error at all — is surfaced as an interruption over the
/// frozen frame, with a resume action that re-opens the
/// same session stream in place, instead of the screen
/// failing wholesale as if the start had been bad.
///
/// Player UI follow-up (after 1.4.0), from the owner's
/// device feedback: the recorded screen's transport row
/// gains ±10 s skip buttons, and the seek bar gains a
/// taller touch target. The buttons follow mpv's own
/// `seekable` property and stay disabled while the stream
/// is not seekable — with the loopback proxy's chunked,
/// range-less responses that is today's steady state (see
/// player_seek_policy). The seek bar's stock Material
/// theme leaves it flush with the bottom edge outside
/// fullscreen (zero margin, and the controls take no
/// safe-area padding there), under the iPhone home
/// indicator where a thumb cannot reach it; the themes
/// below raise its container height and thumb size and
/// lift the non-fullscreen bar off the edge.
///
/// The fixed lift alone did not clear the indicator on
/// the owner's devices (plan 105): the bottom margins
/// of the seek bar and of the bottom button bar sharing
/// its stack now grow by the device's actual bottom
/// view padding, so the whole touch target and the
/// button row sit above the gesture area, and the
/// interruption banner pads itself the same way (see
/// player_safe_area_policy).
///
/// Plan 112: chapter skip for recordings. The points
/// are the unit's own silence-cut chapters, fetched
/// once as the screen opens ([PlayerScreen.loadChapters])
/// and validated on the way in (see the core chapter
/// parsing) — a title whose data is absent or broken
/// simply has no chapter controls, and no interval
/// fallback stands in for them. The transport rows
/// gain previous / next chapter buttons beside the
/// ±10 s skips, following the same seekable signal,
/// and the seek bar gains a tick at each point: the
/// bar is media_kit's, built inside its controls with
/// no slot for markers, so the ticks are an overlay
/// aligned to the bar from the same theme values the
/// controls lay it out with (see player_chapter_policy
/// and _ChapterTicksOverlay). Live viewing has no
/// chapters and is untouched.
///
/// Plan 139: two Fire TV field failures, both on the player
/// side of an otherwise healthy stream. On Android at API 28
/// or below (Fire OS 7), media_kit's async initialization
/// can wait forever for an event reply, so the player is
/// created with the synchronous property path there (see
/// app/mpv_compat.dart). And the viewer's decode-mode
/// setting (see player_hwdec_policy.dart) can move MPEG-2 —
/// or all decoding — off a hardware path that never
/// produces a picture; it is applied before open, alongside
/// the cache mode.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' as services;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app/mpv_compat.dart';
import '../app/variant.dart';
import '../app/providers.dart';
import '../core/core.dart';
import 'player_cache_policy.dart';
import 'player_chapter_policy.dart';
import 'player_cm_autoskip_policy.dart';
import 'player_error_policy.dart';
import 'player_hwdec_policy.dart';
import 'player_resume_policy.dart';
import 'player_safe_area_policy.dart';
import 'player_seek_policy.dart';
import 'player_speed_policy.dart';
import 'player_teardown_policy.dart';
import 'player_track_policy.dart';
import 'player_tv_controls.dart';
import 'player_zap_policy.dart';

/// A channel the viewer can move to from inside the
/// player (live viewing only): the name the header strip
/// shows, and the start that opens the channel's session —
/// the same start the channel's detail view runs for its
/// own viewing (see live_screen.dart). Switching channels
/// is starting the new channel's session after stopping
/// the old one (see PlaybackEngine.startLivePlayback).
class PlayerZapTarget {
  const PlayerZapTarget({required this.name, required this.start});

  /// Display name: the channel's name, as the player's
  /// title for that channel.
  final String name;

  /// Starts this channel's playback session.
  final Future<PlaybackSession> Function() start;
}

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.title,
    required this.session,
    this.live = false,
    this.initialStart,
    this.onResumePosition,
    this.loadChapters,
    this.zapTargets,
    this.zapIndex = 0,
  });

  /// Display heading: a recording's title, or a live channel's
  /// name (plan 39). The screen itself is source-agnostic — it
  /// plays the session's stream, finite or endless.
  final String title;
  final PlaybackSession session;

  /// Whether the session is a live broadcast (plan 43). A live
  /// stream is unseekable by design, so mpv's seek complaint is
  /// non-fatal there (see player_error_policy).
  final bool live;

  /// Where a recording starts playing (plan 86): the resume
  /// position the nasne recorded for the title, when the viewer
  /// chose to continue from it. Null (and always null for live)
  /// starts at the beginning. Handed to mpv as the open start,
  /// so the proxy's time-seek path establishes the stream at
  /// that position from the first byte.
  final Duration? initialStart;

  /// Where the position a recording was stopped at goes when
  /// this screen closes (plan 102): the unit is told, so its
  /// resume point — the value [initialStart] is later read
  /// from — follows the viewer. What is sent follows
  /// player_resume_policy: the stopped-at position, or zero
  /// (clearing the point) when playback ran to the end, and
  /// nothing at all when playback never started. Null (live
  /// viewing has no position to report) disables the report.
  ///
  /// The report is a notification to the unit, not local
  /// persistence: it is awaited inside its own task off the
  /// dispose path, and a failure is logged to the playback
  /// diagnostics and dropped — leaving the player must never
  /// fail or hang because a report did not land.
  ///
  /// Plan 104: the report is decided from the screen's own
  /// fields before teardown and sent as a guarded teardown
  /// step once the player's stop is under way; see
  /// player_teardown_policy for why dispose touches no ref
  /// and lets no step's failure starve the rest.
  final Future<void> Function(Duration position)? onResumePosition;

  /// Where this recording's chapter points come from
  /// (plan 112): called once as the screen opens and
  /// expected to answer the title's validated points.
  /// An empty answer — no chapters, or data that failed
  /// validation — simply leaves the screen without
  /// chapter controls. Null (live viewing has no
  /// chapters) disables the feature. The load runs
  /// beside the open, never before it, and a failure is
  /// logged and dropped: chapters decorate playback and
  /// must not delay or fail it.
  final Future<List<Duration>> Function()? loadChapters;

  /// The channels the viewer can move between without
  /// leaving the player (live viewing only, owner request
  /// 2026-11-23): the band's playable channels in the order
  /// the live list shows them, with the channel this screen
  /// opened at [zapIndex]. The header shows the previous
  /// and next channels beside the current one, and the
  /// up / down keys move as well (see player_zap_policy).
  /// Null — recordings, and live viewing whose band has a
  /// single playable channel — keeps the plain title and
  /// offers no movement.
  final List<PlayerZapTarget>? zapTargets;

  /// Where [zapTargets] starts: the index of the channel
  /// [session] is playing.
  final int zapIndex;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  late final WakelockSession _wakelockSession;

  /// Whether this screen's player runs media_kit's
  /// synchronous property path (plan 139): Android at API 28
  /// or below, decided once in [initState] from the SDK int
  /// read at startup (see app/mpv_compat.dart).
  bool _legacySyncMpvInit = false;

  /// The viewer's video decode mode in force for this screen
  /// (plan 139; see player_hwdec_policy.dart), snapshotted in
  /// [initState] so the video controller and the properties
  /// [_open] sets cannot disagree. A settings change applies
  /// from the next playback, like the buffer choice.
  late final VideoHwdecMode _hwdecMode;

  /// Whether this screen runs on the TV variant, snapshotted
  /// in [initState] (the variant is chosen once at startup).
  /// The TV variant replaces the stock video controls with
  /// the remote-driven ones (plan 147; see
  /// player_tv_controls.dart) — the stock Material controls
  /// answer pointer events only, so a remote can neither
  /// raise them nor focus their buttons.
  late final bool _tvVariant;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _watchdog;
  bool _playing = false;
  String? _error;

  /// Interruption state (plan 80): playback that had started
  /// stopped mid-stream — a fatal player error after the
  /// start, or the silent stall of plan 78 — and the notice
  /// with its resume action is showing over the frozen frame.
  bool _interrupted = false;
  String? _interruptDetail;
  Timer? _stallTimer;

  /// The latest value of the playing stream (unlike
  /// [_playing], which latches once playback has started),
  /// and the signals the interruption policy reads: mpv's
  /// end-of-stream flag, whether buffering was the last
  /// observed state while playing, and the last position a
  /// resume should return to.
  bool _playingNow = false;
  bool _completed = false;
  bool _bufferingSincePlaying = false;
  Duration _lastPosition = Duration.zero;

  /// How long a mid-stream stop may last before it is
  /// surfaced as an interruption (plan 80): long enough for
  /// mpv's own recovery and a passing stall, short enough
  /// that a dead playback does not sit silent.
  static const Duration stallTimeout = Duration(seconds: 10);

  /// Tracks the demuxer currently reports, and the selection
  /// mpv currently holds (plan 53). Both start empty/'auto'
  /// and settle once the stream is being demuxed.
  Tracks _tracks = const Tracks();
  Track _selectedTrack = const Track();

  /// The demuxer's real audio tracks, without media_kit's
  /// synthetic 'auto'/'no' entries (plan 54).
  List<AudioTrack> get _realAudioTracks => [
    for (final track in _tracks.audio)
      if (isRealTrackId(track.id)) track,
  ];

  /// The demuxer's real subtitle tracks (plan 54).
  List<SubtitleTrack> get _realSubtitleTracks => [
    for (final track in _tracks.subtitle)
      if (isRealTrackId(track.id)) track,
  ];

  /// The caption toggle (plan 53). Default off, per the
  /// owner's spec; kept in this state only, never persisted.
  bool _subtitlesOn = false;

  /// The playback rate (plan 86, plan 85 item 7): 1.0 is
  /// normal speed. Offered for recordings only (see
  /// player_speed_policy); kept in this state only, like the
  /// caption and audio selections, and never persisted. mpv
  /// holds the rate on the player instance, so it carries
  /// over the in-place resume's re-open (plan 80) unchanged.
  double _playbackRate = 1.0;

  /// Whether mpv reports the current stream seekable,
  /// observed from its `seekable` property (player UI
  /// follow-up). Starts false — the skip buttons stay
  /// disabled until mpv gives a definite yes — and follows
  /// the property for the screen's lifetime. The buttons
  /// listen to this notifier directly, so no rebuild of
  /// this screen is involved when it flips. The property
  /// observation is registered on the player instance and
  /// dies with it; the notifier itself holds nothing that
  /// needs releasing.
  final ValueNotifier<bool> _seekable = ValueNotifier<bool>(false);

  /// The recording's chapter points (plan 112), loaded
  /// once as the screen opens (see [_loadChapters]).
  /// Empty — live viewing, a title without chapters, a
  /// load that failed — keeps the chapter buttons out
  /// of the transport rows and the ticks off the seek
  /// bar.
  List<Duration> _chapters = const [];

  /// Whether CM auto skip is on for this playback
  /// (user-fork addition): a snapshot of
  /// cmAutoSkipProvider taken in [initState], the same
  /// snapshot rule as the other player settings, so a
  /// change in Settings applies from the next playback.
  bool _cmAutoSkipEnabled = false;

  /// The start of the CM run the viewer seeked into by
  /// hand during this playback: auto skip leaves that
  /// run alone (see player_cm_autoskip_policy). Set
  /// from the position stream when a jump that is not
  /// an auto skip seek lands inside a run.
  Duration? _cmSuppressedRunStart;

  /// The target of an auto skip seek still in flight:
  /// position reports behind it must not retrigger the
  /// same skip, and its landing must not read as a
  /// manual seek. Cleared when the position reaches it
  /// or the seek fails.
  Duration? _cmAutoSkipPendingTarget;

  /// How long playback may take to reach the playing state before
  /// the screen gives up with a timeout error (plan 29). Kept
  /// above mpv's network timeout (plan 30) so mpv's own classified
  /// error normally surfaces first and this stays a backstop.
  static const Duration startTimeout = Duration(seconds: 45);

  /// mpv's network timeout, set before opening (plan 30). The
  /// factory default of 5 s is shorter than a slow path's time to
  /// first byte even with the streaming proxy.
  static const int mpvNetworkTimeoutSeconds = 30;

  /// Seek bar dimensions in the video controls (player UI
  /// follow-up). The stock Material theme's visible bar is
  /// 2.4 px inside a 36 px container with a 12.8 px thumb;
  /// the container is the touch target, so it grows to
  /// 48 px, the thumb to 16 px and the visible bar to 4 px.
  /// The desktop theme takes the same three values.
  static const double seekBarThickness = 4.0;
  static const double seekBarTouchHeight = 48.0;
  static const double seekBarThumbDiameter = 16.0;

  /// How far the non-fullscreen seek bar is lifted off the
  /// video's bottom edge (player UI follow-up). Outside
  /// fullscreen the stock theme gives the bar a zero margin
  /// and the controls no safe-area padding, leaving it
  /// under the iPhone home indicator; the fullscreen theme
  /// already carries a 42 px margin over the safe-area
  /// padding and keeps it. This lift is only the gap kept
  /// above the gesture area: the theme adds the device's
  /// bottom view padding under it (plan 105, see
  /// player_safe_area_policy).
  static const double seekBarBottomLift = 12.0;

  /// The diagnostics log, captured in [initState] (plan
  /// 104): dispose and the teardown it drives read no
  /// provider through ref — Riverpod 3 throws once the
  /// widget is deactivating, and a throw there aborts the
  /// teardown (see player_teardown_policy).
  late final DiagLog _diag;

  /// The session currently playing: [PlayerScreen.session]
  /// at the first open, and the zap target's own session
  /// after a channel switch (see _zapTo). Leaving the
  /// screen stops this one; a switch stops the replaced
  /// one as it swaps.
  late PlaybackSession _session;

  /// Where the viewer stands in [PlayerScreen.zapTargets].
  int _zapIndex = 0;

  /// A channel switch is in flight: the old session is
  /// stopping or the new one is starting. Movement input
  /// is ignored meanwhile, so a held key or a double tap
  /// cannot queue competing starts against one tuner.
  bool _zapping = false;

  /// An open is in flight (the first open, or a switch's):
  /// channel movement and the in-place resume wait for it
  /// to land, so two opens never race on the one player.
  bool _opening = false;

  /// Whether channel movement is offered (see
  /// player_zap_policy).
  bool get _canZap =>
      canZap(live: widget.live, targetCount: widget.zapTargets?.length ?? 0);

  @override
  void initState() {
    super.initState();
    _diag = ref.read(diagLogProvider);
    _tvVariant = ref.read(appVariantProvider).isTv;
    _session = widget.session;
    _zapIndex = widget.zapIndex;
    final zapTargets = widget.zapTargets;
    if (zapTargets != null &&
        (_zapIndex < 0 || _zapIndex >= zapTargets.length)) {
      // A caller-supplied index outside the targets must
      // not reach the header's lookups; fall back to the
      // first target rather than failing the screen.
      _zapIndex = 0;
    }
    if (_canZap) {
      services.HardwareKeyboard.instance.addHandler(_onZapKeyEvent);
    }
    // The player's mpv initialization follows the device's
    // Android generation (plan 139; see app/mpv_compat.dart):
    // at API 28 or below the async initialization can wait
    // forever for an event reply, so the player is created
    // with the synchronous property path there. The SDK int
    // was read at startup (app/android_sdk.dart); an unknown
    // value keeps the long-standing async default.
    final androidSdkInt = ref.read(androidSdkIntProvider);
    _legacySyncMpvInit = shouldUseLegacySyncMpvInit(
      isAndroid: Platform.isAndroid,
      androidSdkInt: androidSdkInt,
    );
    _player = _legacySyncMpvInit
        ? Player(configuration: const PlayerConfiguration(async: false))
        : Player();
    if (_legacySyncMpvInit) {
      _diag(
        DiagCategory.playback,
        'player: legacy sync mpv init (async: false, android api '
        '$androidSdkInt)',
      );
      unawaited(_kickLegacyMpvAfterInit());
    }
    _hwdecMode = ref.read(videoHwdecModeProvider);
    _cmAutoSkipEnabled = ref.read(cmAutoSkipProvider);
    _videoController = videoControllerHardwareAcceleration(_hwdecMode)
        ? VideoController(_player)
        : VideoController(
            _player,
            configuration: const VideoControllerConfiguration(
              enableHardwareAcceleration: false,
            ),
          );
    _wakelockSession = ref.read(playbackWakelockProvider).openSession();
    _watchdog = Timer(startTimeout, _onStartTimeout);
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        _diag(DiagCategory.playback, 'player: playing=$playing');
        _wakelockSession.setPlaying(playing);
        final wasPlaying = _playingNow;
        _playingNow = playing;
        if (_zapping) {
          // A channel switch is in flight: this event may
          // still belong to the channel being left, so it
          // must not drive the start / interruption state
          // machine. _zapTo reconciles from _playingNow
          // when the switch completes.
          return;
        }
        if (playing) {
          _playing = true;
          _watchdog?.cancel();
          // A (re)start clears any interruption state
          // (plan 80): playback is running again, whether it
          // recovered on its own or the user resumed it.
          _stallTimer?.cancel();
          _bufferingSincePlaying = false;
          if (_interrupted && mounted) {
            setState(() {
              _interrupted = false;
              _interruptDetail = null;
            });
          }
        } else if (wasPlaying) {
          _onPlaybackStopped();
        }
      }),
    );
    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        _diag(DiagCategory.playback, 'player: buffering=$buffering');
        if (_playingNow) {
          // Buffering while mpv is trying to play is the
          // signature the plan-78 stalls left just before
          // mpv stopped (plan 80); buffering clearing again
          // while playing is a recovery and clears it.
          _bufferingSincePlaying = buffering;
        }
      }),
    );
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        _diag(DiagCategory.playback, 'player: completed=$completed');
        _completed = completed;
      }),
    );
    _subscriptions.add(
      _player.stream.position.listen((position) {
        final previous = _lastPosition;
        _lastPosition = position;
        _maybeCmAutoSkip(position, previous);
      }),
    );
    _subscriptions.add(
      _player.stream.tracks.listen((tracks) {
        _diag(
          DiagCategory.playback,
          'player: tracks: video=${tracks.video.length} '
          'audio=${tracks.audio.length} subtitle=${tracks.subtitle.length} '
          '(real audio='
          '${realTrackIds([for (final t in tracks.audio) t.id]).length} '
          'real subtitle='
          '${realTrackIds([for (final t in tracks.subtitle) t.id]).length})',
        );
        for (final track in tracks.audio) {
          _diag(
            DiagCategory.playback,
            'player: audio track: id=${track.id} codec=${track.codec} '
            'channels=${track.channelscount} language=${track.language}',
          );
        }
        for (final track in tracks.subtitle) {
          _diag(
            DiagCategory.playback,
            'player: subtitle track: id=${track.id} codec=${track.codec} '
            'language=${track.language}',
          );
        }
        if (mounted) setState(() => _tracks = tracks);
        // Re-resolve the caption selection against the settled
        // track list: applies the forced-off default, or the
        // track the user asked for before the list arrived.
        _applySubtitleSelection();
      }),
    );
    _subscriptions.add(
      _player.stream.track.listen((track) {
        if (mounted) setState(() => _selectedTrack = track);
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((error) {
        _diag(DiagCategory.playback, 'player: error: $error');
        if (_zapping) {
          // An error surfacing during a channel switch may
          // belong to the channel being left (its proxy is
          // closing): it must not cancel the new channel's
          // watchdog or cover the new channel with the
          // start error. The switch's own open arbitrates
          // the new channel's start.
          _diag(
            DiagCategory.playback,
            'player: ignoring an error during a channel switch',
          );
          return;
        }
        if (!playerErrorIsFatal(
          error,
          live: widget.live,
          alreadyPlaying: _playing,
        )) {
          // A seek complaint the policy classes as benign
          // (plan 43, extended after 1.4.0): live viewing,
          // where the stream is unseekable by design, or any
          // playback already under way, where the complaint
          // can only be answering a seek and mpv keeps
          // playing. Leave the watchdog running as the
          // arbiter of a start that never reaches playback.
          _diag(
            DiagCategory.playback,
            'player: ignoring the seek complaint '
            '(live=${widget.live}, alreadyPlaying=$_playing)',
          );
          return;
        }
        _wakelockSession.setPlaying(false);
        _watchdog?.cancel();
        if (!mounted) return;
        if (_playing) {
          // The failure arrived after playback had started
          // (plan 80): an interruption, not a failed start.
          // Keep the frozen frame and offer the in-place
          // resume instead of replacing the screen with the
          // start-failure message.
          setState(() {
            _interrupted = true;
            _interruptDetail = error;
          });
        } else if (_error == null) {
          setState(() => _error = error);
        }
      }),
    );
    _observeSeekable();
    _open();
    _loadChapters();
  }

  void _onStartTimeout() {
    if (!mounted || _playing || _error != null) return;
    _diag(
      DiagCategory.playback,
      'player: no playback within ${startTimeout.inSeconds} seconds; '
      'showing a timeout error',
    );
    setState(
      () => _error =
          '再生が開始できませんでした (${startTimeout.inSeconds} 秒以内に'
          '映像が届きませんでした)。',
    );
  }

  /// A playing→stopped transition (plan 80): when the
  /// policy classes it as a mid-stream death, give mpv a
  /// grace period to recover on its own before surfacing
  /// anything.
  void _onPlaybackStopped() {
    if (!playbackStoppedEarly(
      alreadyPlaying: _playing,
      completed: _completed,
      bufferedBeforeStop: _bufferingSincePlaying,
    )) {
      return;
    }
    _diag(
      DiagCategory.playback,
      'player: playback stopped after buffering without '
      'completing; watching for a recovery for '
      '${stallTimeout.inSeconds} seconds (plan 80)',
    );
    _stallTimer?.cancel();
    _stallTimer = Timer(stallTimeout, _onStallTimeout);
  }

  void _onStallTimeout() {
    if (!mounted || _playingNow || _completed || _error != null) {
      return;
    }
    _diag(
      DiagCategory.playback,
      'player: playback did not recover; showing the '
      'interruption notice (plan 80)',
    );
    setState(() => _interrupted = true);
  }

  /// Re-establishes playback after an interruption, in
  /// place (plan 80): the session — authentication, the
  /// loopback proxy and all — is still alive (only leaving
  /// the screen stops it), so resuming re-opens the same
  /// stream URL on the same player and, for a recording,
  /// starts from the last observed position. The title is
  /// never re-opened from the list, and nothing is
  /// re-asked. The player's properties (cache mode, sid)
  /// persist across the re-open; the track listener
  /// re-applies the caption selection when the new track
  /// list settles, exactly as at the first open.
  Future<void> _resume() async {
    if (_zapping || _opening) return;
    _diag(
      DiagCategory.playback,
      'player: resuming after an interruption at '
      '${_lastPosition.inSeconds}s (live=${widget.live})',
    );
    _stallTimer?.cancel();
    setState(() {
      _interrupted = false;
      _interruptDetail = null;
    });
    // The resume's open holds the same in-flight flag as a
    // switch's open (import adjustment, 2026-11-23): without
    // it a channel switch could start while this open is
    // still landing, and the two opens would race on the one
    // player — the switch stops the session this open is
    // reopening.
    _opening = true;
    try {
      await _player.open(
        Media(
          _session.mediaUri.toString(),
          start: (!widget.live && _lastPosition > Duration.zero)
              ? _lastPosition
              : null,
        ),
      );
      _opening = false;
      _diag(DiagCategory.playback, 'player: resume open completed');
    } catch (e) {
      _opening = false;
      _diag(DiagCategory.playback, 'player: resume failed: $e');
      if (mounted) {
        setState(() {
          _interrupted = true;
          _interruptDetail = '$e';
        });
      }
    }
  }

  /// A key event for channel movement (desktop): the up
  /// key moves to the previous channel, the down key to
  /// the next, and the event is claimed, so the desktop
  /// controls do not also take it (their up / down keys
  /// are volume there; the on-screen volume control keeps
  /// working). Anything else — and any key while a menu
  /// or dialog sits over this screen, or while a switch
  /// or an open is in flight — passes through untouched.
  /// The keys stay live on the start error, so a channel
  /// whose start failed can be left by key as well as by
  /// tap.
  bool _onZapKeyEvent(services.KeyEvent event) {
    if (event is! services.KeyDownEvent) return false;
    if (_zapping || _opening) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    if (event.logicalKey == services.LogicalKeyboardKey.arrowUp) {
      _zapBy(-1);
      return true;
    }
    if (event.logicalKey == services.LogicalKeyboardKey.arrowDown) {
      _zapBy(1);
      return true;
    }
    return false;
  }

  /// Moves [delta] channels from the current one, wrapping
  /// at the band's ends (see player_zap_policy).
  void _zapBy(int delta) {
    if (!_canZap || _zapping || _opening) return;
    _zapTo(
      zapIndexAfter(
        current: _zapIndex,
        delta: delta,
        count: widget.zapTargets!.length,
      ),
    );
  }

  /// A right click (a secondary mouse button press) on
  /// the viewing area opens the channel list (user-fork
  /// addition): the whole band as a menu, where the
  /// header strip only reaches the neighbouring channels
  /// and the up / down keys step one at a time. The
  /// listener only observes — it never takes the event —
  /// so the controls keep every pointer event they
  /// already handle, and a press that is not a right
  /// click, or a screen that cannot zap, passes by
  /// unnoticed.
  void _onPlayerPointerDown(PointerDownEvent event) {
    if ((event.buttons & kSecondaryMouseButton) == 0) return;
    unawaited(_showZapChannelList(event.position));
  }

  /// Shows the band's channels as a menu at [position]
  /// and zaps to the picked one. The channel being
  /// watched carries the check, the same mark the speed
  /// and audio menus use; picking it is a no-op through
  /// [_zapTo], like stepping back onto the same channel.
  /// Opening the menu puts a route over this screen,
  /// which also holds the zap keys back until it closes
  /// (see _onZapKeyEvent). Like the keys, the list stays
  /// available on the start error, so a channel whose
  /// start failed can be left this way too.
  Future<void> _showZapChannelList(Offset position) async {
    if (!_canZap || _zapping || _opening) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final targets = widget.zapTargets!;
    final overlay = Overlay.of(context).context.findRenderObject()!;
    final selected = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & (overlay as RenderBox).size,
      ),
      items: [
        for (var i = 0; i < targets.length; i++)
          CheckedPopupMenuItem<int>(
            value: i,
            checked: i == _zapIndex,
            child: Text(
              targets[i].name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
    if (selected != null && mounted) _zapTo(selected);
  }

  /// Switches playback to the zap target at [index], in
  /// place: the current session stops, the target's
  /// session starts and opens on this screen's player, and
  /// the header follows. A start that fails lands on the
  /// start error this screen already shows for a failed
  /// open — the header strip stays, so the viewer can move
  /// back — and a switch that finishes after the screen
  /// went away stops the session it started, like the
  /// launcher does with a late start.
  ///
  /// The switch stays in flight until the new channel's
  /// open completes: player events arriving meanwhile may
  /// belong to the channel being left, so the listeners
  /// hold them back from the start / interruption state
  /// machine, and this method reconciles the playing
  /// state from the latest event when it lands.
  Future<void> _zapTo(int index) async {
    if (!_canZap || _zapping || _opening || index == _zapIndex) return;
    final target = widget.zapTargets![index];
    _diag(
      DiagCategory.playback,
      'player: zapping to channel ${target.name} '
      '(index $index of ${widget.zapTargets!.length})',
    );
    setState(() => _zapping = true);
    try {
      await _session.stop();
    } catch (e) {
      _diag(DiagCategory.playback, 'player: zap: old session stop failed: $e');
    }
    if (!mounted) return;
    final PlaybackSession newSession;
    try {
      newSession = await target.start();
    } catch (e) {
      _diag(DiagCategory.playback, 'player: zap: start failed: $e');
      if (mounted) {
        setState(() {
          _zapping = false;
          _error = '$e';
        });
      }
      return;
    }
    if (!mounted) {
      await newSession.stop();
      return;
    }
    _session = newSession;
    // The new channel starts the way the first one did:
    // the watchdog arbitrates its start, and the playing /
    // interruption signals begin clean. The player's own
    // properties persist across the switch, and _open
    // re-pins what it pins at every open.
    _watchdog?.cancel();
    _watchdog = Timer(startTimeout, _onStartTimeout);
    _stallTimer?.cancel();
    _playing = false;
    _playingNow = false;
    _completed = false;
    _bufferingSincePlaying = false;
    setState(() {
      _zapIndex = index;
      _interrupted = false;
      _interruptDetail = null;
      _error = null;
      _tracks = const Tracks();
      _selectedTrack = const Track();
    });
    await _open();
    if (!mounted) return;
    setState(() {
      _zapping = false;
      // Player events were held back while the switch was
      // in flight; if the new channel already reached
      // playing in that window, take up the started state
      // the playing listener would have set.
      if (_playingNow) {
        _playing = true;
        _watchdog?.cancel();
      }
    });
  }

  /// Applies the caption selection for the current toggle
  /// state (plan 53): the first caption track when on, and
  /// mpv's no-track selection when off — the off case is what
  /// keeps mpv's language-based auto-selection from turning
  /// captions on by itself.
  Future<void> _applySubtitleSelection() async {
    final id = subtitleTrackIdToSelect(
      subtitlesOn: _subtitlesOn,
      subtitleTrackIds: [for (final track in _realSubtitleTracks) track.id],
    );
    try {
      if (id == null) {
        await _player.setSubtitleTrack(SubtitleTrack.no());
      } else {
        await _player.setSubtitleTrack(
          _realSubtitleTracks.firstWhere((track) => track.id == id),
        );
      }
    } catch (e) {
      _diag(DiagCategory.playback, 'player: subtitle selection failed: $e');
    }
  }

  void _toggleSubtitles() {
    setState(() => _subtitlesOn = !_subtitlesOn);
    _diag(
      DiagCategory.playback,
      'player: subtitles ${_subtitlesOn ? 'on' : 'off'} (user toggle)',
    );
    _applySubtitleSelection();
  }

  Future<void> _selectAudioTrack(int index) async {
    if (index < 0 || index >= _realAudioTracks.length) return;
    final track = _realAudioTracks[index];
    _diag(
      DiagCategory.playback,
      'player: audio track -> ${audioTrackLabel(index)} (id=${track.id})',
    );
    try {
      await _player.setAudioTrack(track);
    } catch (e) {
      _diag(DiagCategory.playback, 'player: audio selection failed: $e');
    }
  }

  /// Applies a user-chosen playback rate (plan 86, plan 85
  /// item 7). mpv pitch-corrects the audio at these rates,
  /// so speech stays intelligible; the proxy and the stream
  /// are untouched — the demuxer just consumes faster.
  Future<void> _selectPlaybackRate(double rate) async {
    if (rate == _playbackRate) return;
    setState(() => _playbackRate = rate);
    _diag(
      DiagCategory.playback,
      'player: playback rate -> ${playbackSpeedLabel(rate)} '
      '(user selection)',
    );
    try {
      await _player.setRate(rate);
    } catch (e) {
      _diag(DiagCategory.playback, 'player: rate change failed: $e');
    }
  }

  int get _selectedAudioIndex => selectedAudioIndex(
    selectedId: _selectedTrack.audio.id,
    trackIds: [for (final track in _realAudioTracks) track.id],
  );

  /// Follows mpv's `seekable` property into [_seekable]
  /// (player UI follow-up): the recorded screen's skip
  /// buttons' enable signal. mpv re-evaluates the property
  /// as the demuxer settles, so this is an observation,
  /// not a one-shot read.
  Future<void> _observeSeekable() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.observeProperty('seekable', (value) async {
        final seekable = isSeekablePropertyValue(value);
        if (seekable != _seekable.value) {
          _diag(
            DiagCategory.playback,
            'player: seekable=$value; skip buttons '
            '${seekable ? 'enabled' : 'disabled'}',
          );
          _seekable.value = seekable;
        }
      });
    } catch (e) {
      _diag(DiagCategory.playback, 'player: seekable observation failed: $e');
    }
  }

  /// Seeks by [offset] (±[skipSeekStep]) from the current
  /// position (player UI follow-up). Reached only through
  /// the skip buttons, which stay disabled while [_seekable]
  /// is false; a refusal that still comes back lands on the
  /// error stream and is classified there (see
  /// player_error_policy), so it cannot fail a playback
  /// already under way.
  Future<void> _skipSeek(Duration offset) async {
    final target = skipSeekTarget(
      position: _player.state.position,
      offset: offset,
      duration: _player.state.duration,
    );
    _diag(
      DiagCategory.playback,
      'player: skip seek by ${offset.inSeconds}s '
      'to ${target.inSeconds}s',
    );
    try {
      await _player.seek(target);
    } catch (e) {
      _diag(DiagCategory.playback, 'player: skip seek failed: $e');
    }
  }

  /// Seeks to an absolute [target] (plan 147): the TV
  /// controls' seek bar steps from the current position
  /// through player_seek_policy and lands here. A refusal
  /// is classified on the error stream like a skip's (see
  /// [_skipSeek]).
  Future<void> _seekToPosition(Duration target) async {
    _diag(
      DiagCategory.playback,
      'player: seek to ${target.inSeconds}s (plan 147)',
    );
    try {
      await _player.seek(target);
    } catch (e) {
      _diag(DiagCategory.playback, 'player: seek failed: $e');
    }
  }

  /// Loads the recording's chapter points once (plan
  /// 112). Runs beside the open, not before it: playback
  /// starts without waiting, and the chapter controls
  /// join the transport rows when the points land. Any
  /// failure — including a synchronous throw from the
  /// loader resolving the unit's services through the
  /// caller's ref — is logged and dropped.
  Future<void> _loadChapters() async {
    final loader = widget.loadChapters;
    if (loader == null || widget.live) return;
    try {
      final chapters = await loader();
      _diag(
        DiagCategory.playback,
        'player: chapters: ${chapters.length} points loaded (plan 112)',
      );
      if (mounted && chapters.isNotEmpty) {
        setState(() => _chapters = chapters);
      }
    } catch (e) {
      _diag(DiagCategory.playback, 'player: chapter load failed: $e');
    }
  }

  /// Seeks to the next or previous chapter point (plan
  /// 112), chosen from the player's current position by
  /// player_chapter_policy. Reached only through the
  /// chapter buttons, which exist only when the title
  /// has points and follow the same seekable signal as
  /// the skip buttons; a side with no point is a no-op.
  Future<void> _seekToChapter({required bool forward}) async {
    final position = _player.state.position;
    final target = forward
        ? nextChapterTarget(chapters: _chapters, position: position)
        : previousChapterTarget(chapters: _chapters, position: position);
    if (target == null) {
      _diag(
        DiagCategory.playback,
        'player: chapter seek ${forward ? 'next' : 'previous'}: '
        'no point from ${position.inSeconds}s (plan 112)',
      );
      return;
    }
    _diag(
      DiagCategory.playback,
      'player: chapter seek ${forward ? 'next' : 'previous'} '
      'to ${target.inSeconds}s (plan 112)',
    );
    try {
      await _player.seek(target);
    } catch (e) {
      _diag(DiagCategory.playback, 'player: chapter seek failed: $e');
    }
  }

  /// CM auto skip (user-fork addition): on each position
  /// report, when the setting is on and this is a
  /// recording with chapter points, ask
  /// player_cm_autoskip_policy whether the position sits
  /// in a commercial-break run and seek past it. Runs
  /// beside playback, never in its way: every guard
  /// failure is a silent no-op, and a failed seek only
  /// logs.
  ///
  /// A position jump the pending auto skip seek does
  /// not explain is a manual seek (a chapter button, a
  /// ±10 s skip, the seek bar): when it lands inside a
  /// run, that run is suppressed for the rest of this
  /// playback, so the viewer can rewind into a break
  /// and watch it without being skipped out of it again.
  void _maybeCmAutoSkip(Duration position, Duration previous) {
    if (!_cmAutoSkipEnabled || widget.live || _chapters.isEmpty) return;
    final duration = _player.state.duration;
    if (duration <= Duration.zero) return;
    final pending = _cmAutoSkipPendingTarget;
    if (pending != null) {
      if (position < pending) return;
      _cmAutoSkipPendingTarget = null;
    } else if ((position - previous).abs() > const Duration(seconds: 2)) {
      final runStart = cmRunStartAt(
        chapters: _chapters,
        position: position,
        duration: duration,
      );
      if (runStart != null) _cmSuppressedRunStart = runStart;
    }
    if (!_playingNow || _completed) return;
    final target = cmAutoSkipTarget(
      chapters: _chapters,
      position: position,
      duration: duration,
      suppressedRunStart: _cmSuppressedRunStart,
    );
    if (target == null) return;
    _cmAutoSkipPendingTarget = target;
    _diag(
      DiagCategory.playback,
      'player: CM auto skip from ${position.inSeconds}s '
      'to ${target.inSeconds}s (user-fork addition)',
    );
    unawaited(_seekForCmAutoSkip(target));
  }

  Future<void> _seekForCmAutoSkip(Duration target) async {
    try {
      await _player.seek(target);
    } catch (e) {
      _diag(DiagCategory.playback, 'player: CM auto skip seek failed: $e');
      if (_cmAutoSkipPendingTarget == target) {
        _cmAutoSkipPendingTarget = null;
      }
    }
  }

  /// Pokes the mpv event loop once the player's handle
  /// exists (plan 139; see app/mpv_compat.dart). The kick is
  /// a backstop beside the synchronous init — its delivery
  /// goes to the log either way, so a field log shows
  /// whether libmpv answered at all. Only ever called on the
  /// legacy path, where the handle getter's initialization
  /// wait completes.
  Future<void> _kickLegacyMpvAfterInit() async {
    try {
      final kicked = kickMpvEventLoop(await _player.handle);
      _diag(
        DiagCategory.playback,
        'player: mpv wakeup kick after init: '
        '${kicked ? 'sent' : 'unavailable'}',
      );
    } catch (e) {
      _diag(DiagCategory.playback, 'player: mpv wakeup kick failed: $e');
    }
  }

  /// Records the decoder state mpv settled on for this start
  /// (plan 139): the hwdec actually in use, the video codec
  /// and whether a video output is configured. Together with
  /// the init timing in [_open], a field log can tell
  /// "stopped in initialization" from "initialized but never
  /// decoded" — the two Fire TV failure shapes of this round.
  /// Best-effort: a failed read is logged and dropped, never
  /// a failed open.
  Future<void> _logDecodeStatus() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      final hwdecCurrent = await platform.getProperty('hwdec-current');
      final videoCodec = await platform.getProperty('video-codec');
      final voConfigured = await platform.getProperty('vo-configured');
      _diag(
        DiagCategory.playback,
        'player: decode status: hwdec-current=$hwdecCurrent '
        'video-codec=$videoCodec vo-configured=$voConfigured',
      );
    } catch (e) {
      _diag(DiagCategory.playback, 'player: decode status read failed: $e');
    }
  }

  Future<void> _open() async {
    _opening = true;
    _diag(DiagCategory.playback, 'player: opening ${_session.mediaUri}');
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        // The first property round trip doubles as the init
        // readiness probe (plan 139): on the devices the
        // legacy sync init exists for, this is the call the
        // async path was observed never to return from, so
        // its duration goes to the log on every start.
        final initStopwatch = Stopwatch()..start();
        await platform.setProperty(
          'network-timeout',
          '$mpvNetworkTimeoutSeconds',
        );
        initStopwatch.stop();
        _diag(
          DiagCategory.playback,
          'player: mpv init ready in '
          '${initStopwatch.elapsedMilliseconds} ms',
        );
        if (_legacySyncMpvInit) {
          // Pre-open wakeup kick (plan 139; see
          // app/mpv_compat.dart).
          try {
            final kicked = kickMpvEventLoop(await _player.handle);
            _diag(
              DiagCategory.playback,
              'player: mpv wakeup kick before open: '
              '${kicked ? 'sent' : 'unavailable'}',
            );
          } catch (e) {
            _diag(DiagCategory.playback, 'player: mpv wakeup kick failed: $e');
          }
        }
        _diag(
          DiagCategory.playback,
          'player: mpv network-timeout set to '
          '${mpvNetworkTimeoutSeconds}s',
        );
        // Captions default to off (plan 53): pin the subtitle
        // selection to "no track" before the stream opens, so
        // mpv's auto-selection never gets a say. The tracks
        // listener re-applies the resolution once the demuxer's
        // track list settles.
        await platform.setProperty('sid', 'no');
        _diag(DiagCategory.playback, 'player: mpv sid pinned to no (default)');
        // The viewer's decode mode (plan 139; see
        // player_hwdec_policy.dart): auto sets nothing and
        // keeps mpv's defaults exactly as they were; the
        // MPEG-2-only mode narrows hwdec-codecs so MPEG-2
        // alone falls back to software decoding; the full
        // software mode pins hwdec off (its video controller
        // was already created without hardware acceleration
        // in initState).
        final hwdecCodecs = hwdecCodecsPropertyFor(_hwdecMode);
        if (hwdecCodecs != null) {
          await platform.setProperty('hwdec-codecs', hwdecCodecs);
        }
        final hwdec = hwdecPropertyFor(_hwdecMode);
        if (hwdec != null) {
          await platform.setProperty('hwdec', hwdec);
        }
        _diag(
          DiagCategory.playback,
          'player: video hwdec mode: ${_hwdecMode.name}'
          '${hwdecCodecs != null ? '; hwdec-codecs=$hwdecCodecs' : ''}'
          '${hwdec != null ? '; hwdec=$hwdec' : ''}',
        );
        // mpv's cache follows the playback kind (plans 54
        // and 80; see player_cache_policy). Live keeps it
        // off: with the demuxer cache on, an audio track
        // switch on the unseekable live stream never
        // re-engages decoding (measured 30 s and counting),
        // and the proxy's prefetch queue is the jitter
        // buffer. Recordings turn it on, sized by the two
        // demuxer limits, so the demuxer's probe and seek
        // re-reads (plan 78.1) are absorbed locally instead
        // of round-tripping the proxy per hop.
        final cacheMode = mpvCacheMode(live: widget.live);
        await platform.setProperty('cache', cacheMode);
        if (!widget.live) {
          // The forward demuxer limit follows the viewer's
          // playback buffer choice (plan 126); the back limit
          // stays at its long-standing value (backward scans
          // are not link buffering — see player_cache_policy).
          final bufferSeconds = ref.read(playbackBufferProvider);
          final demuxerMaxBytes = recordingDemuxerMaxBytesFor(bufferSeconds);
          await platform.setProperty('demuxer-max-bytes', '$demuxerMaxBytes');
          await platform.setProperty(
            'demuxer-max-back-bytes',
            '$recordingDemuxerMaxBackBytes',
          );
          _diag(
            DiagCategory.playback,
            'player: mpv demuxer-max-bytes=$demuxerMaxBytes '
            '(playback buffer: '
            '${bufferSeconds == playbackBufferStandardSeconds ? 'standard' : '$bufferSeconds s'})',
          );
        }
        _diag(
          DiagCategory.playback,
          'player: mpv cache=$cacheMode (live=${widget.live})',
        );
      }
      final start =
          (!widget.live &&
              widget.initialStart != null &&
              widget.initialStart! > Duration.zero)
          ? widget.initialStart
          : null;
      if (start != null) {
        _diag(
          DiagCategory.playback,
          'player: opening at the resume position ${start.inSeconds}s '
          '(plan 86)',
        );
      }
      await _player.open(Media(_session.mediaUri.toString(), start: start));
      _diag(DiagCategory.playback, 'player: open completed');
      await _logDecodeStatus();
      await _applySubtitleSelection();
      _opening = false;
    } catch (e) {
      _diag(DiagCategory.playback, 'player: open failed: $e');
      if (!playerErrorIsFatal('$e', live: widget.live)) {
        // Same seek complaint as the error-stream path, thrown
        // through open() instead (plan 43): not a failed start.
        _diag(
          DiagCategory.playback,
          'player: ignoring the seek complaint for live viewing',
        );
        _opening = false;
        return;
      }
      _watchdog?.cancel();
      if (mounted) setState(() => _error = '$e');
      _opening = false;
    }
  }

  /// The Material (Android / iOS) controls theme with this
  /// screen's seek bar dimensions (player UI follow-up)
  /// and, for recordings, the ±10 s skip buttons in the
  /// transport row. Built from media_kit's defaults via
  /// copyWith so the gestures and the rest of the stock
  /// behaviour carry over unchanged.
  ///
  /// Outside fullscreen the bottom margins also clear the
  /// system gesture area (plan 105): the seek bar's margin
  /// and the bottom button bar's margin grow by
  /// [bottomViewPadding], the device's bottom view
  /// padding, and the button bar's right margin moves the
  /// fullscreen button in from the corner (see
  /// player_safe_area_policy). Fullscreen needs none of
  /// this: media_kit pads the fullscreen controls by the
  /// safe area itself, under the stock 42 px margins.
  MaterialVideoControlsThemeData _materialControlsTheme({
    required bool fullscreen,
    double bottomViewPadding = 0,
  }) {
    final base = fullscreen
        ? kDefaultMaterialVideoControlsThemeDataFullscreen
        : kDefaultMaterialVideoControlsThemeData;
    var data = base.copyWith(
      seekBarHeight: seekBarThickness,
      seekBarContainerHeight: seekBarTouchHeight,
      seekBarThumbSize: seekBarThumbDiameter,
    );
    if (!fullscreen) {
      data = data.copyWith(
        seekBarMargin: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: seekBarBottomMargin(
            lift: seekBarBottomLift,
            viewPaddingBottom: bottomViewPadding,
          ),
        ),
        bottomButtonBarMargin: EdgeInsets.only(
          left: 16,
          right: bottomButtonBarRightMargin,
          bottom: bottomButtonBarBottomMargin(bottomViewPadding),
        ),
      );
    }
    if (!widget.live) {
      data = data.copyWith(
        primaryButtonBar: _recordedPrimaryButtonBar(
          playIconSize: fullscreen ? 56.0 : 48.0,
        ),
      );
    }
    return data;
  }

  /// The desktop controls theme with the same seek bar
  /// dimensions (player UI follow-up); the desktop defaults
  /// are one data set for both normal and fullscreen. The
  /// skip buttons join the bottom transport row, which is
  /// where the desktop controls keep theirs.
  MaterialDesktopVideoControlsThemeData _desktopControlsTheme() {
    var data = kDefaultMaterialDesktopVideoControlsThemeData.copyWith(
      seekBarHeight: seekBarThickness,
      seekBarContainerHeight: seekBarTouchHeight,
      seekBarThumbSize: seekBarThumbDiameter,
    );
    if (!widget.live) {
      data = data.copyWith(bottomButtonBar: _recordedDesktopButtonBar());
    }
    return data;
  }

  /// The Material transport row for recordings: media_kit's
  /// stock row with a ±10 s skip button flanking the
  /// play/pause button on each side (player UI follow-up),
  /// and — when the title has chapter points — a chapter
  /// button outside each skip button (plan 112).
  List<Widget> _recordedPrimaryButtonBar({required double playIconSize}) => [
    const Spacer(flex: 2),
    const MaterialSkipPreviousButton(),
    const Spacer(),
    if (_chapters.isNotEmpty) ...[
      _ChapterSkipButton(
        seekable: _seekable,
        forward: false,
        onSeek: () => _seekToChapter(forward: false),
      ),
      const Spacer(),
    ],
    _SkipSeekButton(
      seekable: _seekable,
      offset: -skipSeekStep,
      onSkip: _skipSeek,
    ),
    const Spacer(),
    MaterialPlayOrPauseButton(iconSize: playIconSize),
    const Spacer(),
    _SkipSeekButton(
      seekable: _seekable,
      offset: skipSeekStep,
      onSkip: _skipSeek,
    ),
    if (_chapters.isNotEmpty) ...[
      const Spacer(),
      _ChapterSkipButton(
        seekable: _seekable,
        forward: true,
        onSeek: () => _seekToChapter(forward: true),
      ),
    ],
    const Spacer(),
    const MaterialSkipNextButton(),
    const Spacer(flex: 2),
  ];

  /// The desktop bottom row for recordings: the stock row
  /// with the ±10 s skip buttons after the skip-next button
  /// (player UI follow-up) and, when the title has chapter
  /// points, the chapter buttons after them (plan 112).
  List<Widget> _recordedDesktopButtonBar() => [
    const MaterialDesktopSkipPreviousButton(),
    const MaterialDesktopPlayOrPauseButton(),
    const MaterialDesktopSkipNextButton(),
    _SkipSeekButton(
      seekable: _seekable,
      offset: -skipSeekStep,
      onSkip: _skipSeek,
      iconSize: 28,
    ),
    _SkipSeekButton(
      seekable: _seekable,
      offset: skipSeekStep,
      onSkip: _skipSeek,
      iconSize: 28,
    ),
    if (_chapters.isNotEmpty) ...[
      _ChapterSkipButton(
        seekable: _seekable,
        forward: false,
        onSeek: () => _seekToChapter(forward: false),
        iconSize: 28,
      ),
      _ChapterSkipButton(
        seekable: _seekable,
        forward: true,
        onSeek: () => _seekToChapter(forward: true),
        iconSize: 28,
      ),
    ],
    const MaterialDesktopVolumeButton(),
    const MaterialDesktopPositionIndicator(),
    const Spacer(),
    const MaterialDesktopFullscreenButton(),
  ];

  /// The video controls with the chapter ticks overlaid
  /// on the seek bar (plan 112): the stock adaptive
  /// controls, plus the ticks layer aligned to their
  /// seek bar. Only built while the title has chapter
  /// points — the plain adaptive controls serve live
  /// viewing and chapterless recordings, exactly as
  /// before.
  Widget _controlsWithChapterTicks(VideoState state) {
    return Stack(
      children: [
        AdaptiveVideoControls(state),
        Positioned.fill(
          child: _ChapterTicksOverlay(player: _player, chapters: _chapters),
        ),
      ],
    );
  }

  /// The TV variant's video controls (plan 147): the
  /// remote-driven bar from player_tv_controls.dart, fed
  /// with this screen's player streams and seek actions.
  /// The chapter ticks the standard variant overlays on
  /// the stock seek bar are drawn by the TV seek bar
  /// itself, so no overlay joins it here.
  Widget _tvControls(VideoState state) {
    return TvVideoControls(
      playingStream: _player.stream.playing,
      positionStream: _player.stream.position,
      durationStream: _player.stream.duration,
      initialPlaying: _player.state.playing,
      initialPosition: _player.state.position,
      initialDuration: _player.state.duration,
      seekable: _seekable,
      live: widget.live,
      chapters: _chapters,
      onTogglePlayPause: () => _player.playOrPause(),
      onPlay: () => _player.play(),
      onPause: () => _player.pause(),
      onSkip: _skipSeek,
      onChapterSeek: (forward) => _seekToChapter(forward: forward),
      onSeek: _seekToPosition,
      onToggleFullscreen: () => state.toggleFullscreen(),
      isFullscreen: () => state.isFullscreen(),
    );
  }

  /// The position leaving this screen reports to the unit,
  /// or null when nothing is to be reported (plan 102; the
  /// terms are player_resume_policy's). Decided from this
  /// state's own fields — deliberately nothing through ref:
  /// dispose runs while the widget is deactivating, where
  /// Riverpod 3 forbids ref (plan 104).
  Duration? _resumePositionToReport() {
    if (widget.onResumePosition == null) return null;
    return resumePositionToReport(
      started: _playing,
      completed: _completed,
      position: _lastPosition,
    );
  }

  /// Sends the resume report (plan 102) as the last teardown
  /// step: the player's stop is already under way, and
  /// nothing about leaving waits on the report landing. The
  /// sink invocation sits inside the try because the sink
  /// resolves the unit's services through the caller's ref
  /// before its future exists — a synchronous throw there is
  /// a failed report, not a failed teardown (plan 104).
  void _reportResumePosition(Duration position) {
    final sink = widget.onResumePosition;
    if (sink == null) return;
    _diag(
      DiagCategory.playback,
      'player: reporting the resume position '
      '${position.inSeconds}s to the unit (plan 102)',
    );
    try {
      unawaited(
        sink(position).then(
          (_) {},
          onError: (Object e) {
            _diag(
              DiagCategory.playback,
              'player: resume position report failed: $e',
            );
          },
        ),
      );
    } catch (e) {
      _diag(DiagCategory.playback, 'player: resume position report failed: $e');
    }
  }

  /// Stops the player and then disposes it (plan 104): the
  /// explicit stop silences mpv first, and the dispose runs
  /// even when the stop fails — media_kit's own dispose also
  /// stops internally, but leaving must not depend on a
  /// single call landing.
  Future<void> _stopAndDisposePlayer() async {
    try {
      await _player.stop();
    } catch (e) {
      _diag(DiagCategory.playback, 'player: stop on leaving failed: $e');
    }
    try {
      await _player.dispose();
    } catch (e) {
      _diag(DiagCategory.playback, 'player: dispose on leaving failed: $e');
    }
  }

  /// Stops the playback session (plan 104): closes the
  /// loopback proxy and the DTCP session behind it. A
  /// failure is logged inside and dropped; the session's
  /// stop can never hold up the rest of the teardown.
  Future<void> _stopSession() async {
    try {
      await _session.stop();
    } catch (e) {
      _diag(
        DiagCategory.playback,
        'player: session stop on leaving failed: $e',
      );
    }
  }

  @override
  void dispose() {
    if (_canZap) {
      services.HardwareKeyboard.instance.removeHandler(_onZapKeyEvent);
    }
    // What leaving reports to the unit is decided first,
    // from plain fields, before anything is torn down
    // (plan 104).
    final resumePosition = _resumePositionToReport();
    // Every step runs unconditionally (plan 104; see
    // player_teardown_policy): a failure in one is logged
    // and dropped, so the rest — above all the player's
    // stop — always run, whichever exit path got here.
    runTeardownSteps(
      [
        (name: 'watchdog', run: () => _watchdog?.cancel()),
        (name: 'stall timer', run: () => _stallTimer?.cancel()),
        (name: 'wakelock', run: () => _wakelockSession.release()),
        (
          name: 'subscriptions',
          run: () {
            for (final subscription in _subscriptions) {
              subscription.cancel();
            }
          },
        ),
        (name: 'player', run: () => unawaited(_stopAndDisposePlayer())),
        (name: 'session', run: () => unawaited(_stopSession())),
        if (resumePosition != null)
          (
            name: 'resume report',
            run: () => _reportResumePosition(resumePosition),
          ),
      ],
      onFailure: (name, error) {
        _diag(
          DiagCategory.playback,
          'player: leaving: the $name step failed: $error',
        );
      },
    );
    super.dispose();
  }

  /// The header while channel movement is offered
  /// (owner request, 2026-11-23): the previous channel on
  /// the left, the channel being watched in the centre and
  /// the next channel on the right; tapping a side moves
  /// to that channel. Each name ellipsizes inside its
  /// third of the bar, so a long channel name never pushes
  /// the others out, and the centre keeps the title's
  /// usual style and place.
  Widget _buildZapTitle(BuildContext context) {
    final targets = widget.zapTargets!;
    final count = targets.length;
    final prevIndex = zapIndexAfter(
      current: _zapIndex,
      delta: -1,
      count: count,
    );
    final nextIndex = zapIndexAfter(current: _zapIndex, delta: 1, count: count);
    final theme = Theme.of(context);
    final sideStyle = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget side(int index, {required bool previous}) {
      return InkWell(
        onTap: _zapping ? null : () => _zapTo(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: previous
                ? MainAxisAlignment.start
                : MainAxisAlignment.end,
            children: [
              if (previous) const Icon(Icons.chevron_left, size: 20),
              Flexible(
                child: Text(
                  targets[index].name,
                  style: sideStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: previous ? TextAlign.left : TextAlign.right,
                ),
              ),
              if (!previous) const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(child: side(prevIndex, previous: true)),
        Expanded(
          child: Text(
            targets[_zapIndex].name,
            style: theme.textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(child: side(nextIndex, previous: false)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The device's bottom view padding — the home
    // indicator's area on iPhone / iPad, the gesture
    // bar's on Android, zero where the system keeps the
    // window clear. The non-fullscreen controls' bottom
    // margins grow by it (plan 105, see
    // player_safe_area_policy). viewPadding, not
    // padding: it reports the raw inset whether or not
    // an ancestor has consumed the padding form.
    final bottomViewPadding = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: _canZap ? _buildZapTitle(context) : Text(widget.title),
        actions: [
          if (canChangePlaybackSpeed(live: widget.live))
            PopupMenuButton<double>(
              tooltip: '再生速度',
              initialValue: _playbackRate,
              onSelected: _selectPlaybackRate,
              itemBuilder: (context) => [
                for (final rate in playbackSpeeds)
                  CheckedPopupMenuItem<double>(
                    value: rate,
                    checked: rate == _playbackRate,
                    child: Text(playbackSpeedLabel(rate)),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.speed),
                    if (_playbackRate != 1.0) ...[
                      const SizedBox(width: 4),
                      Text(playbackSpeedLabel(_playbackRate)),
                    ],
                  ],
                ),
              ),
            ),
          if (canSwitchAudio(_realAudioTracks.length))
            PopupMenuButton<int>(
              tooltip: '音声',
              icon: const Icon(Icons.audiotrack),
              initialValue: _selectedAudioIndex,
              onSelected: _selectAudioTrack,
              itemBuilder: (context) => [
                for (var i = 0; i < _realAudioTracks.length; i++)
                  CheckedPopupMenuItem<int>(
                    value: i,
                    checked: i == _selectedAudioIndex,
                    child: Text(audioTrackLabel(i)),
                  ),
              ],
            ),
          if (canToggleSubtitles(_realSubtitleTracks.length))
            IconButton(
              tooltip: '字幕',
              icon: Icon(
                _subtitlesOn ? Icons.closed_caption : Icons.closed_caption_off,
              ),
              onPressed: _toggleSubtitles,
            ),
        ],
      ),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPlayerPointerDown,
        child: _error != null
            ? Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '再生を開始できませんでした。',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'nasne との接続やネットワークの状態を確認して、'
                          'もう一度お試しください。',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        // The raw player error (an mpv message, or
                        // this screen's own timeout wording) is
                        // diagnostic text, not something a viewer
                        // can act on: it sits behind the detail
                        // expander (plan 86, plan 85 item 9), and
                        // is in the diagnostic log as well.
                        ExpansionTile(
                          title: const Text('詳細'),
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : Stack(
                children: [
                  MaterialVideoControlsTheme(
                    normal: _materialControlsTheme(
                      fullscreen: false,
                      bottomViewPadding: bottomViewPadding,
                    ),
                    fullscreen: _materialControlsTheme(fullscreen: true),
                    child: MaterialDesktopVideoControlsTheme(
                      normal: _desktopControlsTheme(),
                      fullscreen: _desktopControlsTheme(),
                      child: Video(
                        controller: _videoController,
                        // The stock adaptive controls, with
                        // the chapter ticks overlaid while
                        // the title has points (plan 112). The
                        // TV variant builds its own remote-
                        // driven controls instead (plan 147).
                        controls: _tvVariant
                            ? _tvControls
                            : _chapters.isEmpty
                            ? AdaptiveVideoControls
                            : _controlsWithChapterTicks,
                      ),
                    ),
                  ),
                  if (_interrupted) _buildInterruptionBanner(),
                ],
              ),
      ),
    );
  }

  /// The interruption notice (plan 80): shown over the
  /// frozen frame when playback that had started dies
  /// mid-stream. Resume re-establishes the stream in place
  /// (see [_resume]); the close button dismisses the notice
  /// and leaves the stopped frame as it is.
  Widget _buildInterruptionBanner() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: Colors.black87,
        // The banner's buttons sit at the screen's bottom
        // edge like the controls do, so its bottom padding
        // clears the gesture area the same way (plan 105,
        // see player_safe_area_policy).
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          10 + bottomGestureInset(MediaQuery.viewPaddingOf(context).bottom),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '再生が中断されました',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_interruptDetail != null)
                    Text(
                      _interruptDetail!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: _resume, child: const Text('再開')),
            IconButton(
              tooltip: '閉じる',
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => setState(() => _interrupted = false),
            ),
          ],
        ),
      ),
    );
  }
}

/// A ±10-second skip button for the video controls' button
/// bars (player UI follow-up). Follows the seekable signal
/// the player screen observes from mpv: enabled — and white,
/// like the neighbouring transport buttons — while the
/// stream is seekable, and a disabled, dimmed button while
/// it is not, so an unseekable stream shows its state
/// instead of inviting a seek that would be refused.
class _SkipSeekButton extends StatelessWidget {
  const _SkipSeekButton({
    required this.seekable,
    required this.offset,
    required this.onSkip,
    this.iconSize = 36,
  });

  /// The observed seekable signal (see _PlayerScreenState).
  final ValueListenable<bool> seekable;

  /// How far this button seeks: −[skipSeekStep] or
  /// +[skipSeekStep]; the sign also picks the icon.
  final Duration offset;

  /// Invoked with [offset] when the button is tapped.
  final void Function(Duration offset) onSkip;

  /// Icon size: 36 in the Material transport row, matching
  /// its larger centre buttons; the desktop row passes its
  /// own 28.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final forward = offset > Duration.zero;
    return ValueListenableBuilder<bool>(
      valueListenable: seekable,
      builder: (context, canSeek, _) => IconButton(
        tooltip: forward ? '10秒スキップ' : '10秒戻し',
        iconSize: iconSize,
        color: Colors.white,
        onPressed: canSeek ? () => onSkip(offset) : null,
        icon: Icon(forward ? Icons.forward_10 : Icons.replay_10),
      ),
    );
  }
}

/// A chapter skip button for the video controls' button
/// bars (plan 112): seeks to the adjacent chapter point
/// (see player_chapter_policy for which point that is).
/// Like the ±10 s skip buttons it follows the seekable
/// signal — enabled and white while the stream is
/// seekable, disabled and dimmed while it is not — and
/// the bars only include it when the title has chapter
/// points at all.
class _ChapterSkipButton extends StatelessWidget {
  const _ChapterSkipButton({
    required this.seekable,
    required this.forward,
    required this.onSeek,
    this.iconSize = 36,
  });

  /// The observed seekable signal (see _PlayerScreenState).
  final ValueListenable<bool> seekable;

  /// True for the next-chapter button, false for the
  /// previous-chapter one; also picks the icon.
  final bool forward;

  /// Invoked when the button is tapped.
  final VoidCallback onSeek;

  /// Icon size, matching the neighbouring transport
  /// buttons (see _SkipSeekButton).
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: seekable,
      builder: (context, canSeek, _) => IconButton(
        tooltip: forward ? '次のチャプター' : '前のチャプター',
        iconSize: iconSize,
        color: Colors.white,
        onPressed: canSeek ? onSeek : null,
        icon: Icon(forward ? Icons.fast_forward : Icons.fast_rewind),
      ),
    );
  }
}

/// The chapter ticks on the seek bar (plan 112): one
/// mark per chapter point, drawn over the stock seek
/// bar's line.
///
/// media_kit's controls expose neither a slot in their
/// seek bar nor their own visibility, so two alignments
/// are maintained here, both best-effort:
///
/// - Geometry: the line's extent and centre are
///   computed from the effective controls theme — the
///   same values the controls lay the bar out with —
///   via player_chapter_policy, so the ticks follow
///   the app's theming (including the safe-area lift
///   of plan 105, which reaches the ticks through the
///   theme's seek bar margin, and the fullscreen
///   safe-area padding the controls substitute).
/// - Visibility: the stock controls show on
///   interaction and fade after their hover duration.
///   This overlay mirrors that from the pointer
///   activity it can observe through a translucent
///   listener, fading on the same duration. The one
///   divergence the mirror cannot see is a tap meant
///   to hide the controls: the ticks then stay for
///   the remainder of the hover duration.
class _ChapterTicksOverlay extends StatefulWidget {
  const _ChapterTicksOverlay({required this.player, required this.chapters});

  final Player player;

  /// The title's chapter points (see
  /// _PlayerScreenState._chapters).
  final List<Duration> chapters;

  @override
  State<_ChapterTicksOverlay> createState() => _ChapterTicksOverlayState();
}

class _ChapterTicksOverlayState extends State<_ChapterTicksOverlay> {
  bool _visible = false;
  Timer? _hideTimer;
  StreamSubscription<Duration>? _durationSubscription;
  Duration _duration = Duration.zero;

  /// The hover duration of the controls theme resolved
  /// by the latest build; the hide timer mirrors it.
  Duration _hoverDuration = const Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _duration = widget.player.state.duration;
    _durationSubscription = widget.player.stream.duration.listen((duration) {
      if (mounted && duration != _duration) {
        setState(() => _duration = duration);
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _durationSubscription?.cancel();
    super.dispose();
  }

  /// Notes an interaction: the ticks show, and the
  /// hide timer restarts — the mirror of the stock
  /// controls' show-and-fade (see the class comment).
  void _poke() {
    if (!_visible) setState(() => _visible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(_hoverDuration, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fractions = chapterTickFractions(
      chapters: widget.chapters,
      duration: _duration,
    );
    if (fractions.isEmpty) return const SizedBox.expand();
    final platform = Theme.of(context).platform;
    final fullscreen = isFullscreen(context);
    final themePadding = fullscreen
        ? MediaQuery.of(context).padding
        : EdgeInsets.zero;
    // The line's geometry depends on the video area's
    // size, which the layout constraints give (the
    // overlay fills the controls' stack).
    ({double left, double right, double centerY}) lineFor(Size area) {
      if (platform == TargetPlatform.android ||
          platform == TargetPlatform.iOS) {
        final themeWidget = MaterialVideoControlsTheme.maybeOf(context);
        final data = fullscreen
            ? (themeWidget?.fullscreen ??
                  kDefaultMaterialVideoControlsThemeDataFullscreen)
            : (themeWidget?.normal ?? kDefaultMaterialVideoControlsThemeData);
        _hoverDuration = data.controlsHoverDuration;
        return materialChapterSeekBarLine(
          areaWidth: area.width,
          areaHeight: area.height,
          columnPadding: data.padding ?? themePadding,
          seekBarMargin: data.seekBarMargin,
          seekBarHeight: data.seekBarHeight,
        );
      }
      final themeWidget = MaterialDesktopVideoControlsTheme.maybeOf(context);
      final data = fullscreen
          ? (themeWidget?.fullscreen ??
                kDefaultMaterialDesktopVideoControlsThemeDataFullscreen)
          : (themeWidget?.normal ??
                kDefaultMaterialDesktopVideoControlsThemeData);
      _hoverDuration = data.controlsHoverDuration;
      return desktopChapterSeekBarLine(
        areaWidth: area.width,
        areaHeight: area.height,
        columnPadding: data.padding ?? themePadding,
        seekBarMargin: data.seekBarMargin,
        seekBarContainerHeight: data.seekBarContainerHeight,
        buttonBarExtent:
            data.buttonBarHeight +
            data.bottomButtonBarMargin.top +
            data.bottomButtonBarMargin.bottom,
        seekBarTranslate: data.bottomButtonBar.isNotEmpty
            ? desktopSeekBarTranslateWithButtonBar
            : 0,
      );
    }

    if (platform != TargetPlatform.android &&
        platform != TargetPlatform.iOS &&
        platform != TargetPlatform.macOS &&
        platform != TargetPlatform.windows &&
        platform != TargetPlatform.linux) {
      // No stock seek bar on this platform (the
      // adaptive controls show none), so no ticks.
      return const SizedBox.expand();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final line = lineFor(Size(constraints.maxWidth, constraints.maxHeight));
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _poke(),
          onPointerMove: (_) => _poke(),
          onPointerHover: (_) => _poke(),
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _visible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: CustomPaint(
                painter: _ChapterTicksPainter(
                  fractions: fractions,
                  left: line.left,
                  right: line.right,
                  centerY: line.centerY,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints the chapter ticks: a short vertical mark at
/// each chapter fraction, centred on the seek bar's
/// line (see _ChapterTicksOverlay for how the line is
/// located).
class _ChapterTicksPainter extends CustomPainter {
  const _ChapterTicksPainter({
    required this.fractions,
    required this.left,
    required this.right,
    required this.centerY,
  });

  /// Chapter positions as fractions of the duration.
  final List<double> fractions;

  /// The seek bar line's horizontal extent and
  /// vertical centre, in the overlay's coordinates.
  final double left;
  final double right;
  final double centerY;

  /// Tick dimensions: taller than the 4 px line so
  /// the marks read as its divisions, narrow enough
  /// not to be mistaken for the thumb.
  static const double tickHeight = 12;
  static const double tickWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final width = right - left;
    if (width <= 0) return;
    final paint = Paint()..color = const Color(0xE6FFFFFF);
    for (final fraction in fractions) {
      final x = left + width * fraction;
      canvas.drawRect(
        Rect.fromLTWH(
          x - tickWidth / 2,
          centerY - tickHeight / 2,
          tickWidth,
          tickHeight,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ChapterTicksPainter oldDelegate) =>
      !listEquals(oldDelegate.fractions, fractions) ||
      oldDelegate.left != left ||
      oldDelegate.right != right ||
      oldDelegate.centerY != centerY;
}
