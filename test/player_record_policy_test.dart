/// Live record policy tests (user-fork addition): the
/// record action's gating, its feedback wording, and the
/// pure resolution the live side drives — the on-air
/// event, the guide service for a live channel, and the
/// reservation candidate built from them, which must
/// match the shape a guide reservation is created with.
/// The stop side is here too: the reservation state a
/// found reservation puts the programme in, the
/// reservation a guide event owns, and the stop's
/// gating and wording.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/player_record_policy.dart';

const _channel = Channel(
  broadcastingType: 2,
  networkId: 7880,
  transportStreamId: 7880,
  serviceId: 56832,
  serviceType: 1,
  channelNumber: 1,
  serviceName: 'テスト放送',
);

const _otherChannel = Channel(
  broadcastingType: 2,
  networkId: 7880,
  transportStreamId: 7880,
  serviceId: 56833,
  serviceType: 1,
  channelNumber: 2,
  serviceName: '別局',
);

EpgEvent _event(int id, DateTime start, int minutes) => EpgEvent(
  eventId: id,
  start: start,
  duration: Duration(minutes: minutes),
  title: '番組$id',
);

RecordSchedule _reservation(
  String id,
  DateTime start,
  int minutes, {
  String desiredMatchingId = ',,0x1ec8,0x0000',
  int serviceId = 56832,
}) => RecordSchedule(
  id: id,
  start: start,
  durationSeconds: minutes * 60,
  conditionId: '1',
  channel: ScheduleChannel(
    broadcastingType: 2,
    channelType: 2,
    serviceId: serviceId,
  ),
  desiredQualityMode: 100,
  desiredMatchingId: desiredMatchingId,
  reservationCreatorId: '2000',
  priorityFlag: 0,
  recordDestinationId: 'HDD',
);

