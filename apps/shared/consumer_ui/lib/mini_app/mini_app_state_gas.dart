part of 'mini_app_screen.dart';

mixin MiniAppStateGas on State<MiniAppScreen>, MiniAppStateFields {
  FuelPaymentFlow _fuelPaymentFlow = FuelPaymentFlow.prepay;
  FuelPrepayMode _fuelPrepayMode = FuelPrepayMode.amount;
  MenuItem? _selectedFuelGrade;
  final TextEditingController _fuelAmountController = TextEditingController();
  final TextEditingController _fuelLitersController = TextEditingController();
  final TextEditingController _fuelPreauthController = TextEditingController();
  final TextEditingController _pumpNumberController = TextEditingController();
  bool _placingFuelOrder = false;
  String? _fuelOrderError;
  bool _fuelPumpSubmitting = false;
  bool _fuelPreauthEdited = false;

  @override
  void dispose() {
    _fuelAmountController.dispose();
    _fuelLitersController.dispose();
    _fuelPreauthController.dispose();
    _pumpNumberController.dispose();
    super.dispose();
  }

  bool get _isGasStation => _session?.businessType == 'gas_station';

  List<MenuItem> get _fuelGrades => _menu?.items ?? const [];

  void _selectFuelGrade(MenuItem item) {
    setState(() {
      _selectedFuelGrade = item;
    });
  }

  double _parseLiters(String raw) {
    final value = double.tryParse(raw.replaceAll(',', '.').trim());
    return value == null || value.isNaN || value <= 0 ? 0 : value;
  }

  int _parseAmountCents(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null || value.isNaN || value <= 0) return 0;
    return (value * 100).round();
  }

  void _resetFuelDraft() {
    _fuelAmountController.clear();
    _fuelLitersController.clear();
    _fuelPreauthController.clear();
    _pumpNumberController.clear();
    _fuelOrderError = null;
    _selectedFuelGrade = null;
    _fuelPaymentFlow = FuelPaymentFlow.prepay;
    _fuelPrepayMode = FuelPrepayMode.amount;
    _fuelPreauthEdited = false;
  }

  int _resolveFuelPreauthCapCents() {
    final session = _session;
    if (session == null) return 0;
    if (session.fuelPreauthCapCents > 0) {
      return session.fuelPreauthCapCents;
    }
    return session.fuelDefaultPrepayCents;
  }

  String? _fuelPreauthHint() {
    final cap = _resolveFuelPreauthCapCents();
    if (cap <= 0) return null;
    final formatted = (cap / 100).toStringAsFixed(2);
    return 'Default cap: $formatted';
  }
}
