import 'agent_attention_state.dart';

/// Normalized agent-status signal from a CLI hook / plugin payload.
class AgentStatusEvent {
  const AgentStatusEvent({
    required this.state,
    this.toolName,
    this.toolInput,
    this.hookEventName,
    this.toolUseId,
    this.toolAgentId,
    this.toolAgentType,
    this.hasExplicitPrompt = false,
    this.interrupted = false,
  });

  final AgentSeatAttention state;
  final String? toolName;

  /// Preview string for sticky permission matching (Orca `toolInput`).
  final String? toolInput;

  /// Raw hook event name (`PermissionRequest`, `PreToolUse`, …).
  final String? hookEventName;

  /// Claude `tool_use_id` — sticky clear / inheritance key.
  final String? toolUseId;

  /// Claude subagent `agent_id`.
  final String? toolAgentId;

  /// Claude subagent `agent_type` (weaker than [toolAgentId]).
  final String? toolAgentType;

  /// True for UserPromptSubmit-style events that must clear sticky waiting.
  final bool hasExplicitPrompt;

  /// True when this `done` was reached via interrupt/cancel (Claude `Stop` with
  /// `is_interrupt`), not normal completion. Always false for non-done states.
  /// CLI-neutral downstream: the per-CLI normalizer is the only place that knows
  /// how to derive it (codex later reads its own cancel signal).
  final bool interrupted;

  AgentStatusEvent copyWith({
    AgentSeatAttention? state,
    String? toolName,
    String? toolInput,
    String? hookEventName,
    String? toolUseId,
    String? toolAgentId,
    String? toolAgentType,
    bool? hasExplicitPrompt,
    bool? interrupted,
  }) => AgentStatusEvent(
    state: state ?? this.state,
    toolName: toolName ?? this.toolName,
    toolInput: toolInput ?? this.toolInput,
    hookEventName: hookEventName ?? this.hookEventName,
    toolUseId: toolUseId ?? this.toolUseId,
    toolAgentId: toolAgentId ?? this.toolAgentId,
    toolAgentType: toolAgentType ?? this.toolAgentType,
    hasExplicitPrompt: hasExplicitPrompt ?? this.hasExplicitPrompt,
    interrupted: interrupted ?? this.interrupted,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentStatusEvent &&
          state == other.state &&
          toolName == other.toolName &&
          toolInput == other.toolInput &&
          hookEventName == other.hookEventName &&
          toolUseId == other.toolUseId &&
          toolAgentId == other.toolAgentId &&
          toolAgentType == other.toolAgentType &&
          hasExplicitPrompt == other.hasExplicitPrompt &&
          interrupted == other.interrupted;

  @override
  int get hashCode => Object.hash(
    state,
    toolName,
    toolInput,
    hookEventName,
    toolUseId,
    toolAgentId,
    toolAgentType,
    hasExplicitPrompt,
    interrupted,
  );
}
