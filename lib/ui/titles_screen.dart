/// Recorded titles screen (plan 5.6 item 3): the title list with
/// remaining copy counts and protection state, and a detail view
/// with the additional information. Playback goes through the
/// PlaybackEngine boundary only; the v1 stub reports "unsupported"
/// and the UI turns that into the not-implemented notice
/// (plan 1.2 item 5, 5.7).
///
/// Plan 86: when the nasne holds a resume position for a title,
/// the detail view asks whether to continue from it or start at
/// the beginning, and the choice reaches the player as its open
/// start. Before this the position was display-only (plan 85
/// item 1).
///
/// Plan 86.6: list rows and the detail view show the title's
/// thumbnail when the unit provides one. Before this the
/// endpoint was defined but never called (plan 85 item 6).
/// Real-unit measurement (plan 97 / 99) showed the map
/// carries no image — it is a position index — and the
/// actual frames live behind recordedContentThumbnailGet,
/// AES-128-CBC encrypted with an app-common key and stored
/// as 360x240 UYVY; fetchThumbnail decodes them (plan 99).
///
/// Plan 86.5: the list can be searched by title, sorted, and
/// filtered by channel / genre / unwatched; the genre comes
/// from the DIDL merge (upnp:genre). Before this the list was
/// the raw fetch order only (plan 85 item 5).
///
/// Plan 86.3: titles can be deleted from the detail view (and
/// from the list row's menu), behind a confirmation.
/// Protected and currently-recording titles are refused with
/// the reason, before any confirmation. Before this the app
/// had no title deletion at all (plan 85 item 3).
///
/// Plan 98: the detail view's protection switch flips the
/// unit's titleProtectFlag (X_UpdateTitle, the shape verified
/// in plan 86.3). A delete the unit still refuses with error
/// 877 — the title was protected after the list in hand was
/// fetched — is explained as protection and resynced, not
/// reported as a generic failure.
///
/// Plan 100: the list loads progressively. The first chunk
/// (20 titles) is shown as soon as it arrives and the rest
/// follows page by page, instead of the screen waiting for
/// every page plus the DIDL Browse before showing anything.
/// While a stage is incomplete the screen says so beside the
/// filters, and an empty filtered result shows as still
/// loading, never as "no match" — search, filtering and
/// sorting are whole-set operations, and only the complete
/// stage settles them.
///
/// Plan 104 follow-up: a viewing's resume report (plan 102)
/// is reflected in the loaded list at once, the same
/// one-title patch as a protection update (plan 103). The
/// detail the viewer returns to shows the position just
/// recorded — or none, after a completed viewing cleared
/// it — instead of the snapshot from before the playback.
/// The unit already held the new point; only the display
/// lagged, which made the recording look unrecorded.
///
/// In the two-pane layout, a double-click on a title row
/// starts playing it at once (owner request 2026-11-26),
/// through the same start the detail view's 再生 button
/// runs — the resume question included, never skipped
/// (see playRecordedTitle below).
///
/// A right click (desktop) or a long press (touch) on a
/// title row opens that title's menu — 再生 and 削除 —
/// where before this the long press went straight to the
/// delete confirmation (owner request 2026-11-26). The
/// menu is the viewing screen's channel-list menu's kin:
/// an observing pointer listener over the row, a right
/// click answered at once and a touch hold timed from the
/// same listener, and showMenu at the press point. 再生
/// runs the list's own start (the detail's, resume
/// question included); 削除 runs the shared delete flow
/// below, guards and confirmation included.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/providers.dart';
import '../app/state.dart';
import '../app/variant.dart';
import '../core/core.dart';
import 'error_messages.dart';
import 'format.dart';
import 'playback_launcher.dart';
import 'player_screen.dart';
import 'title_list_filter.dart';
import 'schedules_screen.dart' show twoPaneBreakpoint;
import 'tv_focus.dart';
import 'widgets.dart';

/// The resume start a title offers (plan 86): the position the
/// nasne recorded, as a duration, or null when there is nothing
/// to resume from (never played, or playback reached the start).
Duration? resumeStartOf(RecordedTitle title) {
  final seconds = title.resumePointSeconds;
  if (seconds == null || seconds <= 0) return null;
  return Duration(seconds: seconds);
}

/// How far before the recorded position a resume actually
/// starts (plan 98; the mechanism corrected by plan 102).
///
/// Plan 98 assumed the unit derives the position from what
/// it served, read-ahead included, and the rewind corrected
/// for the overshoot. Plan 102 measured otherwise: serving
/// alone never moves the unit's point — the point is what
/// the last client to play the title reported from its own
/// playhead when its playback ended (the official client's
/// write, and now this app's, plan 102). The recorded
/// position is therefore a watched position, and the rewind
/// is kept as a context rewind: a resume replays a few
/// seconds so the viewer picks the thread back up, and any
/// small overshoot in how a client reports is absorbed.
/// The choice dialog still names the recorded position —
/// that is what was watched to; only the open start moves.
const Duration resumeRewind = Duration(seconds: 10);

/// The start a "continue" choice opens at (plan 98): the
/// recorded position rewound by [resumeRewind], clamped at
/// the beginning. Zero when the title offers no resume.
Duration resumePlaybackStartOf(RecordedTitle title) {
  final recorded = resumeStartOf(title);
  if (recorded == null) return Duration.zero;
  final start = recorded - resumeRewind;
  return start < Duration.zero ? Duration.zero : start;
}

