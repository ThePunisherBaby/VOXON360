import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:voxon_data/voxon_data.dart';

/// Cámara del celular apuntando al QR que muestra VOXON POS.
class ScanPairingScreen extends StatefulWidget {
  const ScanPairingScreen({
    super.key,
    required this.instanceId,
    required this.onQr,
  });

  final String instanceId;

  /// Se llama una sola vez con el primer QR de vinculación válido.
  final ValueChanged<PairingQr> onQr;

  @override
  State<ScanPairingScreen> createState() => _ScanPairingScreenState();
}

class _ScanPairingScreenState extends State<ScanPairingScreen> {
  bool _handled = false;
  String? _message;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final qr = PairingQr.tryParse(barcode.rawValue ?? '');
      if (qr != null) {
        _handled = true;
        widget.onQr(qr);
        return;
      }
    }
    if (capture.barcodes.isNotEmpty) {
      setState(() => _message = 'Ese QR no es de una caja VOXON POS');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanea el QR de la caja')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(20),
              child: Text(
                _message ?? 'Apunta la cámara al código QR que muestra la caja',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
