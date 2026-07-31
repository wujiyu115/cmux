import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/session_preferences_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../services/app/connection_mode_service.dart';
import '../services/app/platform_utils.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_profile_repository.dart';
import '../services/ssh/ssh_profile_connection_tester.dart';
import '../services/terminal/terminal_transport_factory.dart';
import 'ssh_profile_setup_page.dart';

class StartupGate extends StatelessWidget {
  const StartupGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    context.watch<SessionPreferencesCubit>();
    // Mobile is a pure LAN pairing client — no SSH home target, no gate.
    if (isPairingClient) return child;
    final mode = context.read<ConnectionModeService>();
    // Desktop with a local/wsl home needs no gate; only an explicit ssh home
    // (desktop optional SSH) requires profile setup.
    if (!mode.isSshMode) return child;

    final sshState = context.watch<SshProfileCubit>().state;

    if (sshState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (mode.requiresSshProfileSetup) {
      return SshProfileSetupPage(
        profileRepository: context.read<SshProfileRepository>(),
        credentialStore: context.read<SshCredentialStore>(),
        connectionTester: SshProfileConnectionTester(
          clientFactory: context
              .read<TerminalTransportFactory>()
              .sshClientFactory,
        ),
        onProfileSaved: () async {
          await context.read<SshProfileCubit>().load();
        },
      );
    }

    return child;
  }
}
