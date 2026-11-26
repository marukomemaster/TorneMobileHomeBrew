/// CS EPG providers, mirroring the BS ones (bs_epg_providers).
/// Terrestrial and BS providers remain unchanged, including
/// their cache keys.
///
/// Channel logos are not fetched for CS: channelLogoDataGet
/// with broadcastingType 4 is unmeasured, so the guide header
/// shows CS channel names without logos (plan 137).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'providers.dart';

/// Measured nasne WebAPI broadcastingType for 110-degree CS
/// digital television (FW 2.60, plan 137): channelListGet,
/// EPGVersionInfoGet and EPGGet all answer for this type, and
/// the version table behind it is the CS EPG store.
const int csBroadcastingType = 4;

final csChannelsProvider = FutureProvider.family<List<Channel>, RegisteredNasne>(
  (ref, reg) async {
    final service = ref.watch(deviceServicesProvider(reg)).deviceInfo;
    final cache = ref.watch(channelCacheProvider);
    try {
      final channels = await service.listChannels(csBroadcastingType);
      await cache.save(reg.host, csBroadcastingType, channels);
      return channels;
    } on NasneError {
      final cached = await cache.load(reg.host, csBroadcastingType);
      if (cached != null) return cached;
      rethrow;
    }
  },
);

final csEpgGuideProvider = FutureProvider.family<EpgGuide, RegisteredNasne>(
  (ref, reg) async {
    final channels = await ref.watch(csChannelsProvider(reg).future);
    return ref
        .watch(deviceServicesProvider(reg))
        .metadata
        .getProgrammeGuide(csBroadcastingType, channels);
  },
);