/// Asks whether to continue from [resumeStart] or start over
/// (plan 86). Returns true for "continue", false for "from the
/// beginning", and null when the dialog was dismissed without a
/// choice (the caller then does not start playback).
Future<bool?> showResumeChoiceDialog(
  BuildContext context,
  Duration resumeStart,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('前回の続きがあります'),
      content: Text(
        '前回は ${formatDurationSeconds(resumeStart.inSeconds)} まで観ました。'
        '続きから再生しますか？',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('最初から再生'),
        ),
        // TV: focus starts on the primary choice; without an
        // autofocus element the dialog opens with no focus in
        // it at all (plan 134; the plan 131 observation).
        FilledButton(
          autofocus: isTvVariant(context),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('続きから再生'),
        ),
      ],
    ),
  );
}

/// The title deletion flow (plan 86.3), shared by the detail
/// view's delete button and the list row menu's 削除.
/// Protected
/// titles (the unit's guard against accidental deletion) and
/// titles still being recorded are refused with the reason and
/// never reach the confirmation. Anything else asks first —
/// deletion cannot be undone — then deletes, refreshes the
/// list and counts, and reports. [onDeleted] runs after a
/// successful deletion (the detail page uses it to go back to
/// the list; the two-pane layout needs nothing, its selection
/// simply stops resolving).
Future<void> deleteRecordedTitle({
  required BuildContext context,
  required WidgetRef ref,
  required RegisteredNasne reg,
  required RecordedTitle title,
  VoidCallback? onDeleted,
}) async {
  if (title.protectFlag) {
    await _showDeleteRefusal(context, 'このタイトルは保護されているため削除できません。');
    return;
  }
  if (title.recordingFlag) {
    await _showDeleteRefusal(context, '録画中のタイトルは削除できません。');
    return;
  }
  final confirmed = await confirmDialog(
    context,
    title: 'タイトルを削除',
    message: '「${title.title}」を削除しますか？\n削除した録画は元に戻せません。',
    confirmLabel: '削除',
  );
  if (!confirmed || !context.mounted) return;
  try {
    await ref.read(deviceServicesProvider(reg)).titles.deleteTitle(title.id);
  } on NasneError catch (e) {
    ref.read(diagLogProvider)(DiagCategory.ui, 'title delete failed: $e');
    if (!context.mounted) return;
    if (e.code == '877') {
      // The unit refused: the title is protected there even
      // though the list in hand said otherwise (plan 86.3 —
      // protection can be set from another client after the
      // list was fetched). Resync the list and explain it the
      // same way as the up-front refusal.
      ref.invalidate(titlesProvider(reg));
      await _showDeleteRefusal(context, 'このタイトルは保護されているため削除できません。');
      return;
    }
    showSnack(context, userMessageForError(e));
    return;
  } catch (e) {
    ref.read(diagLogProvider)(DiagCategory.ui, 'title delete failed: $e');
    if (context.mounted) showSnack(context, '削除できませんでした');
    return;
  }
  ref.invalidate(titlesProvider(reg));
  ref.invalidate(titleCountsProvider(reg));
  if (!context.mounted) return;
  showSnack(context, '削除しました');
  onDeleted?.call();
}

/// The protection toggle flow (plan 98), driven by the title
/// detail's switch: sends the X_UpdateTitle the unit expects
/// (the shape verified in plan 86.3), then rewrites the one
/// title's flag in the loaded list (plan 103). No refetch: the
/// whole list costs more the larger the library grows, and the
/// unit's title list may keep answering with the pre-update
/// flag for a while anyway (device-observed after plan 98), so
/// a refetch could not be trusted to settle the switch either.
/// The patched list state is what the row's lock icon and the
/// detail's switch both read, so both settle at once. A failure
/// changes nothing and surfaces the error. Returns whether the
/// unit accepted the update.
Future<bool> setRecordedTitleProtection({
  required BuildContext context,
  required WidgetRef ref,
  required RegisteredNasne reg,
  required RecordedTitle title,
  required bool protect,
}) async {
  try {
    await ref
        .read(deviceServicesProvider(reg))
        .titles
        .setTitleProtection(title, protect: protect);
  } on NasneError catch (e) {
    ref.read(diagLogProvider)(DiagCategory.ui, 'title protect failed: $e');
    if (context.mounted) showSnack(context, userMessageForError(e));
    return false;
  } catch (e) {
    ref.read(diagLogProvider)(DiagCategory.ui, 'title protect failed: $e');
    if (context.mounted) showSnack(context, '保護を変更できませんでした');
    return false;
  }
  ref.read(titlesProvider(reg).notifier).applyProtection(title.id, protect);
  if (!context.mounted) return true;
  showSnack(context, protect ? '保護しました' : '保護を解除しました');
  return true;
}

/// The resume report a closing player makes (plan 102), and
/// its reflection in the loaded list (plan 104 follow-up).
///
/// The unit is told where the viewing stopped; on success
/// the one title's resume point in the loaded list is
/// rewritten with the reported value — the same one-title
/// patch as a protection update (plan 103) — so the detail
/// the viewer returns to shows the position that was just
/// recorded, and a completed viewing's clear (a reported
/// zero) shows as no position. A failure throws before the
/// patch: the display keeps the old value, and the player's
/// teardown logs the failed report. No refetch either way.
Future<void> reportResumePosition({
  required WidgetRef ref,
  required RegisteredNasne reg,
  required String titleId,
  required Duration position,
}) async {
  await ref
      .read(deviceServicesProvider(reg))
      .titles
      .setResumePosition(titleId, position);
  ref
      .read(titlesProvider(reg).notifier)
      .applyResumePoint(titleId, position.inSeconds);
}

