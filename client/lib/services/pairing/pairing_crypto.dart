import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:pinenacl/x25519.dart';

/// X25519 identity keypair for the pairing handshake.
///
/// The desktop host holds one persisted *static* keypair (pinned by the mobile
/// client from the QR offer). Each connection additionally derives a throwaway
/// *ephemeral* keypair for forward secrecy — [PairingKeyPair.generate] serves
/// both cases.
class PairingKeyPair {
  const PairingKeyPair(this.privateKey);

  factory PairingKeyPair.generate() => PairingKeyPair(PrivateKey.generate());

  /// Rebuilds a keypair from persisted 32-byte private-key material.
  factory PairingKeyPair.fromPrivateBytes(Uint8List bytes) =>
      PairingKeyPair(PrivateKey(bytes));

  final PrivateKey privateKey;

  PublicKey get publicKey => privateKey.publicKey;

  Uint8List get privateBytes => Uint8List.fromList(privateKey);
  Uint8List get publicBytes => Uint8List.fromList(publicKey);

  String get publicKeyB64 => PairingCrypto.b64u(publicBytes);
  String get privateKeyB64 => PairingCrypto.b64u(privateBytes);
}

/// Small crypto helpers shared across the pairing stack: base64url without
/// padding, cryptographically-strong random material, and hashing.
class PairingCrypto {
  const PairingCrypto._();

  /// Padding-free base64url — compact and safe inside a `teampilot://` URL.
  static String b64u(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List unb64u(String s) {
    final pad = (4 - s.length % 4) % 4;
    return base64Url.decode(s + '=' * pad);
  }

  static Uint8List randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => rng.nextInt(256)));
  }

  /// Lowercase hex token (`n` bytes of entropy) for one-time pairing codes and
  /// device/resume secrets. Mirrors `AgentStatusGateway._randomStatusToken`.
  static String randomToken([int n = 24]) {
    final rng = Random.secure();
    return List<String>.generate(
      n,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static PublicKey publicKeyFromB64(String s) => PublicKey(unb64u(s));

  static String sha256Hex(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  /// Constant-time comparison so token validation cannot be timed.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var mismatch = 0;
    for (var i = 0; i < a.length; i++) {
      mismatch |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return mismatch == 0;
  }
}
