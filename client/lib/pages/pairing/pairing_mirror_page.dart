import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../cubits/media_upload_cubit.dart';
import '../../services/pairing/upload_source.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/mobile_toolbar_cubit.dart';
import '../../cubits/pairing_client_cubit.dart';
import '../../cubits/voice_input_cubit.dart';
import '../../repositories/mobile_toolbar_repository.dart';
import '../../services/stt/transcript_insertion.dart';
import '../../services/terminal/keyboard_inset_pty_hold.dart';
import '../../services/terminal/terminal_fonts.dart';
import '../../services/terminal/terminal_layout_coordinator.dart';
import '../../services/terminal/terminal_theme_mapper.dart';
import '../../utils/logging/logger_utils.dart';
import '../../utils/shell_quote.dart';
import '../../utils/ui/app_keys.dart';
import 'mobile_toolbar/mobile_bottom_slot.dart';
import 'mirror_actions_sheet.dart';
import 'mirror_changes_sheet.dart';
import 'mirror_selection_bar.dart';
import 'mirror_terminal_stack.dart';
import 'pairing_nav_bar.dart';

/// Live, interactive mirror of a desktop session.
///
/// A fresh [TerminalEngine] renders the host's snapshot-then-live PTY bytes; the
/// view is **not** read-only, so keystrokes flow back to the desktop PTY as input
/// frames and viewport changes (rotation / soft keyboard) send resize frames.
/// Mirror-only: this phone never spawns a local PTY.
class PairingMirrorPage extends StatefulWidget {
  const PairingMirrorPage({super.key});

  @override
  State<PairingMirrorPage> createState() => _PairingMirrorPageState();
}

