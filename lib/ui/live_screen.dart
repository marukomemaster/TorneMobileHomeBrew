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
/// The programme information is the snapshot the DIDL items
/// carried when the list was fetched; the refresh action
/// re-fetches it (a programme boundary does not update an
/// already listed item).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/providers.dart';
import '../app/state.dart';
import '../core/core.dart';
import 'channel_visibility.dart';
import 'epg_subchannel_visibility.dart';
import 'format.dart';
import 'playback_launcher.dart';
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
              onSelect: (channel, twoPane) {
                if (twoPane) {
                  setState(() => _selectedId = channel.id);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LiveChannelDetailPage(
                        reg: reg,
                        channelId: channel.id,
                      ),
                    ),
                  );
                }
              },
            ),
    );
  }
}

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
      // falls back to the first tab when it is gone.
      final tabBands = [
        for (final band in visibleBands)
          if (band.channels.isNotEmpty) band,
      ];
      final selectedBand = tabBands.firstWhere(
        (band) => band.containerId == selectedBandId,
        orElse: () => tabBands.first,
      );
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
              for (final channel in selectedBand.channels)
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
                  onTap: () => onSelect(channel, twoPane),
                ),
            ],
          );
          final content = Column(
            children: [
              if (tabBands.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: SegmentedButton<String>(
                    segments: [
                      for (final band in tabBands)
                        ButtonSegment<String>(
                          value: band.containerId,
                          label: Text(liveBandTabLabel(band)),
                        ),
                    ],
                    selected: {selectedBand.containerId},
                    onSelectionChanged: (selection) =>
                        onSelectBand(selection.first),
                  ),
                ),
              Expanded(child: listView),
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
        (_useMobile ? channel.mobileRes : channel.originalRes) ??
        channel.res.first;
    setState(() => _starting = true);
    try {
      await startPlaybackAndShowPlayer(
        context: context,
        ref: ref,
        start: () => engine.startLivePlayback(channel, res),
        buildPlayer: (session) {
          final zap = _zapTargetsFor(engine);
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
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// The zap targets for viewing [channel] (channel
  /// movement inside the player, owner request
  /// 2026-11-23): the playable channels of the same band,
  /// in the order the live list shows them — the
  /// subchannel setting applied, as the list applies it —
  /// each with the start this view's own viewing runs, at
  /// this visit's quality, and the index of [channel]
  /// among them. Null when the channel list is not at hand
  /// (its fetch has not landed) or the band offers no
  /// second playable channel: the player then keeps its
  /// plain title and offers no movement.
  ({List<PlayerZapTarget> targets, int index})? _zapTargetsFor(
    PlaybackEngine engine,
  ) {
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
      final useMobile = _useMobile;
      final targets = <PlayerZapTarget>[];
      var index = -1;
      for (final c in band.channels) {
        if (c.res.isEmpty) continue;
        if (c.id == channel.id) index = targets.length;
        final res = (useMobile ? c.mobileRes : c.originalRes) ?? c.res.first;
        targets.add(
          PlayerZapTarget(
            name: c.channelName ?? c.programTitle,
            start: () => engine.startLivePlayback(c, res),
          ),
        );
      }
      if (targets.length < 2 || index < 0) return null;
      return (targets: targets, index: index);
    }
    return null;
  }
}
