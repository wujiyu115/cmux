import 'package:pinenacl/x25519.dart';

import 'pairing_crypto.dart';

/// Role-neutral end-to-end encrypted channel over a derived X25519 `Box`.
///
/// Both peers construct the channel from their own ephemeral private key and the
/// other peer's ephemeral public key; NaCl's `Box` derives the same shared
/// secret on each side (ECDH). Every wire frame is `nonce(24) || box`, exactly
/// the byte layout of NaCl's [EncryptedMessage], so [encrypt]/[decrypt] are pure
/// byte transforms with no side channel of framing.
class E2eeChannel {
  E2eeChannel._(this._box);

  /// Derives the channel from an ephemeral↔ephemeral key agreement. The static
  /// host key is verified separately (pinned from the QR offer) — it never keys
  /// the channel, keeping forward secrecy.
  factory E2eeChannel.derive({
    required PrivateKey myEphemeralPrivate,
    required PublicKey theirEphemeralPublic,
  }) => E2eeChannel._(
    Box(
      myPrivateKey: myEphemeralPrivate,
      theirPublicKey: theirEphemeralPublic,
    ),
  );

  final Box _box;

  /// Returns `nonce(24) || ciphertext`. A fresh random nonce per call.
  Uint8List encrypt(Uint8List plaintext) {
    final message = _box.encrypt(plaintext);
    return Uint8List.fromList(message);
  }

  /// Inverse of [encrypt]. Throws when the frame is truncated, tampered, or
  /// keyed by a different shared secret (NaCl authenticator failure).
  Uint8List decrypt(Uint8List wire) {
    if (wire.length < EncryptedMessage.nonceLength) {
      throw const FormatException('e2ee frame shorter than nonce');
    }
    return _box.decrypt(EncryptedMessage.fromList(wire));
  }

  /// Convenience: a throwaway ephemeral keypair for one connection.
  static PairingKeyPair newEphemeral() => PairingKeyPair.generate();
}
