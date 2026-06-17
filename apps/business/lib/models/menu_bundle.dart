import 'menu_utils.dart';

class BundleRuleModel {
  BundleRuleModel({
    required this.bundleId,
    required this.displayName,
    required this.triggerItemId,
    required this.triggerCategory,
    required this.components,
    required this.promptHintsFr,
  });

  final String bundleId;
  final String displayName;
  final String triggerItemId;
  final String triggerCategory;
  final List<BundleComponentModel> components;
  final String promptHintsFr;

  factory BundleRuleModel.fromJson(Map<String, dynamic> json) {
    return BundleRuleModel(
      bundleId: json['bundleId'] ?? '',
      displayName: json['displayName'] ?? '',
      triggerItemId: json['triggerItemId'] ?? '',
      triggerCategory: json['triggerCategory'] ?? '',
      components: (json['components'] as List<dynamic>? ?? [])
          .map((entry) =>
              BundleComponentModel.fromJson(entry as Map<String, dynamic>))
          .toList(),
      promptHintsFr: json['promptHintsFr'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'bundleId': bundleId,
        'displayName': displayName,
        if (triggerItemId.isNotEmpty) 'triggerItemId': triggerItemId,
        if (triggerCategory.isNotEmpty) 'triggerCategory': triggerCategory,
        'components':
            components.map((component) => component.toJson()).toList(),
        if (promptHintsFr.isNotEmpty) 'promptHintsFr': promptHintsFr,
      };

  BundleRuleModel copyWith({
    String? bundleId,
    String? displayName,
    String? triggerItemId,
    String? triggerCategory,
    List<BundleComponentModel>? components,
    String? promptHintsFr,
  }) {
    return BundleRuleModel(
      bundleId: bundleId ?? this.bundleId,
      displayName: displayName ?? this.displayName,
      triggerItemId: triggerItemId ?? this.triggerItemId,
      triggerCategory: triggerCategory ?? this.triggerCategory,
      components: components ?? this.components,
      promptHintsFr: promptHintsFr ?? this.promptHintsFr,
    );
  }
}

class BundleComponentModel {
  BundleComponentModel({
    required this.role,
    required this.itemIdsCsv,
    required this.category,
    required this.requiredGroupIdsCsv,
  });

  final String role;
  final String itemIdsCsv;
  final String category;
  final String requiredGroupIdsCsv;

  factory BundleComponentModel.fromJson(Map<String, dynamic> json) {
    final itemIds = (json['itemIds'] as List<dynamic>? ?? []).cast<String>();
    final groupIds =
        (json['requiredGroupIds'] as List<dynamic>? ?? []).cast<String>();
    return BundleComponentModel(
      role: json['role'] ?? '',
      itemIdsCsv: itemIds.join(','),
      category: json['category'] ?? '',
      requiredGroupIdsCsv: groupIds.join(','),
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        if (splitCsv(itemIdsCsv).isNotEmpty) 'itemIds': splitCsv(itemIdsCsv),
        if (category.isNotEmpty) 'category': category,
        if (splitCsv(requiredGroupIdsCsv).isNotEmpty)
          'requiredGroupIds': splitCsv(requiredGroupIdsCsv),
      };

  BundleComponentModel copyWith({
    String? role,
    String? itemIdsCsv,
    String? category,
    String? requiredGroupIdsCsv,
  }) {
    return BundleComponentModel(
      role: role ?? this.role,
      itemIdsCsv: itemIdsCsv ?? this.itemIdsCsv,
      category: category ?? this.category,
      requiredGroupIdsCsv: requiredGroupIdsCsv ?? this.requiredGroupIdsCsv,
    );
  }
}