/// Starts playing [title]: the flow the detail view's
/// 再生 button and the title list's double-click share.
/// The resume question comes first when the title offers
/// a position (plan 86) — beginning a session is the
/// expensive step, and the choice belongs before it, not
/// after — then the engine starts at the res [useMobile]
/// picks: the detail visit's quality choice in the
/// detail, the saved quality from the list; the detail
/// also starts from the saved quality, so both starts
/// pick alike. [onStarting] runs at the moment the start
/// itself begins, after the question: the detail view
/// marks its button busy there (plan 35).
Future<void> playRecordedTitle({
  required BuildContext context,
  required WidgetRef ref,
  required RegisteredNasne reg,
  required RecordedTitle title,
  required bool useMobile,
  VoidCallback? onStarting,
}) async {
  final engine = ref.read(deviceServicesProvider(reg)).playback;
  if (!engine.isSupported) {
    await showPlaybackUnsupportedDialog(context, subject: '録画の再生');
    return;
  }
  if (title.res.isEmpty) {
    showSnack(context, '再生可能なコンテンツがありません');
    return;
  }
  final res =
      (useMobile ? title.mobileRes : title.originalRes) ?? title.res.first;
  // Resume (plan 86): a title the viewer stopped midway offers
  // its recorded position. Ask before starting — beginning a
  // session is the expensive step, and the choice belongs
  // before it, not after.
  var initialStart = resumeStartOf(title);
  if (initialStart != null) {
    final resume = await showResumeChoiceDialog(context, initialStart);
    if (!context.mounted) return;
    if (resume == null) return;
    // Continuing opens a little before the recorded position:
    // the context rewind of resumeRewind (plan 98 / 102).
    initialStart = resume ? resumePlaybackStartOf(title) : null;
  }
  onStarting?.call();
  await startPlaybackAndShowPlayer(
    context: context,
    ref: ref,
    start: () => engine.startPlayback(title, res),
    buildPlayer: (session) {
      final records = _recordTargetsForTitle(
        ref: ref,
        reg: reg,
        title: title,
        useMobile: useMobile,
        engine: engine,
        chosenInitialStart: initialStart,
      );
      return PlayerScreen(
        title: title.title,
        session: session,
        initialStart: initialStart,
        // Leaving the player reports where the viewing
        // stopped (plan 102), so the unit's resume point is
        // there for the next viewing — in this app or in
        // the official client — and the loaded list follows
        // the report at once (plan 104 follow-up).
        onResumePosition: (position) => reportResumePosition(
          ref: ref,
          reg: reg,
          titleId: title.id,
          position: position,
        ),
        // The chapter points load as the player opens
        // (plan 112); the service validates them against
        // the listed duration, and an empty answer leaves
        // the player without chapter controls.
        loadChapters: () => ref
            .read(deviceServicesProvider(reg))
            .titles
            .fetchChapters(
              title.id,
              durationSeconds: title.scheduledDurationSeconds ?? 0,
            ),
        // The recorded list rides along (user-fork
        // addition, 2026-11-26): the player's standing
        // list panel offers the other titles, and picking
        // one switches playback without leaving the player.
        recordTargets: records?.targets,
        recordIndex: records?.index ?? 0,
      );
    },
    unsupportedSubject: '録画の再生',
  );
}

/// The record switch targets for playing [title]
/// (user-fork addition, 2026-11-26): the playable
/// titles of the recorded list — the titles provider
/// this tab reads, in the order its loaded stage holds
/// them — each with the start the playback runs, at
/// [useMobile]'s quality, and the index of [title]
/// among them. Null when the list is not at hand (its
/// load has not landed) or it offers no second playable
/// title: the player then offers no movement.
///
/// A switch inside the player does not stop to ask the
/// resume question [playRecordedTitle] asks before its
/// own start — the question would break the flipping
/// the list is for — so a title with a recorded position
/// opens at it, with the usual rewind (see
/// resumePlaybackStartOf), and the rest open at the
/// beginning. The title the playback opened is the one
/// exception: its target keeps the start the viewer just
/// chose, so flipping away and back lands where this
/// viewing began, not where the recorded point says.
({List<PlayerRecordTarget> targets, int index})? _recordTargetsForTitle({
  required WidgetRef ref,
  required RegisteredNasne reg,
  required RecordedTitle title,
  required bool useMobile,
  required PlaybackEngine engine,
  required Duration? chosenInitialStart,
}) {
  final stage = ref.read(titlesProvider(reg)).value;
  if (stage == null) return null;
  final targets = <PlayerRecordTarget>[];
  var index = -1;
  for (final t in stage.titles) {
    if (t.res.isEmpty) continue;
    final isCurrent = t.id == title.id;
    if (isCurrent) index = targets.length;
    final res = (useMobile ? t.mobileRes : t.originalRes) ?? t.res.first;
    targets.add(
      PlayerRecordTarget(
        name: t.title,
        start: () => engine.startPlayback(t, res),
        initialStart: isCurrent
            ? chosenInitialStart
            : (resumeStartOf(t) == null ? null : resumePlaybackStartOf(t)),
        onResumePosition: (position) => reportResumePosition(
          ref: ref,
          reg: reg,
          titleId: t.id,
          position: position,
        ),
        loadChapters: () => ref
            .read(deviceServicesProvider(reg))
            .titles
            .fetchChapters(
              t.id,
              durationSeconds: t.scheduledDurationSeconds ?? 0,
            ),
      ),
    );
  }
  if (targets.length < 2 || index < 0) return null;
  return (targets: targets, index: index);
}

