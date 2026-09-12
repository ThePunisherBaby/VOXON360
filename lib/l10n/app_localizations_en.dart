// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'VOXON90';

  @override
  String get navHome => 'Home';

  @override
  String get navSettings => 'Settings';

  @override
  String get homeTitle => 'Welcome to VOXON90';

  @override
  String get homeSubtitle =>
      'The project foundation is ready. The app\'s features will be built here.';

  @override
  String get homeEnvironment => 'Environment';

  @override
  String get homePlatform => 'Platform';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get languageSystem => 'System';

  @override
  String get notFoundTitle => 'Page not found';

  @override
  String get notFoundAction => 'Back to home';

  @override
  String get connectTitle => 'Connect to the main register';

  @override
  String get connectSubtitle =>
      'Find the device running VOXON90 on the business Wi-Fi. No internet needed.';

  @override
  String get connectSearching => 'Searching the network…';

  @override
  String get connectSearchAgain => 'Search again';

  @override
  String get connectNoneFound =>
      'No main register found. Make sure it is on and on the same Wi-Fi.';

  @override
  String get connectManualLabel => 'Address (IP or IP:port)';

  @override
  String get connectManualAction => 'Connect';

  @override
  String get connectInvalidAddress =>
      'Enter a valid address, for example 192.168.1.10';

  @override
  String get connectUnnamedBusiness => 'Business not set up';

  @override
  String get loginTitle => 'Enter your PIN';

  @override
  String get loginAction => 'Sign in';

  @override
  String get loginDelete => 'Delete';

  @override
  String get loginPinLength => 'The PIN has 4 to 6 digits';

  @override
  String get loginChangeServer => 'Change main register';

  @override
  String get setupTitle => 'Set up your business';

  @override
  String get setupSubtitle =>
      'Everything is stored on the main register, no internet needed.';

  @override
  String get setupBusinessName => 'Business name';

  @override
  String get setupBusinessType => 'Business type';

  @override
  String get businessTypeColmado => 'Corner store';

  @override
  String get businessTypeStore => 'Store';

  @override
  String get businessTypeRestaurant => 'Restaurant';

  @override
  String get setupRnc => 'RNC or ID number (optional)';

  @override
  String get setupOwnerSection => 'Owner';

  @override
  String get setupOwnerName => 'Your name';

  @override
  String get setupOwnerPin => '4 to 6 digit PIN';

  @override
  String get setupAction => 'Save and start';

  @override
  String get fieldRequired => 'This field is required';

  @override
  String get offlineTitle => 'No connection to the main register';

  @override
  String get retry => 'Retry';

  @override
  String get navSell => 'Sell';

  @override
  String get navTables => 'Tables';

  @override
  String get navKitchen => 'Kitchen';

  @override
  String get navSummary => 'Summary';

  @override
  String get logout => 'Sign out';

  @override
  String get sessionExpired =>
      'Your session ended. Sign in again with your PIN.';

  @override
  String get settingsServer => 'Main register';

  @override
  String get settingsSession => 'Session';

  @override
  String get roleOwner => 'Owner';

  @override
  String get roleManager => 'Manager';

  @override
  String get roleCashier => 'Cashier';

  @override
  String get roleWaiter => 'Waiter';

  @override
  String get roleKitchen => 'Kitchen';

  @override
  String get loading => 'Loading…';

  @override
  String get invalidAmount => 'Invalid amount';

  @override
  String get sellSearchHint => 'Search product or scan barcode';

  @override
  String get sellNoProducts => 'No matching products';

  @override
  String get sellCurrentSale => 'Current sale';

  @override
  String get sellEmptyCart => 'Add products to sell';

  @override
  String get sellProductsTab => 'Products';

  @override
  String sellSaleTab(int count) {
    return 'Sale ($count)';
  }

  @override
  String sellStockLeft(String quantity) {
    return '$quantity left';
  }

  @override
  String get sellSubtotal => 'Subtotal';

  @override
  String get sellTax => 'Tax (ITBIS)';

  @override
  String get sellTip => 'Legal tip';

  @override
  String get sellTotal => 'Total';

  @override
  String get sellRemove => 'Remove';

  @override
  String get sellWholeUnits => 'This product is sold in whole units';

  @override
  String get sellInvalidQuantity => 'Invalid quantity';

  @override
  String get paymentCash => 'Cash';

  @override
  String get paymentCard => 'Card';

  @override
  String get paymentTransfer => 'Transfer';

  @override
  String get paymentCredit => 'On credit';

  @override
  String get sellReceived => 'Cash received';

  @override
  String sellChange(String amount) {
    return 'Change: $amount';
  }

  @override
  String sellMissing(String amount) {
    return '$amount missing';
  }

  @override
  String sellCharge(String amount) {
    return 'Charge $amount';
  }

  @override
  String sellCharged(int number) {
    return 'Sale #$number completed';
  }

  @override
  String get sellNewSale => 'New sale';

  @override
  String get sellInsufficientCash => 'Cash received does not cover the total';

  @override
  String get sellCustomerSearch => 'Search customer by name or phone';

  @override
  String get sellChooseCustomer => 'Choose the customer for credit';

  @override
  String sellCreditTo(String name, String amount) {
    return 'Credit to $name · available $amount';
  }

  @override
  String get sellChangeCustomer => 'Change';

  @override
  String get cashOpenTitle => 'Open register';

  @override
  String get cashOpenHint => 'How much cash are you starting with?';

  @override
  String summaryTitle(String day) {
    return 'Summary for $day';
  }

  @override
  String get summarySales => 'Sales';

  @override
  String summaryTickets(int count, String amount) {
    return '$count tickets · average $amount';
  }

  @override
  String get summaryTaxCollected => 'Tax collected';

  @override
  String get summaryReceivables => 'Credit to collect';

  @override
  String get summaryVoided => 'Voided';

  @override
  String get summaryOpenOrders => 'Open orders';

  @override
  String get summaryTopProducts => 'Top sellers today';

  @override
  String get summaryNoSales => 'No sales yet today';

  @override
  String get summaryLowStock => 'Below minimum';

  @override
  String get summaryStockOk => 'Stock is fine';

  @override
  String get summaryDebtors => 'Customers who owe';

  @override
  String get summaryNoDebtors => 'Nobody owes';

  @override
  String get summaryPayments => 'Today\'s payments';

  @override
  String get summaryRegister => 'Register';

  @override
  String get cashClosedHint => 'The register is closed. Open it from Sell.';

  @override
  String cashExpected(String amount) {
    return 'There should be $amount in cash';
  }

  @override
  String get cashCounted => 'Cash counted';

  @override
  String get cashCloseAction => 'Close register';

  @override
  String get cashClosedExact => 'Register closed: it balanced exactly';

  @override
  String cashClosedDifference(String amount) {
    return 'Register closed with a difference of $amount';
  }

  @override
  String get backupAction => 'Back up';

  @override
  String backupDone(String path) {
    return 'Backup saved to $path';
  }

  @override
  String get kitchenAll => 'All';

  @override
  String get kitchenStationKitchen => 'Kitchen';

  @override
  String get kitchenStationBar => 'Bar';

  @override
  String get kitchenEmpty => 'Nothing pending. All caught up!';

  @override
  String kitchenMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get statusPending => 'Not sent';

  @override
  String get statusSent => 'New';

  @override
  String get statusPreparing => 'Preparing';

  @override
  String get statusReady => 'Ready';

  @override
  String get statusServed => 'Served';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get orderTakeout => 'Takeout';

  @override
  String get orderDelivery => 'Delivery';

  @override
  String get tablesFree => 'Free';

  @override
  String tablesOrder(int number, String waiter) {
    return 'Order #$number · $waiter';
  }

  @override
  String tablesItems(int count, String amount) {
    return '$count items · $amount';
  }

  @override
  String get tablesEmpty => 'No tables yet';

  @override
  String get tablesAdd => 'Add table';

  @override
  String get tablesNewName => 'Table name';

  @override
  String get tablesOtherOrders => 'Takeout and delivery';

  @override
  String get tablesSelectHint => 'Tap a table to see or open its order';

  @override
  String get orderAddProduct => 'Add product';

  @override
  String get orderAddProductsHint => 'Search and add products';

  @override
  String orderServedBy(String name) {
    return 'Served by $name';
  }

  @override
  String orderSend(int count) {
    return 'Send $count to kitchen';
  }

  @override
  String get orderNothingToSend => 'Nothing to send';

  @override
  String get orderSent => 'Order sent';

  @override
  String get orderBill => 'Bill';

  @override
  String get orderCharge => 'Charge bill';

  @override
  String orderCharged(String amount) {
    return 'Bill charged: $amount';
  }

  @override
  String get settingsCloud => 'Owner app';

  @override
  String get cloudNotConfigured =>
      'This register started without Firebase. To see your data on your phone, start the server with --firebase-project and --firebase-api-key.';

  @override
  String get cloudLinkHint =>
      'In the VOXON90 Owner app tap “Link register” and type the code shown there.';

  @override
  String get cloudCodeLabel => 'Link code';

  @override
  String get cloudLinkAction => 'Link';

  @override
  String get cloudUnlinkAction => 'Unlink';

  @override
  String get cloudLinked => 'Linked to the owner app';

  @override
  String cloudStateOk(String time) {
    return 'Up to date · $time';
  }

  @override
  String get cloudStatePending => 'Waiting to upload';

  @override
  String get cloudStateOffline =>
      'No internet: it will upload when the connection is back';
}
