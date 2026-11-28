/// Programme guide screen (plan 21): the channel x time grid for
/// terrestrial broadcasts, in the official torne layout style —
/// channels as columns, time flowing downwards, one day at a time.
/// Data comes from MetadataService.getProgrammeGuide (the EPGGet
/// dataset behind the MetadataService boundary, plan 12.8); the
/// screen only slices and renders it.
///
/// Plan 86 (plan 85 item 8): the app bar gains a programme
/// search entry point (epg_search_screen), which searches the
/// same held dataset by keyword and genre; its results open
/// the shared event detail dialog ([showEpgEventDetail]).
///
/// A right click (desktop) or a long press (touch) on an
/// event tile opens that programme's menu — 番組情報を見る /
/// 視聴する / 録画, with 録画解除 in place of 録画 for a
/// programme that already has a reservation — the official
/// app's shape (owner request 2026-11-27, extended
/// 2026-11-28; see epg_menu_policy.dart for which items a
/// programme gets). The menu is the search results' row
/// menu's kin: an observing pointer listener over the tile,
/// a right click answered at once and a touch hold timed
/// from the same listener, and showMenu at the press point.
/// The reservation runs the shared guide-event create (see
/// recordGuideEvent) and reports its outcome with that
/// path's wording; the un-reservation runs the detail
/// dialog's delete flow (plan 124). A programme that has
/// already ended offers no menu at all: the detail dialog
/// offers it no reservation either, and there is nothing
/// else for the menu to carry.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/providers.dart';
import '../app/state.dart';
import '../app/bs_epg_providers.dart';
import '../app/cs_epg_providers.dart';
import '../core/core.dart';
import 'channel_visibility.dart';
import 'epg_genre.dart';
import 'epg_menu_policy.dart';
import 'epg_onair_policy.dart';
import 'epg_reserved.dart';
import 'epg_search_screen.dart';
import 'epg_zoom_policy.dart';
import 'error_messages.dart';
import 'format.dart';
import 'live_screen.dart';
import 'player_record_policy.dart';
import 'schedule_form.dart';
import 'epg_subchannel_visibility.dart';
import 'tv_focus.dart';
import 'widgets.dart';

/// The grid's vertical scale — pixels per broadcast
/// minute — is the viewer's zoom (epg_zoom_policy.dart)
/// over the base density; it is threaded down from the
/// screen, never a constant, so a pinch re-densifies the
/// whole grid at once.
const double _channelWidth = 172;
const double _rulerWidth = 40;
const double _headerHeight = 54;

/// Scroll physics that always settles with the grid aligned to a
/// channel-column boundary. Without it the horizontal scroll can
/// rest a few pixels into a column, leaving the leftmost visible
/// column clipped by the viewport edge (its start-time labels lose
/// their first glyph, plan 22).
class _ChannelSnapPhysics extends ScrollPhysics {
  const _ChannelSnapPhysics({super.parent});

  @override
  _ChannelSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _ChannelSnapPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final double nearest =
        ((position.pixels / _channelWidth).round() * _channelWidth).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    if (velocity.abs() < tolerance.velocity &&
        (position.pixels - nearest).abs() < tolerance.distance) {
      // Already at rest on a boundary: defer to the parent physics,
      // whose simulation is null in this state, so the position goes
      // idle. Returning another spring simulation here would loop
      // forever: BallisticScrollActivity re-enters goBallistic(0) when
      // its simulation completes, so a degenerate start == end spring
      // is recreated endlessly, the position never goes idle, and
      // pointer input to the grid stops being delivered (plan 23).
      return super.createBallisticSimulation(position, velocity);
    }
    if (velocity.abs() < tolerance.velocity) {
      // Slow or finished drag: settle to the nearest boundary.
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        nearest,
        velocity,
        tolerance: tolerance,
      );
    }
    // Fling: continue to the next boundary in the fling direction.
    final double target = velocity > 0
        ? (position.pixels / _channelWidth).ceil() * _channelWidth
        : (position.pixels / _channelWidth).floor() * _channelWidth;
    if (target == position.pixels) {
      return super.createBallisticSimulation(position, velocity);
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      velocity,
      tolerance: tolerance,
    );
  }
}

/// Scroll behaviour for the programme guide: on top of the
/// default drag devices, a pressed mouse button also drags, so
/// desktop users can pull scrollable parts of this screen
/// around the way touch users swipe them (5ch request,
/// 2026-11-21). Applied only around the guide body of this
/// screen; the rest of the app keeps the standard desktop
/// behaviour. The grid itself is the exception: it overrides
/// this with [_EpgGridScrollBehavior] and takes its drags
/// through [_GuideGridScroll], so that one drag can move both
/// axes at once. Event tiles still take plain clicks: the
/// gesture arena only turns a press into a drag once it moves
/// past the slop, so a click that does not move lands on the
/// tile exactly as before.
class _EpgScrollBehavior extends MaterialScrollBehavior {
  const _EpgScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

/// Scroll behaviour for the guide grid subtree: no drag devices
/// at all. [_GuideGridScroll] drives both of the grid's scroll
/// positions from one pan recogniser; the scroll views' own
/// drag recognisers must stay out of the gesture arena
/// entirely, or they would lock each drag to a single axis
/// again.
class _EpgGridScrollBehavior extends MaterialScrollBehavior {
  const _EpgGridScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{};
}

/// The guide grid: the horizontal channel scroll view around
/// the vertical day grid, with drags driven by a single pan
/// recogniser instead of the two scroll views' own drag
/// recognisers.
///
/// A horizontal and a vertical drag recogniser in the same
/// gesture arena lock a drag to whichever axis crosses the
/// touch slop first, so a diagonal pull only ever scrolled one
/// way (reported from the Windows build, 2026-11-21: start
/// pulling vertically and only vertical moves, start
/// horizontally and only horizontal moves). Here the grid
/// subtree's [ScrollConfiguration] offers no drag devices (see
/// [_EpgGridScrollBehavior]), and one [PanGestureRecognizer]
/// forwards every update to both scroll positions through the
/// same hold/drag/end hand-off [Scrollable] itself uses — the
/// arrangement the framework's two-dimensional scrolling uses
/// for DiagonalDragBehavior.free. Each position keeps its own
/// physics, so a released fling still settles the channel axis
/// on a column boundary, the time ruler stays in step through
/// the existing controller link, and plain clicks still land
/// on the event tiles: the pan recogniser only claims a press
/// once it moves past the slop.
///
/// A two-finger pinch zooms the grid's vertical density
/// (owner request 2026-11-28, the official app's gesture):
/// an observing [Listener] — never in the gesture arena, so
/// it cannot disturb the pan or the tiles — watches the
/// pointers over the grid; when a second pointer lands, the
/// pinch takes over (any scroll drag in flight is cancelled)
/// and the finger distance drives the zoom scale, reported
/// through [onZoomChanged]. The scroll stays anchored on
/// the broadcast minute under the fingers: the minute at
/// the pinch's start focal point is re-placed under the
/// focal point at the new density once the rebuild lands.
/// One finger alone never zooms — the pan above owns it.
class _GuideGridScroll extends StatefulWidget {
  const _GuideGridScroll({
    required this.gridController,
    required this.bodyController,
    required this.zoomScale,
    required this.onZoomChanged,
    required this.onZoomEnded,
    required this.child,
  });

