/// Recording switch policy (user-fork addition, 2026-11-26):
/// moving between recordings without leaving the player.
///
/// The channel panel gave live viewing a list kept at hand
/// while zapping (see player_zap_policy); the viewer asked
/// for the same at recordings: the recorded list stays on
/// screen while a title plays, and picking another title
/// switches playback to it in place — stop the old session,
/// start the picked title's session, open it on the same
/// player (see PlayerScreen.recordTargets).
///
/// Movement is recordings only, and only with at least two
/// playable titles: live viewing moves by channel instead,
/// and a single playable title has nowhere to move to.
library;

/// Whether the player offers movement between recordings
/// at all: a recording (not live) with at least two switch
/// targets.
bool canSwitchRecords({required bool live, required int targetCount}) =>
    !live && targetCount > 1;
