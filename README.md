# Exon v2 — owner panel and automatic free clients

Run `client.luau` publicly: no key entry or manual enrollment. Free users connect
automatically, see a participation badge, and can click it to stop. Owners use the
private script provided separately; never publish a copy containing OWNER_KEY.

## Owner panel

The panel opens for a whitelisted owner using the private credential. Right Shift
or `!gui` hides/shows it. Drag the header to move it. It scales to the viewport.

The left list refreshes every five seconds and includes connected free clients
across games, usernames, display names, game/place names, and server status.
Search, click a row, then click a command. A numeric value field is optional:
blank uses the default printed on the button. Join server teleports the owner
to the selected connection's place and instance; access restrictions, full servers,
and Roblox teleport rules still apply. Re-run the owner script after teleporting.
Bring requires the same server and place. Other commands can address a connected
client in another game. The selected connection never silently changes to another
connection. Queued means sent, not verified game success.

Game details come from the participating client; this is not an online tracker
for people who haven't run the script. Old free scripts need updating to report
place/game details and support the new commands. Refresh after the update.

## Short names and chat

    !disco f
    !ws flames 60
    !spin flames 12
    !join username
    !blur "Display Name" 24
    !users
    !help
    !gui
    !stop

Matching ranks exact numeric ID, exact @username, display name, punctuation-
normalized names, prefixes, and literal substring matches. A one-character typo
fallback applies only to queries of at least four characters. Ambiguous matches
are rejected with a list of candidates. No raw regex is evaluated. A single letter
works when unambiguous. Quoted display names can contain spaces. Multiple sessions
of the same account require a GUI selection unless one is in the owner's server.

Aliases: ws/speed → walkspeed, jp → jumppower, tp → bring, stopdisco → undisco,
stand → unsit, reset → resetstats, unnoclip → clip.

## 39 commands

Character: bring, kill, heal, sit, unsit, jump, freeze, unfreeze, fling, kick.
Movement: walkspeed, jumppower, spin, unspin, noclip, clip, gravity, ungravity,
resetstats.
Effects: disco, undisco, blind, unblind, blur, unblur, fov, unfov, invisible,
visible, smoke, unsmoke, sparkles, unsparkles, fire, unfire.
Lighting: day, night, fullbright, unfullbright.

Value defaults / accepted ranges:
walkspeed 50 / 0–200; jumppower 100 / 0–200; spin 10 / 0–50;
blur 24 / 0–56; fov 100 / 20–120; gravity 60 / 0–500.

Undo commands restore properties captured before the effect. Stop and re-execution
remove owned effects and listeners. Character effects are cleared on respawn.
Invisible, screen effects, lighting, and cosmetic particles are local to the
receiving client; they don't promise visibility to other players. Servers can undo
health, movement, physics, speed, or jump changes. This grants no server authority.

## Owners

Edit owners.txt with one numeric Roblox user ID per line. FlamesT_T (9140430988)
is listed. Commit changes and select Manual Deploy → Deploy latest commit in
Render. This public-repository connection requires a manual deployment; connecting
the Git provider in Render can enable automatic deployment.

Owner access requires both an ID on the list and the private OWNER_KEY. An executor
can lie about its ID; the text file is not identity verification. Keep the private
credential out of the public script, GitHub, messages, and logs. Anyone possessing
it can claim another whitelisted ID. Owners cannot be command targets.

## Hosting and compatibility

Live relay: https://exon-priv-relay.onrender.com (readiness: /health)
Source: https://github.com/flamses/exon-priv
Python 3.11+, `pip install -r requirements.txt`, set a random OWNER_KEY secret of
at least 32 characters, then:

    gunicorn --workers 1 --threads 4 --bind 0.0.0.0:$PORT relay:app

Optional DATABASE_PATH / OWNERS_FILE override paths. SQLite migrations preserve
existing sessions. Committed owner grants survive deploys; free clients reconnect
if ephemeral storage is reset. Free hosting may sleep when idle.

Requires executor request/http_request/syn.request, Roblox GUI and teleport APIs.
The Luau compiles; matching, owner controls, and effect cleanup are exercised in
mock runtime checks, not a real executor. Backend tests cover auth, metadata,
version compatibility, exact-session routing, bounds, queues and acknowledgments.
Real in-game layout and executor behavior still need user verification.

Polling is about once per second with failure backoff; online means seen within
15 seconds. Commands expire after ten seconds. Registration is public, bounded to
2000 sessions, and idle sessions expire in two minutes. Independent session tokens
prevent a new registration from replacing an existing inbox. Claims of Roblox ID,
place and server aren't authenticated identities. Add hosting-edge rate limits for
wider distribution. Only fixed allowlisted commands are accepted; no arbitrary Lua.
