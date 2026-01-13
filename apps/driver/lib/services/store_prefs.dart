import 'package:shared_preferences/shared_preferences.dart';

class StorePrefs {
  StorePrefs._();

  static final StorePrefs instance = StorePrefs._();

  static const _storeIdKey = 'driver_store_id';
  static const _phoneKey = 'driver_phone_e164';

  String? _storeId;
  String? _phone;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _storeId = prefs.getString(_storeIdKey);
    _phone = prefs.getString(_phoneKey);
  }

  String storeId({String fallback = 'demo-store'}) {
    final id = _storeId?.trim() ?? '';
    if (id.isNotEmpty) return id;
    return fallback;
  }

  String phone() => _phone?.trim() ?? '';

  Future<void> setStoreId(String value) async {
    _storeId = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeIdKey, _storeId ?? '');
  }

  Future<void> setPhone(String value) async {
    _phone = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneKey, _phone ?? '');
  }
}
