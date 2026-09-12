import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// Nombre visible de la aplicación.
  ///
  /// In es, this message translates to:
  /// **'VOXON90'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In es, this message translates to:
  /// **'Inicio'**
  String get navHome;

  /// No description provided for @navSettings.
  ///
  /// In es, this message translates to:
  /// **'Ajustes'**
  String get navSettings;

  /// No description provided for @homeTitle.
  ///
  /// In es, this message translates to:
  /// **'Bienvenido a VOXON90'**
  String get homeTitle;

  /// No description provided for @homeSubtitle.
  ///
  /// In es, this message translates to:
  /// **'La base del proyecto está lista. Aquí se construirán las funciones de la aplicación.'**
  String get homeSubtitle;

  /// No description provided for @homeEnvironment.
  ///
  /// In es, this message translates to:
  /// **'Entorno'**
  String get homeEnvironment;

  /// No description provided for @homePlatform.
  ///
  /// In es, this message translates to:
  /// **'Plataforma'**
  String get homePlatform;

  /// No description provided for @settingsAppearance.
  ///
  /// In es, this message translates to:
  /// **'Apariencia'**
  String get settingsAppearance;

  /// No description provided for @settingsLanguage.
  ///
  /// In es, this message translates to:
  /// **'Idioma'**
  String get settingsLanguage;

  /// No description provided for @themeSystem.
  ///
  /// In es, this message translates to:
  /// **'Sistema'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In es, this message translates to:
  /// **'Claro'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In es, this message translates to:
  /// **'Oscuro'**
  String get themeDark;

  /// No description provided for @languageSystem.
  ///
  /// In es, this message translates to:
  /// **'Sistema'**
  String get languageSystem;

  /// No description provided for @notFoundTitle.
  ///
  /// In es, this message translates to:
  /// **'Página no encontrada'**
  String get notFoundTitle;

  /// No description provided for @notFoundAction.
  ///
  /// In es, this message translates to:
  /// **'Volver al inicio'**
  String get notFoundAction;

  /// No description provided for @connectTitle.
  ///
  /// In es, this message translates to:
  /// **'Conectar con la caja principal'**
  String get connectTitle;

  /// No description provided for @connectSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Busca el equipo donde corre VOXON90 en el WiFi del negocio. No se necesita internet.'**
  String get connectSubtitle;

  /// No description provided for @connectSearching.
  ///
  /// In es, this message translates to:
  /// **'Buscando en la red…'**
  String get connectSearching;

  /// No description provided for @connectSearchAgain.
  ///
  /// In es, this message translates to:
  /// **'Buscar de nuevo'**
  String get connectSearchAgain;

  /// No description provided for @connectNoneFound.
  ///
  /// In es, this message translates to:
  /// **'No se encontró ninguna caja principal. Revisa que esté encendida y en el mismo WiFi.'**
  String get connectNoneFound;

  /// No description provided for @connectManualLabel.
  ///
  /// In es, this message translates to:
  /// **'Dirección (IP o IP:puerto)'**
  String get connectManualLabel;

  /// No description provided for @connectManualAction.
  ///
  /// In es, this message translates to:
  /// **'Conectar'**
  String get connectManualAction;

  /// No description provided for @connectInvalidAddress.
  ///
  /// In es, this message translates to:
  /// **'Escribe una dirección válida, por ejemplo 192.168.1.10'**
  String get connectInvalidAddress;

  /// No description provided for @connectUnnamedBusiness.
  ///
  /// In es, this message translates to:
  /// **'Negocio sin configurar'**
  String get connectUnnamedBusiness;

  /// No description provided for @loginTitle.
  ///
  /// In es, this message translates to:
  /// **'Entra con tu PIN'**
  String get loginTitle;

  /// No description provided for @loginAction.
  ///
  /// In es, this message translates to:
  /// **'Entrar'**
  String get loginAction;

  /// No description provided for @loginDelete.
  ///
  /// In es, this message translates to:
  /// **'Borrar'**
  String get loginDelete;

  /// No description provided for @loginPinLength.
  ///
  /// In es, this message translates to:
  /// **'El PIN tiene de 4 a 6 dígitos'**
  String get loginPinLength;

  /// No description provided for @loginChangeServer.
  ///
  /// In es, this message translates to:
  /// **'Cambiar de caja principal'**
  String get loginChangeServer;

  /// No description provided for @setupTitle.
  ///
  /// In es, this message translates to:
  /// **'Configura tu negocio'**
  String get setupTitle;

  /// No description provided for @setupSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Todo se guarda en la caja principal, sin internet.'**
  String get setupSubtitle;

  /// No description provided for @setupBusinessName.
  ///
  /// In es, this message translates to:
  /// **'Nombre del negocio'**
  String get setupBusinessName;

  /// No description provided for @setupBusinessType.
  ///
  /// In es, this message translates to:
  /// **'Tipo de negocio'**
  String get setupBusinessType;

  /// No description provided for @businessTypeColmado.
  ///
  /// In es, this message translates to:
  /// **'Colmado'**
  String get businessTypeColmado;

  /// No description provided for @businessTypeStore.
  ///
  /// In es, this message translates to:
  /// **'Tienda'**
  String get businessTypeStore;

  /// No description provided for @businessTypeRestaurant.
  ///
  /// In es, this message translates to:
  /// **'Restaurante'**
  String get businessTypeRestaurant;

  /// No description provided for @setupRnc.
  ///
  /// In es, this message translates to:
  /// **'RNC o cédula (opcional)'**
  String get setupRnc;

  /// No description provided for @setupOwnerSection.
  ///
  /// In es, this message translates to:
  /// **'Dueño'**
  String get setupOwnerSection;

  /// No description provided for @setupOwnerName.
  ///
  /// In es, this message translates to:
  /// **'Tu nombre'**
  String get setupOwnerName;

  /// No description provided for @setupOwnerPin.
  ///
  /// In es, this message translates to:
  /// **'PIN de 4 a 6 dígitos'**
  String get setupOwnerPin;

  /// No description provided for @setupAction.
  ///
  /// In es, this message translates to:
  /// **'Guardar y empezar'**
  String get setupAction;

  /// No description provided for @fieldRequired.
  ///
  /// In es, this message translates to:
  /// **'Este campo es obligatorio'**
  String get fieldRequired;

  /// No description provided for @offlineTitle.
  ///
  /// In es, this message translates to:
  /// **'Sin conexión con la caja principal'**
  String get offlineTitle;

  /// No description provided for @retry.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get retry;

  /// No description provided for @navSell.
  ///
  /// In es, this message translates to:
  /// **'Vender'**
  String get navSell;

  /// No description provided for @navTables.
  ///
  /// In es, this message translates to:
  /// **'Mesas'**
  String get navTables;

  /// No description provided for @navKitchen.
  ///
  /// In es, this message translates to:
  /// **'Cocina'**
  String get navKitchen;

  /// No description provided for @navSummary.
  ///
  /// In es, this message translates to:
  /// **'Resumen'**
  String get navSummary;

  /// No description provided for @logout.
  ///
  /// In es, this message translates to:
  /// **'Salir'**
  String get logout;

  /// No description provided for @sessionExpired.
  ///
  /// In es, this message translates to:
  /// **'Tu sesión terminó. Entra de nuevo con tu PIN.'**
  String get sessionExpired;

  /// No description provided for @settingsServer.
  ///
  /// In es, this message translates to:
  /// **'Caja principal'**
  String get settingsServer;

  /// No description provided for @settingsSession.
  ///
  /// In es, this message translates to:
  /// **'Sesión'**
  String get settingsSession;

  /// No description provided for @roleOwner.
  ///
  /// In es, this message translates to:
  /// **'Dueño'**
  String get roleOwner;

  /// No description provided for @roleManager.
  ///
  /// In es, this message translates to:
  /// **'Gerente'**
  String get roleManager;

  /// No description provided for @roleCashier.
  ///
  /// In es, this message translates to:
  /// **'Cajero'**
  String get roleCashier;

  /// No description provided for @roleWaiter.
  ///
  /// In es, this message translates to:
  /// **'Mesero'**
  String get roleWaiter;

  /// No description provided for @roleKitchen.
  ///
  /// In es, this message translates to:
  /// **'Cocina'**
  String get roleKitchen;

  /// No description provided for @loading.
  ///
  /// In es, this message translates to:
  /// **'Cargando…'**
  String get loading;

  /// No description provided for @invalidAmount.
  ///
  /// In es, this message translates to:
  /// **'Monto inválido'**
  String get invalidAmount;

  /// No description provided for @sellSearchHint.
  ///
  /// In es, this message translates to:
  /// **'Buscar producto o escanear código'**
  String get sellSearchHint;

  /// No description provided for @sellNoProducts.
  ///
  /// In es, this message translates to:
  /// **'No hay productos que coincidan'**
  String get sellNoProducts;

  /// No description provided for @sellCurrentSale.
  ///
  /// In es, this message translates to:
  /// **'Venta actual'**
  String get sellCurrentSale;

  /// No description provided for @sellEmptyCart.
  ///
  /// In es, this message translates to:
  /// **'Agrega productos para vender'**
  String get sellEmptyCart;

  /// No description provided for @sellProductsTab.
  ///
  /// In es, this message translates to:
  /// **'Productos'**
  String get sellProductsTab;

  /// No description provided for @sellSaleTab.
  ///
  /// In es, this message translates to:
  /// **'Venta ({count})'**
  String sellSaleTab(int count);

  /// No description provided for @sellStockLeft.
  ///
  /// In es, this message translates to:
  /// **'Quedan {quantity}'**
  String sellStockLeft(String quantity);

  /// No description provided for @sellSubtotal.
  ///
  /// In es, this message translates to:
  /// **'Subtotal'**
  String get sellSubtotal;

  /// No description provided for @sellTax.
  ///
  /// In es, this message translates to:
  /// **'ITBIS'**
  String get sellTax;

  /// No description provided for @sellTip.
  ///
  /// In es, this message translates to:
  /// **'Propina legal'**
  String get sellTip;

  /// No description provided for @sellTotal.
  ///
  /// In es, this message translates to:
  /// **'Total'**
  String get sellTotal;

  /// No description provided for @sellRemove.
  ///
  /// In es, this message translates to:
  /// **'Quitar'**
  String get sellRemove;

  /// No description provided for @sellWholeUnits.
  ///
  /// In es, this message translates to:
  /// **'Este producto se vende por unidades enteras'**
  String get sellWholeUnits;

  /// No description provided for @sellInvalidQuantity.
  ///
  /// In es, this message translates to:
  /// **'Cantidad inválida'**
  String get sellInvalidQuantity;

  /// No description provided for @paymentCash.
  ///
  /// In es, this message translates to:
  /// **'Efectivo'**
  String get paymentCash;

  /// No description provided for @paymentCard.
  ///
  /// In es, this message translates to:
  /// **'Tarjeta'**
  String get paymentCard;

  /// No description provided for @paymentTransfer.
  ///
  /// In es, this message translates to:
  /// **'Transferencia'**
  String get paymentTransfer;

  /// No description provided for @paymentCredit.
  ///
  /// In es, this message translates to:
  /// **'Fiao'**
  String get paymentCredit;

  /// No description provided for @sellReceived.
  ///
  /// In es, this message translates to:
  /// **'Efectivo recibido'**
  String get sellReceived;

  /// No description provided for @sellChange.
  ///
  /// In es, this message translates to:
  /// **'Devuelta: {amount}'**
  String sellChange(String amount);

  /// No description provided for @sellMissing.
  ///
  /// In es, this message translates to:
  /// **'Faltan {amount}'**
  String sellMissing(String amount);

  /// No description provided for @sellCharge.
  ///
  /// In es, this message translates to:
  /// **'Cobrar {amount}'**
  String sellCharge(String amount);

  /// No description provided for @sellCharged.
  ///
  /// In es, this message translates to:
  /// **'Venta #{number} cobrada'**
  String sellCharged(int number);

  /// No description provided for @sellNewSale.
  ///
  /// In es, this message translates to:
  /// **'Nueva venta'**
  String get sellNewSale;

  /// No description provided for @sellInsufficientCash.
  ///
  /// In es, this message translates to:
  /// **'El efectivo recibido no cubre el total'**
  String get sellInsufficientCash;

  /// No description provided for @sellCustomerSearch.
  ///
  /// In es, this message translates to:
  /// **'Buscar cliente por nombre o teléfono'**
  String get sellCustomerSearch;

  /// No description provided for @sellChooseCustomer.
  ///
  /// In es, this message translates to:
  /// **'Elige el cliente del fiao'**
  String get sellChooseCustomer;

  /// No description provided for @sellCreditTo.
  ///
  /// In es, this message translates to:
  /// **'Fiao a {name} · disponible {amount}'**
  String sellCreditTo(String name, String amount);

  /// No description provided for @sellChangeCustomer.
  ///
  /// In es, this message translates to:
  /// **'Cambiar'**
  String get sellChangeCustomer;

  /// No description provided for @cashOpenTitle.
  ///
  /// In es, this message translates to:
  /// **'Abrir caja'**
  String get cashOpenTitle;

  /// No description provided for @cashOpenHint.
  ///
  /// In es, this message translates to:
  /// **'¿Con cuánto efectivo empiezas?'**
  String get cashOpenHint;

  /// No description provided for @summaryTitle.
  ///
  /// In es, this message translates to:
  /// **'Resumen del {day}'**
  String summaryTitle(String day);

  /// No description provided for @summarySales.
  ///
  /// In es, this message translates to:
  /// **'Ventas'**
  String get summarySales;

  /// No description provided for @summaryTickets.
  ///
  /// In es, this message translates to:
  /// **'{count} tickets · promedio {amount}'**
  String summaryTickets(int count, String amount);

  /// No description provided for @summaryTaxCollected.
  ///
  /// In es, this message translates to:
  /// **'ITBIS cobrado'**
  String get summaryTaxCollected;

  /// No description provided for @summaryReceivables.
  ///
  /// In es, this message translates to:
  /// **'Fiao por cobrar'**
  String get summaryReceivables;

  /// No description provided for @summaryVoided.
  ///
  /// In es, this message translates to:
  /// **'Anuladas'**
  String get summaryVoided;

  /// No description provided for @summaryOpenOrders.
  ///
  /// In es, this message translates to:
  /// **'Órdenes abiertas'**
  String get summaryOpenOrders;

  /// No description provided for @summaryTopProducts.
  ///
  /// In es, this message translates to:
  /// **'Lo más vendido hoy'**
  String get summaryTopProducts;

  /// No description provided for @summaryNoSales.
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay ventas hoy'**
  String get summaryNoSales;

  /// No description provided for @summaryLowStock.
  ///
  /// In es, this message translates to:
  /// **'Bajo el mínimo'**
  String get summaryLowStock;

  /// No description provided for @summaryStockOk.
  ///
  /// In es, this message translates to:
  /// **'Inventario en orden'**
  String get summaryStockOk;

  /// No description provided for @summaryDebtors.
  ///
  /// In es, this message translates to:
  /// **'Clientes que deben'**
  String get summaryDebtors;

  /// No description provided for @summaryNoDebtors.
  ///
  /// In es, this message translates to:
  /// **'Nadie debe'**
  String get summaryNoDebtors;

  /// No description provided for @summaryPayments.
  ///
  /// In es, this message translates to:
  /// **'Cobros de hoy'**
  String get summaryPayments;

  /// No description provided for @summaryRegister.
  ///
  /// In es, this message translates to:
  /// **'Caja'**
  String get summaryRegister;

  /// No description provided for @cashClosedHint.
  ///
  /// In es, this message translates to:
  /// **'La caja está cerrada. Se abre desde Vender.'**
  String get cashClosedHint;

  /// No description provided for @cashExpected.
  ///
  /// In es, this message translates to:
  /// **'Debe haber {amount} en efectivo'**
  String cashExpected(String amount);

  /// No description provided for @cashCounted.
  ///
  /// In es, this message translates to:
  /// **'Efectivo contado'**
  String get cashCounted;

  /// No description provided for @cashCloseAction.
  ///
  /// In es, this message translates to:
  /// **'Cerrar caja'**
  String get cashCloseAction;

  /// No description provided for @cashClosedExact.
  ///
  /// In es, this message translates to:
  /// **'Caja cerrada: cuadró exacto'**
  String get cashClosedExact;

  /// No description provided for @cashClosedDifference.
  ///
  /// In es, this message translates to:
  /// **'Caja cerrada con diferencia de {amount}'**
  String cashClosedDifference(String amount);

  /// No description provided for @backupAction.
  ///
  /// In es, this message translates to:
  /// **'Hacer respaldo'**
  String get backupAction;

  /// No description provided for @backupDone.
  ///
  /// In es, this message translates to:
  /// **'Respaldo guardado en {path}'**
  String backupDone(String path);

  /// No description provided for @kitchenAll.
  ///
  /// In es, this message translates to:
  /// **'Todo'**
  String get kitchenAll;

  /// No description provided for @kitchenStationKitchen.
  ///
  /// In es, this message translates to:
  /// **'Cocina'**
  String get kitchenStationKitchen;

  /// No description provided for @kitchenStationBar.
  ///
  /// In es, this message translates to:
  /// **'Bar'**
  String get kitchenStationBar;

  /// No description provided for @kitchenEmpty.
  ///
  /// In es, this message translates to:
  /// **'No hay nada pendiente. ¡Todo al día!'**
  String get kitchenEmpty;

  /// No description provided for @kitchenMinutes.
  ///
  /// In es, this message translates to:
  /// **'{minutes} min'**
  String kitchenMinutes(int minutes);

  /// No description provided for @statusPending.
  ///
  /// In es, this message translates to:
  /// **'Sin enviar'**
  String get statusPending;

  /// No description provided for @statusSent.
  ///
  /// In es, this message translates to:
  /// **'Nuevo'**
  String get statusSent;

  /// No description provided for @statusPreparing.
  ///
  /// In es, this message translates to:
  /// **'Preparando'**
  String get statusPreparing;

  /// No description provided for @statusReady.
  ///
  /// In es, this message translates to:
  /// **'Listo'**
  String get statusReady;

  /// No description provided for @statusServed.
  ///
  /// In es, this message translates to:
  /// **'Servido'**
  String get statusServed;

  /// No description provided for @statusCancelled.
  ///
  /// In es, this message translates to:
  /// **'Cancelado'**
  String get statusCancelled;

  /// No description provided for @orderTakeout.
  ///
  /// In es, this message translates to:
  /// **'Para llevar'**
  String get orderTakeout;

  /// No description provided for @orderDelivery.
  ///
  /// In es, this message translates to:
  /// **'Delivery'**
  String get orderDelivery;

  /// No description provided for @tablesFree.
  ///
  /// In es, this message translates to:
  /// **'Libre'**
  String get tablesFree;

  /// No description provided for @tablesOrder.
  ///
  /// In es, this message translates to:
  /// **'Orden #{number} · {waiter}'**
  String tablesOrder(int number, String waiter);

  /// No description provided for @tablesItems.
  ///
  /// In es, this message translates to:
  /// **'{count} productos · {amount}'**
  String tablesItems(int count, String amount);

  /// No description provided for @tablesEmpty.
  ///
  /// In es, this message translates to:
  /// **'No hay mesas registradas'**
  String get tablesEmpty;

  /// No description provided for @tablesAdd.
  ///
  /// In es, this message translates to:
  /// **'Agregar mesa'**
  String get tablesAdd;

  /// No description provided for @tablesNewName.
  ///
  /// In es, this message translates to:
  /// **'Nombre de la mesa'**
  String get tablesNewName;

  /// No description provided for @tablesOtherOrders.
  ///
  /// In es, this message translates to:
  /// **'Para llevar y delivery'**
  String get tablesOtherOrders;

  /// No description provided for @tablesSelectHint.
  ///
  /// In es, this message translates to:
  /// **'Toca una mesa para ver o abrir su orden'**
  String get tablesSelectHint;

  /// No description provided for @orderAddProduct.
  ///
  /// In es, this message translates to:
  /// **'Agregar producto'**
  String get orderAddProduct;

  /// No description provided for @orderAddProductsHint.
  ///
  /// In es, this message translates to:
  /// **'Busca y agrega productos'**
  String get orderAddProductsHint;

  /// No description provided for @orderServedBy.
  ///
  /// In es, this message translates to:
  /// **'Atiende {name}'**
  String orderServedBy(String name);

  /// No description provided for @orderSend.
  ///
  /// In es, this message translates to:
  /// **'Enviar {count} a cocina'**
  String orderSend(int count);

  /// No description provided for @orderNothingToSend.
  ///
  /// In es, this message translates to:
  /// **'Nada por enviar'**
  String get orderNothingToSend;

  /// No description provided for @orderSent.
  ///
  /// In es, this message translates to:
  /// **'Comanda enviada'**
  String get orderSent;

  /// No description provided for @orderBill.
  ///
  /// In es, this message translates to:
  /// **'Cuenta'**
  String get orderBill;

  /// No description provided for @orderCharge.
  ///
  /// In es, this message translates to:
  /// **'Cobrar cuenta'**
  String get orderCharge;

  /// No description provided for @orderCharged.
  ///
  /// In es, this message translates to:
  /// **'Cuenta cobrada: {amount}'**
  String orderCharged(String amount);

  /// No description provided for @settingsCloud.
  ///
  /// In es, this message translates to:
  /// **'App del dueño'**
  String get settingsCloud;

  /// No description provided for @cloudNotConfigured.
  ///
  /// In es, this message translates to:
  /// **'Esta caja arrancó sin Firebase. Para ver tus datos en el celular, inicia el servidor con --firebase-project y --firebase-api-key.'**
  String get cloudNotConfigured;

  /// No description provided for @cloudLinkHint.
  ///
  /// In es, this message translates to:
  /// **'En la app VOXON90 Dueño toca «Vincular caja» y escribe aquí el código que aparece.'**
  String get cloudLinkHint;

  /// No description provided for @cloudCodeLabel.
  ///
  /// In es, this message translates to:
  /// **'Código de vínculo'**
  String get cloudCodeLabel;

  /// No description provided for @cloudLinkAction.
  ///
  /// In es, this message translates to:
  /// **'Vincular'**
  String get cloudLinkAction;

  /// No description provided for @cloudUnlinkAction.
  ///
  /// In es, this message translates to:
  /// **'Desvincular'**
  String get cloudUnlinkAction;

  /// No description provided for @cloudLinked.
  ///
  /// In es, this message translates to:
  /// **'Vinculada con la app del dueño'**
  String get cloudLinked;

  /// No description provided for @cloudStateOk.
  ///
  /// In es, this message translates to:
  /// **'Datos al día · {time}'**
  String cloudStateOk(String time);

  /// No description provided for @cloudStatePending.
  ///
  /// In es, this message translates to:
  /// **'Pendiente de subir'**
  String get cloudStatePending;

  /// No description provided for @cloudStateOffline.
  ///
  /// In es, this message translates to:
  /// **'Sin internet: se sube cuando vuelva la conexión'**
  String get cloudStateOffline;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
