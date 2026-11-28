/// Which actions the programme menu offers for one
/// programme, and in what order (owner request 2026-11-28:
/// the menu behind a guide tile's / a search row's long
/// press or right click takes the official app's shape —
/// 番組情報を見る / 視聴する / 録画 — with 録画解除 added
/// for a programme that already has a reservation).
///
/// The conditions mirror the detail dialog's
/// (showEpgEventDetail in epg_screen.dart), so the menu
/// and the dialog never disagree about an event:
///  * watching is offered only while the programme is on
///    air — before the start and after the end there is
///    nothing of this event to watch;
///  * a programme that has already ended offers no menu
///    at all — the dialog gives it no reservation either,
///    and there is nothing else for the menu to carry;
///  * a reserved programme offers 録画解除 in place of
///    録画: it is un-reserved from here, never reserved
///    twice.
library;

/// One action in the programme menu. The declaration
/// order is the menu's display order.
enum EpgMenuAction {
  /// Opens the programme's detail dialog — the same
  /// dialog a plain tap opens.
  detail,

  /// Opens the channel's live viewing; offered only
  /// while the programme is on air.
  watch,

  /// Reserves the programme; offered when it has no
  /// reservation yet.
  record,

  /// Deletes the programme's existing reservation;
  /// offered in place of [record] when one exists.
  unrecord,
}

/// The menu's actions for a programme running
/// [start]–[end] at instant [now]; [reserved] says the
/// programme already has a reservation. Empty when the
/// programme has ended: no menu opens then.
List<EpgMenuAction> epgMenuActions({
  required DateTime start,
  required DateTime end,
  required DateTime now,
  required bool reserved,
}) {
  if (!end.isAfter(now)) return const [];
  return [
    EpgMenuAction.detail,
    // On air now: the detail dialog's watching condition
    // (start <= now < end; the end half is settled above).
    if (!start.isAfter(now)) EpgMenuAction.watch,
    if (reserved) EpgMenuAction.unrecord else EpgMenuAction.record,
  ];
}
