import 'package:flutter/material.dart';

import '../../widgets/shad_snackbar.dart';

void showStoreSettingsSavedSnack(BuildContext context, String storeId) {
  showShadSnack(
    context,
    title: 'Saved',
    message: 'Store settings updated for $storeId',
    type: ShadSnackType.success,
  );
}

void showStoreSettingsSaveFailedSnack(BuildContext context, Object error) {
  showShadSnack(
    context,
    title: 'Save failed',
    message: '$error',
    type: ShadSnackType.error,
  );
}
