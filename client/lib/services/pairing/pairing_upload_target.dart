/// One in-progress upload's destination.
///
/// Opened at `upload.begin`, fed incrementally as chunks arrive, then either
/// committed (moved into place) or aborted (partial data discarded). Exactly one
/// of [commit] / [abort] runs, once.
///
/// This replaced a "hand me the finished bytes" sink: a 512 MiB video cannot be
/// assembled in memory on either end, so the receiver pumps bytes through here
/// instead of accumulating them.
abstract interface class PairingUploadTarget {
  /// Bytes the target must not buffer further — the receiver has already batched
  /// them up to [preferredFlushBytes].
  Future<void> append(List<int> bytes);

  /// Moves the accumulated data into place and returns the absolute path it
  /// landed at. The path is the host's decision; the phone never guesses it.
  Future<String> commit();

  /// Discards the partial data. Must not throw — abort runs on paths that are
  /// already failing, and a throw there would mask the original error.
  Future<void> abort();

  /// How big a bite this target wants before it is worth calling [append].
  ///
  /// Not a single constant, because the cost of one append differs by two orders
  /// of magnitude between backends: a local file is an open/write/close, a WSL
  /// path spawns a `wsl.exe` subprocess, and an SFTP path opens and closes a
  /// remote handle.
  int get preferredFlushBytes;
}

/// Opens a target for the mirrored pane behind a transfer.
///
/// Throwing means "no writable landing spot" and surfaces to the phone as
/// `no_target` — before any bytes cross the network, which is the point of
/// resolving at `upload.begin` rather than at commit.
///
/// The opener — not the receiver — resolves which machine the mirrored terminal
/// pane lives on and touches the filesystem. Keeping that out of the receiver is
/// deliberate: the receiver knows the protocol and nothing about storage.
typedef PairingUploadOpener =
    Future<PairingUploadTarget> Function({
      required String workspaceId,
      required String cwd,
      required String filename,
    });
