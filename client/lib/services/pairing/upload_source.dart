import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// A byte source the upload sender pulls from sequentially.
///
/// Sequential-only on purpose: with no seeking a [FileUploadSource] never pays a
/// `setPosition`, and peak memory on the phone is one chunk rather than the whole
/// file. That is the difference between uploading a 512 MiB video and running out
/// of memory trying.
abstract interface class UploadSource {
  /// Total bytes, known before the first [read] — `upload.begin` has to declare
  /// the size up front so the host can range-check it.
  int get length;

  /// Up to [maxBytes] from the current position. Empty at EOF.
  Future<Uint8List> read(int maxBytes);

  Future<void> close();
}

/// In-memory source.
///
/// Production uses it for nothing; it exists so tests can hand over a literal
/// payload without touching a filesystem.
class MemoryUploadSource implements UploadSource {
  MemoryUploadSource(this.bytes);

  final Uint8List bytes;
  int _offset = 0;

  @override
  int get length => bytes.length;

  @override
  Future<Uint8List> read(int maxBytes) async {
    final end = min(_offset + maxBytes, bytes.length);
    // A view, not a copy: the sender only hands it to the frame encoder.
    final out = Uint8List.sublistView(bytes, _offset, end);
    _offset = end;
    return out;
  }

  @override
  Future<void> close() async {}
}

/// Reads a file off disk one chunk at a time.
///
/// `XFile.path` from image_picker is a real filesystem path on both mobile
/// platforms — the plugin copies the picked asset into the app cache before
/// returning — so this is what the phone uses for a gallery pick.
class FileUploadSource implements UploadSource {
  FileUploadSource._(this._file, this.length);

  /// Stats the file so `upload.begin` can declare a size; the handle opens lazily
  /// on the first [read], so a source that is rejected by the local size check
  /// never opens one at all.
  static Future<FileUploadSource> open(String path) async {
    final file = File(path);
    return FileUploadSource._(file, await file.length());
  }

  final File _file;
  RandomAccessFile? _handle;

  @override
  final int length;

  @override
  Future<Uint8List> read(int maxBytes) async {
    final handle = _handle ??= await _file.open();
    return handle.read(maxBytes);
  }

  @override
  Future<void> close() async {
    final handle = _handle;
    _handle = null;
    await handle?.close();
  }
}