Future<void> _showDeleteRefusal(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('削除できません'),
      content: Text(message),
      actions: [
        TextButton(
          autofocus: isTvVariant(context),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );
}

class TitlesScreen extends ConsumerStatefulWidget {
  const TitlesScreen({super.key});

  @override
  ConsumerState<TitlesScreen> createState() => _TitlesScreenState();
}

class _TitlesScreenState extends ConsumerState<TitlesScreen> {
  String? _selectedId;

  /// The title row last tapped in the two-pane layout,
  /// and when (double-click start, owner request
  /// 2026-11-26): a second tap on the same row within
  /// the framework's double-tap window starts playing
  /// the title at once, without the detour through the
  /// detail pane's 再生 button. The first tap only
  /// selects, exactly as before — selection never waits
  /// to see whether a second tap follows, so a single
  /// click keeps its timing and feel.
  String? _lastTappedTitleId;
  DateTime? _lastTappedAt;

  /// A playback start launched from the list is in
  /// flight: a further double-click must not start a
  /// second session while the first is still starting
  /// (the plan-35 hazard the detail's button guards
  /// against with its own flag).
  bool _startingFromList = false;

  void _handleTitleTap(RegisteredNasne reg, RecordedTitle title, bool twoPane) {
    if (!twoPane) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TitleDetailPage(reg: reg, titleId: title.id),
        ),
      );
      return;
    }
    setState(() => _selectedId = title.id);
    final now = DateTime.now();
    final doubleClicked =
        _lastTappedTitleId == title.id &&
        _lastTappedAt != null &&
        now.difference(_lastTappedAt!) <= kDoubleTapTimeout;
    if (!doubleClicked) {
      _lastTappedTitleId = title.id;
      _lastTappedAt = now;
      return;
    }
    _lastTappedTitleId = null;
    _lastTappedAt = null;
    _startTitleFromList(reg, title);
  }

  /// Starts playing [title] from a list double-click:
  /// the detail view's own start (see [playRecordedTitle],
  /// resume question included) at the saved playback
  /// quality — the quality the detail also starts from,
  /// so the two starts pick the same res.
  Future<void> _startTitleFromList(
    RegisteredNasne reg,
    RecordedTitle title,
  ) async {
    if (_startingFromList) return;
    _startingFromList = true;
    try {
      await playRecordedTitle(
        context: context,
        ref: ref,
        reg: reg,
        title: title,
        useMobile: ref.read(playbackQualityProvider),
      );
    } finally {
      _startingFromList = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reg = ref.watch(selectedRegistrationProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('録画済み'),
        actions: [
          if (reg != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '更新',
              onPressed: () {
                ref.invalidate(titlesProvider(reg));
                ref.invalidate(titleCountsProvider(reg));
              },
            ),
        ],
      ),
      body: reg == null
          ? NoDeviceView(
              onRegister: () =>
                  ref.read(tabIndexProvider.notifier).select(AppTabs.settings),
            )
          : _TitleList(
              reg: reg,
              selectedId: _selectedId,
              onSelect: (title, twoPane) =>
                  _handleTitleTap(reg, title, twoPane),
              onPlay: (title) => _startTitleFromList(reg, title),
            ),
    );
  }
}

class _TitleList extends ConsumerStatefulWidget {
  const _TitleList({
    required this.reg,
    required this.selectedId,
    required this.onSelect,
    required this.onPlay,
  });

  final RegisteredNasne reg;
  final String? selectedId;
  final void Function(RecordedTitle title, bool twoPane) onSelect;

  /// Starts playing a title from its row menu: the list's
  /// own start, owned by the screen's state (its in-flight
  /// guard lives there).
  final void Function(RecordedTitle title) onPlay;

  @override
  ConsumerState<_TitleList> createState() => _TitleListState();
}

