class_name MatchSessionFactory
extends RefCounted

## The only place that knows which concrete session an online / offline match gets.
## Callers keep a plain `MatchSession` and drive it through the base API.


## `tuning` and `transport` only matter online and are ignored offline.
static func create(online: bool, tuning: NetTuning, transport: PeerTransport) -> MatchSession:
	if not online:
		return LocalSession.new()
	var session := RollbackSession.new()
	session.tuning = tuning
	session.transport = transport
	return session