  /// Horizontal (channel axis) scroll of the grid.
  final ScrollController gridController;

  /// Vertical (time axis) scroll of the day grid.
  final ScrollController bodyController;

  /// The grid's current zoom scale (epg_zoom_policy.dart).
  final double zoomScale;

  /// A pinch moved: the scale it asks for. The screen
  /// holds the scale while the pinch runs and persists it
  /// when the pinch ends ([onZoomEnded]).
  final ValueChanged<double> onZoomChanged;

  /// The pinch ended: the scale it settled on.
  final ValueChanged<double> onZoomEnded;

  final Widget child;

  @override
  State<_GuideGridScroll> createState() => _GuideGridScrollState();
}

class _GuideGridScrollState extends State<_GuideGridScroll> {
  Drag? _horizontalDrag;
  Drag? _verticalDrag;
  ScrollHoldController? _horizontalHold;
  ScrollHoldController? _verticalHold;

  /// The pointers currently down over the grid, by pointer
  /// id, in this widget's local coordinates: the pinch
  /// watch. Two entries make a pinch.
  final Map<int, Offset> _pointers = {};

  /// A pinch is running: the pan handlers stand down (the
  /// drag they were driving was cancelled as it began).
  bool _pinching = false;

  /// The zoom scale when the running pinch began.
  double _pinchStartScale = 1;

  /// The distance between the two fingers when the running
  /// pinch began; the scale grows with the distance's
  /// ratio to this.
  double _pinchStartDistance = 0;

  /// The content offset (in start-scale pixels) of the
  /// broadcast minute under the fingers when the pinch
  /// began — the anchor the scroll is re-placed on as the
  /// density changes.
  double _pinchAnchorContentY = 0;

  /// The vertical scroll offset the anchor asks for,
  /// applied after the zoom's rebuild settles (the scroll
  /// extents are the old density's until then).
  double? _pendingBodyTarget;
  bool _anchorJumpQueued = false;

  ScrollPosition? get _horizontalPosition =>
      widget.gridController.hasClients ? widget.gridController.position : null;

  ScrollPosition? get _verticalPosition =>
      widget.bodyController.hasClients ? widget.bodyController.position : null;

  @override
  void dispose() {
    _horizontalHold?.cancel();
    _horizontalDrag?.cancel();
    _verticalHold?.cancel();
    _verticalDrag?.cancel();
    super.dispose();
  }

  void _disposeHorizontalHold() => _horizontalHold = null;

  void _disposeVerticalHold() => _verticalHold = null;

  void _disposeHorizontalDrag() => _horizontalDrag = null;

  void _disposeVerticalDrag() => _verticalDrag = null;

  // The handlers below mirror ScrollableState's touch handlers,
  // once per axis: hold on down, drag on start, and the drag
  // hand-off disposes the hold on its own.
  void _handleDragDown(DragDownDetails details) {
    _horizontalHold = _horizontalPosition?.hold(_disposeHorizontalHold);
    _verticalHold = _verticalPosition?.hold(_disposeVerticalHold);
  }

  void _handleDragStart(DragStartDetails details) {
    final horizontal = _horizontalPosition;
    if (horizontal != null) {
      _horizontalDrag = horizontal.drag(details, _disposeHorizontalDrag);
    }
    if (_horizontalHold != null) _disposeHorizontalHold();
    final vertical = _verticalPosition;
    if (vertical != null) {
      _verticalDrag = vertical.drag(details, _disposeVerticalDrag);
    }
    if (_verticalHold != null) _disposeVerticalHold();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    // A pinch owns the pointers while it runs; its first
    // finger's pan tail must not scroll underneath it.
    if (_pinching) return;
    // ScrollDragController reads primaryDelta, so each axis
    // gets the pan delta projected onto it, as the framework's
    // two-dimensional scrollable does.
    _horizontalDrag?.update(
      DragUpdateDetails(
        sourceTimeStamp: details.sourceTimeStamp,
        delta: Offset(details.delta.dx, 0.0),
        primaryDelta: details.delta.dx,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
    );
    _verticalDrag?.update(
      DragUpdateDetails(
        sourceTimeStamp: details.sourceTimeStamp,
        delta: Offset(0.0, details.delta.dy),
        primaryDelta: details.delta.dy,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
    );
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    _horizontalDrag?.end(
      DragEndDetails(
        velocity: Velocity(pixelsPerSecond: Offset(velocity.dx, 0.0)),
        primaryVelocity: velocity.dx,
      ),
    );
    _verticalDrag?.end(
      DragEndDetails(
        velocity: Velocity(pixelsPerSecond: Offset(0.0, velocity.dy)),
        primaryVelocity: velocity.dy,
      ),
    );
  }

  void _handleDragCancel() {
    _horizontalHold?.cancel();
    _horizontalDrag?.cancel();
    _verticalHold?.cancel();
    _verticalDrag?.cancel();
  }

  // The pinch watch: an observing listener's handlers.
  // They only ever read the pointers and drive the zoom;
  // nothing here takes an event away from the pan or the
  // tiles.

  void _handlePointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) _beginPinch();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pinching && _pointers.length == 2) _updatePinch();
  }

