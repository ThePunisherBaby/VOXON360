// Copia shared/modes.json y shared/plans.json dentro del paquete como texto, para que
// cualquier app (y Dart puro, sin Flutter) tenga los modos y planes sin leer archivos.
//
//   cd packages/voxon_domain && dart run tool/sync_catalogs.dart
//
// La prueba test/catalog_test.dart falla si se olvida correr este comando.
import 'dart:io';

void main() {
  final modes = File('../../shared/modes.json').readAsStringSync();
  final plans = File('../../shared/plans.json').readAsStringSync();
  if (modes.contains("'''") || plans.contains("'''")) {
    stderr.writeln("Los catálogos no pueden contener ''' ");
    exit(1);
  }
  final output = File('lib/src/catalog/catalog_data.g.dart');
  output.writeAsStringSync('''
// Generado por tool/sync_catalogs.dart desde shared/modes.json y shared/plans.json.
// No editar a mano: cambia los JSON y vuelve a correr el comando.

/// Contenido de shared/modes.json.
const modesJson = r\'\'\'
$modes\'\'\';

/// Contenido de shared/plans.json.
const plansJson = r\'\'\'
$plans\'\'\';
''');
  stdout.writeln('Catálogos actualizados en ${output.path}');
}
