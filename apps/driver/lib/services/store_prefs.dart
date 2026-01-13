import 'package:shared_preferences/shared_preferences.dart';

class StorePrefs {
  StorePrefs._();

  static final StorePrefs instance = StorePrefs._();

  static const _storeIdKey = 'driver_store_id';
  static const _phoneKey = 'driver_phone_e164';
  static const _modeKey = 'driver_mode';

  String? _storeId;
  String? _phone;
  String? _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _storeId = prefs.getString(_storeIdKey);
    _phone = prefs.getString(_phoneKey);
    _mode = prefs.getString(_modeKey);
  }

  String storeId({String fallback = 'demo-store'}) {
    final id = _storeId?.trim() ?? '';
    if (id.isNotEmpty) return id;
    if (mode() == 'marketplace') return '';
    return fallback;
  }

  String phone() => _phone?.trim() ?? '';

  String mode() => _mode?.trim().isNotEmpty == true ? _mode!.trim() : 'store';

  Future<void> setStoreId(String value) async {
    _storeId = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeIdKey, _storeId ?? '');
  }

  Future<void> setMode(String value) async {
    _mode = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, _mode ?? '');
  }

  Future<void> setPhone(String value) async {
    _phone = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneKey, _phone ?? '');
  }
}