class _TitleListState extends ConsumerState<_TitleList> {
  final _searchController = TextEditingController();
  String _query = '';
  TitleSortOrder _sort = TitleSortOrder.recordedNewest;
  String? _channelKey;
  String? _genre;
  bool _unwatchedOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _query = '';
      _channelKey = null;
      _genre = null;
      _unwatchedOnly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reg = widget.reg;
    final progress = ref.watch(titlesProvider(reg));
    final counts = ref.watch(titleCountsProvider(reg)).value;
    // The latest stage of the progressive load (plan 100). A
    // stage is provisional until it is marked complete; during
    // a refresh the previous stage stays on screen, with the
    // loading state saying a newer one is on its way.
    final snapshot = progress.value;
    final allTitles = snapshot?.titles ?? const <RecordedTitle>[];
    final stillLoading =
        snapshot == null || !snapshot.complete || progress.isLoading;
    // A load that failed before completing has nothing sound
    // to show — the error view takes over, as it did when the
    // whole list was one future. A failed *refresh* keeps the
    // complete stage it already had.
    final loadFailed =
        progress.hasError && (snapshot == null || !snapshot.complete);
    final channelChoices = titleChannelChoices(allTitles);
    final genreChoices = titleGenreChoices(allTitles);
    // A chosen value can vanish when the list refreshes (its
    // last title was deleted, say); fall back to "all" instead
    // of filtering everything out behind the user's back.
    final channelKey =
        _channelKey != null && channelChoices.contains(_channelKey)
        ? _channelKey
        : null;
    final genre = _genre != null && genreChoices.contains(_genre)
        ? _genre
        : null;
    final filter = TitleListFilter(
      query: _query,
      channelKey: channelKey,
      genre: genre,
      unwatchedOnly: _unwatchedOnly,
    );
    final filteredCount = filter.isActive
        ? applyTitleListView(allTitles, filter: filter, sort: _sort).length
        : null;
    return Column(
      children: [
        if (counts != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('全 ${counts.count} 件 (上限 ${counts.max} 件)'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: AppTextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'タイトルで検索',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: '検索をクリア',
                      onPressed: () => setState(() {
                        _searchController.clear();
                        _query = '';
                      }),
                    ),
            ),
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<TitleSortOrder>(
                  value: _sort,
                  items: [
                    for (final order in TitleSortOrder.values)
                      DropdownMenuItem(value: order, child: Text(order.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sort = value);
                  },
                ),
                DropdownButton<String?>(
                  value: channelKey,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('全チャンネル')),
                    for (final choice in channelChoices)
                      DropdownMenuItem(value: choice, child: Text(choice)),
                  ],
                  onChanged: (value) => setState(() => _channelKey = value),
                ),
                DropdownButton<String?>(
                  value: genre,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('全ジャンル')),
                    for (final choice in genreChoices)
                      DropdownMenuItem(value: choice, child: Text(choice)),
                  ],
                  onChanged: (value) => setState(() => _genre = value),
                ),
                FilterChip(
                  label: const Text('未視聴のみ'),
                  selected: _unwatchedOnly,
                  onSelected: (value) => setState(() => _unwatchedOnly = value),
                ),
                if (filter.isActive) ...[
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('条件をクリア'),
                  ),
                  if (filteredCount != null && !stillLoading)
                    Text('条件に合うのは $filteredCount 件'),
                ],
                // While the load is incomplete (plan 100), the
                // counts beside the filters are provisional and
                // say so; the filtered count is phrased as "so
                // far" so it cannot read as the final answer.
                if (stillLoading) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  Text(
                    filteredCount != null
                        ? '読み込み中… 条件に合うのは現在 $filteredCount 件'
                        : '読み込み中… ${allTitles.length} 件を表示',
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: loadFailed
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: ErrorView(
                    message: userMessageForError(progress.error!),
                    onRetry: () => ref.invalidate(titlesProvider(reg)),
                  ),
                )
              : snapshot == null
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _titleListBody(
                  reg: reg,
                  list: snapshot.titles,
                  stillLoading: stillLoading,
                  filter: filter,
                ),
        ),
      ],
    );
  }

  /// The list itself, over one stage of the progressive load
  /// (plan 100). [stillLoading] separates "nothing (yet)" from
  /// "nothing, finally": an empty list or an empty filtered
  /// result while later pages are still coming shows as
  /// loading, not as the settled answer.
  Widget _titleListBody({
    required RegisteredNasne reg,
    required List<RecordedTitle> list,
    required bool stillLoading,
    required TitleListFilter filter,
  }) {
    if (list.isEmpty) {
      if (stillLoading) {
        return const Center(child: Text('読み込み中…'));
      }
      return const Center(child: Text('録画済みのタイトルはありません'));
    }
    final view = applyTitleListView(list, filter: filter, sort: _sort);
    if (view.isEmpty) {
      if (stillLoading) {
        return const Center(child: Text('読み込み中…'));
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('条件に合うタイトルがありません'),
            const SizedBox(height: 8),
            TextButton(onPressed: _clearFilters, child: const Text('条件をクリア')),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // The tap behaviour and the pane layout must agree
        // on what "wide" means, so both read the same
        // width: the one this list actually gets. The tap
        // once read the MediaQuery window width while the
        // layout read these constraints, which the shell's
        // navigation rail narrows; in the band between the
        // two (a 1024-wide iPad in landscape, a Split View
        // or Stage Manager window) a tap only updated the
        // selection state — no detail page was pushed and
        // no detail pane existed to show it — so selecting
        // a title appeared to do nothing at all.
        final twoPane = constraints.maxWidth >= twoPaneBreakpoint;
        final listView = ListView.builder(
          itemCount: view.length,
          itemBuilder: (context, i) {
            final t = view[i];
            return _TitleRow(
              reg: reg,
              title: t,
              selected: t.id == widget.selectedId,
              twoPane: twoPane,
              onSelect: widget.onSelect,
              onPlay: widget.onPlay,
            );
          },
        );
        if (!twoPane) return listView;
        RecordedTitle? selected;
        for (final t in view) {
          if (t.id == widget.selectedId) selected = t;
        }
        return Row(
          children: [
            Expanded(flex: 5, child: listView),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              flex: 6,
              child: selected == null
                  ? const Center(child: Text('タイトルを選択してください'))
                  : TitleDetailView(reg: reg, title: selected),
            ),
          ],
        );
      },
    );
  }
}

/// One row of the title list: the tile itself, under an
/// observing pointer listener that opens the title's menu
/// — 再生 and 削除 — on a right click or a touch long
/// press (owner request 2026-11-26).
///
/// The arrangement is the viewing screen's (see the player
/// screen's channel-list menu): the listener only observes
/// — it never takes the event — so the tile's tap and the
/// list's scroll keep every pointer event they already
/// handle. A right click is answered at once; a touch hold
/// is timed from the same listener, never a gesture
/// recogniser, so the hold is not competed for. One
/// consequence of not competing: the tile's tap still
/// lands when the held finger lifts, so a hold that opened
/// the menu swallows the tap that follows it — in the
/// one-pane layout that tap would push the detail page
/// over the menu, and in the two-pane layout it would
/// count towards a double-click the viewer never made.
class _TitleRow extends ConsumerStatefulWidget {
  const _TitleRow({
    required this.reg,
    required this.title,
    required this.selected,
    required this.twoPane,
    required this.onSelect,
    required this.onPlay,
  });

