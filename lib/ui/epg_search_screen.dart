/// Programme search screen (plan 86, plan 85 item 8):
/// keyword and genre search over the EPG dataset the guide
/// providers already hold. Each hit leads to the same event
/// detail dialog — and from there the same reservation
/// form — as a tap on the guide grid (see
/// [showEpgEventDetail]).
///
/// Every band is searched together: the viewer thinks in
/// programmes, not in broadcasting types, and the
/// terrestrial / BS / CS split is a guide-grid concern. A band
/// whose guide is still loading or failed to load simply
/// contributes nothing yet; the other band's hits are
/// shown. The search runs over the full dataset, including
/// subchannels the guide grid may be set to hide — finding
/// a programme is the point of searching for it.
///
/// Plan 98: the search runs over an [EpgSearchIndex] built
/// once per dataset (see epg_search.dart), and keystrokes
/// are debounced — a burst of typing applies one search
/// when it settles, not a full rescan per character.
///
/// A right click (desktop) or a long press (touch) on a
/// result row opens that programme's menu — 録画 —
/// reserving it without the trip through the detail
/// dialog (owner request 2026-11-26). The menu is the
/// recorded-titles list's row menu's kin: an observing
/// pointer listener over the row, a right click answered
/// at once and a touch hold timed from the same listener,
/// and showMenu at the press point. The reservation runs
/// the shared guide-event create (see recordGuideEvent)
/// and reports its outcome with that path's wording; a
/// programme already reserved is reported as such by the
/// create, so the item is always offered the same way —
/// the titles menu's stance, whose 削除 likewise lets the
/// shared flow refuse. A programme that has already
/// ended offers no menu at all: the detail dialog offers
/// it no reservation either, and there is nothing else
/// for the menu to carry.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/bs_epg_providers.dart';
import '../app/cs_epg_providers.dart';
import '../app/state.dart';
import '../core/core.dart';
import 'epg_reserved.dart';
import 'epg_screen.dart';
import 'epg_search.dart';
import 'format.dart';
import 'live_screen.dart';
import 'player_record_policy.dart';
import 'tv_focus.dart';
import 'widgets.dart';

class EpgSearchScreen extends ConsumerStatefulWidget {
  const EpgSearchScreen({super.key, required this.reg});

  final RegisteredNasne reg;

  @override
  ConsumerState<EpgSearchScreen> createState() => _EpgSearchScreenState();
}

class _EpgSearchScreenState extends ConsumerState<EpgSearchScreen> {
  final _queryController = TextEditingController();
  String _query = '';

  /// The query the results actually reflect (plan 98):
  /// keystrokes land here only once typing settles for
  /// [queryDebounce], so a burst of input runs one search.
  String _appliedQuery = '';
  Timer? _debounce;
  int? _genreLevel1;

  /// The search index over the current dataset, rebuilt
  /// only when a band's guide object is replaced (a reload),
  /// never per keystroke or per rebuild.
  EpgSearchIndex? _index;
  EpgGuide? _indexedTerrestrial;
  EpgGuide? _indexedBs;
  EpgGuide? _indexedCs;

