import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../repositories/voice_input_repository.dart';
import '../services/stt/stt_provider.dart';
import '../utils/logging/logger_utils.dart';

/// Where a recognition session is in its lifecycle.
///
/// [starting] covers the window where a cloud backend is minting a token and
/// finishing its handshake — the mic button shows a spinner rather than an idle
/// tap that reads as unresponsive.
enum VoiceInputStatus { idle, starting, listening }

/// A recognition failure, mapped to localized copy by the UI (Task 9). Kept an
/// enum so no user-facing string lives in the cubit.
enum VoiceInputFailure { permissionDenied, failed }

/// The persisted voice-input settings plus the live session status.
///
/// No `==`: a `status` change should always rebuild the mic button, so every
/// emit is a distinct instance. Widgets that only care about settings must use
/// `buildWhen` (see Task 9).
@immutable
class VoiceInputState {
  const VoiceInputState({
    required this.provider,
    required this.localeId,
    required this.status,
    required this.credentials,
    required this.systemAvailable,
  });

  final SttProviderType provider;

  /// The pinned recognition-language id, or `''` to let the backend pick.
  final String localeId;

  final VoiceInputStatus status;

  /// The cloud credentials, so [configured] derives without a reload.
  final VoiceCredentials credentials;

  /// Whether the on-device recognizer initialized. Probed once in [load].
  final bool systemAvailable;

  /// Whether the chosen backend has everything it needs to run right now.
  ///
  /// Derived, never stored, so it cannot drift from its source data.
  bool get configured => provider == SttProviderType.system
      ? systemAvailable
      : credentials.hasFor(provider);

  /// Whether any backend could run — drives whether the mic button shows at
  /// all. Derived for the same reason as [configured].
  bool get available =>
      systemAvailable || credentials.hasVolcengine || credentials.hasAliyun;

  VoiceInputState copyWith({
    SttProviderType? provider,
    String? localeId,
    VoiceInputStatus? status,
    VoiceCredentials? credentials,
    bool? systemAvailable,
  }) => VoiceInputState(
    provider: provider ?? this.provider,
    localeId: localeId ?? this.localeId,
    status: status ?? this.status,
    credentials: credentials ?? this.credentials,
    systemAvailable: systemAvailable ?? this.systemAvailable,
  );
}

/// Orchestrates one recognition session at a time and owns the persisted
/// voice-input settings.
///
/// Recognized text and failures leave as broadcast streams rather than state:
/// both are one-shot events (text is inserted into a `TextEditingController`, a
/// failure raises a snackbar), and putting them in state would re-emit on every
/// word. A constructor callback would force this cubit to be created only after
/// its consumers exist, but it lives at the pairing-shell level and outlives
/// both the mirror page and the composer — a stream lets consumers subscribe on
/// their own schedule.
class VoiceInputCubit extends Cubit<VoiceInputState> {
  VoiceInputCubit({
    required VoiceInputRepository repository,
    required SttProvider Function(SttProviderType type, VoiceCredentials creds)
        providerFactory,
    Duration maxDuration = const Duration(seconds: 60),
  })  : _repository = repository,
        _providerFactory = providerFactory,
        _maxDuration = maxDuration,
        super(
          const VoiceInputState(
            provider: SttProviderType.system,
            localeId: '',
            status: VoiceInputStatus.idle,
            credentials: VoiceCredentials.empty,
            systemAvailable: false,
          ),
        );

  final VoiceInputRepository _repository;
  final SttProvider Function(SttProviderType type, VoiceCredentials creds)
      _providerFactory;

  /// A microphone left open is metered cloud spend and an open privacy hole,
  /// and nothing dictated into a terminal runs a minute. A constructor
  /// parameter so the timer test can drive it under `fake_async`.
  final Duration _maxDuration;

  final _transcripts = StreamController<String>.broadcast();
  final _failures = StreamController<VoiceInputFailure>.broadcast();