  final RegisteredNasne reg;
  final RecordedTitle title;
  final bool selected;
  final bool twoPane;
  final void Function(RecordedTitle title, bool twoPane) onSelect;
  final void Function(RecordedTitle title) onPlay;

  @override
  ConsumerState<_TitleRow> createState() => _TitleRowState();
}

class _TitleRowState extends ConsumerState<_TitleRow> {
  Timer? _longPressTimer;
  int? _longPressPointer;
  Offset? _longPressStart;

  /// The last hold opened the menu: the tap the finger's
  /// lift still delivers is that hold's tail, not a tap on
  /// the row, and is swallowed once. A fresh press clears
  /// a leftover — a menu dismissed from its barrier never
  /// delivers the tap, and the next press on the row is a
  /// new gesture, not that hold's tail.
  bool _swallowNextTap = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  /// A right click (a secondary mouse button press) on the
  /// row opens the title's menu at the press point. A touch
  /// press starts the hold the long press is timed from,
  /// the same pair of arrangements as the viewing screen's
  /// listener.
  void _onRowPointerDown(PointerDownEvent event) {
    if ((event.buttons & kSecondaryMouseButton) != 0) {
      unawaited(_showTitleMenu(event.position));
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
      _swallowNextTap = true;
      unawaited(_showTitleMenu(start));
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

  /// The title's menu at [position], the viewing screen's
  /// menu's shape: showMenu over a zero-size rect at the
  /// press point. 再生 runs the list's own start — the
  /// detail view's start, resume question included, at
  /// the saved quality (see playRecordedTitle) — and
  /// 削除 runs the shared delete flow, whose guards
  /// (protected, still recording) refuse before any
  /// confirmation and whose confirmation asks first, the
  /// same as the detail view's delete button.
  Future<void> _showTitleMenu(Offset position) async {
    final title = widget.title;
    final overlay = Overlay.of(context).context.findRenderObject()!;
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & (overlay as RenderBox).size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'play',
          child: Row(
            children: [
              const Icon(Icons.play_arrow, size: 18),
              const SizedBox(width: 8),
              const Text('再生'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18),
              const SizedBox(width: 8),
              const Text('削除'),
            ],
          ),
        ),
      ],
    );
    if (chosen == null || !mounted) return;
    switch (chosen) {
      case 'play':
        widget.onPlay(title);
      case 'delete':
        await deleteRecordedTitle(
          context: context,
          ref: ref,
          reg: widget.reg,
          title: title,
        );
    }
  }

  void _handleTap() {
    if (_swallowNextTap) {
      _swallowNextTap = false;
      return;
    }
    widget.onSelect(widget.title, widget.twoPane);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.title;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onRowPointerDown,
      onPointerMove: _onRowPointerMove,
      onPointerUp: _onRowPointerEnd,
      onPointerCancel: _onRowPointerEnd,
      child: ListTile(
        selected: widget.selected,
        // The official app's compact shape (owner request
        // 2026-11-28): a dense row, the title held to two
        // lines, the when-and-where to one — a long title
        // no longer stretches its row over its neighbours.
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: _TitleLeading(reg: widget.reg, title: t),
        title: Text(
          t.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${t.scheduledStart != null ? formatDateTimeJst(t.scheduledStart!) : ''}'
          '${t.scheduledDurationSeconds != null ? ' (${formatDurationSeconds(t.scheduledDurationSeconds!)})' : ''}'
          '${t.channelName != null ? ' ${t.channelName}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (t.protectFlag) const Icon(Icons.lock, size: 16),
            if (t.newFlag)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.fiber_new, size: 18),
              ),
            if (t.copyCountRemaining != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text('残り ${t.copyCountRemaining} 回'),
              ),
          ],
        ),
        onTap: _handleTap,
      ),
    );
  }
}

/// A title's leading visual (plan 86.6): the thumbnail when the
/// unit provides one, else the movie icon. A title still being
/// recorded keeps the red recording icon — its state matters
/// more than a picture, and its thumbnail may not exist yet.
class _TitleLeading extends ConsumerWidget {
  const _TitleLeading({required this.reg, required this.title});

