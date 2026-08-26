import 'package:shared_preferences/shared_preferences.dart';

/// Whether the app persists its diagnostic log to disk.
///
/// A bare SharedPreferences key rather than a cubit or a repository, because the
/// file sink is wired up in `main()` *before* `runApp` — earlier than any cubit
/// exists. `SharedPreferences` is already loaded by then, so reading one boolean
/// costs nothing and keeps the startup path short.
///
/// **Off by default.** Logging to disk is opt-in: a phone that is merely running
/// the app should not accumulate diagnostic files it will never be asked for. The
/// cost of that choice is real and worth stating — a crash that happens before
/// anyone flips the switch leaves nothing on disk, which is exactly the
/// white-screen case the on-screen boot diagnostics exist to cover instead.
abstract final class DebugLogSettings {
  static const _key = 'teampilot.debug_file_logging.v1';

  static bool read(SharedPreferences preferences) =>
      preferences.getBool(_key) ?? false;

  static Future<void> write(
    SharedPreferences preferences,
    bool enabled,
  ) => preferences.setBool(_key, enabled);
}
