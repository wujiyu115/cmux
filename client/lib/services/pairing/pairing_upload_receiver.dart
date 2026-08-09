import 'dart:typed_data';

import '../../utils/logging/logger_utils.dart';

/// Image extensions a paired phone is allowed to upload.
///
/// `heic` is deliberately included: iPhones shoot HEIC by default and
/// image_picker's conversion to JPEG is unreliable across versions, so
/// omitting it fails randomly on iOS.
const uploadImageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic'};

/// Writes the finished bytes somewhere and returns the path they landed at.
///
/// The sink — not the receiver — resolves which machine the mirrored terminal
/// pane lives on and touches the filesystem. Keeping that out of here is the
/// point: the receiver knows the protocol and nothing about storage.
typedef PairingUploadSink =
    Future<String> Function({
      required String workspaceId,
      required String cwd,
      required String filename,
      required List<int> bytes,
    });

/// Result of [PairingUploadReceiver.begin].
class UploadBeginResult {
  const UploadBeginResult.ok(this.transferId, this.chunkSize) : code = null;
  const UploadBeginResult.error(this.code)
    : transferId = 0,
      chunkSize = 0;

  final int transferId;
  final int chunkSize;
  final String? code;

  bool get isOk => code == null;
}

/// Result of [PairingUploadReceiver.chunk].
class UploadChunkResult {
  const UploadChunkResult.ok(this.received) : code = null;
  const UploadChunkResult.error(this.code) : received = 0;

  final int received;
  final String? code;

  bool get isOk => code == null;
}

/// Result of [PairingUploadReceiver.commit].
class UploadCommitResult {
  const UploadCommitResult.ok(this.path) : code = null;
  const UploadCommitResult.error(this.code) : path = null;

  final String? path;
  final String? code;

  bool get isOk => code == null;
}

class _Transfer {
  _Transfer({
    required this.workspaceId,
    required this.cwd,
    required this.filename,
    required this.declaredSize,
  });

  final String workspaceId;
  final String cwd;
  final String filename;
  final int declaredSize;
  final BytesBuilder builder = BytesBuilder(copy: false);
  int nextIndex = 0;
  int received = 0;
}

/// Assembles a chunked image upload from a paired phone and validates it,
/// handing the finished bytes to an injected [PairingUploadSink].
///
/// This class knows the upload protocol and knows nothing about the
/// filesystem — writing the bytes (and resolving the pane's runtime target)
/// is the sink's job, which keeps this layer testable with a fake and keeps
/// storage concerns out of the pairing code.
///
/// [abandonAll] MUST be called when the connection closes: otherwise the
/// bytes of every unfinished transfer stay pinned in memory, and a phone that
/// reconnects repeatedly feeds the desktop's memory.
class PairingUploadReceiver {
  PairingUploadReceiver({
    required this.sink,
    this.maxBytes = 25 * 1024 * 1024,
    this.chunkSize = 64 * 1024,
  });

  final PairingUploadSink sink;
  final int maxBytes;
  final int chunkSize;

  final Map<int, _Transfer> _transfers = {};
  int _nextId = 0;

  UploadBeginResult begin({
    required String workspaceId,
    required String cwd,
    required String filename,
    required int size,
  }) {
    // Validate before allocating a transfer id: allocating and then rejecting
    // would leave gaps in the id sequence that look like lost frames when
    // debugging. Order is filename → extension → size.
    if (_isBadFilename(filename)) {
      return const UploadBeginResult.error('bad_filename');
    }
    if (!_hasAllowedExtension(filename)) {
      return const UploadBeginResult.error('unsupported_type');
    }
    // One code covers the whole "declared size out of the acceptable range"
    // case — including a malformed negative size, not just a too-big one.
    if (size < 0 || size > maxBytes) {
      return const UploadBeginResult.error('too_large');
    }

    final id = ++_nextId;
    _transfers[id] = _Transfer(
      workspaceId: workspaceId,
      cwd: cwd,
      filename: filename,
      declaredSize: size,
    );
    return UploadBeginResult.ok(id, chunkSize);
  }

  UploadChunkResult chunk(int transferId, int chunkIndex, List<int> bytes) {
    final transfer = _transfers[transferId];
    if (transfer == null) {
      return const UploadChunkResult.error('unknown_transfer');
    }
    if (chunkIndex != transfer.nextIndex) {
      // WebSocket preserves order, so a gap means something is wrong; writing
      // a file with a hole in it would be worse than failing.
      abandon(transferId);
      return const UploadChunkResult.error('write_failed');
    }
    if (transfer.received + bytes.length > transfer.declaredSize) {
      abandon(transferId);
      return const UploadChunkResult.error('too_large');
    }
    transfer.builder.add(bytes);
    transfer.received += bytes.length;
    transfer.nextIndex++;
    return UploadChunkResult.ok(transfer.received);
  }

  Future<UploadCommitResult> commit(int transferId) async {
    final transfer = _transfers[transferId];
    if (transfer == null) {
      return const UploadCommitResult.error('unknown_transfer');
    }
    if (transfer.received != transfer.declaredSize) {
      // Truncation is what this check exists to catch; half a file on disk is
      // worse than no file.
      abandon(transferId);
      return const UploadCommitResult.error('write_failed');
    }
    // Drop it before touching the sink: whether the write succeeds or throws,
    // the transfer must not linger in the table.
    _transfers.remove(transferId);
    try {
      final path = await sink(
        workspaceId: transfer.workspaceId,
        cwd: transfer.cwd,
        filename: transfer.filename,
        bytes: transfer.builder.takeBytes(),
      );
      return UploadCommitResult.ok(path);
    } on Object catch (e, st) {
      AppLogger.instance.w(
        'Pairing upload sink failed ($e)',
        error: e,
        stackTrace: st,
      );
      return const UploadCommitResult.error('write_failed');
    }
  }

  void abandon(int id) {
    _transfers.remove(id);
  }

  void abandonAll() {
    _transfers.clear();
  }

  bool _isBadFilename(String name) {
    return name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.contains('\x00');
  }

  bool _hasAllowedExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return false;
    final ext = name.substring(dot + 1).toLowerCase();
    return uploadImageExtensions.contains(ext);
  }
}