  /// How long typing may pause before its search runs.
  static const Duration queryDebounce = Duration(milliseconds: 200);

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(queryDebounce, () {
      if (mounted) setState(() => _appliedQuery = value);
    });
  }

  void _clearQuery() {
    _debounce?.cancel();
    _queryController.clear();
    setState(() {
      _query = '';
      _appliedQuery = '';
    });
  }

  /// Reserves a result row's programme from its menu:
  /// the shared guide-event create (see recordGuideEvent),
  /// with the outcome reported in that path's wording —
  /// the same feedback the live player's record action
  /// gives. (The create's `unavailable` outcome cannot
  /// occur here: the hit already carries its event.)
  Future<void> _recordHit(EpgSearchHit hit) async {
    final result = await recordGuideEvent(
      ref: ref,
      reg: widget.reg,
      channel: hit.channel,
      event: hit.event,
    );
    if (!mounted) return;
    showSnack(context, liveRecordResultMessage(result));
  }

  EpgSearchIndex _indexFor(EpgGuide? terrestrial, EpgGuide? bs, EpgGuide? cs) {
    if (_index == null ||
        !identical(terrestrial, _indexedTerrestrial) ||
        !identical(bs, _indexedBs) ||
        !identical(cs, _indexedCs)) {
      _index = EpgSearchIndex.fromGuides([?terrestrial, ?bs, ?cs]);
      _indexedTerrestrial = terrestrial;
      _indexedBs = bs;
      _indexedCs = cs;
    }
    return _index!;
  }

  @override
  Widget build(BuildContext context) {
    final terrestrial = ref.watch(epgGuideProvider(widget.reg)).value;
    final bs = ref.watch(bsEpgGuideProvider(widget.reg)).value;
    final cs = ref.watch(csEpgGuideProvider(widget.reg)).value;
    final guides = <EpgGuide>[?terrestrial, ?bs, ?cs];
    final index = _indexFor(terrestrial, bs, cs);
    final genreValues = index.genreValues;
    // A genre picked before the data (re)loaded may not
    // exist in the current dataset; fall back to "all"
    // rather than filtering everything away behind the
    // viewer's back.
    final genre = genreValues.contains(_genreLevel1) ? _genreLevel1 : null;
    final searched = _appliedQuery.trim().isNotEmpty || genre != null;
    final hits = searched
        ? index.search(query: _appliedQuery, genreLevel1: genre)
        : const <EpgSearchHit>[];

    return Scaffold(
      appBar: AppBar(title: const Text('番組検索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: AppTextField(
              controller: _queryController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'キーワード',
                hintText: '番組名・内容・出演者など',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'クリア',
                        onPressed: _clearQuery,
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: _onQueryChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Text('ジャンル'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<int?>(
                    value: genre,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('すべて'),
                      ),
                      for (final value in genreValues)
                        DropdownMenuItem<int?>(
                          value: value,
                          child: Text(epgSearchGenreLabel(value)),
                        ),
                    ],
                    onChanged: (value) => setState(() => _genreLevel1 = value),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildResults(guides, searched, hits)),
        ],
      ),
    );
  }

  Widget _buildResults(
    List<EpgGuide> guides,
    bool searched,
    List<EpgSearchHit> hits,
  ) {
    // Reserved marking (plans 120/124): the same
    // reservation list the guide grid frames in red, so a
    // hit that is already reserved offers deleting the
    // reservation from its detail, exactly like the grid.
    final reservedIndex = EpgReservedIndex.fromSchedules(
      ref.watch(schedulesProvider(widget.reg)).value ??
          const <RecordSchedule>[],
    );
    if (guides.isEmpty) return const LoadingView();
    if (!searched) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'キーワードを入力するか、ジャンルを選ぶと、'
            '番組表から番組を探せます。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (hits.isEmpty) {
      return const Center(child: Text('見つかりませんでした。'));
    }
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        final event = hit.event;
        return _SearchHitRow(
          hit: hit,
          onTap: () => showEpgEventDetail(
            context,
            reg: widget.reg,
            channel: hit.channel,
            channelName: hit.channelName,
            event: event,
            reservedSchedule: reservedIndex.scheduleFor(hit.channel, event),
            onDeleteReserved: (schedule) =>
                deleteScheduleAndInvalidate(ref, widget.reg, schedule),
            onWatch: () => openLiveChannelForEpg(
              context,
              ref,
              reg: widget.reg,
              channel: hit.channel,
            ),
          ),
          onRecord: _recordHit,
        );
      },
    );
  }
}

/// One search result row: the tile itself, under an
/// observing pointer listener that opens the programme's
/// menu — 録画 — on a right click or a touch long press
/// (owner request 2026-11-26).
///
/// The arrangement is the recorded-titles list's (see
/// _TitleRow in titles_screen.dart): the listener only
/// observes — it never takes the event — so the tile's
/// tap and the list's scroll keep every pointer event
/// they already handle. A right click is answered at
/// once; a touch hold is timed from the same listener,
/// never a gesture recogniser, so the hold is not
/// competed for. One consequence of not competing: the
/// tile's tap still lands when the held finger lifts, so
/// a hold that opened the menu swallows the tap that
/// follows it — that tap would open the detail dialog
/// over the menu. A programme that has already ended
/// opens no menu (see the library note), so its hold
/// swallows nothing and the tap tail opens the detail,
/// as a plain tap does.
class _SearchHitRow extends StatefulWidget {
  const _SearchHitRow({
    required this.hit,
    required this.onTap,
    required this.onRecord,
  });

  final EpgSearchHit hit;

