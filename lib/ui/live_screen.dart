/// Live viewing screen (plan 39): the LiveTuner bands and their
/// channels, each with the programme currently on air, and a
/// detail view that starts viewing through the PlaybackEngine
/// boundary — the same DTCP-IP path as recorded playback, with
/// the plan-33 quality choice. The official torne name of the
/// feature, TV視聴, is the screen's title.
///
/// Plan 95: the bands sit under tabs (地デジ / BS / CS, the
/// guide's wording), one band's channels on screen at a time in
/// large rows, instead of one long list with band headings;
/// the guide's subchannel switch applies to the list as well.
///
/// Ahead of the band tabs sits a ピン留め tab (owner request
/// 2026-11-26, KonomiTV-style): the channels the viewer
/// pinned, across every band, in band order. The pin toggle
/// is on each channel row; the choice and its filter are
/// ui/channel_pins.dart.
///
/// The programme information is the snapshot the DIDL items
/// carried when the list was fetched; the refresh action
/// re-fetches it (a programme boundary does not update an
/// already listed item).
///
/// The player's programme actions work from here (user-fork
/// addition, 2026-11-26): a zap target on any band's channel
/// carries the record / state / stop actions for the
/// programme now on air on that channel, resolved in the
/// programme guide at the moment they run (see
/// ui/player_record_policy.dart). CS joined the covered
/// bands when its guide landed (plan 137).
///
/// In the two-pane layout, a double-click on a channel row
/// starts viewing at once (owner request 2026-11-26),
/// through the same start the detail pane's 視聴 button
/// runs (see startLiveChannelViewing below).
library;

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/bs_epg_providers.dart';
import '../app/cs_epg_providers.dart';
import '../app/providers.dart';
import '../app/state.dart';
import '../core/core.dart';
import 'channel_pins.dart';
import 'channel_visibility.dart';
import 'epg_subchannel_visibility.dart';
import 'format.dart';
import 'playback_launcher.dart';
import 'player_record_policy.dart';
import 'player_screen.dart';
import 'schedules_screen.dart' show twoPaneBreakpoint;
import 'tv_focus.dart';
import 'widgets.dart';

class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  String? _selectedId;

  /// Container id of the band whose tab is selected; null
  /// means the first band with channels.
  String? _selectedBandId;

  /// The channel row last tapped in the two-pane layout,
  /// and when (double-click start, owner request
  /// 2026-11-26): a second tap on the same row within the
  /// framework's double-tap window starts viewing at once,
  /// without the detour through the detail pane's 視聴
  /// button. The first tap only selects, exactly as
  /// before — selection never waits to see whether a
  /// second tap follows, so a single click keeps its
  /// timing and feel.
  String? _lastTappedChannelId;
  DateTime? _lastTappedAt;

  /// A viewing start launched from the list is in flight:
  /// a further double-click must not start a second
  /// session while the first is still starting (the
  /// plan-35 hazard the detail's button guards against
  /// with its own flag).
  bool _startingFromList = false;

  void _handleChannelTap(
    RegisteredNasne reg,
    LiveChannel channel,
    bool twoPane,
  ) {
    if (!twoPane) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              LiveChannelDetailPage(reg: reg, channelId: channel.id),
        ),
      );
      return;
    }
    setState(() => _selectedId = channel.id);
    final now = DateTime.now();
    final doubleClicked =
        _lastTappedChannelId == channel.id &&
        _lastTappedAt != null &&
        now.difference(_lastTappedAt!) <= kDoubleTapTimeout;
    if (!doubleClicked) {
      _lastTappedChannelId = channel.id;
      _lastTappedAt = now;
      return;
    }
    _lastTappedChannelId = null;
    _lastTappedAt = null;
    _startViewingFromList(reg, channel);
  }

  /// Starts viewing [channel] from a list double-click:
  /// the detail pane's own start (see
  /// [startLiveChannelViewing]) at the saved playback
  /// quality — the quality the detail pane also starts
  /// from, so the two starts pick the same res.
  Future<void> _startViewingFromList(
    RegisteredNasne reg,
    LiveChannel channel,
  ) async {
    if (_startingFromList) return;
    _startingFromList = true;
    try {
      await startLiveChannelViewing(
        context: context,
        ref: ref,
        reg: reg,
        channel: channel,
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
        title: const Text('TV視聴'),
        actions: [
          if (reg != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '更新',
              onPressed: () => ref.invalidate(liveChannelsProvider(reg)),
            ),
        ],
      ),
      body: reg == null
          ? NoDeviceView(
              onRegister: () =>
                  ref.read(tabIndexProvider.notifier).select(AppTabs.settings),
            )
          : _LiveList(
              reg: reg,
              selectedId: _selectedId,
              selectedBandId: _selectedBandId,
              onSelectBand: (bandId) =>
                  setState(() => _selectedBandId = bandId),
              onSelect: (channel, twoPane) =>
                  _handleChannelTap(reg, channel, twoPane),
            ),
    );
  }
}

