/// The viewer's video decode mode (plan 139): how much of the
/// video decoding mpv may hand to the device's hardware
/// decoder.
///
/// The escape hatch exists for one measured failure shape: on
/// the Fire TV 4K Max (first generation, MT8696 / Fire OS 7)
/// the stream arrived and decrypted in full, but the picture
/// never appeared — playback sat at position zero on a black
/// frame while the hardware path was in charge of MPEG-2
/// 1080i. Switching MPEG-2 alone to software decoding brought
/// the picture up on that device (the nullpon19 fork's
/// v1.5.0-firetv.3, confirmed by the reporting viewer). Which
/// layer inside the hardware path stalls was not isolated,
/// and this setting does not claim it — it offers the way
/// around.
///
/// The modes:
///
///  * [VideoHwdecMode.auto]: nothing is set. mpv and
///    media_kit_video run with their own defaults
///    (hwdec=auto-safe) — the behaviour from before this
///    setting existed, unchanged.
///  * [VideoHwdecMode.mpeg2Software]: only mpv's
///    `hwdec-codecs` is set, to a list without mpeg2video.
///    Codecs on the list keep hardware decoding (H.264, HEVC
///    and the other broadcast-relevant ones); MPEG-2 — the
///    terrestrial / BS original-quality codec — alone falls
///    back to software decoding.
///  * [VideoHwdecMode.software]: no hardware decoding at
///    all: the video controller is created without hardware
///    acceleration, and mpv's `hwdec` is pinned to 'no'
///    before open.
///
/// The setting is offered on Android only (mobile and TV):
/// the failure it answers is Android hardware's, and the
/// desktop builds are out of this round's scope.
///
/// What an unset value means depends on the variant
/// ([defaultVideoHwdecMode]): the standard variant reads it
/// as auto, exactly as before this default existed. The TV
/// variant reads it as [VideoHwdecMode.software] — full
/// software decoding. Two measurements sit behind that
/// choice, and they differ by unit: on plan 139's Fire TV
/// 4K Max (first generation), switching MPEG-2 alone to
/// software brought the picture up, so mpeg2Software was
/// the TV default at first; but on the fork owner's own
/// Fire OS 7 unit (measured on the real device,
/// 2026-11-28) MPEG-2-only software stayed black — that
/// unit's hardware path produces no picture for H.264
/// either, which is what BS / CS broadcasts and the mobile
/// transcode streams are, and only full software decoding
/// brought the picture up. The TV edition exists for that
/// hardware class, and a first-run viewer there should get
/// a picture without having to find this setting first. A
/// mode the viewer stored explicitly always wins over the
/// default, on either variant.
library;

/// How the video decoding for a playback is split between
/// the device's hardware decoder and software (see the
/// library comment). The stored form is the value's [name].
enum VideoHwdecMode {
  auto,
  mpeg2Software,
  software;

  /// The short label the settings screen shows for this mode.
  String get shortLabel => switch (this) {
    VideoHwdecMode.auto => '自動',
    VideoHwdecMode.mpeg2Software => 'MPEG-2 のみソフトウェア',
    VideoHwdecMode.software => 'すべてソフトウェア',
  };

  /// What choosing this mode does, in viewer terms: the
  /// settings screen's explanation and the picker dialog's
  /// per-mode subtitle.
  String get description => switch (this) {
    VideoHwdecMode.auto => '端末の標準の方式でデコードします。',
    VideoHwdecMode.mpeg2Software =>
      'MPEG-2 (地デジ / BS の元画質) だけをソフトウェアでデコードします。'
          '元画質で映像が出ない端末向けです。',
    VideoHwdecMode.software =>
      'すべての映像をソフトウェアでデコードします。'
          '端末によっては動作が重くなります。',
  };
}

/// mpv's `hwdec-codecs` value for the MPEG-2-only software
/// mode: the broadcast-relevant codecs except mpeg2video, so
/// MPEG-2 alone misses the hardware list and falls back to
/// software decoding while the rest keep the hardware path.
/// (mpv consults hwdec-codecs only when a hardware decoder
/// is in play; a codec absent from the list is not
/// hardware-decoded.)
const String mpeg2SoftwareHwdecCodecs = 'h264,hevc,mpeg4,vp8,vp9,av1';

/// The mode in force when the viewer has stored nothing:
/// [VideoHwdecMode.auto] on the standard variant,
/// [VideoHwdecMode.software] on the TV variant (see the
/// library comment for the two measurements behind the TV
/// default — plan 139's unit needed only MPEG-2 in
/// software, the fork owner's Fire OS 7 unit needs every
/// codec there).
VideoHwdecMode defaultVideoHwdecMode({required bool isTv}) =>
    isTv ? VideoHwdecMode.software : VideoHwdecMode.auto;

/// Parses the stored form of the setting (the mode's name,
/// as written by the settings notifier). Null, and any name
/// this build does not know — a newer build's mode, or
/// corruption — read as [fallback] (auto unless the caller
/// passes the variant's default), never as an unreviewed
/// decode path.
VideoHwdecMode parseVideoHwdecMode(
  String? raw, {
  VideoHwdecMode fallback = VideoHwdecMode.auto,
}) {
  for (final mode in VideoHwdecMode.values) {
    if (mode.name == raw) return mode;
  }
  return fallback;
}

/// The `hwdec-codecs` value to set for [mode] before open,
/// or null to set nothing: only the MPEG-2-only mode narrows
/// the list (see [mpeg2SoftwareHwdecCodecs]).
String? hwdecCodecsPropertyFor(VideoHwdecMode mode) =>
    mode == VideoHwdecMode.mpeg2Software ? mpeg2SoftwareHwdecCodecs : null;

/// The `hwdec` value to set for [mode] before open, or null
/// to set nothing: only the full software mode pins decoding
/// off the hardware entirely.
String? hwdecPropertyFor(VideoHwdecMode mode) =>
    mode == VideoHwdecMode.software ? 'no' : null;

/// Whether the video controller for [mode] is created with
/// hardware acceleration: every mode but the full software
/// one keeps media_kit_video's default controller exactly as
/// it was.
bool videoControllerHardwareAcceleration(VideoHwdecMode mode) =>
    mode != VideoHwdecMode.software;
