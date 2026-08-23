import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/bark_push_settings.dart';
import '../repositories/bark_push_repository.dart';
import '../services/notification/bark_push_dispatcher.dart';
import '../services/notification/bark_push_sender.dart';

/// Result of the last "send a test push" press, held so the settings row can
/// show it until the next attempt.
class BarkTestOutcome extends Equatable {
  const BarkTestOutcome.ok() : failure = null;
  const BarkTestOutcome.failed(this.failure);

  /// The server's own words. Null on success.
  final String? failure;

  bool get ok => failure == null;

  @override
  List<Object?> get props => [failure];
}

class BarkPushState extends Equatable {
  const BarkPushState({
    this.settings = BarkPushSettings.defaults,
    this.deviceKey = '',
    this.loaded = false,
    this.testing = false,
    this.lastTest,
  });

  final BarkPushSettings settings;
  final String deviceKey;

  /// False until the keychain read finishes. The settings page uses it to avoid
  /// rendering an empty key field over a key that is still loading, which the
  /// user would then "correct" by retyping it.
  final bool loaded;

  final bool testing;
  final BarkTestOutcome? lastTest;

  BarkPushState copyWith({
    BarkPushSettings? settings,
    String? deviceKey,
    bool? loaded,
    bool? testing,
    BarkTestOutcome? lastTest,
    bool clearLastTest = false,
  }) => BarkPushState(
    settings: settings ?? this.settings,
    deviceKey: deviceKey ?? this.deviceKey,
    loaded: loaded ?? this.loaded,
    testing: testing ?? this.testing,
    lastTest: clearLastTest ? null : (lastTest ?? this.lastTest),
  );

  @override
  List<Object?> get props => [settings, deviceKey, loaded, testing, lastTest];
}

/// Owns the Bark push channel's settings and the test-push action.
///
/// The dispatcher reads [target] on every notice rather than being handed a
/// snapshot, so editing the key or switching mode takes effect immediately.
class BarkPushCubit extends Cubit<BarkPushState> {
  BarkPushCubit({
    required BarkPushRepository repository,
    required BarkPushSender sender,
    required String Function() testTitle,
    required String Function() testBody,
  }) : _repository = repository,
       _sender = sender,
       _testTitle = testTitle,
       _testBody = testBody,
       super(const BarkPushState());

  final BarkPushRepository _repository;
  final BarkPushSender _sender;
  final String Function() _testTitle;
  final String Function() _testBody;

  Future<void> load() async {
    final settings = await _repository.loadSettings();
    final key = await _repository.loadDeviceKey();
    if (isClosed) return;
    emit(state.copyWith(settings: settings, deviceKey: key, loaded: true));
  }

  /// Live view for [BarkPushDispatcher].
  BarkPushTarget target() => BarkPushTarget(
    mode: state.settings.mode,
    serverUrl: state.settings.normalizedServerUrl,
    deviceKey: state.deviceKey,
  );

  Future<void> setMode(BarkPushMode mode) async {
    final settings = state.settings.copyWith(mode: mode);
    emit(state.copyWith(settings: settings, clearLastTest: true));
    await _repository.saveSettings(settings);
  }

  Future<void> setServerUrl(String url) async {
    final settings = state.settings.copyWith(serverUrl: url);
    emit(state.copyWith(settings: settings, clearLastTest: true));
    await _repository.saveSettings(settings);
  }

  Future<void> setDeviceKey(String key) async {
    emit(state.copyWith(deviceKey: key.trim(), clearLastTest: true));
    await _repository.saveDeviceKey(key);
  }

  /// Sends one push with the values currently in the fields.
  ///
  /// Deliberately ignores [BarkPushSettings.mode] — pressing "test" is an
  /// explicit request, and refusing it because the mode says "only when
  /// disconnected" (with the phone right there, connected) would look broken.
  Future<void> sendTest() async {
    if (state.testing) return;
    emit(state.copyWith(testing: true, clearLastTest: true));
    final result = await _sender.send(
      serverUrl: state.settings.normalizedServerUrl,
      deviceKey: state.deviceKey,
      title: _testTitle(),
      body: _testBody(),
    );
    if (isClosed) return;
    emit(
      state.copyWith(
        testing: false,
        lastTest: result.ok
            ? const BarkTestOutcome.ok()
            : BarkTestOutcome.failed(result.failure ?? ''),
      ),
    );
  }
}
