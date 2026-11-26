/// The not-watched channel selection (owner request
/// 2026-11-26): the viewer turns off the channels they never
/// watch, and those channels drop out of the TV視聴 live
/// list and the programme guide. Reached from the settings
/// screen's 番組表 section, next to 見ないジャンル; the
/// choice persists through [HiddenChannelsNotifier] and the
/// filter itself is ui/channel_visibility.dart.
///
/// The channel rows come from the selected unit's live
/// channel list — the one listing that covers every band
/// the live screen shows, CS included. The hidden choice is
/// keyed on the broadcast identity (see
/// channel_visibility.dart), so it names the service, not
/// this unit's row: it holds on every registered unit in
/// the area.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/providers.dart';
import '../app/state.dart';
import '../core/core.dart';
import 'channel_visibility.dart';
import 'live_screen.dart' show liveBandTabLabel;
import 'widgets.dart';

class HiddenChannelsScreen extends ConsumerWidget {
  const HiddenChannelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reg = ref.watch(selectedRegistrationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('見ないチャンネル')),
      body: reg == null
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('登録済みの nasne がありません。'),
            )
          : asyncSection(
              ref.watch(liveChannelsProvider(reg)),
              (bands) => _ChannelSwitches(bands: bands),
              onRetry: () => ref.invalidate(liveChannelsProvider(reg)),
            ),
    );
  }
}

class _ChannelSwitches extends ConsumerWidget {
  const _ChannelSwitches({required this.bands});

  final List<LiveBand> bands;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hiddenChannelsProvider);
    final channels = [for (final band in bands) ...band.channels];
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('オフにしたチャンネルは、TV視聴と番組表に表示されなくなります。'),
        ),
        ListTile(
          leading: const Icon(Icons.restart_alt),
          title: const Text('すべて表示する'),
          subtitle: Text(
            hidden.isEmpty
                ? '非表示のチャンネルはありません'
                : '${hidden.length} チャンネルを非表示にしています',
          ),
          enabled: hidden.isNotEmpty,
          onTap: hidden.isEmpty ? null : () => _reset(context, ref),
        ),
        const Divider(),
        if (channels.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('視聴可能なチャンネルがありません'),
          ),
        for (final band in bands)
          if (band.channels.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                liveBandTabLabel(band),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final channel in band.channels)
              _channelTile(context, ref, channel, hidden),
          ],
      ],
    );
  }

  Widget _channelTile(
    BuildContext context,
    WidgetRef ref,
    LiveChannel channel,
    Set<String> hidden,
  ) {
    final key = liveChannelKeyOf(channel);
    final name = channel.channelName ?? channel.programTitle;
    if (key == null) {
      // No broadcast identity in the item's id: the channel
      // cannot be keyed, so it always stays visible (the
      // filter's rule) and the switch is shown disabled
      // rather than pretending it works.
      return SwitchListTile(
        title: Text(name),
        value: true,
        onChanged: null,
      );
    }
    return SwitchListTile(
      title: Text(name),
      value: !hidden.contains(key),
      onChanged: (visible) =>
          ref.read(hiddenChannelsProvider.notifier).setHidden(key, !visible),
    );
  }

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: '見ないチャンネル',
      message: 'すべてのチャンネルを表示に戻しますか？',
      confirmLabel: 'リセット',
    );
    if (!ok) return;
    await ref.read(hiddenChannelsProvider.notifier).reset();
  }
}
