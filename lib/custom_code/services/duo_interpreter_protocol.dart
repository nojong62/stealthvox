// Room-scoped protocol negotiation for Duo Interpreter.
//
// Remote Config is only a local candidate. Once the host writes
// [kDuoInterpreterProtocolField], both phones must use that room value for the
// lifetime of the session.

const String kDuoInterpreterProtocolLegacyWebrtcV1 = 'legacy_webrtc_v1';
const String kDuoInterpreterProtocolCallablePcV2 = 'callable_pc_v2';

const String kDuoInterpreterProtocolField = 'interpreterProtocol';
const String kDuoInterpreterProtocolLockedAtField =
    'interpreterProtocolLockedAt';
const String kDuoHostCallablePcV2Field = 'hostInterpreterCallablePcV2';
const String kDuoPartnerCallablePcV2Field = 'partnerInterpreterCallablePcV2';

const String kDuoInterpreterCallableCandidate = 'callable';

/// The callable transport is not implemented yet. Keeping this false makes
/// every newly negotiated production room use the verified legacy WebRTC
/// protocol while still exercising the room lock and compatibility logic.
const bool kDuoCallablePcV2RolloutEnabled = false;

bool duoInterpreterCallableCapability({
  required String remoteCandidate,
  bool rolloutEnabled = kDuoCallablePcV2RolloutEnabled,
}) =>
    rolloutEnabled &&
    remoteCandidate.trim().toLowerCase() == kDuoInterpreterCallableCandidate;

String chooseDuoInterpreterProtocol({
  required bool hostCallablePcV2,
  required bool partnerCallablePcV2,
  bool rolloutEnabled = kDuoCallablePcV2RolloutEnabled,
}) {
  if (rolloutEnabled && hostCallablePcV2 && partnerCallablePcV2) {
    return kDuoInterpreterProtocolCallablePcV2;
  }
  return kDuoInterpreterProtocolLegacyWebrtcV1;
}

bool isKnownDuoInterpreterProtocol(Object? value) =>
    value == kDuoInterpreterProtocolLegacyWebrtcV1 ||
    value == kDuoInterpreterProtocolCallablePcV2;
