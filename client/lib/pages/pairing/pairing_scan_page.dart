import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_offer.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
import 'pairing_manual_entry_sheet.dart';
import 'pairing_nav_bar.dart';
import 'pairing_scan_overlay.dart';

/// QR camera scan. Falls back to manual `code` / deep-link entry when the camera
/// is denied or the QR won't resolve. On a valid offer it starts the pairing flow
/// and returns the offer to the caller.
class PairingScanPage extends StatefulWidget {
  const PairingScanPage({super.key});

  @override
  State<PairingScanPage> createState() => _PairingScanPageState();
}

class _PairingScanPageState extends State<PairingScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  /// True while the manual-entry sheet is open, so a background frame can't
  /// decode a code and navigate out from under the user's typing.
  bool _manualOpen = false;

  /// Latches the success reticle between decoding and the pop.
  bool _hit = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || _manualOpen) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final offer = PairingOffer.tryParse(raw);
      if (offer != null) {
        setState(() => _hit = true);
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
    setState(() => _manualOpen = true);
    final offer = await showPairingManualEntrySheet(context);
    if (!mounted) return;
    setState(() => _manualOpen = false);
    if (offer != null) _accept(offer);
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
      AppToast.show(context, message: context.l10n.pairingNoQrInImage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      key: AppKeys.pairingScanPage,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PairingNavBar(
              title: l10n.pairingScanToPair,
              onBack: () => Navigator.of(context).pop(),
              trailing: PairingNavAction(
                key: AppKeys.pairingScanAlbumButton,
                icon: Icons.photo_library_outlined,
                tooltip: l10n.pairingFromAlbum,
                onTap: _pickFromAlbum,
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(controller: _controller, onDetect: _onDetect),
                  PairingScanReticle(hit: _hit),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: PairingScanSheet(
                      hint: l10n.pairingPointAtQr,
                      manualLabel: l10n.pairingEnterManually,
                      manualButtonKey: AppKeys.pairingScanManualButton,
                      onManualEntry: _enterManually,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
