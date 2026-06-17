import 'menu_bundle.dart';
import 'menu_item.dart';

class MenuRecordModel {
  MenuRecordModel({required this.items, required this.bundleRules});

  final List<MenuItemModel> items;
  final List<BundleRuleModel> bundleRules;

  factory MenuRecordModel.empty() {
    return MenuRecordModel(items: const [], bundleRules: const []);
  }

  factory MenuRecordModel.fromJson(Map<String, dynamic> json) {
    return MenuRecordModel(
      items: (json['items'] as List<dynamic>? ?? [])
          .map((entry) => MenuItemModel.fromJson(entry as Map<String, dynamic>))
          .toList(),
      bundleRules: (json['bundleRules'] as List<dynamic>? ?? [])
          .map((entry) =>
              BundleRuleModel.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'items': items.map((item) => item.toJson()).toList(),
        'bundleRules': bundleRules.map((rule) => rule.toJson()).toList(),
      };

  MenuRecordModel copyWith({
    List<MenuItemModel>? items,
    List<BundleRuleModel>? bundleRules,
  }) {
    return MenuRecordModel(
      items: items ?? this.items,
      bundleRules: bundleRules ?? this.bundleRules,
    );
  }
}