/// The tab value of the ピン留め tab. A band's tab value is
/// its container id — always a LiveTuner path carrying
/// slashes — so this bare word can never collide with one.
const String livePinnedTabValue = 'pinned';

/// The short tab label of a live band (plan 95): the guide's
/// 地デジ / BS wording for the measured bands, CS alike; an
/// unrecognised band keeps the title the device advertises.
String liveBandTabLabel(LiveBand band) => switch (liveBandKind(band)) {
  LiveBandKind.terrestrial => '地デジ',
  LiveBandKind.bs => 'BS',
  LiveBandKind.cs => 'CS',
  LiveBandKind.other => band.title,
};

class _LiveList extends ConsumerWidget {
  const _LiveList({
    required this.reg,
    required this.selectedId,
    required this.selectedBandId,
    required this.onSelectBand,
    required this.onSelect,
  });

  final RegisteredNasne reg;
  final String? selectedId;
  final String? selectedBandId;
  final ValueChanged<String> onSelectBand;
  final void Function(LiveChannel channel, bool twoPane) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bands = ref.watch(liveChannelsProvider(reg));
    final showSubchannels = ref.watch(showSubchannelsProvider);
    final hiddenChannels = ref.watch(hiddenChannelsProvider);
    final pinnedChannels = ref.watch(pinnedChannelsProvider);
    return asyncSection(bands, (list) {
      // The guide's subchannel switch applies to this list
      // too (plan 95): the same setting, not a new one. The
      // viewer's not-watched channels drop out as well
      // (owner request 2026-11-26), under the same choice
      // the programme guide applies.
      final visibleBands = liveBandsWithHiddenChannels(
        liveBandsWithSubchannelSetting(list, showSubchannels),
        hiddenChannels,
      );
      final channels = [for (final band in visibleBands) ...band.channels];
      if (channels.isEmpty) {
        return const Center(child: Text('視聴可能なチャンネルがありません'));
      }
      // One tab per band that actually offers a channel; the
      // selected band survives refreshes by container id and
      // falls back to the first tab when it is gone. Ahead of
      // them sits the ピン留め tab, selected under its own
      // value rather than a container id.
      final tabBands = [
        for (final band in visibleBands)
          if (band.channels.isNotEmpty) band,
      ];
      final pinnedSelected = selectedBandId == livePinnedTabValue;
      final selectedBand = pinnedSelected
          ? null
          : tabBands.firstWhere(
              (band) => band.containerId == selectedBandId,
              orElse: () => tabBands.first,
            );
      // The rows on screen: on the ピン留め tab, the pinned
      // channels across every band — read off the already
      // filtered bands, so a not-watched channel stays out
      // even while it is pinned — and on a band tab, the
      // selected band's channels.
      final listedChannels = pinnedSelected
          ? pinnedLiveChannels(visibleBands, pinnedChannels)
          : selectedBand!.channels;
      return LayoutBuilder(
        builder: (context, constraints) {
          // One width decides both the layout and the tap
          // behaviour: the width this list actually gets. Reading
          // the MediaQuery window width for the tap instead left
          // a band (window >= breakpoint, list < breakpoint, e.g.
          // a 1024-wide iPad in landscape past the shell's rail)
          // where a tap updated only the selection and opened
          // nothing. See titles_screen.dart for the full note.
          final twoPane = constraints.maxWidth >= twoPaneBreakpoint;
          final listView = ListView(
            children: [
              for (final channel in listedChannels)
                ListTile(
                  selected: channel.id == selectedId,
                  // The rows are tightened (owner request
                  // 2026-11-26): the vertical padding is
                  // half the plan-95 large-row value and
                  // the tile density is compact, so more
                  // channels fit on screen at once —
                  // measured on a two-line row, 88 down
                  // to 68 logical pixels. Font sizes are
                  // untouched and the subtitle keeps its
                  // two lines, so the channel name and
                  // the current programme read as before.
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.live_tv_outlined),
                  title: Text(channel.channelName ?? channel.programTitle),
                  subtitle: Text(
                    _channelSubtitle(channel),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _pinToggle(ref, channel, pinnedChannels),
                  onTap: () => onSelect(channel, twoPane),
                ),
            ],
          );
          // The ピン留め tab before anything is pinned: the
          // same centred empty form as the no-channels case,
          // saying how a channel gets pinned.
          final listArea = pinnedSelected && listedChannels.isEmpty
              ? const Center(
                  child: Text(
                    'ピン留めしたチャンネルがありません\n'
                    '各チャンネルのピンのアイコンから登録できます',
                    textAlign: TextAlign.center,
                  ),
                )
              : listView;
          final segments = <ButtonSegment<String>>[
            const ButtonSegment<String>(
              value: livePinnedTabValue,
              label: Text('ピン留め'),
            ),
            for (final band in tabBands)
              ButtonSegment<String>(
                value: band.containerId,
                label: Text(liveBandTabLabel(band)),
              ),
          ];
          final content = Column(
            children: [
              if (segments.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: SegmentedButton<String>(
                    segments: segments,
                    selected: {
                      pinnedSelected
                          ? livePinnedTabValue
                          : selectedBand!.containerId,
                    },
                    onSelectionChanged: (selection) =>
                        onSelectBand(selection.first),
                  ),
                ),
              Expanded(child: listArea),
            ],
          );
          if (!twoPane) return content;
          LiveChannel? selected;
          for (final channel in channels) {
            if (channel.id == selectedId) selected = channel;
          }
          return Row(
            children: [
              Expanded(flex: 5, child: content),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                flex: 6,
                child: selected == null
                    ? const Center(child: Text('チャンネルを選択してください'))
                    : LiveChannelDetailView(reg: reg, channel: selected),
              ),
            ],
          );
        },
      );
    }, onRetry: () => ref.invalidate(liveChannelsProvider(reg)));
  }

  /// The row's pin toggle: filled while the channel is
  /// pinned, outlined otherwise, and the choice persists
  /// through the pinned-channels notifier. A channel whose
  /// item carried no broadcast identity cannot be pinned
  /// (the pin filter's rule), so its toggle is shown
  /// disabled rather than pretending it works — the same
  /// treatment as the 見ないチャンネル page's switches.
  Widget _pinToggle(
    WidgetRef ref,
    LiveChannel channel,
    Set<String> pinnedChannels,
  ) {
    final key = liveChannelKeyOf(channel);
    if (key == null) {
      return const IconButton(
        icon: Icon(Icons.push_pin_outlined),
        tooltip: 'ピン留め',
        onPressed: null,
      );
    }
    final pinned = pinnedChannels.contains(key);
    return IconButton(
      icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
      tooltip: pinned ? 'ピン留めを外す' : 'ピン留め',
      onPressed: () =>
          ref.read(pinnedChannelsProvider.notifier).setPinned(key, !pinned),
    );
  }
}

