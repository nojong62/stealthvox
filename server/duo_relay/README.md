# duo_relay — Duo 직접 대화 PCM 릴레이

Duo **직접 대화**에서 두 사람의 실제 목소리를 주고받는 통로다.
받은 PCM 조각을 같은 방의 상대에게 그대로 넘기고 **버린다**. 그게 전부다.

- 전사·번역·TTS 없음
- DB/Storage 저장 없음, 파일 생성 없음
- 로그에 오디오 body 없음 (roomId / uid / role / 연결·종료 / byte count / 오류만)

## 프로토콜

접속 직후 텍스트 프레임으로 hello 한 번:

```json
{
  "type": "hello",
  "roomId": "<duo_sessions 문서 ID>",
  "uid": "<사용자 uid>",
  "role": "HOST" | "GUEST",
  "sessionId": "<통화 세대값>",
  "token": "<RELAY_TOKEN, 설정된 경우>",
  "audio": { "format": "pcm_s16le_mono", "rate": 24000, "channels": 1 }
}
```

서버 응답:

| 프레임 | 뜻 |
| --- | --- |
| `{"type":"ready","partnerPresent":bool}` | 입장 완료 |
| `{"type":"partner","present":bool}` | 상대 입·퇴장 |
| `{"type":"pong"}` | `{"type":"ping"}`에 대한 응답 (RTT 측정용) |
| `{"type":"error","reason":"…"}` | 거절 사유 |

그 뒤로는 **binary 프레임 = PCM16 24kHz mono little-endian 원본**이다.
base64로 감싸지 않고, 헤더도 붙이지 않는다.

## 보호 장치

| 항목 | 값 |
| --- | --- |
| 방 정원 | 2명 (초과 시 `room_full`) |
| 프레임 상한 | 64KB |
| 초당 상한 | 144KB/s (실시간 음성의 3배) 초과 시 연결 종료 |
| hello 유예 | 5초 |
| 같은 uid 재접속 | 옛 연결을 끊고 새 연결로 교체 |
| 상대 소켓 적체 | `bufferedAmount` 초과분은 **버린다** (과거 음성 몰아 재생 방지) |

## 로컬 실행

```bash
cd server/duo_relay
npm install
RELAY_TOKEN=dev-token node index.js
# ws://localhost:8080
```

앱 쪽은 `--dart-define=DUO_RELAY_URL=ws://<PC의 LAN IP>:8080` 로 띄우면 붙는다.

## Cloud Run 배포

```bash
cd server/duo_relay
gcloud run deploy duo-relay \
  --source . \
  --region asia-northeast3 \
  --allow-unauthenticated \
  --port 8080 \
  --timeout 3600 \
  --concurrency 250 \
  --min-instances 1 \
  --max-instances 1 \
  --set-env-vars RELAY_TOKEN=<임의의 긴 문자열>
```

### ⚠️ `--max-instances 1` 인 이유

방 정보는 **인스턴스 메모리에만** 있다. 인스턴스가 둘로 늘면 A와 B가 서로 다른
인스턴스에 붙어 소리가 건너가지 않는다. 동시 통화가 늘어 한 대로 못 버티는
시점이 오면 그때 방 단위 라우팅(Redis pub/sub 또는 room→instance 고정)을
붙여야 한다. **그 전까지 max-instances를 올리면 조용히 통화가 깨진다.**

`--timeout 3600` 은 Cloud Run 요청 최대 시간이라 통화가 1시간을 넘기면 소켓이
끊긴다. 앱은 자동 재접속하므로 통화가 죽지는 않고 짧게 끊긴다.

배포 후 앱의 Remote Config `DuoRelayUrl` 에 `wss://duo-relay-xxxx.run.app` 를,
`DuoRelayToken` 에 위에서 넣은 토큰을 설정한다.