  final RegisteredNasne reg;
  final RecordedTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = Icon(
      title.recordingFlag ? Icons.fiber_manual_record : Icons.movie_outlined,
      color: title.recordingFlag ? Theme.of(context).colorScheme.error : null,
    );
    if (title.recordingFlag) return fallback;
    final bytes = ref
        .watch(titleThumbnailProvider((reg: reg, titleId: title.id)))
        .value;
    if (bytes == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.memory(
        bytes,
        width: 56,
        height: 32,
        fit: BoxFit.cover,
        // The 360x240 frame (plan 99) is scaled down to
        // this box: the high-quality filter keeps the
        // downscale smooth.
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// The detail view's thumbnail banner (plan 86.6): a 16:9
/// picture above the title when the unit provides one, and
/// nothing at all when it does not (no empty box). On the
/// TV variant the banner is width-capped and centred (see
/// build): the unit's thumbnail frames are 360x240 and no
/// larger source exists, so a TV-width banner only
/// stretches blocks.
class _TitleThumbnailBanner extends ConsumerWidget {
  const _TitleThumbnailBanner({required this.reg, required this.titleId});

  final RegisteredNasne reg;
  final String titleId;

  /// The TV banner's width cap. The thumbnail's source
  /// frame is 360 px wide (plan 99), so the cap is a
  /// stretch budget, not a layout choice: at the former
  /// full width (1888 px at 1080p) the frame stretched
  /// past 5x and read as blocks; at 600 px the stretch is
  /// about 1.7x, which the high-quality filter keeps
  /// smooth. Smoothness wins over size (owner, 2026-11-28).
  static const double _tvMaxWidth = 600;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref
        .watch(titleThumbnailProvider((reg: reg, titleId: titleId)))
        .value;
    if (bytes == null) return const SizedBox.shrink();
    final image = Image.memory(
      bytes,
      fit: BoxFit.cover,
      // The frame is always scaled (down in lists, up in
      // this banner): the high-quality filter keeps both
      // directions smooth.
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        // TV: the banner is capped twice over. Its width is
        // held to [_tvMaxWidth] and centred, so the 360x240
        // frame is not stretched across the whole TV (see
        // the constant). Its height is held to 40% of the
        // screen height, as before: at 16:9 the width cap
        // alone gives a 338-tall banner, inside the cap at
        // 1080p, but on a shorter screen the height cap is
        // what keeps the title, the fields and the play
        // button on the first screen. The standard variant
        // keeps the exact 16:9 banner it has always had.
        child: ref.watch(appVariantProvider).isTv
            ? Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _tvMaxWidth,
                    maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                  ),
                  child: AspectRatio(aspectRatio: 16 / 9, child: image),
                ),
              )
            : AspectRatio(aspectRatio: 16 / 9, child: image),
      ),
    );
  }
}

/// The protection row of the title detail (plan 98): the
/// state in the same label/value shape as the other rows,
/// plus the switch that flips it on the unit. [onChanged] is
/// null while an update is in flight, which disables the
/// switch.
class _ProtectionRow extends StatelessWidget {
  const _ProtectionRow({required this.protect, required this.onChanged});

  final bool protect;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              '保護',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(protect ? '保護あり' : 'なし')),
          Switch(value: protect, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Detail page for narrow layouts.
class TitleDetailPage extends ConsumerWidget {
  const TitleDetailPage({super.key, required this.reg, required this.titleId});

  final RegisteredNasne reg;
  final String titleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(titlesProvider(reg));
    return Scaffold(
      appBar: AppBar(title: const Text('タイトルの詳細')),
      body: asyncSection(progress.whenData((stage) => stage.titles), (list) {
        for (final t in list) {
          if (t.id == titleId) {
            return TitleDetailView(
              reg: reg,
              title: t,
              onDeleted: () => Navigator.of(context).pop(),
            );
          }
        }
        return const Center(child: Text('タイトルが見つかりません'));
      }, onRetry: () => ref.invalidate(titlesProvider(reg))),
    );
  }
}

/// The title detail: merged XSRS + DIDL information and the playback
/// action. When the title carries a mobile resource alongside the
/// original, a playback quality choice is offered (plan 33); the
/// choice starts from the saved playback quality — the original
/// quality until one is saved — and writes changes back to it.
class TitleDetailView extends ConsumerStatefulWidget {
  const TitleDetailView({
    super.key,
    required this.reg,
    required this.title,
    this.onDeleted,
  });

  final RegisteredNasne reg;
  final RecordedTitle title;

  /// Runs after this title was deleted from the detail view
  /// (plan 86.3): the pushed detail page goes back to the list.
  /// Null in the two-pane layout, where the refreshed list
  /// simply stops resolving the selection.
  final VoidCallback? onDeleted;

  @override
  ConsumerState<TitleDetailView> createState() => _TitleDetailViewState();
}

class _TitleDetailViewState extends ConsumerState<TitleDetailView> {
  /// Playback quality choice (plan 33): false = the title's
  /// original resource (DR / 3倍), true = the mobile transcode.
  /// The visit starts from the saved quality
  /// (playbackQualityProvider) and a change here writes back
  /// to it, so the choice carries to the next viewing. Null
  /// until the viewer touches the choice on this visit — the
  /// saved value, including its asynchronous restore, shows
  /// through meanwhile.
  bool? _useMobileChoice;

  /// The quality in effect on this visit: this screen's own
  /// choice once made, the saved quality otherwise.
  bool get _useMobile => _useMobileChoice ?? ref.read(playbackQualityProvider);

  /// A playback start is in flight (plan 35). Starting takes a
  /// second or more (credentials -> HEAD -> AKE -> proxy); the
  /// build-13 field log showed a second tap in that window
  /// starting a whole second session, whose player screen then
  /// shared — and dropped — the first one's wakelock. While a
  /// start is in flight the button is disabled and _play is
  /// re-entrancy-guarded.
  bool _starting = false;

  /// A protection update is in flight (plan 98). The switch is
  /// disabled meanwhile: a second flip would be built from the
  /// same listed document as the first, and the two updates
  /// have no order between them worth having.
  bool _protectBusy = false;

  RegisteredNasne get reg => widget.reg;
  RecordedTitle get title => widget.title;

