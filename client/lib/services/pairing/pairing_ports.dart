/// The ports LAN pairing agrees on, in the order both sides walk them.
///
/// The desktop listener claims the first one it can bind; a phone whose saved
/// `ws://ip:port/pair/ws` no longer answers re-probes the rest on the same host
/// before giving up. Without that agreement a fixed port is only half a fix: the
/// moment the desktop has to fall back — port already bound by a second
/// instance, or inside a Windows excluded range reserved by Hyper-V / WSL /
/// Docker, where binding fails with access-denied even though nobody is
/// listening — every paired phone is stranded again.
///
/// Dynamic-range ports with no IANA assignment, and above the default Windows
/// ephemeral range (1024–15000 here) so an unrelated outbound socket cannot
/// randomly squat one.
const List<int> kPairingPortLadder = [47821, 47822, 47823, 47824];
