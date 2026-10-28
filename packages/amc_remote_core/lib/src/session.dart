import '../amc_remote_core.dart';

final class RemoteSession {
  RemoteSession({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.role,
    required this.expiresAt,
  });
  final String id, peerId, peerName;
  final RemoteRole role;
  final DateTime expiresAt;
  RemoteSessionState _state = RemoteSessionState.idle;
  Set<RemoteScope> _scopes = const {};
  RemoteSessionState get state => _state;
  Set<RemoteScope> get scopes => _scopes;
  bool get terminal =>
      _state == RemoteSessionState.ended || _state == RemoteSessionState.failed;

  void transition(RemoteSessionState next) {
    if (next == RemoteSessionState.connected &&
        !_scopes.contains(RemoteScope.view)) {
      throw StateError('Session has no approved view grant');
    }
    const allowed = {
      RemoteSessionState.idle: {RemoteSessionState.requesting},
      RemoteSessionState.requesting: {RemoteSessionState.awaitingApproval},
      RemoteSessionState.awaitingApproval: {RemoteSessionState.negotiating},
      RemoteSessionState.negotiating: {RemoteSessionState.connected},
      RemoteSessionState.connected: {RemoteSessionState.reconnecting},
      RemoteSessionState.reconnecting: {RemoteSessionState.connected},
    };
    if (terminal ||
        !(next == RemoteSessionState.ended ||
            next == RemoteSessionState.failed ||
            (allowed[_state]?.contains(next) ?? false))) {
      throw StateError('Invalid session transition: $_state → $next');
    }
    _state = next;
    if (terminal) _scopes = const {};
  }

  void grant(Set<RemoteScope> value) {
    if (_state != RemoteSessionState.awaitingApproval ||
        !value.contains(RemoteScope.view)) {
      throw StateError('A session must be approved before negotiation');
    }
    _scopes = Set.unmodifiable(value);
  }

  bool allows(RemoteScope scope, DateTime now) =>
      _state == RemoteSessionState.connected &&
      _scopes.contains(scope) &&
      now.isBefore(expiresAt);

  void revoke(RemoteScope scope) =>
      _scopes = Set.unmodifiable(_scopes.where((s) => s != scope));
}

/// Authorizes every data-channel event against the current grant and session
/// state. A reconnect cannot inject input until media is confirmed again.
final class RemoteAccessPolicy {
  RemoteAccessPolicy(this.session)
    : _gate = RemoteInputGate(
        sessionId: session.id,
        expiresAt: session.expiresAt,
      );
  final RemoteSession session;
  final RemoteInputGate _gate;
  bool accept(RemoteInputPacket packet, DateTime now) {
    final scope = packet.input is RemoteClipboard
        ? RemoteScope.clipboard
        : RemoteScope.input;
    _gate.setEnabled(session.allows(scope, now));
    return _gate.accept(packet, now: now);
  }
}
