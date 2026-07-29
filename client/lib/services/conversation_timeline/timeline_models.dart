import 'package:ai_message_core/ai_message_core.dart';

class TimelineSeat {
  const TimelineSeat({required this.sessionId, required this.memberId});

  final String sessionId;
  final String memberId;
}

class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.role,
    required this.parts,
    this.createdAt,
    required this.source,
    this.deliveryChannel,
    this.cliOrder = 0,
  });

  final String id;
  final AiRole role;
  final List<AiMessagePart> parts;
  final DateTime? createdAt;
  final String source;
  final String? deliveryChannel;
  final int cliOrder;
}

class TimelineSnapshot {
  const TimelineSnapshot({required this.messages});

  final List<AiMessage> messages;
}