/// The list subtitle: the on-air time range and programme title
/// (the channel name already heads the tile), or the programme
/// outline when the item carried no channel name.
String _channelSubtitle(LiveChannel channel) {
  final start = channel.programStart;
  final end = channel.programEnd;
  final range = start != null && end != null
      ? '${formatTimeJst(start)}–${formatTimeJst(end)} '
      : '';
  if (channel.channelName != null) return '$range${channel.programTitle}';
  return '$range${channel.description ?? ''}';
}

/// The live channel carrying a programme-guide service,
/// matched on the (networkId, transportStreamId, serviceId)
/// triple the DIDL ids and the guide share (plan 95); null
/// when the LiveTuner tree has no such channel.
LiveChannel? liveChannelForService(
  List<LiveBand> bands, {
  required int networkId,
  required int transportStreamId,
  required int serviceId,
}) {
  for (final band in bands) {
    for (final channel in band.channels) {
      if (channel.networkId == networkId &&
          channel.transportStreamId == transportStreamId &&
          channel.serviceId == serviceId) {
        return channel;
      }
    }
  }
  return null;
}

/// From the programme guide to live viewing (plan 95):
/// resolves the guide channel's live channel and opens its
/// detail page, where the 視聴 button starts playback. When
/// the channel cannot be resolved — a band the LiveTuner
/// tree does not carry, or a failed fetch — a snackbar says
/// so instead of navigating nowhere.
Future<void> openLiveChannelForEpg(
  BuildContext context,
  WidgetRef ref, {
  required RegisteredNasne reg,
  required Channel channel,
}) async {
  final List<LiveBand> bands;
  try {
    bands = await ref.read(liveChannelsProvider(reg).future);
  } catch (_) {
    if (context.mounted) showSnack(context, 'チャンネル情報を取得できませんでした');
    return;
  }
  final live = liveChannelForService(
    bands,
    networkId: channel.networkId,
    transportStreamId: channel.transportStreamId,
    serviceId: channel.serviceId,
  );
  if (!context.mounted) return;
  if (live == null) {
    showSnack(context, '視聴可能なチャンネルが見つかりません');
    return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => LiveChannelDetailPage(reg: reg, channelId: live.id),
    ),
  );
}

