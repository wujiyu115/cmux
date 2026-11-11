import 'package:meta/meta.dart';

import '../../models/pane_mode.dart';
import '../../repositories/pairing_settings_repository.dart';
import 'pairing_client.dart';

/// Reads and writes a paired desktop's *own* settings over a short-lived
/// connection.
///
/// The mobile settings screen has no mirror open, so it cannot borrow the
/// mirror page's client: opening and closing one connection per action keeps
/// settings out of the live-mirror lifecycle (and out of its reconnect logic)
/// without keeping a socket alive for a screen that changes a value once.
class HostSettingsClient {
  const HostSettingsClient({
    this.connectTimeout = const Duration(seconds: 12),
    this.newClient,
  });

  final Duration connectTimeout;

  /// Injection point for tests; production dials a real [PairingClient].
  final PairingClient Function()? newClient;

  /// Reads the pane defaults [desktop] will use for the windows it creates next.
  Future<PairingPaneDefaults> readPaneDefaults(PairedDesktop desktop) =>
      withClient(desktop, (client) => client.paneDefaults());

  /// Writes them. Returns what the host kept, not what was sent: the desktop
  /// normalises an empty command to its own default.
  Future<PairingPaneDefaults> writePaneDefaults(
    PairedDesktop desktop, {
    required PaneMode mode,
    required String chatAgentCommand,
  }) => withClient(
    desktop,
    (client) => client.setPaneDefaults(
      mode: mode.wire,
      chatAgentCommand: chatAgentCommand,
    ),
  );

  /// One connect → run → close. The client is always closed, including when
  /// `body` throws, so a failed edit cannot leave a socket pinned to a desktop
  /// the user is no longer looking at.
  @visibleForTesting
  Future<T> withClient<T>(
    PairedDesktop desktop,
    Future<T> Function(PairingClient client) body,
  ) async {
    final client = newClient?.call() ?? PairingClient();
    try {
      await client
          .connect(
            wsUrls: desktop.connectCandidates,
            token: desktop.deviceToken,
            hostPublicKeyB64: desktop.hostPublicKeyB64,
            deviceId: desktop.id,
          )
          .timeout(connectTimeout);
      return await body(client);
    } finally {
      await client.close();
    }
  }
}
