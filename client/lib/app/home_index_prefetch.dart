import '../repositories/session_repository.dart';
import '../utils/logging/logger.dart';

/// Warms the workspace index cache as early as [main] allows.
Future<void> prefetchHomeIndexSnapshots(String teampilotRoot) async {
  final sw = Stopwatch()..start();
  await SessionRepository(rootDir: teampilotRoot).loadWorkspacesIndex();
  appLogger.i('[boot] prefetchHomeIndexSnapshots +${sw.elapsedMilliseconds}ms');
}
