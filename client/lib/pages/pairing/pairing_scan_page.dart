import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_offer.dart';
import '../../utils/ui/app_keys.dart';

/// QR camera scan (orca `pair-scan`). Falls back to manual `code` / deep-link
/// entry when the camera is denied or the QR won't resolve. On a valid offer it
/// starts the pairing flow and returns the offer to the caller.
class PairingScanPage extends StatefulWidget {
  const PairingScanPage({super.key});

  @override
  State<PairingScanPage> createState() => _PairingScanPageState();
}

class _PairingScanPageState extends State<PairingScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final offer = PairingOffer.tryParse(raw);
      if (offer != null) {
        _accept(offer);
        return;
      }
    }
  }

  void _accept(PairingOffer offer) {
    if (_handled) return;
    _handled = true;
    context.read<PairingClientCubit>().beginPairing(offer);
    Navigator.of(context).pop(offer);
  }

  Future<void> _enterManually() async {
    final offer = await showDialog<PairingOffer>(
      context: context,
      builder: (_) => const _ManualEntryDialog(),
    );
    if (offer != null && mounted) _accept(offer);
  }

  /// Emulators (and phones that can't physically point at the desktop) can pick
  /// a saved screenshot of the QR code from the gallery and decode it offline.
  Future<void> _pickFromAlbum() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final capture = await _controller.analyzeImage(picked.path);
    for (final barcode in capture?.barcodes ?? const []) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final offer = PairingOffer.tryParse(raw);
      if (offer != null) {
        _accept(offer);
        return;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.pairingNoQrInImage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      key: AppKeys.pairingScanPage,
      appBar: AppBar(
        title: Text(l10n.pairingScanToPair),
        actions: [
          IconButton(
            key: AppKeys.pairingScanAlbumButton,
            tooltip: l10n.pairingFromAlbum,
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _pickFromAlbum,
          ),
          TextButton(
            key: AppKeys.pairingScanManualButton,
            onPressed: _enterManually,
            child: Text(l10n.pairingEnterManually),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.pairingPointAtQr,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualEntryDialog extends StatefulWidget {
  const _ManualEntryDialog();

  @override
  State<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<_ManualEntryDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final offer = PairingOffer.tryParse(_controller.text);
    if (offer == null) {
      setState(() => _error = context.l10n.pairingInvalidCode);
      return;
    }
    Navigator.of(context).pop(offer);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.pairingEnterPairingCode),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 6,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          decoration: InputDecoration(
            hintText: l10n.pairingCodeHint,
            errorText: _error,
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.pairingPair)),
      ],
    );
  }
}
