import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/app/debug_log_settings.dart';
import '../../services/storage/app_storage.dart';
import '../../utils/logging/logger_utils.dart';
import '../../utils/ui/app_keys.dart';
import '../system/log_helpers.dart';
import 'pairing_nav_bar.dart';

/// Phone-sized viewer for the app's diagnostic log, plus the switch that decides
/// whether it is written at all.
///
/// A separate page from the desktop `LogViewerPanel` rather than a reuse of it:
/// that one is a 920×640 dialog with a desktop-density toolbar and
/// non-selectable rows, none of which survives a phone. What is shared is the
/// part worth sharing — `logMonospaceStyle` / `logLineColor` from
/// `log_helpers.dart`, so a warning looks the same on both.
///
/// The whole point is that a log on a phone is unreachable otherwise: the file
/// lives in app-private storage (`/data/data/<pkg>/files/logs` on Android), so
/// without copy-to-clipboard here there is no way to get it off the device.
class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key, this.appDataRoot});

  /// Where the `logs/` directory lives. Injected so a test does not need the
  /// path bootstrapper running; production leaves it null and reads the global,
  /// which is initialized long before this page can be reached.
  final String? appDataRoot;

  /// Route helper, matching the other pushed mobile pages.
  static Route<void> route({String? appDataRoot}) => MaterialPageRoute(
    builder: (_) => DebugLogPage(appDataRoot: appDataRoot),
  );

  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<DebugLogPage> {
  String get _root =>
      widget.appDataRoot ?? AppPathsBootstrapper.current.basePath;

  /// Tail only. A 5 MiB rotation ceiling would take minutes to render on a phone
  /// and nobody reads the top of it.
  static const _maxLines = 1000;

  bool _enabled = false;
  bool _loading = true;
  List<String> _lines = const [];
  String? _path;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final logger = AppLogger.instance;
    try {
      final preferences = await SharedPreferences.getInstance();
      final enabled = DebugLogSettings.read(preferences);
      final path = logger.currentLogFilePath;
      final lines = path == null
          ? const <String>[]
          : await logger.readLogFileLines(path);
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _path = path;
        _lines = lines.length > _maxLines
            ? lines.sublist(lines.length - _maxLines)
            : lines;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _setEnabled(bool value) async {
    // Optimistic: the switch must not lag behind the finger while the sink opens.
    setState(() => _enabled = value);
    final preferences = await SharedPreferences.getInstance();
    await DebugLogSettings.write(preferences, value);
    await AppLogger.instance.setFileLoggingEnabled(
      value,
      appDataRoot: _root,
    );
    // Turning it on creates the file, so re-read to pick up the new path.
    await _load();
  }

  Future<void> _copyAll() async {
    // The path is included because a bug report with 1000 lines and no idea
    // which file they came from is harder to act on.
    final header = _path == null ? '' : '# $_path\n';
    await Clipboard.setData(ClipboardData(text: '$header${_lines.join('\n')}'));
    if (!mounted) return;
    TpToast.show(context, message: context.l10n.debugLogCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;

    return Scaffold(
      key: AppKeys.debugLogPage,
      body: SafeArea(
        child: Column(
          children: [
            PairingNavBar.large(
              title: l10n.debugLogTitle,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.lg),
              child: TpCard.outlined(
                child: TpPreferenceRow(
                  title: l10n.debugLogWriteToFile,
                  subtitle: l10n.debugLogWriteToFileHint,
                  trailing: Switch(
                    key: AppKeys.debugLogEnableSwitch,
                    value: _enabled,
                    onChanged: _setEnabled,
                  ),
                ),
              ),
            ),
            SizedBox(height: spacing.sm),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _path ?? l10n.debugLogNoFile,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TpIconButton(
                    key: AppKeys.debugLogRefreshButton,
                    icon: Icons.refresh,
                    tooltip: l10n.logViewerRefresh,
                    onTap: _load,
                  ),
                  TpIconButton(
                    key: AppKeys.debugLogCopyButton,
                    icon: Icons.copy_all_outlined,
                    tooltip: l10n.debugLogCopyAll,
                    onTap: _lines.isEmpty ? null : _copyAll,
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: cs.outlineVariant),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return _Message(text: l10n.logViewerReadFailed(error));
    }
    if (_lines.isEmpty) {
      return _Message(
        text: _enabled ? l10n.logViewerEmpty : l10n.debugLogDisabledHint,
      );
    }
    // Selectable rather than plain Text: on a phone, picking one stack frame out
    // is often all the user wants, and copy-all is the wrong tool for that.
    return ListView.builder(
      padding: EdgeInsets.all(context.tpSpacing.sm),
      itemCount: _lines.length,
      itemBuilder: (context, index) {
        final line = _lines[index];
        return SelectableText(
          line,
          style: logMonospaceStyle(
            context,
            color: logLineColor(context, line),
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(context.tpSpacing.xl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}
