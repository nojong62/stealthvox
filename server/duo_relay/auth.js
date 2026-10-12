"use strict";

async function verifyRelayMembership({
  roomId,
  uid,
  idToken,
  verifyRoom = true,
  loadRoom,
  verifyIdToken,
}) {
  if (!verifyRoom) return { ok: true };
  if (!idToken) return { ok: false, reason: "missing_id_token" };

  try {
    const decoded = await verifyIdToken(idToken);
    if (!decoded || decoded.uid !== uid) {
      return { ok: false, reason: "uid_mismatch" };
    }

    const room = await loadRoom(roomId);
    if (!room) return { ok: false, reason: "room_not_found" };
    if (room.isDuoEnabled !== true) {
      return { ok: false, reason: "room_closed" };
    }
    const hostUid = room.hostUid ? String(room.hostUid) : "";
    const partnerUid = room.partnerUid ? String(room.partnerUid) : "";
    if (uid !== hostUid && uid !== partnerUid) {
      return { ok: false, reason: "not_a_member" };
    }
    return { ok: true };
  } catch (error) {
    return { ok: false, reason: `verify_failed(${error.code || error.name})` };
  }
}

module.exports = { verifyRelayMembership };
