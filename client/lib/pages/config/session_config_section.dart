import 'dart:async';
import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/pane_mode.dart';
import '../../models/session_preferences.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/app/connection_mode_service.dart';
import '../../utils/ui/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import 'push_channel_section.dart';
import 'runtime_target_picker.dart';
import 'session_config_constants.dart';

class SessionConfigWorkspace extends StatelessWidget {
  const SessionConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          _SessionHeading(
            title: l10n.session,
            subtitle: l10n.sessionPageSubtitle,
          ),
          const SizedBox(height: 16),
        ],
        const Expanded(child: _SessionControls()),
      ],
    );
  }
}

class _SessionHeading extends StatelessWidget {
  const _SessionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: styles.lgSemiboldSnug),
        const SizedBox(height: 6),
        Text(subtitle, style: styles.mutedMd),
      ],
    );
  }
}

class _SessionControls extends StatefulWidget {
  const _SessionControls();

  @override
  State<_SessionControls> createState() => _SessionControlsState();
}

class _SessionControlsState extends State<_SessionControls> {
  SessionPreferencesCubit? _cubit;
  var _controllersReady = false;
  late final TextEditingController _sshCwdController;
  late final FocusNode _sshCwdFocus;
  late final Debouncer _sshCwdPersistDebouncer;
  String _lastSyncedSshCwd = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubit ??= context.read<SessionPreferencesCubit>();
    if (_controllersReady) return;
    _controllersReady = true;
    _sshCwdPersistDebouncer = Debouncer(
      tag: 'session_ssh_default_working_directory',
      duration: kSessionPathPersistDebounce,
    );
    _sshCwdFocus = FocusNode()..addListener(_onSshCwdFocusChanged);
    final sshCwd = _cubit!.state.preferences.defaultSshWorkingDirectory;
    _sshCwdController = TextEditingController(text: sshCwd);
    _lastSyncedSshCwd = sshCwd;
  }

  @override
  void dispose() {
    _sshCwdPersistDebouncer.dispose();
    _sshCwdFocus.removeListener(_onSshCwdFocusChanged);
    _sshCwdFocus.dispose();
    _sshCwdController.dispose();
    super.dispose();
  }

  void _syncFromState(String sshCwd) {
    if (sshCwd != _lastSyncedSshCwd) {
      _sshCwdPersistDebouncer.cancel();
      _lastSyncedSshCwd = sshCwd;
      _sshCwdController.value = TextEditingValue(
        text: sshCwd,
        selection: TextSelection.collapsed(offset: sshCwd.length),
      );
    }
  }

  Future<void> _persistSshCwdFromField() async {
    if (!mounted) return;
    final cubit = _cubit!;
    final trimmed = _sshCwdController.text.trim();
    final stored = cubit.state.preferences.defaultSshWorkingDirectory.trim();
    if (trimmed == stored) return;
    await cubit.setDefaultSshWorkingDirectory(_sshCwdController.text);
  }

  void _onSshCwdFocusChanged() {
    if (!mounted) return;
    if (!_sshCwdFocus.hasFocus) {
      _flushSshCwdPersist();
    }
  }

  void _scheduleDebouncedSshCwdPersist() {
    _sshCwdPersistDebouncer(() {
      if (mounted) {
        _persistSshCwdFromField();
      }
    });
  }

  void _flushSshCwdPersist() {
    if (!mounted) return;
    _sshCwdPersistDebouncer.cancel();
    _persistSshCwdFromField();
  }

  Future<void> _resetSshCwd() async {
    _sshCwdPersistDebouncer.cancel();
    _sshCwdController.clear();
    await _cubit!.setDefaultSshWorkingDirectory('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = _cubit!;
    final isSshMode = context.select<ConnectionModeService, bool>(
      (service) => service.isSshMode,
    );

    return BlocSelector<
      SessionPreferencesCubit,
      SessionPreferencesState,
      _SessionControlsSnapshot
    >(
      selector: (state) => _SessionControlsSnapshot.from(state.preferences),
      builder: (context, snapshot) {
        _syncFromState(snapshot.defaultSshWorkingDirectory);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpCard.outlined(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const RuntimeTargetPicker(),
                    if (isSshMode) ...[
                      TpPreferenceStack(
                        title: l10n.sshDefaultWorkingDirectoryTitle,
                        subtitle: l10n.sshDefaultWorkingDirectorySubtitle,
                        body: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _sshCwdController,
                                focusNode: _sshCwdFocus,
                                decoration: const InputDecoration(
                                  hintText: '~/work/workspace',
                                  hintMaxLines: 1,
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.never,
                                ),
                                onChanged: (_) =>
                                    _scheduleDebouncedSshCwdPersist(),
                                onSubmitted: (_) => _flushSshCwdPersist(),
                              ),
                            ),
                            const SizedBox(width: 6),
                            TextButton(
                              onPressed:
                                  snapshot.defaultSshWorkingDirectory.isEmpty
                                  ? null
                                  : _resetSshCwd,
                              child: Text(l10n.cliExecutablePathReset),
                            ),
                          ],
                        ),
                        showDividerBelow: true,
                      ),
                      TpPreferenceRow(
                        title: 'SSH 使用 bash 登录环境',
                        subtitle:
                            '通过 bash -lc 启动远端 flashskyai，以便读取远端 shell 配置中的 PATH。',
                        trailing: Switch(
                          value: snapshot.sshUseLoginShell,
                          onChanged: (value) =>
                              cubit.setSshUseLoginShell(value),
                        ),
                        showDividerBelow: true,
                      ),
                    ],
                    TpPreferenceRow(
                      key: AppKeys.newPaneModeRow,
                      title: l10n.newPaneModeTitle,
                      subtitle: l10n.newPaneModeDescription,
                      trailing: TpSegmentedControl(
                        // ToggleSwitch latches its initial index, and the
                        // stored value arrives after the first build.
                        key: ValueKey(snapshot.newPaneMode),
                        totalSwitches: 2,
                        initialLabelIndex: snapshot.newPaneMode == PaneMode.chat
                            ? 1
                            : 0,
                        labels: [
                          l10n.newPaneModeTerminal,
                          l10n.newPaneModeChat,
                        ],
                        onToggle: (index) => unawaited(
                          cubit.setNewPaneMode(
                            index == 1 ? PaneMode.chat : PaneMode.terminal,
                          ),
                        ),
                      ),
                      showDividerBelow: true,
                    ),
                    TpPreferenceRow(
                      key: AppKeys.chatAgentCommandRow,
                      title: l10n.chatAgentCommandTitle,
                      subtitle: l10n.chatAgentCommandDescription,
                      trailing: _ChatAgentCommandField(
                        value: snapshot.chatAgentCommand,
                        onCommit: cubit.setChatAgentCommand,
                      ),
                      showDividerBelow: snapshot.newPaneMode == PaneMode.chat,
                    ),
                    TpPreferenceRow(
                      title: l10n.terminalScrollbackLinesTitle,
                      subtitle: l10n.terminalScrollbackLinesDescription,
                      trailing: SizedBox(
                        width: 120,
                        child: TextFormField(
                          initialValue: '${snapshot.terminalScrollbackLines}',
                          keyboardType: TextInputType.number,
                          onFieldSubmitted: (value) {
                            final parsed = int.tryParse(value.trim());
                            if (parsed != null) {
                              unawaited(
                                cubit.setTerminalScrollbackLines(parsed),
                              );
                            }
                          },
                        ),
                      ),
                      showDividerBelow: true,
                    ),
                    TpPreferenceRow(
                      title: l10n.terminalLinkClickOpensInAppTitle,
                      subtitle: l10n.terminalLinkClickOpensInAppDescription,
                      trailing: Switch(
                        key: AppKeys.terminalLinkClickOpensInAppSwitch,
                        value: snapshot.terminalLinkClickOpensInApp,
                        onChanged: (value) =>
                            cubit.setTerminalLinkClickOpensInApp(value),
                      ),
                      showDividerBelow: true,
                    ),
                    TpPreferenceRow(
                      title: l10n.openExistingSessionStartsTerminalTitle,
                      subtitle:
                          l10n.openExistingSessionStartsTerminalDescription,
                      trailing: Switch(
                        key: AppKeys.openExistingSessionStartsTerminalSwitch,
                        value: snapshot.openExistingSessionStartsTerminal,
                        onChanged: (value) =>
                            cubit.setOpenExistingSessionStartsTerminal(value),
                      ),
                      showDividerBelow: true,
                    ),
                    TpPreferenceRow(
                      title: l10n.simpleModeDefaultFullAccessTitle,
                      subtitle: l10n.simpleModeDefaultFullAccessDescription,
                      trailing: Switch(
                        key: AppKeys.simpleModeDefaultFullAccessSwitch,
                        value: snapshot.simpleModeDefaultFullAccess,
                        onChanged: (value) =>
                            cubit.setSimpleModeDefaultFullAccess(value),
                      ),
                      showDividerBelow: true,
                    ),
                    TpPreferenceRow(
                      title: l10n.notifyOnSessionIdleTitle,
                      subtitle: l10n.notifyOnSessionIdleDescription,
                      trailing: Switch(
                        value: snapshot.notifyOnSessionIdle,
                        onChanged: (value) =>
                            cubit.setNotifyOnSessionIdle(value),
                      ),
                      showDividerBelow: true,
                    ),
                    TpPreferenceRow(
                      title: l10n.notifyOnPtyIdleTitle,
                      subtitle: l10n.notifyOnPtyIdleDescription,
                      trailing: Switch(
                        key: AppKeys.notifyOnPtyIdleSwitch,
                        value: snapshot.notifyOnPtyIdle,
                        // Only meaningful while the master switch is on.
                        onChanged: snapshot.notifyOnSessionIdle
                            ? (value) => cubit.setNotifyOnPtyIdle(value)
                            : null,
                      ),
                      showDividerBelow: true,
                    ),
                    TpPreferenceRow(
                      title: l10n.notifyWhileWatchingTitle,
                      subtitle: l10n.notifyWhileWatchingDescription,
                      trailing: Switch(
                        key: AppKeys.notifyWhileWatchingSwitch,
                        value: snapshot.notifyWhileWatching,
                        onChanged: (value) =>
                            cubit.setNotifyWhileWatching(value),
                      ),
                      showDividerBelow: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SessionHeading(
                title: l10n.barkPushSectionTitle,
                subtitle: l10n.barkPushSectionSubtitle,
              ),
              const SizedBox(height: 12),
              const TpCard.outlined(child: PushChannelSection()),
            ],
          ),
        );
      },
    );
  }
}

