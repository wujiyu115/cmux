import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/plugin_cubit.dart';
import '../../../cubits/session_preferences_cubit.dart';
import '../../../cubits/skill_cubit.dart';
import '../../../cubits/workbench/workbench_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../utils/ui/app_keys.dart';
import '../../../models/config_bundle.dart';
import '../../../models/landing_launch_context.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../models/runtime_target.dart';
import '../../../services/compose/compose_file_attach.dart';
import '../../../services/compose/compose_landing_drop_ingestor.dart';
import '../../../services/storage/app_storage.dart';
import '../../../services/compose/compose_landing_bundle.dart';
import '../../../services/compose/compose_text_edit.dart';
import '../../../services/compose/compose_voice_input.dart';
import '../../../utils/workspace/landing_draft_resolver.dart';
import '../../../utils/workspace/workspace_path_utils.dart';
import '../../../services/storage/home_target_controller.dart';
import '../../../repositories/workspace_project_config_repository.dart';
import 'workspace_chat_landing_compose_card.dart';
import 'workspace_landing_selectors.dart';

typedef LandingComposeSubmit =
    void Function(String message, LandingLaunchContext draft);

class WorkspaceChatLanding extends StatefulWidget {
  const WorkspaceChatLanding({
    required this.workspace,
    required this.onSubmit,
    this.isSubmitting = false,
    this.disabled = false,
    this.initialText,
    this.showLandingChrome = true,
    super.key,
  });

  final Workspace workspace;
  final LandingComposeSubmit onSubmit;
  final bool isSubmitting;
  final bool disabled;
  final String? initialText;

  /// When false, renders only the compose card (Ask AI embed) — no back
  /// button, project/worktree header, or full-bleed landing shell.
  final bool showLandingChrome;

  @override
  State<WorkspaceChatLanding> createState() => _WorkspaceChatLandingState();
}

