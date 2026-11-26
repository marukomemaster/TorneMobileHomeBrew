/// Recording the programme being watched (user-fork
/// addition, 2026-11-26): the live player's record action
/// — a button in the tap-shown controls and an item in
/// the channel list menu — reserves the programme now on
/// air on the channel being watched.
///
/// The reservation itself is the guide's own creation
/// path, driven from the live side (see live_screen.dart):
/// the on-air event is resolved in the programme guide,
/// the candidate is built from it exactly as a guide
/// reservation is (see [liveRecordCandidate]), an existing
/// reservation for the event is reported instead of
/// duplicated, the device conflict check runs before the
/// create, and the reservation list is invalidated after
/// it, so the 予約 screen shows the new reservation
/// without a manual refresh.
///
/// What the device is sent follows the measured create
/// contract: the guide offers this same reservation for
/// an event that has already started (its detail offers
/// 録画予約 until the event ends) and the prefilled form
/// sends the event's own start unchanged, so a started
/// programme is reserved with its true start — nothing
/// here trims it to "now". Whether the unit then records
/// the remainder or refuses the past start is the
/// device's side of that contract, unmeasured from here;
/// a refusal comes back as a failed create and is
/// reported as such (see [LiveRecordResult.failed]).
///
/// The same controls also stop the programme (user-fork
/// addition, 2026-11-26): while the watched programme
/// has a reservation, the record button and menu item
/// offer stopping it instead — 録画停止 while the
/// reservation covers the moment (the unit is recording
/// it), 予約を取り消し while it is still ahead. Stopping
/// is the reservation list's own delete — the same
/// confirmation dialog pattern, the same
/// `deleteSchedule` call, the same invalidation — driven
/// from the live side like the create. The state comes
/// from a query the live side answers (see
/// [LiveProgrammeReservationState]); the player asks
/// when a channel becomes the watched one and again
/// after each record / stop, so the offered action
/// follows zapping and the viewer's own actions. A
/// programme boundary passing while the viewer simply
/// keeps watching is not re-queried — the same
/// staleness the player's channel snapshot already has.
library;

import 'package:material_ui/material_ui.dart';

import '../core/core.dart';
import 'epg_reserved.dart';

/// What one press of the record action came to.
enum LiveRecordResult {
  /// The reservation was created.
  created,

  /// The programme already has a reservation; nothing
  /// was created.
  alreadyReserved,

  /// Another reservation overlaps the programme, so
  /// nothing was created. (The guide's form asks whether
  /// to proceed in this case; a one-press action from
  /// the player does not ask, it reports.)
  conflict,

  /// The programme being watched could not be resolved
  /// in the programme guide — the guide could not be
  /// fetched, it has no service for the channel, or no
  /// event in it is on air — so there was nothing
  /// definite to reserve.
  unavailable,

  /// The reservation list could not be read, or the
  /// create itself failed.
  failed,
}

/// Whether the record action can run: live viewing whose
/// current channel carries a record action, and no
/// record, channel switch or open in flight (a second
/// press must not race a duplicate create, or act on a
/// channel the viewer is leaving).
bool canRecordCurrentProgramme({
  required bool live,
  required bool hasRecordAction,
  required bool busy,
}) => live && hasRecordAction && !busy;

/// The viewer's feedback for a finished record attempt,
/// in the app's reservation wording: the created message
/// is the reservation form's own, and the failure
/// messages follow the playback screens' plain forms.
String liveRecordResultMessage(LiveRecordResult result) => switch (result) {
  LiveRecordResult.created => '予約を作成しました',
  LiveRecordResult.alreadyReserved => 'すでに予約されています',
  LiveRecordResult.conflict => '競合する予約があるため予約できませんでした',
  LiveRecordResult.unavailable => '番組情報を取得できませんでした',
  LiveRecordResult.failed => '予約を作成できませんでした',
};

/// The event on air at [now] among [events]: the one
/// that has started and not yet ended — the same span
/// the guide's detail treats as watchable. Null when no
/// event covers the moment: a gap in the guide's data,
/// or a snapshot that no longer reaches it.
EpgEvent? onAirEvent(List<EpgEvent> events, DateTime now) {
  for (final event in events) {
    if (!event.start.isAfter(now) && event.end.isAfter(now)) return event;
  }
  return null;
}

/// The guide service carrying the live channel with the
/// given broadcast identity — the (networkId,
/// transportStreamId, serviceId) triple the live list
/// and the guide share (plan 95). Null when the guide
/// has no such service, or the channel carried no
/// identity to match on.
EpgServiceGuide? guideServiceForLiveChannel(
  EpgGuide guide, {
  required int? networkId,
  required int? transportStreamId,
  required int? serviceId,
}) {
  if (networkId == null || transportStreamId == null || serviceId == null) {
    return null;
  }
  for (final service in guide.services) {
    final channel = service.channel;
    if (channel.networkId == networkId &&
        channel.transportStreamId == transportStreamId &&
        channel.serviceId == serviceId) {
      return service;
    }
  }
  return null;
}

/// The reservation candidate for [event] on [channel],
/// built exactly as a reservation created from the
/// programme guide is — the prefilled form and the
/// auto-record checker build the same shape: the
/// event's own start and duration, the guide service as
/// the reservation's channel, and the event id carried
/// into the desired matching id. Quality and destination
/// keep the create template's defaults, as the
/// checker's creations do.
NewRecordSchedule liveRecordCandidate({
  required Channel channel,
  required EpgEvent event,
}) {
  return NewRecordSchedule(
    start: event.start,
    durationSeconds: event.duration.inSeconds,
    channel: ScheduleChannel(
      broadcastingType: channel.broadcastingType,
      channelType: channel.broadcastingType,
      serviceId: channel.serviceId,
    ),
    networkId: channel.networkId,
    eventId: event.eventId,
  );
}