  Future<void> _toggleProtection(bool protect) async {
    setState(() => _protectBusy = true);
    try {
      await setRecordedTitleProtection(
        context: context,
        ref: ref,
        reg: reg,
        title: title,
        protect: protect,
      );
    } finally {
      if (mounted) setState(() => _protectBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = title;
    // The quality choice in effect: this visit's own choice
    // once made, the saved quality otherwise. Watching the
    // saved quality rebuilds this view when its asynchronous
    // restore lands.
    final bool useMobile =
        _useMobileChoice ?? ref.watch(playbackQualityProvider);
    // The protection state this view shows is the loaded
    // list's: a successful toggle rewrites it there (plan 103),
    // and this view is rebuilt with the updated title.
    final protectValue = t.protectFlag;
    final channels = ref.watch(channelsProvider(reg)).value;
    final credentialSummary = ref.watch(credentialSummaryProvider);
    final credentialsMissing =
        credentialSummary.hasValue && credentialSummary.value == null;
    final sizeBytes = t.res
        .map((r) => r.cleartextSize)
        .whereType<int>()
        .firstOrNull;
    final qualities = [
      for (final r in t.res)
        if (r.quality != null) r.quality!,
    ];
    final originalRes = t.originalRes;
    final mobileRes = t.mobileRes;
    final originalLabel = originalRes?.quality == null
        ? '元画質'
        : '元画質 (${resQualityLabel(originalRes!.quality)})';
    return ListView(
      padding: const EdgeInsets.all(16),
      // TV: D-pad traversal can only move to children the
      // sliver has laid out, and the stretch between the
      // protection switch and the play controls — the size /
      // resume / quality rows plus the description sections —
      // is far longer than the default cache extent, so focus
      // stopped dead at the switch and the play button could
      // never be reached by remote (measured on a real unit:
      // the gap is ~750 px). Lay out the whole page up front;
      // it is a page of text, so the cost is negligible. The
      // standard variant keeps the default extent.
      scrollCacheExtent: ref.watch(appVariantProvider).isTv
          ? const ScrollCacheExtent.pixels(3000)
          : null,
      children: [
        if (!t.recordingFlag) _TitleThumbnailBanner(reg: reg, titleId: t.id),
        // TV: the heading is display-only; it holds focus
        // (TvFocusAnchor) so D-pad traversal can scroll back to
        // the top of the detail (plan 123).
        TvFocusAnchor(
          child: Text(t.title, style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: 12),
        if (t.scheduledStart != null)
          FieldRow(
            label: '録画日時',
            value: formatDateTimeWithWeekdayJst(t.scheduledStart!),
          ),
        if (t.scheduledDurationSeconds != null)
          FieldRow(
            label: '長さ',
            value: formatDurationSeconds(t.scheduledDurationSeconds!),
          ),
        FieldRow(
          label: 'チャンネル',
          value: t.channelName ?? channelDisplayName(channels, t.channel),
        ),
        if (t.genre != null && t.genre!.isNotEmpty)
          FieldRow(label: 'ジャンル', value: t.genre!),
        if (t.desiredQualityMode != null)
          FieldRow(
            label: '画質モード',
            value: qualityModeLabel(t.desiredQualityMode!),
          ),
        if (t.copyCountRemaining != null)
          FieldRow(label: '残コピー回数', value: '${t.copyCountRemaining} 回'),
        // The protection row (plan 98): a switch for finished
        // titles. A title still being recorded keeps the static
        // display — the verified update shape covers finished
        // titles, and a recording's listed item is still
        // changing under the unit.
        if (t.recordingFlag)
          FieldRow(label: '保護', value: t.protectFlag ? '保護あり' : 'なし')
        else
          _ProtectionRow(
            protect: protectValue,
            onChanged: _protectBusy ? null : _toggleProtection,
          ),
        if (t.recordingFlag) const FieldRow(label: '状態', value: '録画中'),
        if (sizeBytes != null)
          FieldRow(label: 'サイズ', value: formatBytes(sizeBytes)),
        if (t.resumePointSeconds != null && t.resumePointSeconds! > 0)
          FieldRow(
            label: '再開位置',
            value: formatDurationSeconds(t.resumePointSeconds!),
          ),
        if (qualities.isNotEmpty)
          FieldRow(label: 'res 品質', value: qualities.join(', ')),
        if (t.description != null && t.description!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('概要', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(t.description!),
        ],
        if (t.longDescription != null && t.longDescription!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('詳細', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(t.longDescription!),
        ],
        const SizedBox(height: 24),
        if (mobileRes != null) ...[
          Text('再生画質', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(originalLabel)),
              const ButtonSegment(value: true, label: Text('モバイル')),
            ],
            selected: {useMobile},
            onSelectionChanged: (selection) {
              setState(() => _useMobileChoice = selection.first);
              ref.read(playbackQualityProvider.notifier).set(selection.first);
            },
          ),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: _starting ? null : () => _play(context, ref),
          icon: const Icon(Icons.play_arrow),
          label: const Text('再生'),
        ),
        // The credential note shows only while no pair is
        // imported (plan 86.2): as a permanent fixture it told
        // people who had already imported that they still had
        // something to do. While the state is loading nothing
        // is shown, so the text never flickers in and out.
        if (credentialsMissing) ...[
          const SizedBox(height: 8),
          const Text('録画の再生には資格情報のインポートが必要です。'),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => deleteRecordedTitle(
            context: context,
            ref: ref,
            reg: reg,
            title: title,
            onDeleted: widget.onDeleted,
          ),
          icon: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          label: Text(
            'このタイトルを削除',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }

  Future<void> _play(BuildContext context, WidgetRef ref) async {
    if (_starting) return;
    try {
      await playRecordedTitle(
        context: context,
        ref: ref,
        reg: reg,
        title: title,
        useMobile: _useMobile,
        onStarting: () {
          if (mounted) setState(() => _starting = true);
        },
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }
}