/// Starts viewing [channel]: the flow the detail pane's
/// 視聴 button and the channel list's double-click share.
/// The engine's live start runs at the res [useMobile]
/// picks — the detail visit's quality choice in the
/// detail, the saved quality from the list; the detail
/// also starts from the saved quality, so both starts
/// pick alike — with the zap targets of the channel's
/// band, under the shared launcher's failure handling.
/// [onStarting] runs at the moment the start itself
/// begins, after the pre-checks have passed: the detail
/// view marks its button busy there (plan 35).
Future<void> startLiveChannelViewing({
  required BuildContext context,
  required WidgetRef ref,
  required RegisteredNasne reg,
  required LiveChannel channel,
  required bool useMobile,
  VoidCallback? onStarting,
}) async {
  final engine = ref.read(deviceServicesProvider(reg)).playback;
  if (!engine.isSupported) {
    await showPlaybackUnsupportedDialog(context, subject: 'TV視聴');
    return;
  }
  if (channel.res.isEmpty) {
    showSnack(context, '視聴可能なコンテンツがありません');
    return;
  }
  final res =
      (useMobile ? channel.mobileRes : channel.originalRes) ??
      channel.res.first;
  onStarting?.call();
  await startPlaybackAndShowPlayer(
    context: context,
    ref: ref,
    start: () => engine.startLivePlayback(channel, res),
    buildPlayer: (session) {
      final zap = _liveZapTargetsFor(
        ref: ref,
        reg: reg,
        channel: channel,
        useMobile: useMobile,
        engine: engine,
      );
      return PlayerScreen(
        title: channel.channelName ?? channel.programTitle,
        session: session,
        live: true,
        zapTargets: zap?.targets,
        zapIndex: zap?.index ?? 0,
      );
    },
    unsupportedSubject: 'TV視聴',
    startFailureMessage: '視聴を開始できませんでした',
  );
}

/// The zap targets for viewing [channel] (channel
/// movement inside the player, owner request
/// 2026-11-23): the playable channels of the same band,
/// in the order the live list shows them — the
/// subchannel setting applied, as the list applies it —
/// each with the start the viewing runs, at [useMobile]'s
/// quality, and the index of [channel] among them. Null
/// when the channel list is not at hand (its fetch has
/// not landed) or the band offers no second playable
/// channel: the player then keeps its plain title and
/// offers no movement.
({List<PlayerZapTarget> targets, int index})? _liveZapTargetsFor({
  required WidgetRef ref,
  required RegisteredNasne reg,
  required LiveChannel channel,
  required bool useMobile,
  required PlaybackEngine engine,
}) {
  final bands = ref.read(liveChannelsProvider(reg)).value;
  if (bands == null) return null;
  // The same two filters the list applies, so zapping
  // inside the player walks the channels the viewer
  // actually sees — a not-watched channel is never zapped
  // into either.
  final visible = liveBandsWithHiddenChannels(
    liveBandsWithSubchannelSetting(bands, ref.read(showSubchannelsProvider)),
    ref.read(hiddenChannelsProvider),
  );
  for (final band in visible) {
    if (!band.channels.any((c) => c.id == channel.id)) continue;
    final targets = <PlayerZapTarget>[];
    var index = -1;
    for (final c in band.channels) {
      if (c.res.isEmpty) continue;
      if (c.id == channel.id) index = targets.length;
      final res = (useMobile ? c.mobileRes : c.originalRes) ?? c.res.first;
      final actions = _liveProgrammeActionsFor(
        ref: ref,
        reg: reg,
        band: band,
        channel: c,
      );
      targets.add(
        PlayerZapTarget(
          name: c.channelName ?? c.programTitle,
          start: () => engine.startLivePlayback(c, res),
          record: actions?.record,
          programmeState: actions?.programmeState,
          stopProgramme: actions?.stopProgramme,
        ),
      );
    }
    if (targets.length < 2 || index < 0) return null;
    return (targets: targets, index: index);
  }
  return null;
}

