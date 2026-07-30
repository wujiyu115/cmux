import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../extensions/extension_management_page.dart';

/// Which global management view is shown in the workspace-home right pane.
enum HomeGlobalView {
  extensions;

  /// Query key on `/home-v2` for deep-linking a global management pane.
  static const globalQueryParam = 'global';

  String get routeSegment => name;

  /// `/home-v2?global=<segment>` — opens the main workspace with this sidebar
  /// shortcut selected.
  String get homeLocation => Uri(
    path: '/home-v2',
    queryParameters: {globalQueryParam: routeSegment},
  ).toString();

  /// Resolves [globalQueryParam] (e.g. `extensions`) back to a view.
  static HomeGlobalView? fromSegment(String? segment) {
    final value = segment?.trim();
    if (value == null || value.isEmpty) return null;
    for (final view in values) {
      if (view.routeSegment == value) return view;
    }
    return null;
  }
}

/// Embeds a global management page (Extensions / Automations) inside the
/// workspace-home right pane. Sub-section
/// navigation stays local (via [onSelectSection] overrides) so it never breaks
/// out of the home shell.
class HomeGlobalSection extends StatefulWidget {
  const HomeGlobalSection({
    required this.view,
    this.onOpenTeam,
    super.key,
  });

  final HomeGlobalView view;

  /// Selects a team and leaves the global view (My Teams open action).
  final ValueChanged<String>? onOpenTeam;

  @override
  State<HomeGlobalSection> createState() => _HomeGlobalSectionState();
}

class _HomeGlobalSectionState extends State<HomeGlobalSection> {
  ExtensionSection _extension = ExtensionSection.installed;

  @override
  Widget build(BuildContext context) {
    final content = switch (widget.view) {
      HomeGlobalView.extensions => ExtensionManagementPage(
        section: _extension,
        onSelectSection: (s) => setState(() => _extension = s),
      ),
    };
    if (MediaQuery.disableAnimationsOf(context)) return content;
    return content
        .animate(key: ValueKey(widget.view))
        .fadeIn(duration: 180.ms, curve: Curves.easeOut)
        .slideX(
          begin: 0.025,
          end: 0,
          duration: 220.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
