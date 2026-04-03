import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static const _masterCodeKey = 'master_code';
  static const _bagTargetKey = 'bag_target';
  static const _boxTargetKey = 'box_target';

  Future<String> getMasterCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_masterCodeKey) ?? '';
  }

  Future<int> getBagTarget() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_bagTargetKey) ?? 10;
  }

  Future<int> getBoxTarget() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_boxTargetKey) ?? 100;
  }

  Future<void> saveSetup({
    required String masterCode,
    required int bagTarget,
    required int boxTarget,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_masterCodeKey, masterCode);
    await prefs.setInt(_bagTargetKey, bagTarget);
    await prefs.setInt(_boxTargetKey, boxTarget);
  }
}
