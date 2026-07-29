import 'package:ai_message_core/ai_message_core.dart';

import 'timeline_merge.dart';
import 'timeline_models.dart';

/// Builds the display timeline for one seat from its CLI transcript. CLI
/// messages keep their [cliOrder], used when [AiMessage.createdAt] is missing.
TimelineSnapshot buildConversationTimeline({
  required List<AiMessage> cliMessages,
}) {
  final cliEvents = <TimelineEvent>[
    for (var i = 0; i < cliMessages.length; i++)
      TimelineEvent(
        id: cliMessages[i].id,
        role: cliMessages[i].role,
        parts: cliMessages[i].parts,
        createdAt: cliMessages[i].createdAt,
        source: 'cli',
        deliveryChannel: cliMessages[i].deliveryChannel,
        cliOrder: i,
      ),
  ];

  return mergeTimeline(events: cliEvents);
}
