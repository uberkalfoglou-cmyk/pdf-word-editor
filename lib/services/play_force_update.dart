import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Blocks on a Play Store immediate update when one is available.
///
/// Does nothing in debug, on sideloads, or if Play has not rolled the
/// new version out to this device yet. The first store build must
/// include this check, otherwise older installs cannot be forced.
Future<void> forcePlayUpdateIfNeeded() async {
  if (kDebugMode) return;
  try {
    final info = await InAppUpdate.checkForUpdate();
    if (info.updateAvailability != UpdateAvailability.updateAvailable) {
      return;
    }
    if (info.immediateUpdateAllowed) {
      await InAppUpdate.performImmediateUpdate();
      return;
    }
    if (info.flexibleUpdateAllowed) {
      await InAppUpdate.startFlexibleUpdate();
      await InAppUpdate.completeFlexibleUpdate();
    }
  } catch (e, st) {
    debugPrint('[play_force_update] $e\n$st');
  }
}
