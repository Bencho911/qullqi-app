/// Rutas de la app en un solo lugar.
abstract final class Routes {
  // Pestañas (cada una conserva su propio historial).
  static const home = '/inicio';
  static const transactions = '/movimientos';
  static const planning = '/planes';
  static const accounts = '/cuentas';

  // Acceso (sin sesión).
  static const welcome = '/bienvenida';
  static const signUp = '/registro';
  static const signUpPhone = '/registro/celular';
  static const signUpCode = '/registro/codigo';
  static const createPin = '/registro/pin';
  static const signIn = '/ingresar';
  static const resetPassword = '/recuperar';
  static const lock = '/desbloquear';

  /// Rutas que se ven sin sesión.
  static const Set<String> public = {
    welcome,
    signUp,
    signUpPhone,
    signUpCode,
    createPin,
    signIn,
    resetPassword,
  };

  // Pantallas que se abren encima de las pestañas.
  static const profile = '/perfil';
  static const editProfile = '/perfil/datos';
  static const changePin = '/perfil/pin';
  static const devices = '/perfil/dispositivos';
  static const notificationSettings = '/perfil/avisos';
  static const notifications = '/notificaciones';
  static const addExpense = '/agregar/gasto';
  static const addIncome = '/agregar/ingreso';
  static const moveMoney = '/mover-plata';
  static const scanReceipt = '/escanear';
  static const connectAccount = '/conectar-cuenta';
  static const reviewTransfers = '/traslados-por-revisar';
  static const manualAccount = '/cuenta-manual';

  /// Importar un extracto, opcionalmente a una cuenta ya elegida.
  static const importStatement = '/importar-extracto';
  static String importStatementTo(String accountId) =>
      '$importStatement?cuenta=$accountId';

  // Negocio.
  static const invoices = '/cobros';
  static const newInvoice = '/cobro-nuevo';
  static const invoicePattern = '/cobro/:id';
  static String invoice(String id) => '/cobro/$id';
  static const iva = '/iva';

  // Planes.
  static const budgetPattern = '/presupuesto/:id';
  static String budget(String id) => '/presupuesto/$id';
  static const budgetEditor = '/presupuesto-editor';
  static String editBudget(String id) => '$budgetEditor?id=$id';
  static const goalPattern = '/meta/:id';
  static String goal(String id) => '/meta/$id';
  static const newGoal = '/meta-nueva';
  static const contributePattern = '/meta/:id/aportar';
  static String contribute(String id) => '/meta/$id/aportar';

  /// Cobros que se repiten cada mes.
  static const recurring = '/recurrentes';

  /// Reglas de categorías y su editor (con un comercio y una categoría de
  /// partida opcionales).
  static const rules = '/reglas';
  static const newRule = '/regla-nueva';
  static String newRuleFor({
    required String keyword,
    required String categoryId,
  }) =>
      '$newRule?comercio=${Uri.encodeQueryComponent(keyword)}'
      '&categoria=$categoryId';

  /// Historial de patrimonio y plan para pagar las tarjetas.
  static const netWorth = '/patrimonio';
  static const debtPlan = '/plan-de-deudas';

  // Inversiones.
  static const investments = '/inversiones';
  static const investmentPattern = '/inversion/:id';
  static String investment(String id) => '/inversion/$id';
  static const updateInvestmentPattern = '/inversion/:id/valor';
  static String updateInvestment(String id) => '/inversion/$id/valor';
  static const addInvestment = '/inversion-nueva';
  static const connectInvestment = '/conectar-inversion';

  /// Simulador de crecimiento. Puede abrirse con valores de partida:
  /// una meta (`meta`), o lo que ya tienes (`inicial`) y su tasa (`tasa`).
  static const simulator = '/simulador';
  static String simulatorForGoal(String goalId) => '$simulator?meta=$goalId';
  static String simulatorFrom({required int initial, double? rate}) =>
      '$simulator?inicial=$initial${rate == null ? '' : '&tasa=$rate'}';

  /// Detalle de una cuenta o tarjeta (encima de las pestañas).
  static const accountPattern = '/cuenta/:id';
  static String account(String id) => '/cuenta/$id';

  /// Reconectar una cuenta cuyo permiso venció.
  static String reconnect(String accountId) =>
      '$connectAccount?reconectar=$accountId';

  /// Detalle de un movimiento. Se abre encima de las pestañas para que
  /// "atrás" vuelva a donde estabas (Inicio o Movimientos).
  static const transactionPattern = '/movimiento/:id';
  static String transaction(String id) => '/movimiento/$id';

  /// Galería del sistema de diseño (solo en modo desarrollo).
  static const gallery = '/dev/galeria';
}
