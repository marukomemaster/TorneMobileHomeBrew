/// Pinned (favourite) channels for the TV視聴 screen
/// (owner request 2026-11-26): a ピン留め tab ahead of the
/// band tabs lists the channels the viewer pinned, across
/// every band, the way KonomiTV's pinned tab does. The
/// choice itself lives in the pinned-channels notifier
/// (app/providers.dart) and is toggled from the live list's
/// rows.
///
/// The identity a channel is pinned under is the
/// (networkId, transportStreamId, serviceId) triple — the
/// same identity the not-watched choice uses
/// (channel_visibility.dart) — so one channel carries one
/// name on both surfaces, and a channel whose identity is
/// not known cannot be pinned at all, like it cannot be
/// hidden.
library;

import '../core/core.dart';
import 'channel_visibility.dart';

/// Whether a channel under [key] is pinned. A null key
/// (identity unknown) is never pinned.
bool channelIsPinned(String? key, Set<String> pinnedKeys) =>
    key != null && pinnedKeys.contains(key);

/// The pinned channels of [bands], flattened in band order
/// and, within a band, in the order the live list shows
/// them — the deterministic order the ピン留め tab lists.
/// Callers pass the bands after the subchannel and
/// not-watched filters, so a channel the viewer hid never
/// appears here even while it stays pinned. An empty
/// choice returns an empty list.
List<LiveChannel> pinnedLiveChannels(
  List<LiveBand> bands,
  Set<String> pinnedKeys,
) {
  if (pinnedKeys.isEmpty) return const [];
  return [
    for (final band in bands)
      for (final channel in band.channels)
        if (channelIsPinned(liveChannelKeyOf(channel), pinnedKeys)) channel,
  ];
}
