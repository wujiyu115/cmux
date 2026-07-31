import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/connection_mode.dart';

ConnectionMode defaultConnectionMode() {
  if (Platform.isAndroid) return ConnectionMode.ssh;
  return ConnectionMode.localPty;
}

/// Hosts a real desktop window, so `window_manager` is available. False on
/// Android and iOS, where the plugin is not registered and every call would
/// throw [MissingPluginException].
bool get hasDesktopWindow =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Linux / Windows / macOS window chrome; false on Android and iOS.
bool get useCustomDesktopWindowTitleBar => hasDesktopWindow;

/// Desktop hosts the pairing LAN server (shows QR, mirrors its own sessions).
bool get isPairingHost =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Mobile is a pure pairing/mirror client (scans QR, never binds a server).
bool get isPairingClient => Platform.isAndroid || Platform.isIOS;

/// macOS uses left-aligned traffic-light window controls instead of the
/// Windows-style buttons on the right.
bool get useMacWindowChromeStyle =>
    useCustomDesktopWindowTitleBar && Platform.isMacOS;

@Deprecated('Use ConnectionModeService.requiresSshProfileSetup')
bool get requiresSshProfile => Platform.isAndroid;

/// Hub landing + pushed section pages instead of a side-by-side workspace shell.
bool useAndroidHubNavigation(BuildContext context) => Platform.isAndroid;

/// Closes the root [Scaffold] drawer after a sidebar navigation action.
void closeAndroidDrawerIfOpen(BuildContext context) {
  if (!Platform.isAndroid) return;
  final scaffold = Scaffold.maybeOf(context);
  if (scaffold != null && scaffold.isDrawerOpen) {
    scaffold.closeDrawer();
  }
}

/// [GoRouter.go] from the navigation drawer and dismiss it on Android.
void goFromSidebar(BuildContext context, String path) {
  closeAndroidDrawerIfOpen(context);
  context.go(path);
}

/// Hub section navigation: push on Android hub flow, go on desktop split shell.
void navigateWorkspaceRoute(BuildContext context, String path) {
  if (useAndroidHubNavigation(context)) {
    context.push(path);
  } else {
    context.go(path);
  }
}

@Deprecated('Use useAndroidHubNavigation')
bool useAndroidConfigNavigation(BuildContext context) =>
    useAndroidHubNavigation(context);