class _WorkspaceChatLandingState extends State<WorkspaceChatLanding> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  late final ComposeVoiceInput _voiceInput;

  var _dangerouslySkipPermissions = true;
  String? _selectedPresetId;
  var _voiceListening = false;
  var _voiceSoundLevel = 0.0;
  var _discardVoiceTranscript = false;
  TextEditingValue? _voiceInsertBaseline;
  Stopwatch? _voiceStopwatch;
  Timer? _voiceTimer;
  String? _selectedProjectPath;
  String? _selectedWorktreePath;
  List<RuntimeTarget> _runtimeTargets = const [];
  Future<void>? _runtimeTargetsLoad;
  ConfigBundle _workspaceProjectBundle = const ConfigBundle();
  int _workspaceBundleGeneration = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _voiceInput = ComposeVoiceInput(
      onFinalTranscript: (text) {
        if (!mounted || _discardVoiceTranscript) return;
        if (_voiceInsertBaseline != null) {
          _controller.value = _voiceInsertBaseline!;
        }
        _controller.value = insertTextAtSelection(
          _controller,
          text,
          separatorBefore: ' ',
          separatorAfter: ' ',
        );
        _voiceInsertBaseline = null;
        setState(() {});
      },
      onListeningChanged: (listening) {
        if (!mounted) return;
        _applyVoiceListening(listening);
      },
      onSoundLevel: (level) {
        if (!mounted) return;
        setState(() => _voiceSoundLevel = level);
      },
      onError: (error) {
        if (!mounted) return;
        final l10n = context.l10n;
        final message = speechRecognitionErrorIsPermissionDenied(error)
            ? l10n.workspaceChatLandingVoicePermissionDenied
            : l10n.workspaceChatLandingVoiceUnavailable;
        AppToast.show(
          context,
          message: message,
          variant: TpToastVariant.warning,
        );
        _applyVoiceListening(false);
      },
    );
    // Speech init is deferred to first mic tap (_toggleVoice) so workspace
    // open does not block on speech_to_text platform channels.
    final seed = widget.initialText;
    if (seed != null && seed.isNotEmpty) {
      _controller.value = TextEditingValue(
        text: seed,
        selection: TextSelection.collapsed(offset: seed.length),
      );
    }
    unawaited(_loadDraft());
    unawaited(_loadWorkspaceProjectBundle());
  }

  void _applyVoiceListening(bool listening) {
    if (listening) {
      _discardVoiceTranscript = false;
      _voiceInsertBaseline ??= _controller.value;
      final needsRebuild = !_voiceListening || _voiceStopwatch == null;
      _voiceListening = true;
      if (_voiceStopwatch == null) _startVoiceSessionClock();
      if (needsRebuild && mounted) setState(() {});
      return;
    }
    if (!_voiceListening && _voiceStopwatch == null) return;
    if (_discardVoiceTranscript) {
      _voiceInsertBaseline = null;
    }
    _voiceListening = false;
    _stopVoiceSessionClock();
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _runtimeTargetsLoad ??= _loadRuntimeTargets();
  }

  @override
  void didUpdateWidget(covariant WorkspaceChatLanding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.workspaceId != widget.workspace.workspaceId) {
      unawaited(_loadWorkspaceProjectBundle());
    }
  }

  /// Latest workspace manifest (member machine pins) from [ChatCubit].
  Workspace _workspaceForLaunch() {
    final id = widget.workspace.workspaceId;
    return context.read<ChatCubit>().state.workspaces.firstWhere(
      (w) => w.workspaceId == id,
      orElse: () => widget.workspace,
    );
  }

  Future<void> _loadRuntimeTargets() async {
    try {
      final targets = await context
          .read<HomeTargetController>()
          .listSelectable();
      if (!mounted) return;
      setState(() => _runtimeTargets = targets);
    } on Object {
      // HomeTargetController unavailable outside the app shell.
    }
  }

  void _startVoiceSessionClock() {
    _voiceStopwatch = Stopwatch()..start();
    _voiceSoundLevel = 0;
    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopVoiceSessionClock() {
    _voiceTimer?.cancel();
    _voiceTimer = null;
    _voiceStopwatch?.stop();
    _voiceStopwatch = null;
    _voiceSoundLevel = 0;
  }

  Duration get _voiceElapsed => _voiceStopwatch?.elapsed ?? Duration.zero;

  @override
  void dispose() {
    _stopVoiceSessionClock();
    _voiceInput.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _attachFiles() async {
    if (widget.isSubmitting) return;
    await pickAndInsertComposeFileReferences(
      controller: _controller,
      workspaceRoot: _activeLaunchDirectory(),
      filesystem: AppStorage.fs,
    );
    if (!mounted) return;
    setState(() {});
    _focusNode.requestFocus();
  }

  ComposeLandingDropIngestor _composeDropIngestor() {
    return ComposeLandingDropIngestor(
      workspaceRoot: _activeLaunchDirectory(),
      onInsertReferences: _insertComposeReferences,
    );
  }

  void _insertComposeReferences(List<String> references) {
    insertComposeReferences(_controller, references);
    if (!mounted) return;
    setState(() {});
    _focusNode.requestFocus();
  }

  Future<bool> _pasteComposeImage() async {
    if (widget.isSubmitting) return false;
    final pasted = await pasteComposeImageAttachment(
      controller: _controller,
      workspaceRoot: _activeLaunchDirectory(),
    );
    if (pasted && mounted) setState(() {});
    return pasted;
  }

  Future<void> _toggleVoice() async {
    if (widget.isSubmitting) return;

    final available = await _voiceInput.initialize();
    if (!mounted) return;
    if (!available) {
      AppToast.show(
        context,
        message: _voiceInput.permissionDenied
            ? context.l10n.workspaceChatLandingVoicePermissionDenied
            : context.l10n.workspaceChatLandingVoiceUnavailable,
        variant: TpToastVariant.warning,
      );
      return;
    }

    final started = await _voiceInput.toggleListening(
      preferredLocale: Localizations.localeOf(context),
    );
    if (!mounted) return;
    if (!started && !_voiceInput.isSessionActive) return;
    if (started || _voiceInput.isSessionActive) {
      _focusNode.requestFocus();
    }
  }

  Future<void> _cancelVoice() async {
    if (!_voiceListening && !_voiceInput.isSessionActive) return;
    _discardVoiceTranscript = true;
    await _voiceInput.endSession(discard: true);
  }

  Future<void> _stopVoice() async {
    if (!_voiceListening && !_voiceInput.isSessionActive) return;
    _discardVoiceTranscript = false;
    await _voiceInput.endSession(discard: false);
  }

  Future<void> _loadWorkspaceProjectBundle() async {
    final generation = ++_workspaceBundleGeneration;
    try {
      final config = await WorkspaceProjectConfigRepository().load(
        widget.workspace.workspaceId,
      );
      if (!mounted || generation != _workspaceBundleGeneration) return;
      setState(() => _workspaceProjectBundle = config.bundle);
    } on Object {
      if (!mounted || generation != _workspaceBundleGeneration) return;
      setState(() => _workspaceProjectBundle = const ConfigBundle());
    }
  }

  ConfigBundle _slashBundleForDraft(LandingLaunchContext draft) {
    return slashBundleForLanding(
      draft: draft,
      workspace: _workspaceProjectBundle,
    );
  }

  Future<void> _loadDraft() async {
    final draft = await resolveLandingDraft(
      workspaceId: widget.workspace.workspaceId,
      simpleModeDefaultFullAccess: context
          .read<SessionPreferencesCubit>()
          .state
          .preferences
          .simpleModeDefaultFullAccess,
    );
    if (!mounted) return;
    setState(() => _applyDraft(draft));
    await _syncActiveProjectFromDraft();
    // Sync may return early after dispose; do not touch context/setState.
  }

  Future<void> _syncActiveProjectFromDraft() async {
    final projectPath = _projectResolver().resolveSelectedProjectPath();
    if (projectPath.trim().isEmpty) return;
    try {
      final cubit = context.read<WorktreeCubit>();
      // WorktreeCubit is bound by WorkspaceToolsScopeSync once the tools plane
      // resolves (loading stays true until that first bind+load completes).
      if (cubit.state.loading) {
        await cubit.stream.firstWhere((s) => !s.loading);
        if (!mounted) return;
      }
      await cubit.selectProject(
        projectPath,
        preferWorktreePath: _selectedWorktreePath,
      );
      if (!mounted) return;
      final worktreePath = _worktreeResolver(
        cubit.state,
      ).resolveSelectedWorktreePath();
      setState(() => _selectedWorktreePath = worktreePath);
    } on ProviderNotFoundException {
      // Landing rendered outside the workspace split pane.
    }
  }


  void _applyDraft(LandingLaunchContext draft) {
    _selectedPresetId = draft.presetId;
    _selectedProjectPath = draft.projectFolderPath?.trim().isNotEmpty == true
        ? draft.projectFolderPath!.trim()
        : null;
    _selectedWorktreePath =
        draft.workingDirectoryPath?.trim().isNotEmpty == true
        ? draft.workingDirectoryPath!.trim()
        : null;
    _dangerouslySkipPermissions = draft.dangerouslySkipPermissions;

    _selectedPresetId ??= draft.presetId;
  }

  WorktreeState? _worktreeState(BuildContext context) {
    try {
      return context.watch<WorktreeCubit>().state;
    } on ProviderNotFoundException {
      return null;
    }
  }

  WorkspaceLandingProjectResolver _projectResolver() {
    return WorkspaceLandingProjectResolver(
      workspace: widget.workspace,
      runtimeTargets: _runtimeTargets,
      storedProjectPath: _selectedProjectPath,
    );
  }

  WorkspaceLandingWorktreeResolver _worktreeResolver(
    WorktreeState? worktreeState,
  ) {
    final projectPath = _projectResolver().resolveSelectedProjectPath();
    WorktreeCubit? cubit;
    try {
      cubit = context.read<WorktreeCubit>();
    } on ProviderNotFoundException {
      cubit = null;
    }
    return WorkspaceLandingWorktreeResolver(
      projectPath: projectPath,
      worktreeState: worktreeState,
      storedWorktreePath: _selectedWorktreePath,
      cachedWorktrees: cubit?.worktreesForProject(projectPath) ?? const [],
    );
  }

  Future<void> _selectProject(Object? value) async {
    if (value is! String || value.trim().isEmpty) return;
    final path = normalizeWorkspacePath(value);
    setState(() {
      _selectedProjectPath = path;
      _selectedWorktreePath = null;
    });
    try {
      final cubit = context.read<WorktreeCubit>();
      await cubit.selectProject(
        path,
        preferWorktreePath: _selectedWorktreePath,
      );
      if (!mounted) return;
      final worktreePath = _worktreeResolver(
        cubit.state,
      ).resolveSelectedWorktreePath();
      setState(() => _selectedWorktreePath = worktreePath);
      cubit.setCurrentWorktree(worktreePath);
    } on ProviderNotFoundException {
      // Landing rendered outside the workspace split pane.
    }
    _persistDraft();
  }

  void _selectWorktree(Object? value) {
    if (value is! String || value.trim().isEmpty) return;
    final path = normalizeWorkspacePath(value);
    setState(() => _selectedWorktreePath = path);
    _persistDraft();
    try {
      context.read<WorktreeCubit>().setCurrentWorktree(path);
    } on ProviderNotFoundException {
      // Landing rendered outside the workspace split pane.
    }
  }

  void _syncLaunchFromWorktree(WorktreeState state) {
    final projectPath = _projectResolver().resolveSelectedProjectPath();
    if (!workspacePathsEqual(state.repoPath, projectPath)) return;
    final path = normalizeWorkspacePath(state.currentWorktreePath);
    if (path.isEmpty) return;
    final resolver = _worktreeResolver(state);
    if (!resolver.options.any((o) => workspacePathsEqual(o.path, path))) {
      return;
    }
    final stored = _selectedWorktreePath?.trim() ?? '';
    if (stored.isNotEmpty && workspacePathsEqual(stored, path)) return;
    setState(() => _selectedWorktreePath = path);
    _persistDraft();
  }

  String _activeLaunchDirectory() {
    WorktreeState? worktreeState;
    try {
      worktreeState = context.read<WorktreeCubit>().state;
    } on ProviderNotFoundException {
      worktreeState = null;
    }
    return _worktreeResolver(worktreeState).resolveSelectedWorktreePath();
  }

  String? _optionalLaunchDirectory() {
    final path = _activeLaunchDirectory().trim();
    return path.isEmpty ? null : path;
  }

  LandingLaunchContext _currentDraft() {
    WorktreeState? worktreeState;
    try {
      worktreeState = context.read<WorktreeCubit>().state;
    } on ProviderNotFoundException {
      worktreeState = null;
    }
    final projectResolver = _projectResolver();
    final selectedProjectPath = projectResolver.resolveSelectedProjectPath();
    final worktreeResolver = _worktreeResolver(worktreeState);
    final selectedWorktreePath = worktreeResolver.resolveSelectedWorktreePath();
    return LandingLaunchContext(
      isPersonal: true,
      presetId: _selectedPresetId,
      projectFolderPath: selectedProjectPath.trim().isEmpty
          ? null
          : selectedProjectPath,
      workingDirectoryPath: selectedWorktreePath.trim().isEmpty
          ? null
          : selectedWorktreePath,
      dangerouslySkipPermissions: _dangerouslySkipPermissions,
    );
  }

  void _persistDraft() {
    unawaited(
      persistLandingDraft(widget.workspace.workspaceId, _currentDraft()),
    );
  }

  bool get _canSubmit {
    if (widget.disabled || widget.isSubmitting) return false;
    if (_controller.text.trim().isEmpty) return false;
    return true;
  }

  void _submit() {
    unawaited(_submitAfterLaunchGate());
  }

  Future<void> _submitAfterLaunchGate() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.disabled || widget.isSubmitting) return;

    widget.onSubmit(text, _currentDraft());
  }

  void _setDangerouslySkipPermissions(bool value) {
    if (_dangerouslySkipPermissions == value) return;
    setState(() => _dangerouslySkipPermissions = value);
    _persistDraft();
  }

  void _selectPreset(String presetId) {
    setState(() => _selectedPresetId = presetId);
    _persistDraft();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final skills = context.watch<SkillCubit>().state.installed;
    final plugins = context.watch<PluginCubit>().state.installed;
    final slashBundle = _slashBundleForDraft(_currentDraft());
    final worktreeState = _worktreeState(context);
    final projectResolver = _projectResolver();
    final selectedProjectPath = projectResolver.resolveSelectedProjectPath();
    final projectLabel = projectResolver.labelFor(selectedProjectPath);
    final worktreeResolver = _worktreeResolver(worktreeState);
    final selectedWorktreePath = worktreeResolver.resolveSelectedWorktreePath();
    final worktreeLabel = worktreeResolver.labelFor(selectedWorktreePath);
    final composeCard = WorkspaceChatLandingComposeCard(
      controller: _controller,
      focusNode: _focusNode,
      hint: l10n.workspaceChatLandingInputHint,
      isSubmitting: widget.isSubmitting,
      canSubmit: _canSubmit,
      onSubmit: _submit,
      onChanged: (_) => setState(() {}),
      dangerouslySkipPermissions: _dangerouslySkipPermissions,
      defaultPermissionsLabel: l10n.workspaceChatLandingDefaultPermissions,
      fullAccessPermissionsLabel: l10n.workspaceChatLandingFullAccessPermissions,
      onPermissionSelected: _setDangerouslySkipPermissions,
      attachTooltip: l10n.workspaceChatLandingAttach,
      voiceTooltip: l10n.workspaceChatLandingVoice,
      voiceCancelTooltip: l10n.workspaceChatLandingVoiceCancel,
      voiceStopTooltip: l10n.workspaceChatLandingVoiceStop,
      isVoiceListening: _voiceListening,
      voiceElapsed: _voiceElapsed,
      voiceSoundLevel: _voiceSoundLevel,
      onAttach: () => unawaited(_attachFiles()),
      onVoice: () => unawaited(_toggleVoice()),
      onVoiceCancel: () => unawaited(_cancelVoice()),
      onVoiceStop: () => unawaited(_stopVoice()),
      dropTarget: _composeDropIngestor(),
      onPasteImage: _pasteComposeImage,
      workspaceRoot: _activeLaunchDirectory(),
      skills: skills,
      plugins: plugins,
      slashBundle: slashBundle,
    );

    final body = widget.showLandingChrome
        ? Stack(
            children: [
              ColoredBox(
                color: cs.surface,
                child: SizedBox.expand(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: spacing.xl,
                        vertical: spacing.xxl,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 880),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            WorkspaceLandingHeaderRow(
                              projectLabel: projectLabel,
                              projectHintWhenEmpty:
                                  l10n.workspaceChatLandingSelectProject,
                              projectMenuSpecs: projectResolver.menuSpecs(
                                selectedProjectPath,
                              ),
                              onProjectSelected: (value) =>
                                  unawaited(_selectProject(value)),
                              showWorktreeSelector:
                                  worktreeResolver.showsWorktreeSelector,
                              worktreeLabel: worktreeLabel,
                              worktreeHintWhenEmpty:
                                  l10n.workspaceChatLandingSelectWorktree,
                              worktreeMenuSpecs: worktreeResolver.menuSpecs(
                                selectedWorktreePath,
                              ),
                              onWorktreeSelected: _selectWorktree,
                            ),
                            SizedBox(height: spacing.sm),
                            composeCard,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: spacing.md,
                left: spacing.md,
                child: TpIconButton(
                  key: AppKeys.workspaceChatLandingBackButton,
                  icon: Icons.arrow_back,
                  tooltip: l10n.workspaceChatLandingBackToStart,
                  backgroundColor: Colors.transparent,
                  onTap: () {
                    final workspaceId = widget.workspace.workspaceId;
                    context.read<ChatCubit>().dismissNewChat();
                    context.read<WorkbenchCubit>().enterWelcome(workspaceId);
                  },
                ),
              ),
            ],
          )
        : composeCard;

    return BlocListener<WorktreeCubit, WorktreeState>(
      listenWhen: (previous, current) =>
          previous.currentWorktreePath != current.currentWorktreePath,
      listener: (context, state) => _syncLaunchFromWorktree(state),
      child: body,
    );
  }
}
