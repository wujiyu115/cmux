import '../../models/app_session.dart';
import 'model/session_connect_request.dart';

/// Rebuilds an [ExistingSessionConnect] for [session].
ExistingSessionConnect buildRetryExistingSessionConnect({
  required AppSession session,
  bool preserveWorkbenchView = true,
}) {
  return ExistingSessionConnect(
    session: session,
    preserveWorkbenchView: preserveWorkbenchView,
  );
}
