class_name MatchSessionFactory
extends RefCounted

## The only place that knows which concrete session an online / offline match gets.
## Callers keep a plain `MatchSession` and drive it through the base API.


## `tuning`, `transport` and `lag_presets` only matter online and are ignored offline.
static func create(online: bool, tuning: NetTuning, transport: PeerTransport, lag_presets: Array[LagProfile]) -> MatchSession:
	if not online:
		return LocalSession.new()
	var session := RollbackSession.new()
	session.tuning = tuning
	session.transport = transport
	session.lag_presets = lag_presets
	return session