  void _handlePointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pinching && _pointers.length < 2) {
      _pinching = false;
      widget.onZoomEnded(widget.zoomScale);
    }
  }

  /// The second finger landed: the pinch takes over from
  /// whatever the first finger was doing (a scroll drag in
  /// flight is cancelled, so its release cannot fling),
  /// and the anchor is fixed — the broadcast minute under
  /// the fingers, in the density of this moment.
  void _beginPinch() {
    final points = _pointers.values.toList();
    _pinchStartDistance = (points[0] - points[1]).distance;
    _pinchStartScale = widget.zoomScale;
    final focal = (points[0] + points[1]) / 2;
    // The day grid's viewport starts below the channel
    // header, so the focal point's place inside it is its
    // distance from there.
    _pinchAnchorContentY =
        (_verticalPosition?.pixels ?? 0) + (focal.dy - _headerHeight);
    _pinching = true;
    _handleDragCancel();
  }

  /// A finger moved mid-pinch: the finger distance's
  /// growth over its starting distance is the zoom, and
  /// the anchor minute is re-placed under the fingers at
  /// the new density.
  void _updatePinch() {
    final points = _pointers.values.toList();
    final distance = (points[0] - points[1]).distance;
    if (_pinchStartDistance <= 0) return;
    final scale = clampEpgZoomScale(
      _pinchStartScale * distance / _pinchStartDistance,
    );
    if ((scale - widget.zoomScale).abs() > 0.001) {
      widget.onZoomChanged(scale);
    }
    final focal = (points[0] + points[1]) / 2;
    final ratio =
        epgPxPerMinuteForScale(scale) /
        epgPxPerMinuteForScale(_pinchStartScale);
    _pendingBodyTarget =
        _pinchAnchorContentY * ratio - (focal.dy - _headerHeight);
    _queueAnchorJump();
  }

  /// Applies the anchor's scroll offset once the zoom's
  /// rebuild has settled: until then the scroll position's
  /// extents are still the old density's, and a jump would
  /// clamp against them.
  void _queueAnchorJump() {
    if (_anchorJumpQueued) return;
    _anchorJumpQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorJumpQueued = false;
      final target = _pendingBodyTarget;
      _pendingBodyTarget = null;
      final position = _verticalPosition;
      if (target == null || position == null || !mounted) return;
      position.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer(
                supportedDevices: const <PointerDeviceKind>{
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.invertedStylus,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.unknown,
                },
              ),
              (PanGestureRecognizer instance) {
                instance
                  ..onDown = _handleDragDown
                  ..onStart = _handleDragStart
                  ..onUpdate = _handleDragUpdate
                  ..onEnd = _handleDragEnd
                  ..onCancel = _handleDragCancel
                  ..dragStartBehavior = DragStartBehavior.start
                  ..velocityTrackerBuilder = ScrollConfiguration.of(context)
                      .velocityTrackerBuilder(context)
                  ..gestureSettings = MediaQuery.maybeGestureSettingsOf(
                    context,
                  );
              },
            ),
      },
      child: ScrollConfiguration(
        behavior: const _EpgGridScrollBehavior(),
        child: SingleChildScrollView(
          controller: widget.gridController,
          scrollDirection: Axis.horizontal,
          physics: const _ChannelSnapPhysics(),
          child: widget.child,
        ),
      ),
      ),
    );
  }
}

class EpgScreen extends ConsumerStatefulWidget {
  const EpgScreen({super.key});

  @override
  ConsumerState<EpgScreen> createState() => _EpgScreenState();
}

class _EpgScreenState extends ConsumerState<EpgScreen> {
  /// Selected day as a JST calendar date (stored as a UTC-midnight
  /// DateTime of the JST date fields, like format.dart's helpers).
  DateTime? _selectedDay;
  bool _scrolledToNow = false;
  int _selectedBand = terrestrialBroadcastingType;

  /// The zoom scale while a pinch is running: the pinch
  /// drives the grid's density live through this, and the
  /// settled scale goes to the persisted setting
  /// (epgZoomProvider) when the pinch ends — so the
  /// key-value store sees one write per pinch, not one
  /// per finger move.
  double? _pinchZoomScale;

