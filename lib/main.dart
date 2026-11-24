import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'data/hydration_repository.dart';
import 'platform/hydration_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await HydrationRepository.open();
  runApp(
    HydrationApp(
      repository: repository,
      notifications: HydrationNotifications(repository),
    ),
  );
}
