// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'VOXON90';

  @override
  String get navHome => 'Inicio';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get homeTitle => 'Bienvenido a VOXON90';

  @override
  String get homeSubtitle =>
      'La base del proyecto está lista. Aquí se construirán las funciones de la aplicación.';

  @override
  String get homeEnvironment => 'Entorno';

  @override
  String get homePlatform => 'Plataforma';

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get languageSystem => 'Sistema';

  @override
  String get notFoundTitle => 'Página no encontrada';

  @override
  String get notFoundAction => 'Volver al inicio';

  @override
  String get connectTitle => 'Conectar con la caja principal';

  @override
  String get connectSubtitle =>
      'Busca el equipo donde corre VOXON90 en el WiFi del negocio. No se necesita internet.';

  @override
  String get connectSearching => 'Buscando en la red…';

  @override
  String get connectSearchAgain => 'Buscar de nuevo';

  @override
  String get connectNoneFound =>
      'No se encontró ninguna caja principal. Revisa que esté encendida y en el mismo WiFi.';

  @override
  String get connectManualLabel => 'Dirección (IP o IP:puerto)';

  @override
  String get connectManualAction => 'Conectar';

  @override
  String get connectInvalidAddress =>
      'Escribe una dirección válida, por ejemplo 192.168.1.10';

  @override
  String get connectUnnamedBusiness => 'Negocio sin configurar';

  @override
  String get loginTitle => 'Entra con tu PIN';

  @override
  String get loginAction => 'Entrar';

  @override
  String get loginDelete => 'Borrar';

  @override
  String get loginPinLength => 'El PIN tiene de 4 a 6 dígitos';

  @override
  String get loginChangeServer => 'Cambiar de caja principal';

  @override
  String get setupTitle => 'Configura tu negocio';

  @override
  String get setupSubtitle =>
      'Todo se guarda en la caja principal, sin internet.';

  @override
  String get setupBusinessName => 'Nombre del negocio';

  @override
  String get setupBusinessType => 'Tipo de negocio';

  @override
  String get businessTypeColmado => 'Colmado';

  @override
  String get businessTypeStore => 'Tienda';

  @override
  String get businessTypeRestaurant => 'Restaurante';

  @override
  String get setupRnc => 'RNC o cédula (opcional)';

  @override
  String get setupOwnerSection => 'Dueño';

  @override
  String get setupOwnerName => 'Tu nombre';

  @override
  String get setupOwnerPin => 'PIN de 4 a 6 dígitos';

  @override
  String get setupAction => 'Guardar y empezar';

  @override
  String get fieldRequired => 'Este campo es obligatorio';

  @override
  String get offlineTitle => 'Sin conexión con la caja principal';

  @override
  String get retry => 'Reintentar';

  @override
  String get navSell => 'Vender';

  @override
  String get navTables => 'Mesas';

  @override
  String get navKitchen => 'Cocina';

  @override
  String get navSummary => 'Resumen';

  @override
  String get logout => 'Salir';

  @override
  String get sessionExpired => 'Tu sesión terminó. Entra de nuevo con tu PIN.';

  @override
  String get settingsServer => 'Caja principal';

  @override
  String get settingsSession => 'Sesión';

  @override
  String get roleOwner => 'Dueño';

  @override
  String get roleManager => 'Gerente';

  @override
  String get roleCashier => 'Cajero';

  @override
  String get roleWaiter => 'Mesero';

  @override
  String get roleKitchen => 'Cocina';

  @override
  String get loading => 'Cargando…';

  @override
  String get invalidAmount => 'Monto inválido';

  @override
  String get sellSearchHint => 'Buscar producto o escanear código';

  @override
  String get sellNoProducts => 'No hay productos que coincidan';

  @override
  String get sellCurrentSale => 'Venta actual';

  @override
  String get sellEmptyCart => 'Agrega productos para vender';

  @override
  String get sellProductsTab => 'Productos';

  @override
  String sellSaleTab(int count) {
    return 'Venta ($count)';
  }

  @override
  String sellStockLeft(String quantity) {
    return 'Quedan $quantity';
  }

  @override
  String get sellSubtotal => 'Subtotal';

  @override
  String get sellTax => 'ITBIS';

  @override
  String get sellTip => 'Propina legal';

  @override
  String get sellTotal => 'Total';

  @override
  String get sellRemove => 'Quitar';

  @override
  String get sellWholeUnits => 'Este producto se vende por unidades enteras';

  @override
  String get sellInvalidQuantity => 'Cantidad inválida';

  @override
  String get paymentCash => 'Efectivo';

  @override
  String get paymentCard => 'Tarjeta';

  @override
  String get paymentTransfer => 'Transferencia';

  @override
  String get paymentCredit => 'Fiao';

  @override
  String get sellReceived => 'Efectivo recibido';

  @override
  String sellChange(String amount) {
    return 'Devuelta: $amount';
  }

  @override
  String sellMissing(String amount) {
    return 'Faltan $amount';
  }

  @override
  String sellCharge(String amount) {
    return 'Cobrar $amount';
  }

  @override
  String sellCharged(int number) {
    return 'Venta #$number cobrada';
  }

  @override
  String get sellNewSale => 'Nueva venta';

  @override
  String get sellInsufficientCash => 'El efectivo recibido no cubre el total';

  @override
  String get sellCustomerSearch => 'Buscar cliente por nombre o teléfono';

  @override
  String get sellChooseCustomer => 'Elige el cliente del fiao';

  @override
  String sellCreditTo(String name, String amount) {
    return 'Fiao a $name · disponible $amount';
  }

  @override
  String get sellChangeCustomer => 'Cambiar';

  @override
  String get cashOpenTitle => 'Abrir caja';

  @override
  String get cashOpenHint => '¿Con cuánto efectivo empiezas?';

  @override
  String summaryTitle(String day) {
    return 'Resumen del $day';
  }

  @override
  String get summarySales => 'Ventas';

  @override
  String summaryTickets(int count, String amount) {
    return '$count tickets · promedio $amount';
  }

  @override
  String get summaryTaxCollected => 'ITBIS cobrado';

  @override
  String get summaryReceivables => 'Fiao por cobrar';

  @override
  String get summaryVoided => 'Anuladas';

  @override
  String get summaryOpenOrders => 'Órdenes abiertas';

  @override
  String get summaryTopProducts => 'Lo más vendido hoy';

  @override
  String get summaryNoSales => 'Todavía no hay ventas hoy';

  @override
  String get summaryLowStock => 'Bajo el mínimo';

  @override
  String get summaryStockOk => 'Inventario en orden';

  @override
  String get summaryDebtors => 'Clientes que deben';

  @override
  String get summaryNoDebtors => 'Nadie debe';

  @override
  String get summaryPayments => 'Cobros de hoy';

  @override
  String get summaryRegister => 'Caja';

  @override
  String get cashClosedHint => 'La caja está cerrada. Se abre desde Vender.';

  @override
  String cashExpected(String amount) {
    return 'Debe haber $amount en efectivo';
  }

  @override
  String get cashCounted => 'Efectivo contado';

  @override
  String get cashCloseAction => 'Cerrar caja';

  @override
  String get cashClosedExact => 'Caja cerrada: cuadró exacto';

  @override
  String cashClosedDifference(String amount) {
    return 'Caja cerrada con diferencia de $amount';
  }

  @override
  String get backupAction => 'Hacer respaldo';

  @override
  String backupDone(String path) {
    return 'Respaldo guardado en $path';
  }

  @override
  String get kitchenAll => 'Todo';

  @override
  String get kitchenStationKitchen => 'Cocina';

  @override
  String get kitchenStationBar => 'Bar';

  @override
  String get kitchenEmpty => 'No hay nada pendiente. ¡Todo al día!';

  @override
  String kitchenMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get statusPending => 'Sin enviar';

  @override
  String get statusSent => 'Nuevo';

  @override
  String get statusPreparing => 'Preparando';

  @override
  String get statusReady => 'Listo';

  @override
  String get statusServed => 'Servido';

  @override
  String get statusCancelled => 'Cancelado';

  @override
  String get orderTakeout => 'Para llevar';

  @override
  String get orderDelivery => 'Delivery';

  @override
  String get tablesFree => 'Libre';

  @override
  String tablesOrder(int number, String waiter) {
    return 'Orden #$number · $waiter';
  }

  @override
  String tablesItems(int count, String amount) {
    return '$count productos · $amount';
  }

  @override
  String get tablesEmpty => 'No hay mesas registradas';

  @override
  String get tablesAdd => 'Agregar mesa';

  @override
  String get tablesNewName => 'Nombre de la mesa';

  @override
  String get tablesOtherOrders => 'Para llevar y delivery';

  @override
  String get tablesSelectHint => 'Toca una mesa para ver o abrir su orden';

  @override
  String get orderAddProduct => 'Agregar producto';

  @override
  String get orderAddProductsHint => 'Busca y agrega productos';

  @override
  String orderServedBy(String name) {
    return 'Atiende $name';
  }

  @override
  String orderSend(int count) {
    return 'Enviar $count a cocina';
  }

  @override
  String get orderNothingToSend => 'Nada por enviar';

  @override
  String get orderSent => 'Comanda enviada';

  @override
  String get orderBill => 'Cuenta';

  @override
  String get orderCharge => 'Cobrar cuenta';

  @override
  String orderCharged(String amount) {
    return 'Cuenta cobrada: $amount';
  }

  @override
  String get settingsCloud => 'App del dueño';

  @override
  String get cloudNotConfigured =>
      'Esta caja arrancó sin Firebase. Para ver tus datos en el celular, inicia el servidor con --firebase-project y --firebase-api-key.';

  @override
  String get cloudLinkHint =>
      'En la app VOXON90 Dueño toca «Vincular caja» y escribe aquí el código que aparece.';

  @override
  String get cloudCodeLabel => 'Código de vínculo';

  @override
  String get cloudLinkAction => 'Vincular';

  @override
  String get cloudUnlinkAction => 'Desvincular';

  @override
  String get cloudLinked => 'Vinculada con la app del dueño';

  @override
  String cloudStateOk(String time) {
    return 'Datos al día · $time';
  }

  @override
  String get cloudStatePending => 'Pendiente de subir';

  @override
  String get cloudStateOffline =>
      'Sin internet: se sube cuando vuelva la conexión';
}