/// The programme actions a zap target for [channel] in
/// [band] carries (user-fork addition, 2026-11-26):
/// record, state and stop for the programme now on air
/// on the channel, as one set (see PlayerZapTarget).
/// Only the terrestrial and BS bands carry them — the
/// programme guide, which the actions resolve the
/// on-air programme in, has no CS side, the same limit
/// the reservation form has — and only a channel with
/// its full broadcast identity can be found in the
/// guide at all.
({
  Future<LiveRecordResult> Function() record,
  Future<LiveProgrammeReservationState> Function() programmeState,
  Future<LiveRecordStopResult> Function() stopProgramme,
})?
_liveProgrammeActionsFor({
  required WidgetRef ref,
  required RegisteredNasne reg,
  required LiveBand band,
  required LiveChannel channel,
}) {
  final broadcastingType = switch (liveBandKind(band)) {
    LiveBandKind.terrestrial => terrestrialBroadcastingType,
    LiveBandKind.bs => bsBroadcastingType,
    LiveBandKind.cs => csBroadcastingType,
    _ => null,
  };
  if (broadcastingType == null ||
      channel.networkId == null ||
      channel.transportStreamId == null ||
      channel.serviceId == null) {
    return null;
  }
  return (
    record: () => _recordOnAirProgramme(
      ref: ref,
      reg: reg,
      channel: channel,
      broadcastingType: broadcastingType,
    ),
    programmeState: () => _onAirProgrammeState(
      ref: ref,
      reg: reg,
      channel: channel,
      broadcastingType: broadcastingType,
    ),
    stopProgramme: () => _stopOnAirProgramme(
      ref: ref,
      reg: reg,
      channel: channel,
      broadcastingType: broadcastingType,
    ),
  );
}

/// The programme now on air on [channel], resolved in
/// the programme guide at the moment of the call: the
/// guide service carrying the channel's broadcast
/// identity, and the event in it that covers now (see
/// player_record_policy). Null when the guide cannot
/// be fetched, has no such service, or no event in it
/// is on air. The guide is read through its provider
/// each time, so an action run after a zap — or long
/// into a viewing — resolves the programme then on
/// air, not the one at open.
Future<({Channel channel, EpgEvent event})?> _onAirProgramme({
  required WidgetRef ref,
  required RegisteredNasne reg,
  required LiveChannel channel,
  required int broadcastingType,
}) async {
  final EpgGuide guide;
  try {
    guide = await ref.read(
      (switch (broadcastingType) {
        bsBroadcastingType => bsEpgGuideProvider(reg),
        csBroadcastingType => csEpgGuideProvider(reg),
        _ => epgGuideProvider(reg),
      }).future,
    );
  } catch (e) {
    ref.read(diagLogProvider)(
      DiagCategory.ui,
      'live: programme guide fetch for the record action failed: $e',
    );
    return null;
  }
  final service = guideServiceForLiveChannel(
    guide,
    networkId: channel.networkId,
    transportStreamId: channel.transportStreamId,
    serviceId: channel.serviceId,
  );
  if (service == null) return null;
  final event = onAirEvent(service.events, DateTime.now());
  if (event == null) return null;
  return (channel: service.channel, event: event);
}