/// Saves on submit and on losing focus, so a typed command is never lost by
/// clicking somewhere else.
class _ChatAgentCommandField extends StatefulWidget {
  const _ChatAgentCommandField({required this.value, required this.onCommit});

  final String value;
  final Future<void> Function(String) onCommit;

  @override
  State<_ChatAgentCommandField> createState() => _ChatAgentCommandFieldState();
}

class _ChatAgentCommandFieldState extends State<_ChatAgentCommandField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_ChatAgentCommandField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the stored value only when the user is not editing it.
    if (!_focus.hasFocus &&
        widget.value != oldWidget.value &&
        widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (_controller.text == widget.value) return;
    unawaited(widget.onCommit(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: TextField(
        key: AppKeys.chatAgentCommandField,
        controller: _controller,
        focusNode: _focus,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _commit(),
        decoration: const InputDecoration(
          hintText: 'claude',
          hintMaxLines: 1,
          floatingLabelBehavior: FloatingLabelBehavior.never,
        ),
      ),
    );
  }
}

class _SessionControlsSnapshot {
  const _SessionControlsSnapshot({
    required this.defaultSshWorkingDirectory,
    required this.sshUseLoginShell,
    required this.terminalScrollbackLines,
    required this.terminalLinkClickOpensInApp,
    required this.openExistingSessionStartsTerminal,
    required this.simpleModeDefaultFullAccess,
    required this.notifyOnSessionIdle,
    required this.notifyOnPtyIdle,
    required this.notifyWhileWatching,
    required this.newPaneMode,
    required this.chatAgentCommand,
  });

