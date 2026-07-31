import 'dart:convert';

import 'pairing_crypto.dart';

/// The QR payload a desktop shows and a phone scans (also carried by the
/// `teampilot://pair?code=` deep link). Contains everything the client needs to
/// dial and authenticate the first time: the LAN URLs to try, the one-time
/// pairing code, and the host static public key to pin (MITM defence).
class PairingOffer {
  const PairingOffer({
    required this.version,
    required this.wsUrls,
    required this.token,
    required this.hostPublicKeyB64,
    required this.expiresAtMs,
  });

  static const currentVersion = 1;
  static const scheme = 'teampilot';

  final int version;
  final List<String> wsUrls;
  final String token;
  final String hostPublicKeyB64;
  final int expiresAtMs;

  Map<String, Object?> toJson() => {
    'v': version,
    'wsUrls': wsUrls,
    'token': token,
    'pk': hostPublicKeyB64,
    'exp': expiresAtMs,
  };

  /// Compact deep link: `teampilot://pair?code=<base64url(json)>`.
  String toDeepLink() {
    final code = PairingCrypto.b64u(utf8.encode(jsonEncode(toJson())));
    return '$scheme://pair?code=$code';
  }

  /// Parses either a full deep link or a bare `code` payload. Returns null on
  /// any malformed input rather than throwing.
  static PairingOffer? tryParse(String input) {
    final code = extractPairingCodeFromUrl(input) ?? input.trim();
    if (code.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(PairingCrypto.unb64u(code)));
      if (decoded is! Map) return null;
      final token = decoded['token'];
      final pk = decoded['pk'];
      if (token is! String || pk is! String) return null;
      return PairingOffer(
        version: decoded['v'] is int ? decoded['v'] as int : currentVersion,
        wsUrls:
            (decoded['wsUrls'] as List?)?.whereType<String>().toList() ??
            const [],
        token: token,
        hostPublicKeyB64: pk,
        expiresAtMs: decoded['exp'] is int ? decoded['exp'] as int : 0,
      );
    } on Object {
      return null;
    }
  }

  /// Pulls the `code` query parameter out of a `teampilot://pair?code=…` URL.
  /// Returns null when the string is not such a link.
  static String? extractPairingCodeFromUrl(String url) {
    final trimmed = url.trim();
    if (!trimmed.contains('://')) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme != scheme) return null;
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) return null;
    return code;
  }
}

/// Host-side one-time pairing window. Opening starts a TTL during which a single
/// [consume] of the matching code succeeds; a used or expired window is closed.
class PairingOfferWindow {
  PairingOfferWindow({int Function()? clock})
    : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _clock;
  String? _token;
  int _expiresAtMs = 0;

  static const defaultTtl = Duration(minutes: 15);

  /// Opens a fresh window and returns the one-time token to embed in the offer.
  String open({Duration ttl = defaultTtl}) {
    _token = PairingCrypto.randomToken(18);
    _expiresAtMs = _clock() + ttl.inMilliseconds;
    return _token!;
  }

  bool get isOpen => _token != null && _clock() < _expiresAtMs;

  int get expiresAtMs => _expiresAtMs;

  void close() {
    _token = null;
    _expiresAtMs = 0;
  }

  /// Single-use: succeeds only when [token] matches the open window; consuming
  /// closes the window so a replay fails.
  bool consume(String token) {
    if (!isOpen) return false;
    final ok = PairingCrypto.constantTimeEquals(_token!, token);
    if (ok) close();
    return ok;
  }
}
