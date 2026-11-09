import 'package:flutter/material.dart';

/// Tablet adaptation for the pairing client — iPad and Android large screens
/// (tablets, foldables, ChromeOS, and either platform in split-screen).
///
/// The pairing UI is a 1:1 port of a 393-logical-px phone prototype, and its
/// navigation is *stateful in a way that only makes sense on a phone*: the shell
/// swaps the whole screen between the workspace list and the mirror
/// (`PairingClientPhase.connected` ↔ `mirroring`), so opening a terminal throws
/// the list away and going back rebuilds it collapsed at the top. On a phone
/// that is the right trade — there is no room for both. On a 1024–1366pt iPad it
/// is pure waste: the list is a sidebar, and only the right pane should swap.
///
/// Nothing here branches on `Platform`, on purpose: the phone/tablet split is a
/// size question, and an Android tablet must get exactly what an iPad gets.
/// Everything tablet-specific lives here so the breakpoint and the caps are one
/// decision instead of scattered magic numbers.
abstract final class PairingTabletLayout {
  /// Material's tablet breakpoint, applied to the window's *shortest* side.
  ///
  /// Shortest side rather than width: a phone in landscape is 844–932 wide, and
  /// taking the two-pane shell there would squeeze a 430pt-tall terminal into a
  /// column beside a list — it would pass a width test and fail the height one.
  /// A full-screen tablet is ≥ 600 on its shortest side whichever way it is held
  /// (iPad ≥ 744, Android 7" ≈ 600, foldable inner screens ≈ 670), and a
  /// split-screen pane narrower than this correctly falls back to the phone stack
  /// instead of cramming two panes into a phone-sized window.
  static const double tabletShortestSide = 600;

  /// Fixed sidebar width of the two-pane workspace shell: wide enough for a
  /// workspace title plus the trailing count, narrow enough that an iPad mini in
  /// portrait (744) still gives the terminal the majority of the screen.
  static const double sidebarWidth = 336;

  /// Floor for [sidebarWidth] as a share of the window ([sidebarShare]).
  ///
  /// Only reachable while a mirror is open and the window shrinks back under the
  /// breakpoint: the shell deliberately does *not* swap to the phone stack then
  /// (see `_PairingMobileShellState._useTwoPane` — the swap would re-parent the
  /// mirror and blank its engine), so the two panes have to fit a window that is
  /// no longer tablet-sized instead.
  static const double sidebarMinWidth = 220;

  /// Sidebar as a fraction of the window in that pinned case, so the terminal is
  /// never left with a sliver.
  static const double sidebarShare = 0.42;

  /// Sidebar width for the current window: [sidebarWidth] on a real tablet, and
  /// a share of the width when a pinned shell is squeezed under the breakpoint.
  static double sidebarWidthFor(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return (width * sidebarShare).clamp(sidebarMinWidth, sidebarWidth);
  }

  /// Single-column surfaces (the hosts feed and its settings tab) cap their
  /// content instead of stretching a 15pt row across 1366pt, where the eye has
  /// to travel the full width to read one line.
  static const double readableContentMaxWidth = 720;

  /// Bottom sheets are phone furniture — 20px top corners, one row per option.
  /// Uncapped, a 1366pt sheet reads as a toolbar across the bottom of the
  /// screen, so on a tablet they are capped and centred instead.
  static const double sheetMaxWidth = 560;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= tabletShortestSide;

  /// `maxWidth` for a pairing sheet: the window width on a phone (equivalent to
  /// no cap, which is what the phone layout assumes) and [sheetMaxWidth] on a
  /// tablet, where [showModalBottomSheet] then centres the sheet for us.
  static double sheetMaxWidthFor(BuildContext context) =>
      isTablet(context) ? sheetMaxWidth : MediaQuery.sizeOf(context).width;
}

/// Caps a single-column page's width on a tablet and centres it, leaving phone
/// layout untouched.
///
/// A no-op below the [PairingTabletLayout.tabletShortestSide] breakpoint, so the
/// phone prototype's measurements still hold pixel for pixel.
class PairingTabletReadableContent extends StatelessWidget {
  const PairingTabletReadableContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!PairingTabletLayout.isTablet(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: PairingTabletLayout.readableContentMaxWidth,
        ),
        child: child,
      ),
    );
  }
}