  final String defaultSshWorkingDirectory;
  final bool sshUseLoginShell;
  final int terminalScrollbackLines;
  final bool terminalLinkClickOpensInApp;
  final bool openExistingSessionStartsTerminal;
  final bool simpleModeDefaultFullAccess;
  final bool notifyOnSessionIdle;
  final bool notifyOnPtyIdle;
  final bool notifyWhileWatching;
  final PaneMode newPaneMode;
  final String chatAgentCommand;

  static _SessionControlsSnapshot from(SessionPreferences preferences) {
    return _SessionControlsSnapshot(
      defaultSshWorkingDirectory: preferences.defaultSshWorkingDirectory,
      sshUseLoginShell: preferences.sshUseLoginShell,
      terminalScrollbackLines: preferences.terminalScrollbackLines,
      terminalLinkClickOpensInApp: preferences.terminalLinkClickOpensInApp,
      openExistingSessionStartsTerminal:
          preferences.openExistingSessionStartsTerminal,
      simpleModeDefaultFullAccess: preferences.simpleModeDefaultFullAccess,
      notifyOnSessionIdle: preferences.notifyOnSessionIdle,
      notifyOnPtyIdle: preferences.notifyOnPtyIdle,
      notifyWhileWatching: preferences.notifyWhileWatching,
      newPaneMode: preferences.newPaneMode,
      chatAgentCommand: preferences.chatAgentCommand,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _SessionControlsSnapshot &&
        other.defaultSshWorkingDirectory == defaultSshWorkingDirectory &&
        other.sshUseLoginShell == sshUseLoginShell &&
        other.terminalScrollbackLines == terminalScrollbackLines &&
        other.terminalLinkClickOpensInApp == terminalLinkClickOpensInApp &&
        other.openExistingSessionStartsTerminal ==
            openExistingSessionStartsTerminal &&
        other.simpleModeDefaultFullAccess == simpleModeDefaultFullAccess &&
        other.notifyOnSessionIdle == notifyOnSessionIdle &&
        other.notifyOnPtyIdle == notifyOnPtyIdle &&
        other.notifyWhileWatching == notifyWhileWatching &&
        other.newPaneMode == newPaneMode &&
        other.chatAgentCommand == chatAgentCommand;
  }

  @override
  int get hashCode => Object.hash(
    defaultSshWorkingDirectory,
    sshUseLoginShell,
    terminalScrollbackLines,
    terminalLinkClickOpensInApp,
    openExistingSessionStartsTerminal,
    simpleModeDefaultFullAccess,
    notifyOnSessionIdle,
    notifyOnPtyIdle,
    notifyWhileWatching,
    newPaneMode,
    chatAgentCommand,
  );
}