  /// Final recognized sentences, ready to insert into the composer.
  Stream<String> get transcripts => _transcripts.stream;

  /// One event per recognition failure, mapped to copy by the UI.
  Stream<VoiceInputFailure> get failures => _failures.stream;

  // The current session. All null between sessions; set together in
  // [startListening] and cleared together in [_teardown] / [stopListening].
  SttProvider? _provider;
  StreamSubscription<SttResult>? _subscription;
  Timer? _capTimer;

  /// The most recent interim result, kept as a fallback for an utterance that
  /// ends before the backend settles a final.
  String? _lastPartial;

  /// Whether a final has already reached the composer this session. Guards the
  /// fallback so a stale interim is never re-inserted after a final.
  bool _insertedFinal = false;

  /// Loads persisted settings and probes on-device availability.
  Future<void> load() async {
    final prefs = await _repository.loadPrefs();
    if (isClosed) return;
    final credentials = await _repository.loadCredentials();
    if (isClosed) return;

    // Probe the system recognizer with a throwaway provider, then dispose it so
    // nothing lingers holding the mic.
    final probe = _providerFactory(SttProviderType.system, credentials);
    final systemAvailable = await probe.isAvailable();
    probe.dispose();
    if (isClosed) return;

    emit(
      state.copyWith(
        provider: prefs.provider,
        localeId: prefs.localeId,
        status: VoiceInputStatus.idle,
        credentials: credentials,
        systemAvailable: systemAvailable,
      ),
    );
  }

  /// Opens a recognition session. A no-op if one is already running, or if the
  /// selected backend is not [configured] — an unconfigured backend must not
  /// open a session (a cloud backend with no credentials would dial a socket
  /// with an empty app id and fail opaquely). Routing an unconfigured tap to the
  /// settings page is the UI's job — a cubit must not know about `Navigator`.
  Future<void> startListening() async {
    if (state.status != VoiceInputStatus.idle) return;
    if (!state.configured) return;

    emit(state.copyWith(status: VoiceInputStatus.starting));

    final provider = _providerFactory(state.provider, state.credentials);
    _provider = provider;
    _lastPartial = null;
    _insertedFinal = false;

    final localeId = state.localeId.isEmpty ? null : state.localeId;
    _subscription = provider.start(localeId: localeId).listen(
      _onResult,
      onError: _finishWithFailure,
      onDone: _finishNaturally,
    );

    // `ready` resolves false rather than throwing, so this never needs a catch;
    // real errors arrive on the stream instead.
    final ready = await provider.ready;
    if (!ready) {
      _teardown();
      if (isClosed) return;
      emit(state.copyWith(status: VoiceInputStatus.idle));
      return;
    }
    if (isClosed) {
      _teardown();
      return;
    }
    emit(state.copyWith(status: VoiceInputStatus.listening));
    _capTimer = Timer(_maxDuration, stopListening);
  }

  void _onResult(SttResult result) {
    if (result.isFinal) {
      _transcripts.add(result.text);
      _insertedFinal = true;
      _lastPartial = null;
    } else {
      _lastPartial = result.text;
    }
  }

  /// The backend closed the session on its own. If no final ever landed, insert
  /// the last interim so a short utterance is not lost; once a final has been
  /// sent, the interim was cleared and nothing stale is re-inserted.
  Future<void> _finishNaturally() async {
    if (_provider == null) return;
    if (!_insertedFinal) {
      final partial = _lastPartial;
      if (partial != null && partial.isNotEmpty) _transcripts.add(partial);
    }
    _teardown();
    if (isClosed) return;
    emit(state.copyWith(status: VoiceInputStatus.idle));
  }

