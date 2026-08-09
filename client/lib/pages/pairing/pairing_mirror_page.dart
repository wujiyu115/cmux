import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../cubits/image_upload_cubit.dart';
import '../../cubits/mobile_toolbar_cubit.dart';
import '../../cubits/pairing_client_cubit.dart';
import '../../cubits/voice_input_cubit.dart';
import '../../repositories/mobile_toolbar_repository.dart';
import '../../services/stt/transcript_insertion.dart';
import '../../services/terminal/terminal_fonts.dart';
import '../../theme/app_fonts.dart';
import '../../theme/app_typography_scale.dart';
import '../../utils/shell_quote.dart';
import '../../utils/ui/app_keys.dart';
import 'mobile_toolbar/mobile_bottom_slot.dart';
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

class _PairingMirrorPageState extends State<PairingMirrorPage> {
  late final TerminalEngine _engine;
  late final TerminalController _controller;
  late final MobileToolbarCubit _toolbar;

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
  late final ImageUploadCubit _upload;
  StreamSubscription<String>? _uploadPaths;

  /// Borrowed from the pairing shell — the page only ever stops it, never
  /// closes it. Captured here because [dispose] cannot `context.read`.
  late final VoiceInputCubit _voice;

  /// Last geometry the host acknowledged, shown in the nav bar so a mismatched
  /// mirror (phone rotated, desktop resized) is visible rather than mysterious.
  ({int cols, int rows})? _geometry;

  @override
  void initState() {
    super.initState();
    _engine = TerminalEngine(config: TerminalConfig.defaults());
    _controller = TerminalController();

    final cubit = context.read<PairingClientCubit>();
    // Host → engine: snapshot then live bytes, already ordered by the host.
    final sub = cubit.activeSubscription;
    _hostOutput = sub?.output.listen(_engine.feed);
    // Engine → host: keystrokes / paste / mouse reports become input frames.
    _localInput = _engine.output.listen(cubit.sendInput);

    // Toolbar keys bypass the engine and go straight out as input frames, so
    // they work whether or not the terminal holds focus.
    _toolbar = MobileToolbarCubit(
      repository: SharedPrefsMobileToolbarRepository(
        context.read<SharedPreferences>(),
      ),
      sendInput: cubit.sendInput,
    );
    _toolbar.load();

    _voice = context.read<VoiceInputCubit>();
    // Recognized speech goes into the composer's controller, not into cubit
    // state: a per-result emit would rebuild the panel on every spoken word.
    _transcripts = _voice.transcripts.listen((text) {
      _composerText.value = insertTranscript(_composerText.value, text);
    });

    _upload = ImageUploadCubit(
      pickImage: _pickImage,
      upload: cubit.uploadImage,
    );
    // The host decides the path; the phone never guesses it. Quote it so a cwd
    // containing a space still yields one shell argument.
    _uploadPaths = _upload.paths.listen((path) {
      _composerText.value = insertTranscript(
        _composerText.value,
        '${shellQuotePath(path)} ',
      );
    });
  }

  /// Reads one gallery image off disk into memory. The only place `image_picker`
  /// is used, so the cubit takes plain callbacks and stays testable. [XFile.name]
  /// is already a bare filename with no directory part; the host validates it
  /// independently, so both checks exist.
  Future<PickedImage?> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    return PickedImage(
      filename: picked.name,
      bytes: await picked.readAsBytes(),
    );
  }

  @override
  void dispose() {
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
    final cs = Theme.of(context).colorScheme;
    final typography = context.appTypography;
    final cubit = context.read<PairingClientCubit>();
    final geometry = _geometry;
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
                  title: title,
                  onBack: cubit.leaveMirror,
                  trailing: geometry == null
                      ? null
                      : Text(
                          '${geometry.cols}×${geometry.rows}',
                          textAlign: TextAlign.right,
                          style: appMonoTextStyle(
                            context,
                            fontSize: typography.bodySmall,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              Expanded(
                child: TerminalView(
                  _engine,
                  controller: _controller,
                  // Without this the view falls back to TerminalStyle.defaults(),
                  // whose family is 'monospace' — a fontconfig generic that iOS
                  // cannot resolve, so glyphs come from the proportional system
                  // face while cells are sized from that same face's 'W'
                  // advance. Narrow glyphs then float in oversized cells. The
                  // desktop terminal has always passed this; the mirror did not.
                  textStyle: appTerminalTextStyle(context),
                  autofocus: true,
                  padding: const EdgeInsets.all(4),
                  onPtyResize: (columns, rows) {
                    cubit.sendResize(columns, rows);
                    if (geometry?.cols == columns && geometry?.rows == rows) {
                      return;
                    }
                    setState(() => _geometry = (cols: columns, rows: rows));
                  },
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
