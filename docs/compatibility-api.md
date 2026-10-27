# Compatibility API v1

Archway reads two HTTPS URLs from Settings: a catalog URL for `GET` and a submission URL for `POST`. Existing Settings values take precedence. Otherwise, the app uses the base URL embedded in its bundle at build time, or the public service if none is embedded. Build with `ARCHWAY_API_BASE_URL=https://compatibility.example.org scripts/build-app.sh release` to embed another HTTPS origin; paths, credentials, queries, and fragments are not accepted. The app appends `/api/catalog` and `/api/reports`. Public API addresses are not secrets; database access and moderation credentials remain server-side. Self-hosting and moderation are documented in [services/compatibility/README.md](../services/compatibility/README.md). The app loads its last successful catalog from disk at startup, then attempts a network refresh with an eight-second request timeout. Failed refreshes leave the cache intact. It never runs instructions from the catalog.

`GET` returns JSON with `schemaVersion: 1`, `generatedAt`, and `aggregates`. Each aggregate contains a Steam `gameID`, `mode` (`singleplayer` or `multiplayer`), `context`, `counts`, and `features`. Optional `suggestedProfile` is decoded as data but not applied by this client. `counts` is an object keyed by `works`, `limited`, `unplayable`, and `notTested`. `features` is an object keyed by `join`, `host`, `invites`, `crossplay`, `voice`, and `disconnects`, each containing outcome counts. Omitted outcome keys mean zero. The app accepts at most 2 MB and 5,000 aggregates; counts must be between zero and one million.

`POST` sends one report as `application/json`. A 2xx response acknowledges it. The server must deduplicate by `id` (UUID), since a lost acknowledgement can cause a retry. An unacknowledged report remains in a local queue and is retried only when the person chooses Retry Sending or submits another report. Local games have negative device-local IDs and are saved on the Mac without posting.

Dates are numeric seconds since 2001-01-01 UTC, the default Swift `JSONEncoder` format. No Steam account identifier, executable path, logs, or playtime is included. The optional note is limited to 500 characters. Report payloads are limited to 16 KB.

The context object has `runtimeVersion`, `appVersion`, `macOSVersion`, `chip`, `gameVersion`, `graphicsBackend`, and `profile`. Unknown values are the literal string `Unknown`. Profile has `launchArguments` (each a literal argv token, no shell expansion) and `graphicsAPI` (`gameDefault`, `d3d11`, or `d3d12`). `d3d11` and `d3d12` pass Unity's `-force-d3d11` and `-force-d3d12`; games built with other engines ignore them. The graphics backend is shared by the Steam bottle; it is reported but cannot be selected per game. Catalog counts appear as a current configuration match when the runtime, macOS major version, game version, graphics backend, and profile match; the app version, chip, and macOS minor and patch versions are summed. Other configurations are shown separately. A game counts as tested once at least three singleplayer reports exist and most of them are `works`; once the current runtime has three reports of its own, only those count.

Illustrative catalog (these are not actual test results):

```json
{
  "schemaVersion": 1,
  "generatedAt": 815270400,
  "aggregates": [{
    "gameID": 1144200,
    "mode": "multiplayer",
    "context": {
      "runtimeVersion": "11.20-0f9b980",
      "appVersion": "1.0",
      "macOSVersion": "15.1.0",
      "chip": "Apple M4",
      "gameVersion": "12345678",
      "graphicsBackend": "d3dmetal",
      "profile": {"launchArguments": ["-dx11"], "graphicsAPI": "gameDefault"}
    },
    "counts": {"works": 4, "limited": 2, "unplayable": 1, "notTested": 0},
    "features": {"join": {"works": 4, "limited": 1}, "voice": {"notTested": 3}}
  }]
}
```

Example report body:

```json
{
  "id": "6f62b02b-e6bc-47b5-a5e1-ce87e7038860",
  "gameID": 1144200,
  "mode": "multiplayer",
  "outcome": "limited",
  "features": {"join": "works", "voice": "notTested", "disconnects": "limited"},
  "issue": "network",
  "note": "Disconnected once while joining",
  "context": {
    "runtimeVersion": "11.20-0f9b980",
    "appVersion": "1.0",
    "macOSVersion": "15.1.0",
    "chip": "Apple M4",
    "gameVersion": "12345678",
    "graphicsBackend": "d3dmetal",
    "profile": {"launchArguments": ["-dx11"], "graphicsAPI": "gameDefault"}
  },
  "createdAt": 815270400
}
```
