import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/upload_limits.dart';

void main() {
  const caps = PairingUploadCaps();

  group('kindOf', () {
    test('classifies every allowlisted image extension', () {
      for (final ext in uploadImageExtensions) {
        expect(
          caps.kindOf('shot.$ext'),
          UploadMediaKind.image,
          reason: '.$ext should be an image',
        );
      }
    });

    test('classifies every allowlisted video extension', () {
      for (final ext in uploadVideoExtensions) {
        expect(
          caps.kindOf('clip.$ext'),
          UploadMediaKind.video,
          reason: '.$ext should be a video',
        );
      }
    });

    test('is case-insensitive', () {
      expect(caps.kindOf('SHOT.PNG'), UploadMediaKind.image);
      expect(caps.kindOf('Clip.MP4'), UploadMediaKind.video);
      expect(caps.kindOf('Clip.MoV'), UploadMediaKind.video);
    });

    test('only the last dot counts', () {
      expect(caps.kindOf('holiday.mp4.tar'), isNull);
      expect(caps.kindOf('holiday.tar.mp4'), UploadMediaKind.video);
    });

    test('rejects an unknown extension', () {
      for (final name in const [
        'notes.txt',
        'run.sh',
        'archive.zip',
        // A codec, not a container — deliberately absent from the allowlist.
        'stream.hevc',
        'stream.h265',
      ]) {
        expect(caps.kindOf(name), isNull, reason: name);
      }
    });

    test('rejects a name with no extension at all', () {
      expect(caps.kindOf('Makefile'), isNull);
      expect(caps.kindOf('trailing.'), isNull);
      expect(caps.kindOf(''), isNull);
    });

    test('the image and video sets do not overlap', () {
      expect(
        uploadImageExtensions.intersection(uploadVideoExtensions),
        isEmpty,
        reason: 'an extension in both sets would make kindOf order-dependent',
      );
    });
  });

  group('maxBytesFor', () {
    test('images get the image cap and videos the video cap', () {
      expect(caps.maxBytesFor('shot.png'), 25 * 1024 * 1024);
      expect(caps.maxBytesFor('clip.mp4'), 512 * 1024 * 1024);
      expect(
        caps.maxBytesFor('clip.mov'),
        greaterThan(caps.maxBytesFor('shot.jpg')!),
        reason: 'a minute of 4K HEVC dwarfs any photo',
      );
    });

    test('is null for a disallowed extension', () {
      expect(caps.maxBytesFor('notes.txt'), isNull);
      expect(caps.maxBytesFor('Makefile'), isNull);
    });

    test('honours injected caps', () {
      const tight = PairingUploadCaps(imageMaxBytes: 10, videoMaxBytes: 20);
      expect(tight.maxBytesFor('a.png'), 10);
      expect(tight.maxBytesFor('a.mp4'), 20);
    });

    test('maxBytesForKind mirrors maxBytesFor', () {
      expect(caps.maxBytesForKind(UploadMediaKind.image), caps.imageMaxBytes);
      expect(caps.maxBytesForKind(UploadMediaKind.video), caps.videoMaxBytes);
      expect(caps.maxBytesForKind(null), isNull);
    });
  });
}