/// The reservation state of the programme being
/// watched, as the live side last reported it: decides
/// whether the player's record controls offer recording
/// the programme, stopping its recording, or cancelling
/// its reservation.
enum LiveProgrammeReservationState {
  /// No reservation covers the programme (or its state
  /// could not be read): the controls offer recording.
  none,

  /// A reservation for the programme exists but has not
  /// started: the controls offer cancelling it.
  reserved,

  /// A reservation for the programme covers the moment
  /// — the unit is recording it: the controls offer
  /// stopping the recording.
  recording,
}

/// The reservation state a found [reservation] puts the
/// watched programme in at [now]: covering the moment is
/// a recording in progress, a start still ahead is a
/// reservation to cancel, and a reservation already over
/// leaves nothing to stop (the match was by event, so
/// this is the device having normalised the span — the
/// programme is still on air, its recording is not).
LiveProgrammeReservationState liveProgrammeReservationState({
  required RecordSchedule? reservation,
  required DateTime now,
}) {
  if (reservation == null) return LiveProgrammeReservationState.none;
  if (!reservation.end.isAfter(now)) {
    return LiveProgrammeReservationState.none;
  }
  if (reservation.start.isAfter(now)) {
    return LiveProgrammeReservationState.reserved;
  }
  return LiveProgrammeReservationState.recording;
}

/// The reservation in [schedules] that belongs to
/// [event] on [channel], under the same two identities
/// the guide's reserved marks use (see [EpgReservedIndex]):
/// an event reservation matches on (broadcasting type,
/// service, event id) parsed out of its desired matching
/// id; any reservation also matches on (broadcasting
/// type, service, start) — the identity a manual
/// reservation, which carries event id 0, is found by.
/// An event-id match wins over a start match. Null when
/// no reservation belongs to the event.
RecordSchedule? reservationForEvent(
  List<RecordSchedule> schedules, {
  required Channel channel,
  required EpgEvent event,
}) {
  RecordSchedule? byStart;
  for (final s in schedules) {
    if (s.channel.broadcastingType != channel.broadcastingType ||
        s.channel.serviceId != channel.serviceId) {
      continue;
    }
    final eventId = desiredMatchingEventId(s.desiredMatchingId);
    if (eventId != null && eventId != 0 && eventId == event.eventId) {
      return s;
    }
    if (s.start == event.start) byStart ??= s;
  }
  return byStart;
}

/// Whether the stop action can run: live viewing whose
/// current channel carries a stop action, a programme
/// state that has something to stop, and no record,
/// stop, channel switch or open in flight.
bool canStopCurrentProgramme({
  required bool live,
  required bool hasStopAction,
  required LiveProgrammeReservationState state,
  required bool busy,
}) =>
    live &&
    hasStopAction &&
    state != LiveProgrammeReservationState.none &&
    !busy;

/// What the record controls offer for [state], worded
/// as the action itself: the button tooltips and the
/// channel menu's item share this one label.
String liveProgrammeActionLabel(LiveProgrammeReservationState state) =>
    switch (state) {
      LiveProgrammeReservationState.none => '録画',
      LiveProgrammeReservationState.reserved => '予約を取り消し',
      LiveProgrammeReservationState.recording => '録画停止',
    };

/// The record controls' icon for [state], shared by the
/// control bars and the TV controls so the surfaces
/// cannot drift apart.
IconData liveProgrammeActionIcon(LiveProgrammeReservationState state) =>
    switch (state) {
      LiveProgrammeReservationState.none => Icons.fiber_manual_record,
      LiveProgrammeReservationState.reserved => Icons.event_busy,
      LiveProgrammeReservationState.recording => Icons.stop_circle,
    };

/// What one press of the stop action came to. The
/// recording / reservation split mirrors the state the
/// delete acted on, so the feedback can word the two
/// apart like the actions themselves are worded.
enum LiveRecordStopResult {
  /// A recording in progress was stopped (its
  /// reservation deleted).
  stopped,

  /// A reservation that had not started was cancelled
  /// (deleted).
  cancelled,

  /// By the time the stop ran, the programme had no
  /// reservation to delete — it was cancelled elsewhere,
  /// or the programme could no longer be resolved.
  gone,

  /// Stopping a recording in progress failed at the
  /// delete.
  stopFailed,

  /// Cancelling a reservation failed at the delete.
  cancelFailed,

  /// The reservation list could not even be read, so
  /// nothing was decided or deleted.
  failed,
}

/// The viewer's feedback for a finished stop attempt.
/// The success messages mirror the action labels; the
/// undecided failure is phrased on the delete itself,
/// the reservation list's own noun for the operation.
String liveRecordStopResultMessage(LiveRecordStopResult result) =>
    switch (result) {
      LiveRecordStopResult.stopped => '録画を停止しました',
      LiveRecordStopResult.cancelled => '予約を取り消しました',
      LiveRecordStopResult.gone => '予約はすでに取り消されています',
      LiveRecordStopResult.stopFailed => '録画を停止できませんでした',
      LiveRecordStopResult.cancelFailed => '予約を取り消せませんでした',
      LiveRecordStopResult.failed => '予約を削除できませんでした',
    };
