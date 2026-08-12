// ============================================================================
// duo_relay — StealthVox Duo 직접 대화용 PCM 릴레이
// ----------------------------------------------------------------------------
// 하는 일은 하나뿐이다.
//
//   A(roomId) → 같은 방의 B에게 그대로 전달
//   B(roomId) → 같은 방의 A에게 그대로 전달
//
// 하지 않는 일:
//   · STT / 번역 / TTS  — 소리의 내용을 보지 않는다
//   · 저장              — DB도 Storage도 파일도 없다
//   · PCM 로깅          — 로그에 오디오 body를 남기지 않는다 (byte count만)
//
// 로그에 남기는 것: roomId, uid, role, 연결/종료, byte count, 오류.
// ============================================================================

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = parseInt(process.env.PORT || "8080", 10);

// 비어 있으면 토큰 검사를 하지 않는다(개발용). 운영에서는 반드시 설정한다.
const RELAY_TOKEN = (process.env.RELAY_TOKEN || "").trim();

// 방 검증. 켜면 Firestore의 duo_sessions/{roomId} 문서를 직접 읽어
//   · 방이 실제로 열려 있는지(isDuoEnabled)
//   · 붙으려는 uid가 그 방의 hostUid/partnerUid가 맞는지
// 를 확인한다. 토큰만으로는 "토큰을 아는 사람이 아무 방에나" 붙을 수 있다.
const VERIFY_ROOM = (process.env.VERIFY_ROOM || "1") !== "0";

let firestore = null;
let firebaseAuth = null;
if (VERIFY_ROOM) {
  // Cloud Run 기본 서비스 계정으로 초기화된다(키 파일 불필요).
  const admin = require("firebase-admin");
  admin.initializeApp();
  firestore = admin.firestore();
  firebaseAuth = admin.auth();
}

/// 방 문서를 짧게 캐시한다. 통화 한 번에 Firestore를 두 번만 읽으면 충분하고,
/// 재접속이 잦을 때 읽기 요금이 튀는 것을 막는다.
const ROOM_CACHE_TTL_MS = 30 * 1000;
const roomCache = new Map();

async function loadRoom(roomId) {
  const cached = roomCache.get(roomId);
  if (cached && Date.now() - cached.at < ROOM_CACHE_TTL_MS) return cached.data;
  const snap = await firestore.collection("duo_sessions").doc(roomId).get();
  const data = snap.exists ? snap.data() : null;
  roomCache.set(roomId, { at: Date.now(), data });
  if (roomCache.size > 500) {
    for (const [key, value] of roomCache.entries()) {
      if (Date.now() - value.at >= ROOM_CACHE_TTL_MS) roomCache.delete(key);
    }
  }
  return data;
}