void main() {
  group('canRecordCurrentProgramme', () {
    test('live with an action and nothing in flight can record', () {
      expect(
        canRecordCurrentProgramme(
          live: true,
          hasRecordAction: true,
          busy: false,
        ),
        isTrue,
      );
    });

    test('a recording offers no record action', () {
      expect(
        canRecordCurrentProgramme(
          live: false,
          hasRecordAction: true,
          busy: false,
        ),
        isFalse,
      );
    });

    test('a channel without a record action cannot record', () {
      expect(
        canRecordCurrentProgramme(
          live: true,
          hasRecordAction: false,
          busy: false,
        ),
        isFalse,
      );
    });

    test('a record, switch or open in flight blocks a second press', () {
      expect(
        canRecordCurrentProgramme(
          live: true,
          hasRecordAction: true,
          busy: true,
        ),
        isFalse,
      );
    });
  });

  group('liveRecordResultMessage', () {
    test('wording per outcome', () {
      expect(liveRecordResultMessage(LiveRecordResult.created), '予約を作成しました');
      expect(
        liveRecordResultMessage(LiveRecordResult.alreadyReserved),
        'すでに予約されています',
      );
      expect(
        liveRecordResultMessage(LiveRecordResult.conflict),
        '競合する予約があるため予約できませんでした',
      );
      expect(
        liveRecordResultMessage(LiveRecordResult.unavailable),
        '番組情報を取得できませんでした',
      );
      expect(liveRecordResultMessage(LiveRecordResult.failed), '予約を作成できませんでした');
    });
  });

  group('onAirEvent', () {
    final start = DateTime(2026, 11, 26, 19, 0);
    final events = [
      _event(1, start.subtract(const Duration(hours: 1)), 60),
      _event(2, start, 30),
      _event(3, start.add(const Duration(minutes: 30)), 30),
    ];

    test('the event spanning now is the one on air', () {
      expect(
        onAirEvent(events, start.add(const Duration(minutes: 10)))?.eventId,
        2,
      );
    });

    test('the start instant belongs to the starting event', () {
      expect(onAirEvent(events, start)?.eventId, 2);
    });

    test('the end instant belongs to the next event, not the ending one', () {
      expect(
        onAirEvent(events, start.add(const Duration(minutes: 30)))?.eventId,
        3,
      );
    });

    test('before every event and in a gap there is none', () {
      expect(
        onAirEvent(events, start.subtract(const Duration(hours: 2))),
        null,
      );
      expect(onAirEvent(events, start.add(const Duration(hours: 2))), null);
      expect(onAirEvent(const [], start), null);
    });
  });

  group('guideServiceForLiveChannel', () {
    final guide = EpgGuide(
      broadcastingType: 2,
      services: [
        EpgServiceGuide(channel: _otherChannel, events: const []),
        EpgServiceGuide(channel: _channel, events: const []),
      ],
    );

    test('matches on the broadcast identity triple', () {
      final service = guideServiceForLiveChannel(
        guide,
        networkId: 7880,
        transportStreamId: 7880,
        serviceId: 56832,
      );
      expect(service?.channel.serviceName, 'テスト放送');
    });

    test('no match when the guide has no such service', () {
      expect(
        guideServiceForLiveChannel(
          guide,
          networkId: 7880,
          transportStreamId: 7880,
          serviceId: 99999,
        ),
        isNull,
      );
    });

    test('a channel without identity never matches', () {
      expect(
        guideServiceForLiveChannel(
          guide,
          networkId: null,
          transportStreamId: 7880,
          serviceId: 56832,
        ),
        isNull,
      );
    });
  });

  group('liveRecordCandidate', () {
    test('carries the event and service as a guide reservation does', () {
      final start = DateTime(2026, 11, 26, 19, 0);
      final candidate = liveRecordCandidate(
        channel: _channel,
        event: _event(42, start, 45),
      );
      expect(candidate.start, start);
      expect(candidate.durationSeconds, 45 * 60);
      expect(candidate.channel.broadcastingType, 2);
      expect(candidate.channel.channelType, 2);
      expect(candidate.channel.serviceId, 56832);
      expect(candidate.networkId, 7880);
      expect(candidate.eventId, 42);
      expect(candidate.desiredMatchingId, ',,0x1ec8,0x002a');
    });
  });

  group('liveProgrammeReservationState', () {
    final start = DateTime(2026, 11, 26, 19, 0);
    final now = start.add(const Duration(minutes: 10));

    test('no reservation is none', () {
      expect(
        liveProgrammeReservationState(reservation: null, now: now),
        LiveProgrammeReservationState.none,
      );
    });

    test('a reservation covering now is recording', () {
      expect(
        liveProgrammeReservationState(
          reservation: _reservation('a', start, 60),
          now: now,
        ),
        LiveProgrammeReservationState.recording,
      );
      expect(
        liveProgrammeReservationState(
          reservation: _reservation('a', now, 60),
          now: now,
        ),
        LiveProgrammeReservationState.recording,
      );
    });

    test('a reservation still ahead is reserved', () {
      expect(
        liveProgrammeReservationState(
          reservation: _reservation(
            'a',
            now.add(const Duration(minutes: 5)),
            60,
          ),
          now: now,
        ),
        LiveProgrammeReservationState.reserved,
      );
    });

    test('a reservation already over is none', () {
      expect(
        liveProgrammeReservationState(
          reservation: _reservation('a', start, 10),
          now: now,
        ),
        LiveProgrammeReservationState.none,
      );
    });
  });

  group('reservationForEvent', () {
    final start = DateTime(2026, 11, 26, 19, 0);
    final event = _event(42, start, 45);

    test('finds an event reservation by its event id', () {
      // The device may have normalised the start; the
      // event id still identifies the reservation.
      final found = reservationForEvent(
        [
          _reservation(
            'a',
            start.add(const Duration(minutes: 1)),
            44,
            desiredMatchingId: '0x1ec8,0x1ec8,0xde00,0x002a',
          ),
        ],
        channel: _channel,
        event: event,
      );
      expect(found?.id, 'a');
    });

    test('finds a manual reservation by its start', () {
      final found = reservationForEvent(
        [_reservation('m', start, 45)],
        channel: _channel,
        event: event,
      );
      expect(found?.id, 'm');
    });

    test('an event-id match wins over a start match', () {
      final found = reservationForEvent(
        [
          _reservation('byStart', start, 45),
          _reservation(
            'byEvent',
            start.add(const Duration(minutes: 2)),
            43,
            desiredMatchingId: ',,0x1ec8,0x002a',
          ),
        ],
        channel: _channel,
        event: event,
      );
      expect(found?.id, 'byEvent');
    });

    test('another service or an empty list finds nothing', () {
      expect(
        reservationForEvent(
          [_reservation('x', start, 45, serviceId: 99999)],
          channel: _channel,
          event: event,
        ),
        isNull,
      );
      expect(
        reservationForEvent(const [], channel: _channel, event: event),
        isNull,
      );
    });
  });

  group('canStopCurrentProgramme', () {
    test('a recording with nothing in flight can stop', () {
      expect(
        canStopCurrentProgramme(
          live: true,
          hasStopAction: true,
          state: LiveProgrammeReservationState.recording,
          busy: false,
        ),
        isTrue,
      );
    });

    test('state none has nothing to stop', () {
      expect(
        canStopCurrentProgramme(
          live: true,
          hasStopAction: true,
          state: LiveProgrammeReservationState.none,
          busy: false,
        ),
        isFalse,
      );
    });

    test('a recording, a missing action or work in flight blocks it', () {
      expect(
        canStopCurrentProgramme(
          live: false,
          hasStopAction: true,
          state: LiveProgrammeReservationState.reserved,
          busy: false,
        ),
        isFalse,
      );
      expect(
        canStopCurrentProgramme(
          live: true,
          hasStopAction: false,
          state: LiveProgrammeReservationState.reserved,
          busy: false,
        ),
        isFalse,
      );
      expect(
        canStopCurrentProgramme(
          live: true,
          hasStopAction: true,
          state: LiveProgrammeReservationState.reserved,
          busy: true,
        ),
        isFalse,
      );
    });
  });

  group('liveProgrammeActionLabel', () {
    test('wording per state', () {
      expect(
        liveProgrammeActionLabel(LiveProgrammeReservationState.none),
        '録画',
      );
      expect(
        liveProgrammeActionLabel(LiveProgrammeReservationState.reserved),
        '予約を取り消し',
      );
      expect(
        liveProgrammeActionLabel(LiveProgrammeReservationState.recording),
        '録画停止',
      );
    });
  });

  group('liveRecordStopResultMessage', () {
    test('wording per outcome', () {
      expect(
        liveRecordStopResultMessage(LiveRecordStopResult.stopped),
        '録画を停止しました',
      );
      expect(
        liveRecordStopResultMessage(LiveRecordStopResult.cancelled),
        '予約を取り消しました',
      );
      expect(
        liveRecordStopResultMessage(LiveRecordStopResult.gone),
        '予約はすでに取り消されています',
      );
      expect(
        liveRecordStopResultMessage(LiveRecordStopResult.stopFailed),
        '録画を停止できませんでした',
      );
      expect(
        liveRecordStopResultMessage(LiveRecordStopResult.cancelFailed),
        '予約を取り消せませんでした',
      );
      expect(
        liveRecordStopResultMessage(LiveRecordStopResult.failed),
        '予約を削除できませんでした',
      );
    });
  });
}
