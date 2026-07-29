/// Identifies the reporting seat on a `POST /agent-status` request.
const agentStatusMemberHeader = 'X-Member';

/// Identifies the session that owns the seat.
const agentStatusSessionHeader = 'X-Session';

/// Shared secret for status posts that arrive over an SSH reverse tunnel.
const agentStatusTokenHeader = 'X-Bus-Token';
