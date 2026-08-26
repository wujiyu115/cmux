/// What a paired phone may upload, and how big it may be.
///
/// This table lives in its own file rather than beside the receiver because
/// *both* sides need it: the host enforces it in
/// `PairingUploadReceiver.begin`, and the phone applies the same caps locally
/// so an oversized pick is rejected without a round trip. A mobile cubit
/// importing `pairing_upload_receiver.dart` would be a layering smell, and two
/// copies of the numbers would drift apart in the "too large" copy.
library;

/// Image extensions a paired phone is allowed to upload.
///
/// `heic` is deliberately included: iPhones shoot HEIC by default and
/// image_picker's conversion to JPEG is unreliable across versions, so
/// omitting it fails randomly on iOS.
const uploadImageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic'};

/// Video *containers* a paired phone is allowed to upload.
///
/// Containers, not codecs: HEVC / H.265 is a codec that lives inside `mp4`,
/// `mov` or `mkv`, so there is nothing to allowlist for it beyond the
/// container — an iPhone's HEVC clip arrives as `.mov`. Raw elementary streams
/// (`.hevc`, `.h265`, `.h264`) are deliberately absent: no phone gallery
/// produces them, nothing plays them without remuxing, and every extension
/// here is one more thing an agent's toolchain may be pointed at.
///
/// - `mp4` — Android's default recording container and iOS's export target.
/// - `mov` — what iOS records natively (QuickTime, HEVC inside).
/// - `m4v` — Apple's MPEG-4 variant; some iOS share paths emit it.
/// - `3gp` — still produced by low-end Android camera apps and MMS.
/// - `webm` — screen recorders and Chrome capture.
/// - `mkv` — some Android OEM recorders, and anything transcoded.
/// - `avi` — the weakest of the seven, kept only because "an old clip already
///   in the gallery" is a real case and it costs nothing under extension-only
///   allow-listing.
const uploadVideoExtensions = {
  'mp4',
  'mov',
  'm4v',
  '3gp',
  'webm',
  'mkv',
  'avi',
};

/// Which family an allowed upload belongs to. Drives the cap and the wording of
/// the "too large" message, which differs between an image and a video.
enum UploadMediaKind { image, video }

/// Per-kind size caps.
///
/// Videos get a far larger budget than images because a phone-shot minute of
/// 4K HEVC is around 170 MiB — an image-sized cap would make video upload
/// useless. The host streams chunks straight to disk, so the cap bounds the
/// transfer, not host memory.
class PairingUploadCaps {
  const PairingUploadCaps({
    this.imageMaxBytes = 25 * 1024 * 1024,
    this.videoMaxBytes = 512 * 1024 * 1024,
  });

  final int imageMaxBytes;
  final int videoMaxBytes;

  /// The kind [filename]'s extension names, or null when it is not allowed.
  ///
  /// Extension-only, deliberately: no MIME sniffing, no magic bytes. That has
  /// been the design since this pipeline shipped and it is not an oversight —
  /// a phone that lies about the extension gets that extension's cap, and the
  /// worst outcome is a mislabeled file in the pane's cwd, which
  /// `resolveUploadDestination`'s never-overwrite rule already contains.
  UploadMediaKind? kindOf(String filename) {
    final ext = _extensionOf(filename);
    if (ext == null) return null;
    if (uploadImageExtensions.contains(ext)) return UploadMediaKind.image;
    if (uploadVideoExtensions.contains(ext)) return UploadMediaKind.video;
    return null;
  }

  /// Cap for [filename], or null when its extension is not allowed at all.
  int? maxBytesFor(String filename) => maxBytesForKind(kindOf(filename));

  /// Cap for an already-resolved [kind], or null for null.
  int? maxBytesForKind(UploadMediaKind? kind) => switch (kind) {
    UploadMediaKind.image => imageMaxBytes,
    UploadMediaKind.video => videoMaxBytes,
    null => null,
  };

  static String? _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1).toLowerCase();
  }
}
