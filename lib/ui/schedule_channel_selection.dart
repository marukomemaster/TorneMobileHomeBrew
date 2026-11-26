/// Safe channel selection for XSRS recordings (terrestrial, BS and CS).
/// Keys include band, network, TS and service; a serviceId alone is not unique.
library;

import '../core/core.dart';

String scheduleChannelKey(Channel c) =>
    '${c.broadcastingType}:${c.networkId}:${c.transportStreamId}:${c.serviceId}';

/// Returns null rather than silently switching an EPG reservation to another
/// service. An original XSRS item only has band + serviceId, so time-change
/// may preselect it only when the match is unambiguous.
String? initialScheduleChannelKey(
  List<Channel> choices,
  int band,
  String? selectedKey, {
  Channel? prefill,
  ScheduleChannel? original,
  bool defaultToFirst = false,
}) {
  final valid = [
    for (final c in choices)
      if (c.broadcastingType == band) c,
  ];
  bool contains(String key) => valid.any((c) => scheduleChannelKey(c) == key);
  if (selectedKey != null) {
    return contains(selectedKey) ? selectedKey : null;
  }
  if (prefill != null && prefill.broadcastingType == band) {
    final key = scheduleChannelKey(prefill);
    return contains(key) ? key : null;
  }
  if (original != null && original.broadcastingType == band) {
    final matches = valid.where((c) => c.serviceId == original.serviceId);
    return matches.length == 1 ? scheduleChannelKey(matches.single) : null;
  }
  return defaultToFirst && valid.isNotEmpty
      ? scheduleChannelKey(valid.first)
      : null;
}

Channel? resolveScheduleChannel(List<Channel> choices, int band, String? key) {
  if (key == null) return null;
  for (final c in choices) {
    if (c.broadcastingType == band && scheduleChannelKey(c) == key) {
      return c;
    }
  }
  return null;
}