class _PairingMirrorPageState extends State<PairingMirrorPage>
    with WidgetsBindingObserver {
  late final TerminalEngine _engine;
  late final TerminalController _controller;
  late final MobileToolbarCubit _toolbar;

  /// Reaches [TerminalViewState.beginPtyHold] — the only way to bracket the
  /// soft-keyboard animation from out here.
  final _terminalViewKey = GlobalKey<TerminalViewState>();

  /// Last theme handed to the engine, so a rebuild that changed nothing about the
  /// colours does not re-enter the Rust side.
  TerminalTheme? _appliedTheme;

  /// Number of changed files in the mirrored pane's repository, or null when it
  /// is unknown (not a repo, host too old, request failed).
  ///
  /// Read once on open and then only when the pane's agent finishes a turn: each
  /// read is a `git status` on the host, and between turns the answer does not
  /// change on its own.
  final _changeCount = ValueNotifier<int?>(null);
  StreamSubscription<void>? _changeHints;

  /// Turns the IME animation's per-frame insets into one PTY resize.
  late final _keyboardHold = KeyboardInsetPtyHold(
    target: () {
      final state = _terminalViewKey.currentState;
      return state == null ? null : ptyHoldTargetFor(state);
    },
  );

  /// The composer's draft outlives the panel: flipping to the key bar unmounts
  /// the panel, and the half-typed command has to still be there on the way
  /// back. It dies with the page, which is why it is not persisted.
  final _composerText = TextEditingController();
  final _composerFocus = FocusNode();
  StreamSubscription<Uint8List>? _hostOutput;
  StreamSubscription<Uint8List>? _localInput;
  StreamSubscription<String>? _transcripts;

  /// Picks and uploads one image at a time; created here so `image_picker`
  /// stays out of the cubit and the cubit stays testable.
  late final MediaUploadCubit _upload;
  StreamSubscription<String>? _uploadPaths;

  /// Borrowed from the pairing shell — the page only ever stops it, never
  /// closes it. Captured here because [dispose] cannot `context.read`.
  late final VoiceInputCubit _voice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine = TerminalEngine(config: TerminalConfig.defaults());
    _controller = TerminalController();

    final cubit = context.read<PairingClientCubit>();
    // Host → engine: snapshot then live bytes, already ordered by the host.
    final sub = cubit.activeSubscription;
    _hostOutput = sub?.output.listen(_engine.feed);

    // Toolbar keys bypass the engine and go straight out as input frames, so
    // they work whether or not the terminal holds focus. Created before the
    // engine's own output is wired up, because that wiring reads through it.
    _toolbar = MobileToolbarCubit(
      repository: SharedPrefsMobileToolbarRepository(
        context.read<SharedPreferences>(),
      ),
      sendInput: cubit.sendInput,
    );
    _toolbar.load();

    // Engine → host: keystrokes / paste / mouse reports become input frames.
    //
    // Routed through the toolbar so an armed Ctrl / Alt applies to the *soft
    // keyboard* too. The key caps cover no letters, so `Ctrl+C` typed on the
    // phone keyboard has no other way to become 0x03 — see
    // [MobileToolbarCubit.consumeModifiers].
    _localInput = _engine.output.listen(
      (bytes) => cubit.sendInput(_toolbar.consumeModifiers(bytes)),
    );

    _voice = context.read<VoiceInputCubit>();
    // Recognized speech goes into the composer's controller, not into cubit
    // state: a per-result emit would rebuild the panel on every spoken word.
    _transcripts = _voice.transcripts.listen((text) {
      _composerText.value = insertTranscript(_composerText.value, text);
    });

    _upload = MediaUploadCubit(
      pickMedia: _pickMedia,
      upload: cubit.uploadMedia,
      cancelUpload: cubit.cancelUpload,
    );
    // The host decides the path; the phone never guesses it. Quote it so a cwd
    // containing a space still yields one shell argument.
    _uploadPaths = _upload.paths.listen((path) {
      _composerText.value = insertTranscript(
        _composerText.value,
        '${shellQuotePath(path)} ',
      );
    });

    _changeHints = cubit.gitRefreshHints.listen((_) => _refreshChangeCount());
    unawaited(_refreshChangeCount());
  }

  Future<void> _refreshChangeCount() async {
    final changes = await context.read<PairingClientCubit>().gitChanges();
    if (!mounted) return;
    _changeCount.value = changes == null || !changes.isRepository
        ? null
        : changes.files.length;
  }

  /// Reconfigures the engine whenever the resolved terminal theme changes.
  ///
  /// The colours have to reach the *engine*, not just [TerminalView]: the area
  /// outside the cell grid — the sub-cell remainder the viewport resolver centres
  /// — is cleared engine-side from its config, so a mirror left on
  /// `TerminalConfig.defaults()` framed the grid in the default background no
  /// matter what Flutter painted behind it. The desktop path does the same thing
  /// through `TerminalSession.applyTerminalTheme`.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = _resolveTerminalTheme();
    if (theme.background == _appliedTheme?.background) return;
    _appliedTheme = theme;
    _engine.reconfigure(terminalConfigFromTheme(theme));
  }

  TerminalTheme _resolveTerminalTheme() => teampilotTerminalTheme(
    Theme.of(context).colorScheme,
    isDark: Theme.of(context).brightness == Brightness.dark,
    mode: context.watch<LayoutCubit>().state.preferences.terminalThemeMode,
  );

  /// The soft keyboard does not arrive in one step — see [KeyboardInsetPtyHold]
  /// for why every frame of that animation must not become its own SIGWINCH.
  /// Read from [View] rather than `MediaQuery`: this fires before the inherited
  /// widget is rebuilt, so the MediaQuery value here is still the old one.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    final view = View.of(context);
    _keyboardHold.onInsetChanged(
      view.viewInsets.bottom / view.devicePixelRatio,
    );
  }

  /// One gallery pick — image or video, same sheet.
  ///
  /// `pickMedia` rather than a separate video button: one tap, one sheet, and the
  /// phone's own picker already distinguishes the two. It requires iOS 14, which
  /// is why the deployment target was raised.
  ///
  /// The only place `image_picker` is used, so the cubit takes plain callbacks and
  /// stays testable. [XFile.name] is already a bare filename with no directory
  /// part; the host validates it independently, so both checks exist.
  ///
  /// Deliberately *not* `readAsBytes()`: a 512 MiB video read into a `Uint8List`
  /// on a phone is an out-of-memory kill, which is the whole reason the upload
  /// streams. `XFile.path` is a real path — image_picker copies the picked asset
  /// into the app cache before returning.
  ///
  /// `requestFullMetadata: false` skips the iOS photo-library permission prompt
  /// (PHPicker needs none) and costs nothing here: no resize or re-encode is
  /// requested either way.
  Future<PickedMedia?> _pickMedia() async {
    final picked = await ImagePicker().pickMedia(requestFullMetadata: false);
    if (picked == null) {
      // Also what a platform picker that fails to return a path looks like, so
      // it is worth a line: on the cubit side a null pick is silent (it means
      // "user backed out"), which makes a broken picker indistinguishable from
      // a cancelled one.
      AppLogger.instance.i('Media pick returned nothing');
      return null;
    }
    final source = await FileUploadSource.open(picked.path);
    AppLogger.instance.i(
      'Media picked: name=${picked.name} bytes=${source.length} '
      'mime=${picked.mimeType} path=${picked.path}',
    );
    return PickedMedia(filename: picked.name, source: source);
  }

  /// Copies the touch selection to the system clipboard and clears it.
  ///
  /// Empty selections are skipped rather than clobbering whatever the user had
  /// on the clipboard. Clearing after the copy matches the desktop flow, where
  /// a completed copy ends the selection — and on a phone it also removes the
  /// chip, which is the only signal that the copy landed.
  Future<void> _copySelection() async {
    final text = _controller.readSelectionText();
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _controller.clearSelection();
  }

  /// Second-level menu behind the nav bar's more icon: git changes for the
  /// mirrored pane's repo, or a jump back to the live edge of the scrollback.
  Future<void> _showActionsMenu() async {
    final action = await showMirrorActionsSheet(
      context,
      changeCount: _changeCount.value,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case MirrorAction.gitDiff:
        unawaited(
          showMirrorChangesSheet(context, context.read<PairingClientCubit>()),
        );
      case MirrorAction.scrollToLatest:
        unawaited(_controller.scrollToBottom());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Before the terminal view goes: a flush here would push a grid nobody is
    // looking at any more.
    _keyboardHold.dispose();
    _hostOutput?.cancel();
    _localInput?.cancel();
    // Cancel before disposing the controller: an in-flight result must not
    // write into a disposed controller. Stop the mic (never close — the shell
    // owns the cubit); one of the four paths that must not leave it hot.
    _transcripts?.cancel();
    // Same reason as the transcript subscription: an upload can still land a
    // path after this page is torn down, and that path must not be written into
    // an already-disposed controller — so cancel before _composerText.dispose().
    _uploadPaths?.cancel();
    _changeHints?.cancel();
    _changeCount.dispose();
    _voice.stopListening();
    _controller.dispose();
    _engine.dispose();
    _composerText.dispose();
    _composerFocus.dispose();
    _toolbar.close();
    _upload.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PairingClientCubit>();
    // The desktop's tab label for the mirrored pane, not the OSC title the
    // running program last set (a bare cwd basename like `flutter_alacritty`).
    // Renames on the desktop flow through here live; the OSC title is only the
    // fallback for a tree that does not know this pane.
    final paneTitle = context.select<PairingClientCubit, String?>(
      (c) => c.state.mirroredPaneTitle,
    );
    // The same theme the desktop pane passes, so the mirror renders the app's
    // terminal colours instead of the engine's built-in defaults.
    final terminalTheme = _resolveTerminalTheme();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          // The fourth path that must not leave the microphone hot.
          _voice.stopListening();
          cubit.leaveMirror();
        }
      },
      child: Scaffold(
        key: AppKeys.pairingMirrorPage,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              ValueListenableBuilder<String>(
                valueListenable: _engine.title,
                builder: (context, title, _) => PairingNavBar(
                  title: paneTitle ?? title,
                  onBack: cubit.leaveMirror,
                  // Changed files are reachable from *here* rather than only
                  // from the workspace list: the reader is watching an agent
                  // work in this terminal, and leaving the mirror to see what it
                  // touched is exactly the trip worth avoiding.
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder<int?>(
                        valueListenable: _changeCount,
                        builder: (context, count, _) => MirrorChangesAction(
                          count: count,
                          onTap: () => _showActionsMenu(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: MirrorTerminalStack(
                  // The grid can only be a whole number of cells, so the resolver
                  // hands the sub-cell remainder back as centered padding
                  // (`viewport_resolver.dart`) — up to a cell of width split left
                  // and right, and a row of height split top and bottom. That is
                  // unavoidable; what made it *visible* is that the remainder is
                  // cleared by the engine, not by Flutter, so it took the colour
                  // from the engine's config rather than from anything painted
                  // behind it. So the colour has to be set in two places, and
                  // measuring showed both are needed: the engine's config (see
                  // [didChangeDependencies]) covers the remainder inside its
                  // surface, and this box covers the frame *outside* that surface —
                  // 23 logical rows at the top and ~14 at each side, which was
                  // still showing the Scaffold's black once the first half was
                  // fixed. Same packed RGB feeds both, so they cannot disagree.
                  terminal: ColoredBox(
                    color: Color(0xFF000000 | terminalTheme.background),
                    child: TerminalView(
                      _engine,
                      key: _terminalViewKey,
                      controller: _controller,
                      theme: terminalTheme,
                      // Without this the view falls back to TerminalStyle.defaults(),
                      // whose family is 'monospace' — a fontconfig generic that iOS
                      // cannot resolve, so glyphs come from the proportional system
                      // face while cells are sized from that same face's 'W'
                      // advance. Narrow glyphs then float in oversized cells. The
                      // desktop terminal has always passed this; the mirror did not.
                      textStyle: appTerminalTextStyle(context),
                      autofocus: true,
                      // Zero padding so the grid fills the full phone width; the
                      // resolver's sub-cell remainder is the only inset left.
                      padding: EdgeInsets.zero,
                      onPtyResize: cubit.sendResize,
                    ),
                  ),
                  // A phone has no Ctrl+Shift+C and no right-click menu, so the
                  // touch selection a long press starts needs its own exit: the
                  // chip appears while a selection is live and copies it out.
                  overlay: ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) => _controller.selectionActive
                        ? MirrorSelectionBar(onCopy: _copySelection)
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
              MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: _toolbar),
                  BlocProvider.value(value: _voice),
                  BlocProvider.value(value: _upload),
                ],
                child: MobileBottomSlot(
                  controller: _composerText,
                  focusNode: _composerFocus,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
