import 'package:shared_ui/shared_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/pairing/pairing_client.dart';

/// Maps the cubit's per-[PairingStage] statuses onto [TpStepRail] items.
///
/// Each step keeps its own hint about what it was doing; the rail marks *which*
/// step failed and the footer carries the message, so the failure reason is
/// stated once.
List<TpStepItem> buildPairingStageItems({
  required AppLocalizations l10n,
  required List<PairingStageStatus> statuses,
}) {
  return [
    for (final stage in PairingStage.values)
      _itemFor(stage: stage, l10n: l10n, statuses: statuses),
  ];
}

TpStepItem _itemFor({
  required PairingStage stage,
  required AppLocalizations l10n,
  required List<PairingStageStatus> statuses,
}) {
  final status = stage.index < statuses.length
      ? statuses[stage.index]
      : PairingStageStatus.idle;
  final (label, note) = switch (stage) {
    PairingStage.connect => (
      l10n.pairingStageConnect,
      l10n.pairingStageConnectNote,
    ),
    PairingStage.secureChannel => (
      l10n.pairingStageSecureChannel,
      l10n.pairingStageSecureChannelNote,
    ),
    PairingStage.authenticate => (
      l10n.pairingStageAuthenticate,
      l10n.pairingStageAuthenticateNote,
    ),
    PairingStage.loadWorkspaces => (
      l10n.pairingStageLoadWorkspaces,
      l10n.pairingStageLoadWorkspacesNote,
    ),
  };
  return TpStepItem(label: label, status: _toStepStatus(status), note: note);
}

TpStepStatus _toStepStatus(PairingStageStatus status) => switch (status) {
  PairingStageStatus.idle => TpStepStatus.idle,
  PairingStageStatus.active => TpStepStatus.active,
  PairingStageStatus.done => TpStepStatus.done,
  PairingStageStatus.fail => TpStepStatus.fail,
};