/// Creates the reservation for a programme-guide
/// [event] on its guide [channel]: the guide's own
/// creation path, driven as the auto-record checker
/// drives it — the candidate built from the event as a
/// guide reservation is (see [liveRecordCandidate]), an
/// existing reservation for the event reported instead
/// of duplicated, the device conflict check before the
/// create, and the reservation list invalidated after
/// it, so the 予約 screen shows the new reservation
/// without a manual refresh. An event that has already
/// started is reserved with its true start, as the
/// guide's form sends it (see player_record_policy).
///
/// The one create path behind every one-press record
/// action the fork adds: the live player's record
/// action resolves the on-air event and drives this
/// (see [_recordOnAirProgramme]), and the programme
/// search results' row menu drives it with the hit's
/// event (see epg_search_screen.dart).
Future<LiveRecordResult> recordGuideEvent({
  required WidgetRef ref,
  required RegisteredNasne reg,
  required Channel channel,
  required EpgEvent event,
}) async {
  final services = ref.read(deviceServicesProvider(reg));
  final candidate = liveRecordCandidate(channel: channel, event: event);
  try {
    final existing = await ref.read(schedulesProvider(reg).future);
    if (reservationForEvent(existing, channel: channel, event: event) !=
        null) {
      return LiveRecordResult.alreadyReserved;
    }
    final conflicts = await services.schedules.checkConflicts(candidate);
    if (conflicts.isNotEmpty) return LiveRecordResult.conflict;
    await services.schedules.createSchedule(candidate);
  } catch (e) {
    ref.read(diagLogProvider)(
      DiagCategory.ui,
      'record: creating the guide event reservation failed: $e',
    );
    return LiveRecordResult.failed;
  }
  ref.invalidate(schedulesProvider(reg));
  return LiveRecordResult.created;
}

/// Creates the reservation for the programme now on
/// air on [channel] (user-fork addition, 2026-11-26):
/// the on-air event resolved in the guide, then the
/// shared guide-event create (see [recordGuideEvent]).
Future<LiveRecordResult> _recordOnAirProgramme({
  required WidgetRef ref,
  required RegisteredNasne reg,
  required LiveChannel channel,
  required int broadcastingType,
}) async {
  final resolved = await _onAirProgramme(
    ref: ref,
    reg: reg,
    channel: channel,
    broadcastingType: broadcastingType,
  );
  if (resolved == null) return LiveRecordResult.unavailable;
  return recordGuideEvent(
    ref: ref,
    reg: reg,
    channel: resolved.channel,
    event: resolved.event,
  );
}

/// The reservation state of the programme now on air
/// on [channel] (user-fork addition, 2026-11-26): the
/// reservation the on-air event owns, read from the
/// reservation list and classified against now (see
/// player_record_policy). Anything unreadable answers
/// none: the controls then offer recording, and a
/// press re-checks before it creates.
Future<LiveProgrammeReservationState> _onAirProgrammeState({
  required WidgetRef ref,
  required RegisteredNasne reg,
  required LiveChannel channel,
  required int broadcastingType,
}) async {
  final resolved = await _onAirProgramme(
    ref: ref,
    reg: reg,
    channel: channel,
    broadcastingType: broadcastingType,
  );
  if (resolved == null) return LiveProgrammeReservationState.none;
  final List<RecordSchedule> existing;
  try {
    existing = await ref.read(schedulesProvider(reg).future);
  } catch (_) {
    return LiveProgrammeReservationState.none;
  }
  return liveProgrammeReservationState(
    reservation: reservationForEvent(
      existing,
      channel: resolved.channel,
      event: resolved.event,
    ),
    now: DateTime.now(),
  );
}

/// Stops the programme now on air on [channel]
/// (user-fork addition, 2026-11-26): deletes its
/// reservation through the reservation list's own
/// delete — the same call the 予約 screen's delete
/// makes — and invalidates the list, as that delete
/// does. Whether the outcome is worded as stopping a
/// recording or cancelling a reservation follows the
/// state the found reservation is in at the delete.
Future<LiveRecordStopResult> _stopOnAirProgramme({
  required WidgetRef ref,
  required RegisteredNasne reg,
  required LiveChannel channel,
  required int broadcastingType,
}) async {
  final resolved = await _onAirProgramme(
    ref: ref,
    reg: reg,
    channel: channel,
    broadcastingType: broadcastingType,
  );
  if (resolved == null) return LiveRecordStopResult.gone;
  final List<RecordSchedule> existing;
  try {
    existing = await ref.read(schedulesProvider(reg).future);
  } catch (e) {
    ref.read(diagLogProvider)(
      DiagCategory.ui,
      'live: reading the reservations for the stop action failed: $e',
    );
    return LiveRecordStopResult.failed;
  }
  final reservation = reservationForEvent(
    existing,
    channel: resolved.channel,
    event: resolved.event,
  );
  if (reservation == null) return LiveRecordStopResult.gone;
  final recording =
      liveProgrammeReservationState(
        reservation: reservation,
        now: DateTime.now(),
      ) ==
      LiveProgrammeReservationState.recording;
  try {
    await ref
        .read(deviceServicesProvider(reg))
        .schedules
        .deleteSchedule(reservation.id);
  } catch (e) {
    ref.read(diagLogProvider)(
      DiagCategory.ui,
      'live: stopping the on-air programme failed: $e',
    );
    return recording
        ? LiveRecordStopResult.stopFailed
        : LiveRecordStopResult.cancelFailed;
  }
  ref.invalidate(schedulesProvider(reg));
  return recording
      ? LiveRecordStopResult.stopped
      : LiveRecordStopResult.cancelled;
}

