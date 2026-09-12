/// Lo que va dentro del QR de VOXON POS: `voxon://pair?p=<vinculación>&t=<token>`.
final class PairingQr {
  const PairingQr(this.pairingId, this.qrToken);

  static final _pairingId = RegExp(r'^[A-Za-z0-9]{10,40}$');
  static final _token = RegExp(r'^[A-Za-z0-9_-]{20,128}$');

  /// El QR leído, o null si no es un QR de vinculación de VOXON.
  static PairingQr? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'voxon' || uri.host != 'pair') {
      return null;
    }
    final pairingId = uri.queryParameters['p'];
    final qrToken = uri.queryParameters['t'];
    if (pairingId == null ||
        qrToken == null ||
        !_pairingId.hasMatch(pairingId) ||
        !_token.hasMatch(qrToken)) {
      return null;
    }
    return PairingQr(pairingId, qrToken);
  }

  final String pairingId;
  final String qrToken;

  String get uri => 'voxon://pair?p=$pairingId&t=$qrToken';
}

/// Solo números, sin espacios: lo que el usuario escribió de un código de 6 números.
String cleanPairingCode(String input) => input.replaceAll(RegExp(r'\D'), '');

/// `482913` → `482 913`, más fácil de leer en voz alta.
String formatPairingCode(String code) =>
    code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
