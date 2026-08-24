library;

import 'package:flutter/widgets.dart';

/// Last-resort failure UI: paints the error as plain text with **no** theme, no
/// localization, no bundled font, and no Material.
///
/// Exists because the rich [showInitErrorApp] can itself fail — it awaits a
/// theme, resolves l10n delegates, and reads package info, any of which is
/// unavailable in exactly the early-startup failures it is meant to report. When
/// that happens the app shows nothing at all.
///
/// "Nothing at all" is not hypothetical: on iOS there is no native splash
/// (`flutter_native_splash: ios: false`), no reachable log file on a
/// non-jailbroken device, and a release build renders a *blank* box for an
/// uncaught build error rather than the debug red screen. A white rectangle was
/// the entire diagnostic surface. Everything here is deliberately primitive so
/// that it cannot become a second white screen.

/// Colours are literals, not theme lookups: a theme is one of the things that
/// may have failed to load.
const _background = Color(0xFF1A0F0F);
const _foreground = Color(0xFFFFD5D5);
const _accent = Color(0xFFFF6B6B);

/// Replaces the whole app with [title] and [detail] as scrollable text.
void showFatalTextApp({required String title, required String detail}) {
  runApp(_FatalTextApp(title: title, detail: detail));
}

/// Widget shown in place of any subtree whose build threw.
///
/// Release builds normally render `ErrorWidget` as an empty grey box with no
/// text, which is indistinguishable from a hung app. Wiring this into
/// [ErrorWidget.builder] makes a release build say what broke.
Widget buildFatalErrorWidget(FlutterErrorDetails details) =>
    _FatalText(title: 'Render error', detail: details.exceptionAsString());

class _FatalTextApp extends StatelessWidget {
  const _FatalTextApp({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) =>
      _FatalText(title: title, detail: detail);
}

class _FatalText extends StatelessWidget {
  const _FatalText({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    // Directionality and MediaQuery are supplied explicitly: this may render
    // outside any WidgetsApp, where neither is inherited.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery.fromView(
        view: View.of(context),
        child: ColoredBox(
          color: _background,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _accent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      detail,
                      // No fontFamily on purpose — naming a bundled or generic
                      // family is another way to render nothing.
                      style: const TextStyle(color: _foreground, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
