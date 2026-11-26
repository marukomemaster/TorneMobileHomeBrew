/// Applies the viewer's not-watched channels (owner request
/// 2026-11-26) to the two channel listings: the TV視聴 live
/// list and the programme guide. A hidden channel drops out
/// of both, the way a subchannel drops out under the
/// subchannel switch (epg_subchannel_visibility.dart); the
/// choice itself lives in the hidden-channels notifier
/// (app/providers.dart) and its settings page
/// (hidden_channels_screen.dart).
///
/// The identity a channel is hidden under is the
/// (networkId, transportStreamId, serviceId) triple — the
/// same identity the guide and the LiveTuner tree are
/// matched on (live_screen.dart's liveChannelForService), so
/// one choice covers both surfaces and every band. Channels
/// whose identity is not known (a live item whose DIDL id
/// carried no parameters) cannot be classified and stay
/// visible, like the subchannel filter's rule.
library;

import '../core/core.dart';

/// The stored key of one channel: its
/// (networkId, transportStreamId, serviceId) triple in
/// decimal, colon-separated.
String channelVisibilityKey({
  required int networkId,
  required int transportStreamId,
  required int serviceId,
}) => '$networkId:$transportStreamId:$serviceId';

/// The key of a guide channel.
String channelKeyOf(Channel channel) => channelVisibilityKey(
  networkId: channel.networkId,
  transportStreamId: channel.transportStreamId,
  serviceId: channel.serviceId,
);

/// The key of a live channel, or null when the item carried
/// no (network, transport stream, service) identity.
String? liveChannelKeyOf(LiveChannel channel) {
  final networkId = channel.networkId;
  final transportStreamId = channel.transportStreamId;
  final serviceId = channel.serviceId;
  if (networkId == null || transportStreamId == null || serviceId == null) {
    return null;
  }
  return channelVisibilityKey(
    networkId: networkId,
    transportStreamId: transportStreamId,
    serviceId: serviceId,
  );
}

/// Whether a channel under [key] is hidden by the viewer's
/// choice. A null key (identity unknown) is never hidden.
bool channelIsHidden(String? key, Set<String> hiddenKeys) =>
    key != null && hiddenKeys.contains(key);

/// The programme guide without the hidden channels'
/// services. An empty choice returns the guide unchanged.
EpgGuide guideWithHiddenChannels(EpgGuide guide, Set<String> hiddenKeys) {
  if (hiddenKeys.isEmpty) return guide;
  final services = [
    for (final service in guide.services)
      if (!channelIsHidden(channelKeyOf(service.channel), hiddenKeys)) service,
  ];
  if (services.length == guide.services.length) return guide;
  return EpgGuide(broadcastingType: guide.broadcastingType, services: services);
}

/// The live bands without the hidden channels. Bands keep
/// their containers even when every channel drops out; the
/// list screen already skips empty bands for its tabs.
List<LiveBand> liveBandsWithHiddenChannels(
  List<LiveBand> bands,
  Set<String> hiddenKeys,
) {
  if (hiddenKeys.isEmpty) return bands;
  return [
    for (final band in bands)
      LiveBand(
        containerId: band.containerId,
        title: band.title,
        channels: [
          for (final channel in band.channels)
            if (!channelIsHidden(liveChannelKeyOf(channel), hiddenKeys))
              channel,
        ],
      ),
  ];
}
