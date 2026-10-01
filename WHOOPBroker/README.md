# WHOOP connector setup

This optional server exchanges OAuth codes and refreshes tokens. It does not
collect or store health measurements. The iPhone fetches them directly from
WHOOP and stores them locally in SwiftData. No WHOOP client secret belongs in
the iOS app, its Info.plist, or git.

1. Create an app at https://developer-dashboard.whoop.com/ using your WHOOP
   account. Enable `read:cycles`, `read:recovery`, `read:sleep`, `read:workout`,
   and `read:body_measurement`.
2. Deploy `server.mjs` as a Node 22+ service behind HTTPS. Set server-side
   environment variables `WHOOP_CLIENT_ID`, `WHOOP_CLIENT_SECRET`, and
   `PUBLIC_URL` (the HTTPS origin, for example `https://whoop.example.com`).
   The service listens on `PORT` (8080 by default). Start with `npm start`.
3. Register `https://whoop.example.com/callback` as the WHOOP redirect URL.
   `PUBLIC_URL` must match that origin exactly. Do not register the iPhone's
   custom URL scheme with WHOOP; the server owns the WHOOP callback.
4. In Locked In Fit → Settings → WHOOP, enter the HTTPS origin and tap
   **Connect WHOOP**. Consent includes `offline` for rotating refresh tokens.
5. The first connection imports 30 days. Choose 90 days or one year to backfill.
   Pull to refresh for a manual sync. Foreground activation refreshes the last
   week when the previous sync is more than 15 minutes old.

`GET /health` is a readiness check. Auth state expires in ten minutes;
exchange tickets expire after one minute and are usable once. The browser
redirect contains a ticket, never access/refresh tokens. Tokens and state
exist only in process memory, so an in-progress authorization must restart if
that instance restarts. Use one instance or sticky routing; multiple independent
instances cannot finish each other's handshakes. Disable query-string/body
logging in your reverse proxy. Rate limiting uses the actual socket IP, which
means requests behind one reverse proxy share a limit (60/minute). For a public,
multi-user deployment, add edge rate limiting with a trusted proxy policy and
a shared expiring session store first.

No server is provisioned by this code change. Live consent/sync needs a registered
WHOOP app and the hosted connector. No credentials are preconfigured.

## Data semantics

- API v2; paginated collections; cycles use numeric IDs, sleep/workouts UUIDs.
- Recovery joins by cycle ID; sleep is displayed on the wake date. Cycles are
  physiological intervals and must not be treated as midnight calendar days.
- All response fields are preserved in the local raw record and JSON backup.
- Energy converts kJ ÷ 4.184 to kcal. Cycle energy is **total** energy, never
  an extra active-energy credit. WHOOP workout records don't duplicate manual
  workouts, strength scores, or Apple Health activity totals.
- Pending/missing/calibrating values remain explicit; missing is never zero.
- Profile weight is undated; it does not become a fake scale entry.
- Stress Monitor, Healthspan/WHOOP Age, Pace of Aging, and journal insights are
  not in the public API. The UI explicitly identifies this limitation.
- Disconnect revokes access and retains imported history. Delete history is a
  separate confirmed action; old backups can still contain those records.
- Refresh imports update known IDs. Remote deletions are not automatically
  propagated: local history is retained, and the user may explicitly delete it.

Run `npm test` to verify state binding, one-time tickets, expiry, refresh,
and HTTPS configuration checks. Official reference: https://developer.whoop.com/api/
and https://developer.whoop.com/docs/developing/oauth/.
