import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../models/layout_preferences.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/split_layout.dart';
import 'home_config_section.dart';
import 'home_all_workspaces_pane.dart';
import 'home_workspace_library_section.dart';
import 'home_workspace_library_view.dart';
import 'home_workspace_sidebar.dart';
import 'workspace_pane_animations.dart';

/// New Apifox-style workspace home body (workspaces rail + right pane). The
/// window chrome (title bar + open workspace tabs) is provided by
/// [HomeShell].
class HomePage extends StatefulWidget {
  const HomePage({
    this.initialSection,
    this.initialMemberId,
    super.key,
  });

  /// Team-config tab to open on first build (deep-link from e.g. the launch
  /// config-incomplete dialog).
  final TeamConfigSection? initialSection;

  /// Member to focus when [initialSection] is [TeamConfigSection.members].
  final String? initialMemberId;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var _allWorkspacesActive = true;
  String? _selectedIdentityId;

  /// Favorites / recent library pane; mutually exclusive with all-workspaces.
  HomeLibraryView? _libraryView;

  @override
  void initState() {
    super.initState();
    if (widget.initialSection != null) {
      _allWorkspacesActive = false;
    }
  }

  void _selectIdentity(String profileId) {
    setState(() {
      _selectedIdentityId = profileId;
      _allWorkspacesActive = false;
      _libraryView = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final libraryView = _libraryView;

    return WorkspacePageCardShell(
      child: BlocBuilder<LayoutCubit, LayoutState>(
        buildWhen: (a, b) =>
            a.preferences.homeSidebarWidth != b.preferences.homeSidebarWidth,
        builder: (context, layoutState) {
          return TwoPaneSplitView(
            axis: Axis.horizontal,
            first: HomeSidebar(
              activeLibraryView: libraryView,
              allWorkspacesActive: _allWorkspacesActive && libraryView == null,
              onSelectAllWorkspaces: () => setState(() {
                _allWorkspacesActive = true;
                _libraryView = null;
                _selectedIdentityId = null;
              }),
              onSelectLibraryView: (view) => setState(() {
                _allWorkspacesActive = false;
                _libraryView = view;
              }),
            ),
            second: Padding(
              padding: const EdgeInsets.fromLTRB(44, 48, 42, 18),
              child: _HomeRightPane(
                libraryView: libraryView,
                allWorkspacesActive: _allWorkspacesActive,
                selectedIdentityId: _selectedIdentityId,
                initialSection: widget.initialSection,
                initialMemberId: widget.initialMemberId,
                onOpenTeam: _selectIdentity,
              ),
            ),
            initialSize: layoutState.preferences.homeSidebarWidth,
            minSize: LayoutPreferences.minHomeSidebarWidth,
            maxSize: double.infinity,
            minSecondarySize: LayoutPreferences.minWorkspaceHubContentWidth,
            onSizeChanged: (width) {
              context.read<LayoutCubit>().setHomeSidebarWidth(width);
            },
          );
        },
      ),
    );
  }
}

class _HomeRightPane extends StatefulWidget {
  const _HomeRightPane({
    required this.libraryView,
    required this.allWorkspacesActive,
    required this.selectedIdentityId,
    required this.initialSection,
    required this.initialMemberId,
    required this.onOpenTeam,
  });

  final HomeLibraryView? libraryView;
  final bool allWorkspacesActive;
  final String? selectedIdentityId;
  final TeamConfigSection? initialSection;
  final String? initialMemberId;
  final ValueChanged<String> onOpenTeam;

  @override
  State<_HomeRightPane> createState() => _HomeRightPaneState();
}

class _HomeRightPaneState extends State<_HomeRightPane> {
  WorkspaceRightPaneDescriptor? _previousDescriptor;
  @override
  Widget build(BuildContext context) {
    final descriptor = _resolveDescriptor(context);
    final previous = _previousDescriptor;

    final pane = WorkspacePaneAnimations.switcher(
      context: context,
      descriptor: descriptor,
      previous: previous,
      child: _buildPane(context, descriptor),
    );

    if (previous != descriptor) {
      _previousDescriptor = descriptor;
    }

    return pane;
  }

  WorkspaceRightPaneDescriptor _resolveDescriptor(BuildContext context) {
    if (widget.libraryView != null) {
      return WorkspaceRightPaneDescriptor.library(widget.libraryView!);
    }
    return const WorkspaceRightPaneDescriptor.allWorkspaces();
  }

  Widget _buildPane(
    BuildContext context,
    WorkspaceRightPaneDescriptor descriptor,
  ) {
    return switch (descriptor.kind) {
      WorkspaceRightPaneKind.allWorkspaces => const HomeAllWorkspacesPane(),
      WorkspaceRightPaneKind.library => HomeLibrarySection(
        view: descriptor.libraryView!,
      ),
    };
  }
}