  /// A stream error: tear the session down *before* emitting idle, so the UI
  /// cannot allow another tap while the previous provider is still alive.
  Future<void> _finishWithFailure(Object error, StackTrace stackTrace) async {
    if (_provider == null) return;
    _failures.add(
      error is VoicePermissionDeniedException
          ? VoiceInputFailure.permissionDenied
          : VoiceInputFailure.failed,
    );
    AppLogger.instance.w(
      'Voice input failed ($error)',
      error: error,
      stackTrace: stackTrace,
    );
    _teardown();
    if (isClosed) return;
    emit(state.copyWith(status: VoiceInputStatus.idle));
  }

  /// Cancels the subscription and disposes the provider. Does not call
  /// `stop()` — the session is already ending (done, errored, or never ready),
  /// so there is nothing left to gracefully close.
  ///
  /// The subscription cancel is issued unawaited: cancelling a subscription
  /// whose broadcast stream has already closed never completes under
  /// `fake_async`, and awaiting it would hang. Nothing depends on the cancel
  /// having finished — [_provider] is already the null that gates re-entry.
  void _teardown() {
    _capTimer?.cancel();
    _capTimer = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final provider = _provider;
    _provider = null;
    provider?.dispose();
    _lastPartial = null;
    _insertedFinal = false;
  }

  /// Stops a running session gracefully. Idempotent — safe to call when idle.
  ///
  /// Calls `stop()` (which closes the stream) *before* cancelling the
  /// subscription: cancelling first and then closing a broadcast stream never
  /// completes under `fake_async`, which would hang the cap-timer path. Nulling
  /// [_provider] up front makes the `onDone` that closing triggers a no-op in
  /// [_finishNaturally], so the stream close does not double-emit.
  Future<void> stopListening() async {
    final provider = _provider;
    if (provider == null) return;
    final subscription = _subscription;
    _provider = null;
    _capTimer?.cancel();
    _capTimer = null;
    _lastPartial = null;
    _insertedFinal = false;
    await provider.stop();
    // Unawaited: cancelling a subscription whose broadcast stream `stop()` just
    // closed never completes under `fake_async` (see [_teardown]).
    if (subscription != null) unawaited(subscription.cancel());
    _subscription = null;
    provider.dispose();
    if (isClosed) return;
    emit(state.copyWith(status: VoiceInputStatus.idle));
  }

  /// Switches the backend, stopping any in-flight session first so the old
  /// socket cannot keep streaming audio the user thinks they redirected.
  Future<void> setProvider(SttProviderType type) async {
    await stopListening();
    if (isClosed) return;
    emit(state.copyWith(provider: type));
    await _repository.savePrefs(
      VoiceInputPrefs(provider: type, localeId: state.localeId),
    );
  }

  /// Pins the recognition language, stopping any in-flight session first.
  Future<void> setLocaleId(String localeId) async {
    await stopListening();
    if (isClosed) return;
    emit(state.copyWith(localeId: localeId));
    await _repository.savePrefs(
      VoiceInputPrefs(provider: state.provider, localeId: localeId),
    );
  }

  /// Persists one credential field and folds it into live state so [configured]
  /// updates without a reload.
  Future<void> setCredential(VoiceCredentialField field, String value) async {
    await _repository.saveCredential(field, value);
    if (isClosed) return;
    emit(
      state.copyWith(credentials: state.credentials.withField(field, value)),
    );
  }

  /// Round-trip milliseconds to a working session for the current backend.
  /// Builds a throwaway provider and disposes it; leaves [state] untouched.
  Future<int> testConnection() async {
    final provider = _providerFactory(state.provider, state.credentials);
    try {
      return await provider.testConnection();
    } finally {
      provider.dispose();
    }
  }

  @override
  Future<void> close() async {
    try {
      // Only awaits the stop this call issues. A stop started inside the cap
      // timer's callback runs in that timer's zone, and a widget test's fake
      // clock stops advancing once the test body ends — awaiting such a future
      // from close() would deadlock until the test timeout. By the time close()
      // runs after the cap fires, the session is already torn down and this is
      // a no-op.
      await stopListening();
    } finally {
      await _transcripts.close();
      await _failures.close();
      await super.close();
    }
  }
}