  /// The row's plain tap: the shared event detail dialog,
  /// as before the menu existed.
  final VoidCallback onTap;

  /// Reserves the row's programme: the screen's own
  /// record run (its feedback lives there).
  final void Function(EpgSearchHit hit) onRecord;

  @override
  State<_SearchHitRow> createState() => _SearchHitRowState();
}

class _SearchHitRowState extends State<_SearchHitRow> {
  Timer? _longPressTimer;
  int? _longPressPointer;
  Offset? _longPressStart;

  /// The last hold opened the menu: the tap the finger's
  /// lift still delivers is that hold's tail, not a tap
  /// on the row, and is swallowed once. A fresh press
  /// clears a leftover — a menu dismissed from its
  /// barrier never delivers the tap, and the next press
  /// on the row is a new gesture, not that hold's tail.
  bool _swallowNextTap = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  /// A right click (a secondary mouse button press) on
  /// the row opens the programme's menu at the press
  /// point. A touch press starts the hold the long press
  /// is timed from, the same pair of arrangements as the
  /// titles list's listener.
  void _onRowPointerDown(PointerDownEvent event) {
    if ((event.buttons & kSecondaryMouseButton) != 0) {
      unawaited(_showHitMenu(event.position));
      return;
    }
    if ((event.buttons & kPrimaryButton) != 0) {
      _swallowNextTap = false;
      if (event.kind == PointerDeviceKind.touch) {
        _longPressPointer = event.pointer;
        _longPressStart = event.position;
        _longPressTimer?.cancel();
        _longPressTimer = Timer(kLongPressTimeout, _onRowLongPressFired);
      }
    }
  }

  /// The held touch reached the long-press timeout still
  /// down: open the menu where the press began.
  void _onRowLongPressFired() {
    _longPressTimer = null;
    final start = _longPressStart;
    _longPressPointer = null;
    _longPressStart = null;
    if (start != null && mounted) {
      unawaited(_showHitMenu(start));
    }
  }

  /// Ends a tracked hold without opening the menu: the
  /// finger lifted or the press was cancelled before the
  /// timeout.
  void _onRowPointerEnd(PointerEvent event) {
    if (event.pointer != _longPressPointer) return;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _longPressPointer = null;
    _longPressStart = null;
  }

  /// A tracked press that wanders past the touch slop is
  /// a scroll of the list, not a hold: it stops being a
  /// long press.
  void _onRowPointerMove(PointerMoveEvent event) {
    if (event.pointer != _longPressPointer) return;
    final start = _longPressStart;
    if (start != null && (event.position - start).distance > kTouchSlop) {
      _onRowPointerEnd(event);
    }
  }

  /// The programme's menu at [position], the titles
  /// menu's shape: showMenu over a zero-size rect at the
  /// press point. A programme that has already ended has
  /// nothing to offer — the detail dialog offers it no
  /// reservation either — so no menu opens, and nothing
  /// is swallowed: a hold's tap tail goes on to open the
  /// detail, as a plain tap does. When the menu does
  /// open, the tap tail is swallowed first, so it cannot
  /// open the detail over the menu.
  Future<void> _showHitMenu(Offset position) async {
    final hit = widget.hit;
    if (!hit.event.end.isAfter(DateTime.now())) return;
    _swallowNextTap = true;
    final overlay = Overlay.of(context).context.findRenderObject()!;
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & (overlay as RenderBox).size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'record',
          child: Row(
            children: [
              const Icon(Icons.fiber_manual_record, size: 18),
              const SizedBox(width: 8),
              const Text('録画'),
            ],
          ),
        ),
      ],
    );
    if (chosen != 'record' || !mounted) return;
    widget.onRecord(hit);
  }

  void _handleTap() {
    if (_swallowNextTap) {
      _swallowNextTap = false;
      return;
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final hit = widget.hit;
    final event = hit.event;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onRowPointerDown,
      onPointerMove: _onRowPointerMove,
      onPointerUp: _onRowPointerEnd,
      onPointerCancel: _onRowPointerEnd,
      child: ListTile(
        title: Text(event.title ?? '番組情報なし'),
        subtitle: Text(
          '${hit.channelName}\n'
          '${formatDateTimeWithWeekdayJst(event.start)} 〜 '
          '${formatTimeJst(event.end)}',
        ),
        isThreeLine: true,
        onTap: _handleTap,
      ),
    );
  }
}