  final _rulerController = ScrollController();
  final _bodyController = ScrollController();
  final _gridController = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _link(_rulerController, _bodyController);
    _link(_bodyController, _rulerController);
  }

  void _link(ScrollController from, ScrollController to) {
    from.addListener(() {
      if (_syncing || !to.hasClients) return;
      _syncing = true;
      if ((to.offset - from.offset).abs() > 0.5) to.jumpTo(from.offset);
      _syncing = false;
    });
  }

  @override
  void dispose() {
    _rulerController.dispose();
    _bodyController.dispose();
    _gridController.dispose();
    super.dispose();
  }

  /// The JST calendar date (as UTC fields) containing [instant].
  static DateTime _jstDateOf(DateTime instant) {
    final jst = instant.toUtc().add(const Duration(hours: 9));
    return DateTime.utc(jst.year, jst.month, jst.day);
  }

  /// Invalidates the selected band's guide providers. A
  /// refresh also drops the band's channel logos (terrestrial
  /// and BS; CS fetches no logos, plan 137); the error retry
  /// leaves logos alone, as it always has.
  void _invalidateBandGuide(RegisteredNasne reg, {required bool refresh}) {
    switch (_selectedBand) {
      case bsBroadcastingType:
        ref.invalidate(bsChannelsProvider(reg));
        ref.invalidate(bsEpgGuideProvider(reg));
        if (refresh) ref.invalidate(bsChannelLogosProvider(reg));
      case csBroadcastingType:
        ref.invalidate(csChannelsProvider(reg));
        ref.invalidate(csEpgGuideProvider(reg));
      default:
        ref.invalidate(epgGuideProvider(reg));
        if (refresh) ref.invalidate(channelLogosProvider(reg));
    }
  }

  /// The instant a JST calendar date starts.
  static DateTime _jstDayStart(DateTime jstDate) =>
      jstDate.subtract(const Duration(hours: 9));

  /// Reserves a guide tile's programme from its menu:
  /// the shared guide-event create (see recordGuideEvent),
  /// with the outcome reported in that path's wording —
  /// the same feedback the search results' row menu and
  /// the live player's record action give.
  Future<void> _recordEvent(
    RegisteredNasne reg,
    Channel channel,
    EpgEvent event,
  ) async {
    final result = await recordGuideEvent(
      ref: ref,
      reg: reg,
      channel: channel,
      event: event,
    );
    if (!mounted) return;
    showSnack(context, liveRecordResultMessage(result));
  }

  @override
  Widget build(BuildContext context) {
    final reg = ref.watch(selectedRegistrationProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('番組表'),
        actions: [
          if (reg != null)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '番組検索',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EpgSearchScreen(reg: reg),
                ),
              ),
            ),
          if (reg != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '更新',
              onPressed: () {
                ref.invalidate(schedulesProvider(reg));
                _invalidateBandGuide(reg, refresh: true);
              },
            ),
        ],
      ),
      body: reg == null
          ? NoDeviceView(
              onRegister: () =>
                  ref.read(tabIndexProvider.notifier).select(AppTabs.settings),
            )
          : ScrollConfiguration(
              behavior: const _EpgScrollBehavior(),
              child: _buildBandGuide(reg),
            ),
    );
  }

  Widget _buildBandGuide(RegisteredNasne reg) {
    final guideAsync = switch (_selectedBand) {
      bsBroadcastingType => ref.watch(bsEpgGuideProvider(reg)),
      csBroadcastingType => ref.watch(csEpgGuideProvider(reg)),
      _ => ref.watch(epgGuideProvider(reg)),
    };
    // CS channel logos are not fetched (unmeasured, plan 137);
    // the header falls back to channel names alone.
    final logos = switch (_selectedBand) {
      bsBroadcastingType =>
        ref.watch(bsChannelLogosProvider(reg)).value ??
            const <int, List<int>>{},
      csBroadcastingType => const <int, List<int>>{},
      _ =>
        ref.watch(channelLogosProvider(reg)).value ?? const <int, List<int>>{},
    };
    // Reserved marking (plan 120): the same reservation list the
    // schedules tab shows, shared through schedulesProvider, so a
    // reservation created or deleted anywhere — including from
    // this guide — repaints the grid when the provider is
    // invalidated. While the list is loading or failed the guide
    // simply shows no frames; it never blocks on it.
    final reservedIndex = EpgReservedIndex.fromSchedules(
      ref.watch(schedulesProvider(reg)).value ?? const <RecordSchedule>[],
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: terrestrialBroadcastingType,
                label: Text('地デジ'),
              ),
              ButtonSegment<int>(value: bsBroadcastingType, label: Text('BS')),
              ButtonSegment<int>(value: csBroadcastingType, label: Text('CS')),
            ],
            selected: {_selectedBand},
            onSelectionChanged: (selection) => setState(() {
              _selectedBand = selection.first;
              _scrolledToNow = false;
            }),
          ),
        ),
        Expanded(
          child: guideAsync.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              message: userMessageForError(e),
              onRetry: () {
                ref.invalidate(schedulesProvider(reg));
                _invalidateBandGuide(reg, refresh: false);
              },
            ),
            data: (guide) => _GuideView(
              reg: reg,
              reservedIndex: reservedIndex,
              // The viewer's not-watched channels drop out of
              // the guide as they do from the live list (owner
              // request 2026-11-26): the column itself goes,
              // not just its events.
              guide: guideWithHiddenChannels(
                guideWithSubchannelSetting(
                  guide,
                  ref.watch(showSubchannelsProvider),
                ),
                ref.watch(hiddenChannelsProvider),
              ),
              hiddenGenres: ref.watch(hiddenEpgGenresProvider),
              onWatchEvent: (channel) => openLiveChannelForEpg(
                context,
                ref,
                reg: reg,
                channel: channel,
              ),
              onDeleteReserved: (schedule) =>
                  deleteScheduleAndInvalidate(ref, reg, schedule),
              onRecordEvent: (channel, event) =>
                  _recordEvent(reg, channel, event),
              logos: logos,
              selectedDay: _selectedDay,
              onSelectDay: (day) => setState(() {
                _selectedDay = day;
                _scrolledToNow = false;
              }),
              rulerController: _rulerController,
              bodyController: _bodyController,
              gridController: _gridController,
              scrolledToNow: _scrolledToNow,
              onScrolledToNow: () => _scrolledToNow = true,
              zoomScale: _pinchZoomScale ?? ref.watch(epgZoomProvider),
              onZoomChanged: (scale) =>
                  setState(() => _pinchZoomScale = scale),
              onZoomEnded: (scale) {
                setState(() => _pinchZoomScale = null);
                unawaited(ref.read(epgZoomProvider.notifier).set(scale));
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _GuideView extends StatelessWidget {
  const _GuideView({
    required this.reg,
    required this.reservedIndex,
    required this.guide,
    required this.hiddenGenres,
    required this.onWatchEvent,
    required this.onDeleteReserved,
    required this.onRecordEvent,
    required this.logos,
    required this.selectedDay,
    required this.onSelectDay,
    required this.rulerController,
    required this.bodyController,
    required this.gridController,
    required this.scrolledToNow,
    required this.onScrolledToNow,
    required this.zoomScale,
    required this.onZoomChanged,
    required this.onZoomEnded,
  });

  final RegisteredNasne reg;

  /// Which events already have a reservation (plan 120).
  final EpgReservedIndex reservedIndex;
  final EpgGuide guide;

  /// Genres the viewer marked as not watched (plan 95):
  /// their tiles paint blank.
  final Set<int> hiddenGenres;

  /// Opens live viewing for a guide channel (plan 95);
  /// offered from the event detail while the event is on air.
  final void Function(Channel channel) onWatchEvent;

  /// Deletes the reservation covering a guide event
  /// (plan 124); wired by the screen to the device.
  final Future<void> Function(RecordSchedule schedule) onDeleteReserved;

  /// Reserves a guide event from its tile's menu (owner
  /// request 2026-11-27); wired by the screen to the
  /// shared guide-event create.
  final void Function(Channel channel, EpgEvent event) onRecordEvent;
  final Map<int, List<int>> logos;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onSelectDay;
  final ScrollController rulerController;
  final ScrollController bodyController;
  final ScrollController gridController;
  final bool scrolledToNow;
  final VoidCallback onScrolledToNow;

  /// The grid's zoom scale (epg_zoom_policy.dart): the
  /// density every part of the grid below is laid out at.
  final double zoomScale;

  /// A pinch over the grid moved / ended (see
  /// _GuideGridScroll).
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<double> onZoomEnded;

  @override
  Widget build(BuildContext context) {
    final pxPerMinute = epgPxPerMinuteForScale(zoomScale);
    final from = guide.from;
    final to = guide.to;
    if (from == null || to == null || guide.services.isEmpty) {
      return const Center(child: Text('番組データがありません。'));
    }
    final firstDay = _EpgScreenState._jstDateOf(from);
    final lastDay = _EpgScreenState._jstDateOf(
      to.subtract(const Duration(seconds: 1)),
    );
    final days = <DateTime>[
      for (
        var d = firstDay;
        !d.isAfter(lastDay);
        d = d.add(const Duration(days: 1))
      )
        d,
    ];
    final today = _EpgScreenState._jstDateOf(DateTime.now());
    final day = selectedDay != null && days.contains(selectedDay)
        ? selectedDay!
        : (days.contains(today) ? today : days.first);
    final dayStart = _EpgScreenState._jstDayStart(day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    // Initial position: one hour before "now" when today is shown.
    if (!scrolledToNow && day == today) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (bodyController.hasClients) {
          final now = DateTime.now();
          final minutes = now.difference(dayStart).inMinutes - 60;
          // Clamp to the scrollable range: late in the evening the
          // raw target exceeds the maximum extent, and an out-of-range
          // rest position leaves the grid in a corrected state that
          // does not accept drags cleanly (plan 23).
          final target = math.max(0, minutes * pxPerMinute).toDouble();
          bodyController.jumpTo(
            math.min(target, bodyController.position.maxScrollExtent),
          );
        }
        onScrolledToNow();
      });
    }

    return Column(
      children: [
        _DaySelector(days: days, selected: day, onSelect: onSelectDay),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _rulerWidth,
                child: Column(
                  children: [
                    const SizedBox(height: _headerHeight),
                    Expanded(
                      child: _TimeRuler(
                        controller: rulerController,
                        pxPerMinute: pxPerMinute,
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _GuideGridScroll(
                  gridController: gridController,
                  bodyController: bodyController,
                  zoomScale: zoomScale,
                  onZoomChanged: onZoomChanged,
                  onZoomEnded: onZoomEnded,
                  child: SizedBox(
                    width: _channelWidth * guide.services.length,
                    child: Column(
                      children: [
                        _ChannelHeader(services: guide.services, logos: logos),
                        Expanded(
                          child: _DayGrid(
                            reg: reg,
                            reservedIndex: reservedIndex,
                            services: guide.services,
                            hiddenGenres: hiddenGenres,
                            onWatchEvent: onWatchEvent,
                            onDeleteReserved: onDeleteReserved,
                            onRecordEvent: onRecordEvent,
                            dayStart: dayStart,
                            dayEnd: dayEnd,
                            controller: bodyController,
                            pxPerMinute: pxPerMinute,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.days,
    required this.selected,
    required this.onSelect,
  });

  final List<DateTime> days;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final today = _EpgScreenState._jstDateOf(DateTime.now());
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          for (final day in days)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(
                  day == today
                      ? '今日 ${day.month}/${day.day}'
                      : '${day.month}/${day.day} (${formatWeekdayJst(day.add(const Duration(hours: 9)))})',
                ),
                selected: day == selected,
                onSelected: (_) => onSelect(day),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({required this.services, required this.logos});

  final List<EpgServiceGuide> services;
  final Map<int, List<int>> logos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _headerHeight,
      child: Row(
        children: [
          for (final service in services)
            SizedBox(
              width: _channelWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (logos[service.channel.serviceId] != null)
                      SizedBox(
                        height: 24,
                        child: Image.memory(
                          Uint8List.fromList(logos[service.channel.serviceId]!),
                          fit: BoxFit.contain,
                        ),
                      ),
                    Text(
                      service.channel.serviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeRuler extends StatelessWidget {
  const _TimeRuler({required this.controller, required this.pxPerMinute});

  final ScrollController controller;

  /// The grid's density (pixels per broadcast minute) at
  /// the current zoom.
  final double pxPerMinute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      controller: controller,
      physics: const NeverScrollableScrollPhysics(),
      child: SizedBox(
        height: 24 * 60 * pxPerMinute,
        child: Stack(
          children: [
            for (var hour = 0; hour < 24; hour++)
              Positioned(
                top: hour * 60 * pxPerMinute + 2,
                left: 0,
                right: 0,
                child: Text(
                  '$hour',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.reg,
    required this.reservedIndex,
    required this.services,
    required this.hiddenGenres,
    required this.onWatchEvent,
    required this.onDeleteReserved,
    required this.onRecordEvent,
    required this.dayStart,
    required this.dayEnd,
    required this.controller,
    required this.pxPerMinute,
  });

  final RegisteredNasne reg;
  final EpgReservedIndex reservedIndex;
  final List<EpgServiceGuide> services;
  final Set<int> hiddenGenres;
  final void Function(Channel channel) onWatchEvent;

  /// Deletes the reservation covering a guide event
  /// (plan 124); wired by the screen to the device.
  final Future<void> Function(RecordSchedule schedule) onDeleteReserved;

  /// Reserves a guide event from its tile's menu (owner
  /// request 2026-11-27); wired by the screen to the
  /// shared guide-event create.
  final void Function(Channel channel, EpgEvent event) onRecordEvent;
  final DateTime dayStart;
  final DateTime dayEnd;
  final ScrollController controller;

  /// The grid's density (pixels per broadcast minute) at
  /// the current zoom.
  final double pxPerMinute;

  @override
  Widget build(BuildContext context) {
    final dayHeight = 24 * 60 * pxPerMinute;
    final isToday =
        _EpgScreenState._jstDateOf(DateTime.now()) ==
        _EpgScreenState._jstDateOf(dayStart);
    final nowOffset = isToday
        ? DateTime.now().difference(dayStart).inMinutes * pxPerMinute
        : null;
    return SingleChildScrollView(
      controller: controller,
      child: SizedBox(
        height: dayHeight,
        child: Stack(
          children: [
            // Hour gridlines.
            for (var hour = 0; hour <= 24; hour++)
              Positioned(
                top: hour * 60 * pxPerMinute,
                left: 0,
                right: 0,
                child: const Divider(height: 1),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < services.length; i++)
                  SizedBox(
                    width: _channelWidth,
                    height: dayHeight,
                    child: Stack(
                      children: [
                        for (final event in services[i].events.where(
                          (e) =>
                              e.end.isAfter(dayStart) &&
                              e.start.isBefore(dayEnd),
                        ))
                          _EventTile(
                            key: ValueKey(
                              '${services[i].channel.serviceId}-${event.eventId}-${event.start}',
                            ),
                            event: event,
                            channel: services[i].channel,
                            channelName: services[i].channel.serviceName,
                            reg: reg,
                            dayStart: dayStart,
                            suppressed: epgGenreSuppressed(
                              event.genreLevel1,
                              hiddenGenres,
                            ),
                            reserved: reservedIndex.isReserved(
                              services[i].channel,
                              event,
                            ),
                            reservedSchedule: reservedIndex.scheduleFor(
                              services[i].channel,
                              event,
                            ),
                            onDeleteReserved: onDeleteReserved,
                            onRecord: () =>
                                onRecordEvent(services[i].channel, event),
                            onWatch: () => onWatchEvent(services[i].channel),
                            pxPerMinute: pxPerMinute,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            if (nowOffset != null && nowOffset >= 0 && nowOffset <= dayHeight)
              Positioned(
                top: nowOffset,
                left: 0,
                right: 0,
                child: Container(height: 2, color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}

/// One event's tile in the day grid.
///
/// A right click (desktop) or a long press (touch) on the
/// tile opens the programme's menu — 番組情報を見る /
/// 視聴する / 録画, or 録画解除 for a programme that
/// already has a reservation (owner requests 2026-11-27
/// and 2026-11-28; the composition is epg_menu_policy's).
/// The arrangement is the search
/// results' row menu's (see _SearchHitRow in
/// epg_search_screen.dart): an observing pointer listener
/// over the tile — it never takes the event, so the
/// tile's tap and the grid's pan scroll keep every pointer
/// event they already handle — a right click answered at
/// once, and a touch hold timed from the same listener,
/// never a gesture recogniser, so the hold is not
/// competed for. One consequence of not competing: the
/// tile's tap still lands when the held finger lifts, so
/// a hold that opened the menu swallows the tap that
/// follows it — that tap would open the detail dialog
/// over the menu. A programme that has already ended
/// opens no menu (see the library note), so its hold
/// swallows nothing and the tap tail opens the detail,
/// as a plain tap does.
class _EventTile extends StatefulWidget {
  const _EventTile({
    super.key,
    required this.event,
    required this.channel,
    required this.channelName,
    required this.reg,
    required this.dayStart,
    required this.suppressed,
    required this.reserved,
    required this.reservedSchedule,
    required this.onDeleteReserved,
    required this.onRecord,
    required this.onWatch,
    required this.pxPerMinute,
  });

  final EpgEvent event;
  final Channel channel;
  final String channelName;
  final RegisteredNasne reg;
  final DateTime dayStart;

  /// The event's genre is one the viewer marked as not
  /// watched (plan 95): the tile paints as a blank of plain
  /// surface colour — no tint, no text — so it does not draw
  /// the eye. The slot and the tap (the detail dialog) stay.
  final bool suppressed;

  /// The event already has a recording reservation
  /// (plan 120): the tile is framed in red, over whatever
  /// tint (or suppression blank) it otherwise paints, so
  /// the reservation reads at a glance without hiding
  /// the genre.
  final bool reserved;

  /// The reservation covering this event, when there is
  /// one (plan 124): the detail dialog offers deleting it
  /// instead of a new reservation.
  final RecordSchedule? reservedSchedule;

  /// Deletes [reservedSchedule] on the device (plan 124).
  final Future<void> Function(RecordSchedule schedule) onDeleteReserved;

  /// Reserves this tile's programme from its menu: the
  /// screen's own record run (its feedback lives there).
  final VoidCallback onRecord;

  /// Opens live viewing for this tile's channel (plan 95);
  /// the detail dialog — and now the tile's menu — offer
  /// it only while the event is on air.
  final VoidCallback onWatch;

  /// The grid's density (pixels per broadcast minute) at
  /// the current zoom: the tile's place and height in the
  /// day come from it.
  final double pxPerMinute;

  @override
  State<_EventTile> createState() => _EventTileState();
}

class _EventTileState extends State<_EventTile> {
  Timer? _longPressTimer;
  int? _longPressPointer;
  Offset? _longPressStart;

  /// The last hold opened the menu: the tap the finger's
  /// lift still delivers is that hold's tail, not a tap
  /// on the tile, and is swallowed once. A fresh press
  /// clears a leftover — a menu dismissed from its
  /// barrier never delivers the tap, and the next press
  /// on the tile is a new gesture, not that hold's tail.
  bool _swallowNextTap = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  /// A right click (a secondary mouse button press) on
  /// the tile opens the programme's menu at the press
  /// point. A touch press starts the hold the long press
  /// is timed from, the same pair of arrangements as the
  /// search results' listener.
  void _onTilePointerDown(PointerDownEvent event) {
    if ((event.buttons & kSecondaryMouseButton) != 0) {
      unawaited(_showEventMenu(event.position));
      return;
    }
    if ((event.buttons & kPrimaryButton) != 0) {
      _swallowNextTap = false;
      if (event.kind == PointerDeviceKind.touch) {
        _longPressPointer = event.pointer;
        _longPressStart = event.position;
        _longPressTimer?.cancel();
        _longPressTimer = Timer(kLongPressTimeout, _onTileLongPressFired);
      }
    }
  }

  /// The held touch reached the long-press timeout still
  /// down: open the menu where the press began.
  void _onTileLongPressFired() {
    _longPressTimer = null;
    final start = _longPressStart;
    _longPressPointer = null;
    _longPressStart = null;
    if (start != null && mounted) {
      unawaited(_showEventMenu(start));
    }
  }

  /// Ends a tracked hold without opening the menu: the
  /// finger lifted or the press was cancelled before the
  /// timeout.
  void _onTilePointerEnd(PointerEvent event) {
    if (event.pointer != _longPressPointer) return;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _longPressPointer = null;
    _longPressStart = null;
  }

  /// A tracked press that wanders past the touch slop is
  /// a pan of the grid, not a hold: it stops being a long
  /// press.
  void _onTilePointerMove(PointerMoveEvent event) {
    if (event.pointer != _longPressPointer) return;
    final start = _longPressStart;
    if (start != null && (event.position - start).distance > kTouchSlop) {
      _onTilePointerEnd(event);
    }
  }

  /// The programme's menu at [position], the search
  /// menu's shape: showMenu over a zero-size rect at the
  /// press point, its items from epg_menu_policy (the
  /// official app's shape). A programme that has already
  /// ended has nothing to offer — the detail dialog offers
  /// it no reservation either — so no menu opens, and
  /// nothing is swallowed: a hold's tap tail goes on to
  /// open the detail, as a plain tap does. When the menu
  /// does open, the tap tail is swallowed first, so it
  /// cannot open the detail over the menu.
  Future<void> _showEventMenu(Offset position) async {
    final event = widget.event;
    final actions = epgMenuActions(
      start: event.start,
      end: event.end,
      now: DateTime.now(),
      reserved: widget.reservedSchedule != null,
    );
    if (actions.isEmpty) return;
    _swallowNextTap = true;
    final overlay = Overlay.of(context).context.findRenderObject()!;
    final chosen = await showMenu<EpgMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & (overlay as RenderBox).size,
      ),
      items: [for (final action in actions) epgMenuItem(action)],
    );
    if (chosen == null || !mounted) return;
    switch (chosen) {
      case EpgMenuAction.detail:
        _openDetail();
      case EpgMenuAction.watch:
        widget.onWatch();
      case EpgMenuAction.record:
        widget.onRecord();
      case EpgMenuAction.unrecord:
        final schedule = widget.reservedSchedule;
        if (schedule != null) {
          await confirmAndDeleteGuideReservation(
            context,
            schedule: schedule,
            onDeleteReserved: widget.onDeleteReserved,
          );
        }
    }
  }

  void _handleTap() {
    if (_swallowNextTap) {
      _swallowNextTap = false;
      return;
    }
    _openDetail();
  }

  /// The tile's plain tap (and the menu's 番組情報を見る):
  /// the shared programme detail dialog.
  void _openDetail() {
    showEpgEventDetail(
      context,
      reg: widget.reg,
      channel: widget.channel,
      channelName: widget.channelName,
      event: widget.event,
      onWatch: widget.onWatch,
      reservedSchedule: widget.reservedSchedule,
      onDeleteReserved: widget.onDeleteReserved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final dayStart = widget.dayStart;
    final suppressed = widget.suppressed;
    final reserved = widget.reserved;
    final theme = Theme.of(context);
    final startMin = math.max(0, event.start.difference(dayStart).inMinutes);
    final endMin = math.min(24 * 60, event.end.difference(dayStart).inMinutes);
    final top = startMin * widget.pxPerMinute;
    final height = math.max(
      10,
      (endMin - startMin) * widget.pxPerMinute - 1,
    );
    // On air right now (epg_onair_policy): the tile's
    // genre tint deepens and — unless the reserved frame
    // owns the edge — an accent frame joins it, so the
    // programme on air reads at a glance. A suppressed
    // tile stays the plain blank it is: drawing the eye
    // is exactly what suppression is against.
    final onAir =
        !suppressed &&
        epgEventIsOnAir(start: event.start, end: event.end, now: DateTime.now());
    final title = event.title;
    final timeText = formatTimeJst(event.start);
    final timeStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.bold,
    );
    // Title lines that fit under the time line: the time line is
    // about 16px at the labelSmall size and a title line about
    // 17px, with 2px of vertical padding at each edge.
    final maxTitleLines = ((height - 4 - 16) / 17).floor();
    return Positioned(
      top: top,
      left: 1,
      right: 1,
      height: height.toDouble(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onTilePointerDown,
        onPointerMove: _onTilePointerMove,
        onPointerUp: _onTilePointerEnd,
        onPointerCancel: _onTilePointerEnd,
        child: Container(
          // The tile's frame (plan 120, on-air emphasis)
          // is a foreground decoration: it paints over the
          // tile's edge and leaves the genre tint inside
          // untouched. The reserved frame owns the edge
          // when both apply (epg_onair_policy).
          foregroundDecoration: epgTileFrame(
            reserved: reserved,
            onAir: onAir,
            onAirColor: theme.colorScheme.primary,
          ),
          child: Material(
            // Tiles are tinted by the event's genre (plan 86,
            // plan 85 item 10); events without a known genre
            // keep the neutral colour they have always had.
            // A suppressed genre (plan 95) paints the plain
            // surface instead, with no text below. A tile on
            // air paints the deepened on-air tint instead of
            // the resting one.
            color: suppressed
                ? theme.colorScheme.surface
                : onAir
                ? epgOnAirTileColor(
                    genreLevel1: event.genreLevel1,
                    surface: theme.colorScheme.surface,
                    fallback: theme.colorScheme.surfaceContainerHighest,
                    accent: theme.colorScheme.primary,
                  )
                : epgGenreTileColor(
                    genreLevel1: event.genreLevel1,
                    surface: theme.colorScheme.surface,
                    fallback: theme.colorScheme.surfaceContainerHighest,
                  ),
            borderRadius: BorderRadius.circular(3),
            // Tiles too short for their text must not paint outside
            // their box: spilled glyphs used to bleed into the tile
            // below and get half-covered there (plan 22).
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: _handleTap,
              child: suppressed
                  ? const SizedBox.expand()
                  : maxTitleLines >= 1
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(timeText, style: timeStyle),
                          if (title != null)
                            Expanded(
                              child: Text(
                                title,
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                                maxLines: maxTitleLines.clamp(1, 4),
                              ),
                            ),
                        ],
                      ),
                    )
                  : Padding(
                      // Compact form for tiles too short for two lines:
                      // time and title share one small line.
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            timeText,
                            style: timeStyle?.copyWith(
                              fontSize: 10,
                              height: 1.1,
                            ),
                          ),
                          if (title != null) ...[
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                title,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10,
                                  height: 1.1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the programme detail dialog for a guide [event],
/// with the reservation action wired to the prefilled form
/// when the event has not ended yet. Shared by the guide
/// grid's tiles and the programme search results (plan 86),
/// so both paths offer exactly the same detail and the same
/// way into a reservation.
///
/// Reserve from the guide (plan 28): opens the create form
/// prefilled with this event, through the same XSRS create
/// path as a manual reservation. Events that have already
/// ended cannot be reserved.
///
/// Watch from the guide (plan 95): while the event is on air,
/// [onWatch] — wired by the caller to the channel's live
/// viewing — is offered next to the reservation. Before the
/// start and after the end there is nothing of this event to
/// watch (the live stream carries whatever is on air then),
/// so the action is not shown at all.
///
/// Delete from the guide (plan 124): when the event is
/// already reserved — [reservedSchedule] is the concrete
/// reservation the guide's marking matched (plan 120) —
/// the dialog offers deleting that reservation instead of
/// the reservation form, through [onDeleteReserved].
void showEpgEventDetail(
  BuildContext context, {
  required RegisteredNasne reg,
  required Channel channel,
  required String channelName,
  required EpgEvent event,
  VoidCallback? onWatch,
  RecordSchedule? reservedSchedule,
  Future<void> Function(RecordSchedule schedule)? onDeleteReserved,
}) {
  final now = DateTime.now();
  final watchable =
      onWatch != null && !event.start.isAfter(now) && event.end.isAfter(now);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => EpgEventDetailDialog(
      event: event,
      channelName: channelName,
      onReserve: event.end.isAfter(now)
          ? () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ScheduleFormPage.fromEpg(
                    reg,
                    channel: channel,
                    event: event,
                  ),
                ),
              );
            }
          : null,
      onWatch: watchable
          ? () {
              Navigator.of(dialogContext).pop();
              onWatch();
            }
          : null,
      onDeleteReservation: reservedSchedule != null && onDeleteReserved != null
          ? () => _deleteReservedFromDetail(
              context,
              dialogContext,
              reservedSchedule,
              onDeleteReserved,
            )
          : null,
    ),
  );
}

/// One row of the programme menu (see epg_menu_policy.dart
/// for which actions a programme gets, and their order).
/// Shared by the guide tile's menu and the search row's
/// menu, so both offer the same items in the same words.
PopupMenuItem<EpgMenuAction> epgMenuItem(EpgMenuAction action) {
  final (icon, label) = switch (action) {
    EpgMenuAction.detail => (Icons.info_outline, '番組情報を見る'),
    EpgMenuAction.watch => (Icons.live_tv, '視聴する'),
    EpgMenuAction.record => (Icons.fiber_manual_record, '録画'),
    EpgMenuAction.unrecord => (Icons.remove_circle_outline, '録画解除'),
  };
  return PopupMenuItem<EpgMenuAction>(
    value: action,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ],
    ),
  );
}

/// The delete flow behind the detail dialog's
/// delete-reservation action (plan 124): confirm, delete
/// the matched reservation on the device, then close the
/// detail and report. The reservation-list invalidation
/// rides along in [onDeleteReserved], so the guide's red
/// frame clears with the same repaint as the schedules
/// tab. A refusal from the device keeps the detail open
/// and shows the reason, the way the schedules tab's
/// delete does.
Future<void> _deleteReservedFromDetail(
  BuildContext context,
  BuildContext dialogContext,
  RecordSchedule schedule,
  Future<void> Function(RecordSchedule schedule) onDeleteReserved,
) async {
  final deleted = await _deleteReservedConfirmed(
    context,
    schedule,
    onDeleteReserved,
  );
  if (!deleted) return;
  if (context.mounted) {
    Navigator.of(dialogContext).pop();
    showSnack(context, '予約を削除しました');
  }
}

/// The confirmation and the device call behind deleting a
/// guide programme's reservation, shared by the detail
/// dialog's delete action and the programme menus'
/// 録画解除 (owner request 2026-11-28): one confirmation,
/// never two. True when the reservation was deleted. A
/// refusal from the device is reported here and answers
/// false, so the caller keeps whatever it has open; the
/// success report is the caller's, so it can first close
/// what it has open (the detail dialog).
Future<bool> _deleteReservedConfirmed(
  BuildContext context,
  RecordSchedule schedule,
  Future<void> Function(RecordSchedule schedule) onDeleteReserved,
) async {
  final ok = await confirmDialog(
    context,
    title: '予約を削除',
    message: '${formatDateTimeWithWeekdayJst(schedule.start)} の予約を削除しますか？',
  );
  if (!ok) return false;
  try {
    await onDeleteReserved(schedule);
  } on NasneError catch (e) {
    if (context.mounted) showSnack(context, userMessageForError(e));
    return false;
  }
  return true;
}

/// Deletes a guide programme's reservation from its menu
/// — the guide tile's and the search row's 録画解除: the
/// detail dialog's delete flow (see
/// [_deleteReservedConfirmed]) with no dialog to close:
/// confirm, delete, report.
Future<void> confirmAndDeleteGuideReservation(
  BuildContext context, {
  required RecordSchedule schedule,
  required Future<void> Function(RecordSchedule schedule) onDeleteReserved,
}) async {
  final deleted = await _deleteReservedConfirmed(
    context,
    schedule,
    onDeleteReserved,
  );
  if (deleted && context.mounted) showSnack(context, '予約を削除しました');
}

class EpgEventDetailDialog extends StatelessWidget {
  const EpgEventDetailDialog({
    super.key,
    required this.event,
    required this.channelName,
    this.onReserve,
    this.onWatch,
    this.onDeleteReservation,
  });

  final EpgEvent event;
  final String channelName;

  /// Opens the prefilled reservation form (plan 28); null when
  /// the event has already ended.
  final VoidCallback? onReserve;

  /// Opens the channel's live viewing (plan 95); null unless
  /// the event is on air now.
  final VoidCallback? onWatch;

  /// Deletes the reservation this event already has
  /// (plan 124); when given, it replaces the reservation
  /// action — a reserved event is un-reserved from here,
  /// not reserved twice.
  final VoidCallback? onDeleteReservation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final genreLabel = epgGenreLabel(event.genreLevel1);
    // TV: the primary action (reserve — or delete, which
    // replaces it for a reserved event (plan 124) — else
    // watch, else close) takes focus as the dialog opens
    // (plan 134). Exactly one action carries autofocus in
    // every combination; the destructive step itself is the
    // confirmation behind the delete action, which focuses
    // its cancel side (see confirmDialog).
    final tv = isTvVariant(context);
    return AlertDialog(
      title: Text(event.title ?? '番組情報なし'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(channelName, style: theme.textTheme.bodySmall),
            if (genreLabel != null)
              Text('ジャンル: $genreLabel', style: theme.textTheme.bodySmall),
            Text(
              '${formatDateTimeWithWeekdayJst(event.start)} 〜 '
              '${formatTimeJst(event.end)}'
              '（${event.duration.inMinutes}分）',
              style: theme.textTheme.bodyMedium,
            ),
            if (event.shortText != null && event.shortText!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(event.shortText!),
            ],
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('番組内容', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(event.description!),
            ],
            if (event.cast != null && event.cast!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('出演者', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(event.cast!),
            ],
            for (final item in event.extendedItems) ...[
              const SizedBox(height: 12),
              Text(item.label, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(item.value),
            ],
            if (event.extendedText != null &&
                event.extendedText!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(event.extendedText!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus:
              tv &&
              onWatch == null &&
              onReserve == null &&
              onDeleteReservation == null,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
        if (onWatch != null)
          FilledButton.icon(
            autofocus: tv && onReserve == null && onDeleteReservation == null,
            onPressed: onWatch,
            icon: const Icon(Icons.live_tv, size: 18),
            label: const Text('試聴'),
          ),
        if (onDeleteReservation != null)
          FilledButton.icon(
            autofocus: tv,
            onPressed: onDeleteReservation,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('予約を削除'),
          )
        else if (onReserve != null)
          FilledButton.icon(
            autofocus: tv,
            onPressed: onReserve,
            icon: const Icon(Icons.fiber_manual_record, size: 18),
            label: const Text('録画予約'),
          ),
      ],
    );
  }
}
