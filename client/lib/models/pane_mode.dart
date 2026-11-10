/// What a workspace terminal pane *is*, decided once when it is created.
///
/// This used to be a live view toggle: one pane, two views, a button to flip
/// between them. It is not a toggle any more — the mode is a launch option, so
/// a chat pane starts its agent and a terminal pane does not, and nothing has
/// to guess which of the two a running pane is showing.
enum PaneMode {
  /// An interactive shell. The user types whatever they like, agent CLIs
  /// included.
  terminal,

  /// A conversation with an agent CLI. The pane still runs the CLI in a PTY
  /// (that is what makes it interruptible and inspectable), but it renders the
  /// session the CLI persists instead of the raw screen.
  chat;

  /// Wire/label form (`session.list` reports this).
  String get wire => name;

  /// Parses a stored or wire value, defaulting to [terminal] so an unreadable
  /// setting can never silently start an agent.
  static PaneMode parse(Object? value) {
    if (value is PaneMode) return value;
    if (value is String && value.trim().toLowerCase() == chat.wire) {
      return chat;
    }
    return terminal;
  }
}