/// hello가 주장하는 roomId/uid가 실제 방 참가자인지 확인한다.
/// idToken이 함께 왔으면 uid 소유까지 검증한다(비회원 게스트는 토큰이 없다).
async function verifyMembership({ roomId, uid, idToken }) {
  if (!VERIFY_ROOM) return { ok: true };
  try {
    if (idToken) {
      const decoded = await firebaseAuth.verifyIdToken(idToken);
      if (decoded.uid !== uid) return { ok: false, reason: "uid_mismatch" };
    }
    const room = await loadRoom(roomId);
    if (!room) return { ok: false, reason: "room_not_found" };
    if (room.isDuoEnabled !== true) return { ok: false, reason: "room_closed" };
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

// 방 하나에 붙을 수 있는 최대 인원. Duo는 1:1이다.
const MAX_PEERS_PER_ROOM = 2;

// 오디오 프레임 상한(bytes). 24kHz mono PCM16 기준 1초는 48000바이트다.
const MAX_FRAME_BYTES = 64 * 1024;

// 한 연결이 흘릴 수 있는 최대 속도. 실시간 음성은 초당 48000바이트라
// 넉넉히 3배까지만 허용하고 넘으면 끊는다.
const MAX_BYTES_PER_SEC = 48000 * 3;

// hello를 이 시간 안에 안 보내면 끊는다.
const HELLO_TIMEOUT_MS = 5000;

// 기존 duo_sessions 문서 ID 모양만 통과시킨다.
const ROOM_ID_PATTERN = /^[A-Za-z0-9_-]{6,64}$/;

/** roomId -> Map(connectionId -> peer) */
const rooms = new Map();

let nextConnectionId = 1;

function log(event, fields) {
  const parts = [`event=${event}`];
  for (const [key, value] of Object.entries(fields || {})) {
    if (value === undefined || value === null) continue;
    parts.push(`${key}=${value}`);
  }
  console.log(parts.join(" "));
}

function sendJson(ws, payload) {
  if (ws.readyState !== ws.OPEN) return;
  try {
    ws.send(JSON.stringify(payload));
  } catch (error) {
    log("send_json_failed", { reason: error.code || error.name });
  }
}

function roomPeers(roomId) {
  let peers = rooms.get(roomId);
  if (!peers) {
    peers = new Map();
    rooms.set(roomId, peers);
  }
  return peers;
}

function broadcastPresence(roomId) {
  const peers = rooms.get(roomId);
  if (!peers) return;
  for (const peer of peers.values()) {
    if (!peer.joined) continue;
    const partnerPresent = [...peers.values()].some(
      (other) => other !== peer && other.joined
    );
    sendJson(peer.ws, { type: "partner", present: partnerPresent });
  }
}

function closePeer(peer, code, reason) {
  try {
    peer.ws.close(code, reason);
  } catch (_) {
    // 이미 닫힌 소켓이면 무시한다.
  }
}

const server = http.createServer((req, res) => {
  // Cloud Run 헬스체크용. WebSocket 업그레이드는 아래 wss가 가로챈다.
  if (req.url === "/healthz" || req.url === "/") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("ok");
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server, maxPayload: MAX_FRAME_BYTES });

wss.on("connection", (ws) => {
  const peer = {
    id: nextConnectionId++,
    ws,
    roomId: null,
    uid: null,
    role: null,
    sessionId: null,
    joined: false,
    joining: false,
    inBytes: 0,
    outBytes: 0,
    windowBytes: 0,
    windowStartedAt: Date.now(),
    connectedAt: Date.now(),
  };

  const helloTimer = setTimeout(() => {
    if (!peer.joined) {
      log("hello_timeout", { conn: peer.id });
      closePeer(peer, 4001, "hello_timeout");
    }
  }, HELLO_TIMEOUT_MS);

  ws.on("message", (data, isBinary) => {
    if (isBinary) {
      handleAudio(peer, data);
      return;
    }
    handleControl(peer, data).catch((error) => {
      log("control_failed", { conn: peer.id, reason: error.code || error.name });
    });
  });

  ws.on("close", () => {
    clearTimeout(helloTimer);
    if (peer.roomId) {
      const peers = rooms.get(peer.roomId);
      if (peers) {
        peers.delete(peer.id);
        if (peers.size === 0) rooms.delete(peer.roomId);
      }
      broadcastPresence(peer.roomId);
    }
    log("disconnect", {
      conn: peer.id,
      room: peer.roomId,
      uid: peer.uid,
      role: peer.role,
      inBytes: peer.inBytes,
      outBytes: peer.outBytes,
      seconds: Math.round((Date.now() - peer.connectedAt) / 1000),
    });
  });

  ws.on("error", (error) => {
    log("socket_error", {
      conn: peer.id,
      room: peer.roomId,
      reason: error.code || error.name,
    });
  });

  async function handleControl(currentPeer, raw) {
    let message;
    try {
      message = JSON.parse(raw.toString());
    } catch (_) {
      return;
    }
    if (message.type === "ping") {
      sendJson(currentPeer.ws, { type: "pong" });
      return;
    }
    if (message.type !== "hello" || currentPeer.joined || currentPeer.joining) {
      return;
    }

    const roomId = String(message.roomId || "");
    const uid = String(message.uid || "");
    const role = String(message.role || "");
    const sessionId = String(message.sessionId || "");
    const token = String(message.token || "");
    const idToken = String(message.idToken || "");

    if (RELAY_TOKEN && token !== RELAY_TOKEN) {
      sendJson(currentPeer.ws, { type: "error", reason: "unauthorized" });
      log("hello_rejected", { conn: currentPeer.id, reason: "token" });
      closePeer(currentPeer, 4003, "unauthorized");
      return;
    }
    if (!ROOM_ID_PATTERN.test(roomId) || !uid || !sessionId) {
      sendJson(currentPeer.ws, { type: "error", reason: "bad_hello" });
      log("hello_rejected", { conn: currentPeer.id, reason: "shape" });
      closePeer(currentPeer, 4002, "bad_hello");
      return;
    }

    // 방 참가자 확인. 캐시가 오래돼 상대가 막 들어온 걸 못 봤을 수 있으므로
    // 한 번은 캐시를 버리고 다시 읽는다.
    currentPeer.joining = true;
    let verdict = await verifyMembership({ roomId, uid, idToken });
    if (!verdict.ok && verdict.reason === "not_a_member") {
      roomCache.delete(roomId);
      verdict = await verifyMembership({ roomId, uid, idToken });
    }
    currentPeer.joining = false;
    if (currentPeer.ws.readyState !== currentPeer.ws.OPEN) return;
    if (!verdict.ok) {
      sendJson(currentPeer.ws, { type: "error", reason: verdict.reason });
      log("hello_rejected", {
        conn: currentPeer.id,
        room: roomId,
        uid,
        reason: verdict.reason,
      });
      closePeer(currentPeer, 4006, verdict.reason);
      return;
    }

    const peers = roomPeers(roomId);
    // 같은 uid가 재접속한 경우(끊겼다 붙음) 옛 연결을 먼저 정리한다.
    for (const other of [...peers.values()]) {
      if (other.uid === uid && other !== currentPeer) {
        log("replace_stale_peer", { room: roomId, uid, conn: other.id });
        peers.delete(other.id);
        closePeer(other, 4004, "replaced");
      }
    }
    if (peers.size >= MAX_PEERS_PER_ROOM) {
      sendJson(currentPeer.ws, { type: "error", reason: "room_full" });
      log("hello_rejected", { conn: currentPeer.id, room: roomId, reason: "full" });
      closePeer(currentPeer, 4005, "room_full");
      return;
    }

    currentPeer.roomId = roomId;
    currentPeer.uid = uid;
    currentPeer.role = role;
    currentPeer.sessionId = sessionId;
    currentPeer.joined = true;
    peers.set(currentPeer.id, currentPeer);
    clearTimeout(helloTimer);

    const partnerPresent = [...peers.values()].some(
      (other) => other !== currentPeer && other.joined
    );
    sendJson(currentPeer.ws, { type: "ready", partnerPresent });
    broadcastPresence(roomId);
    log("join", {
      conn: currentPeer.id,
      room: roomId,
      uid,
      role,
      peers: peers.size,
    });
  }

  function handleAudio(currentPeer, chunk) {
    if (!currentPeer.joined) return;

    // 속도 제한 — 실시간 음성보다 훨씬 빠르게 밀어넣는 연결은 끊는다.
    const now = Date.now();
    if (now - currentPeer.windowStartedAt >= 1000) {
      currentPeer.windowStartedAt = now;
      currentPeer.windowBytes = 0;
    }
    currentPeer.windowBytes += chunk.length;
    if (currentPeer.windowBytes > MAX_BYTES_PER_SEC) {
      log("rate_limited", {
        conn: currentPeer.id,
        room: currentPeer.roomId,
        uid: currentPeer.uid,
      });
      closePeer(currentPeer, 4008, "rate_limited");
      return;
    }

    currentPeer.inBytes += chunk.length;
    const peers = rooms.get(currentPeer.roomId);
    if (!peers) return;

    // 받은 조각을 그대로 상대에게. 복사도 변환도 저장도 하지 않는다.
    for (const other of peers.values()) {
      if (other === currentPeer || !other.joined) continue;
      if (other.ws.readyState !== other.ws.OPEN) continue;
      // 상대 소켓이 이미 밀려 있으면 오래된 소리를 더 쌓지 않고 버린다.
      if (other.ws.bufferedAmount > MAX_BYTES_PER_SEC) {
        other.dropped = (other.dropped || 0) + chunk.length;
        continue;
      }
      try {
        other.ws.send(chunk, { binary: true });
        other.outBytes += chunk.length;
      } catch (error) {
        log("forward_failed", {
          conn: other.id,
          room: other.roomId,
          reason: error.code || error.name,
        });
      }
    }
  }
});

server.listen(PORT, () => {
  log("listening", { port: PORT, tokenRequired: RELAY_TOKEN ? 1 : 0 });
});

function shutdown(signal) {
  log("shutdown", { signal });
  for (const peers of rooms.values()) {
    for (const peer of peers.values()) closePeer(peer, 1001, "server_shutdown");
  }
  rooms.clear();
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 3000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