/// Detail page for narrow layouts.
class LiveChannelDetailPage extends ConsumerWidget {
  const LiveChannelDetailPage({
    super.key,
    required this.reg,
    required this.channelId,
  });

  final RegisteredNasne reg;
  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bands = ref.watch(liveChannelsProvider(reg));
    return Scaffold(
      appBar: AppBar(title: const Text('チャンネルの詳細')),
      body: asyncSection(bands, (list) {
        for (final band in list) {
          for (final channel in band.channels) {
            if (channel.id == channelId) {
              return LiveChannelDetailView(reg: reg, channel: channel);
            }
          }
        }
        return const Center(child: Text('チャンネルが見つかりません'));
      }, onRetry: () => ref.invalidate(liveChannelsProvider(reg))),
    );
  }
}

/// The channel detail: the current programme's information and
/// the viewing action, with the plan-33 quality choice when the
/// channel offers a mobile resource. The choice starts from the
/// saved playback quality — the original quality until one is
/// saved — and writes changes back to it.
class LiveChannelDetailView extends ConsumerStatefulWidget {
  const LiveChannelDetailView({
    super.key,
    required this.reg,
    required this.channel,
  });

  final RegisteredNasne reg;
  final LiveChannel channel;

  @override
  ConsumerState<LiveChannelDetailView> createState() =>
      _LiveChannelDetailViewState();
}

class _LiveChannelDetailViewState extends ConsumerState<LiveChannelDetailView> {
  /// Playback quality choice (plan 33, shared with recordings).
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

  /// A viewing start is in flight (plan 35 guard, shared with
  /// recordings): while set, the button is disabled and _watch
  /// is re-entrancy-guarded.
  bool _starting = false;

  RegisteredNasne get reg => widget.reg;
  LiveChannel get channel => widget.channel;

  @override
  Widget build(BuildContext context) {
    final ch = channel;
    // The quality choice in effect: this visit's own choice
    // once made, the saved quality otherwise. Watching the
    // saved quality rebuilds this view when its asynchronous
    // restore lands.
    final bool useMobile =
        _useMobileChoice ?? ref.watch(playbackQualityProvider);
    final originalRes = ch.originalRes;
    final mobileRes = ch.mobileRes;
    final originalLabel = originalRes?.quality == null
        ? '元画質'
        : '元画質 (${resQualityLabel(originalRes!.quality)})';
    final start = ch.programStart;
    final end = ch.programEnd;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // TV: the heading and the closing note are display-only;
        // both hold focus (TvFocusAnchor) so D-pad traversal can
        // scroll to both ends of the detail (plan 123).
        TvFocusAnchor(
          child: Text(
            ch.programTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        if (ch.channelName != null)
          FieldRow(label: 'チャンネル', value: ch.channelName!),
        if (start != null && end != null)
          FieldRow(
            label: '放送時間',
            value:
                '${formatDateTimeWithWeekdayJst(start)}–${formatTimeJst(end)}',
          ),
        if (ch.genre != null) FieldRow(label: 'ジャンル', value: ch.genre!),
        if (ch.description != null && ch.description!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('概要', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(ch.description!),
        ],
        if (ch.longDescription != null && ch.longDescription!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('詳細', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(ch.longDescription!),
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
          onPressed: _starting ? null : () => _watch(context, ref),
          icon: const Icon(Icons.play_arrow),
          label: const Text('視聴'),
        ),
        const SizedBox(height: 8),
        const TvFocusAnchor(
          child: Text('視聴には DTCP-IP の資格情報が必要です (設定画面からインポートできます)。'),
        ),
      ],
    );
  }

  Future<void> _watch(BuildContext context, WidgetRef ref) async {
    if (_starting) return;
    try {
      await startLiveChannelViewing(
        context: context,
        ref: ref,
        reg: reg,
        channel: channel,
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
