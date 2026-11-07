# Exon v3 — one shared chat-only script-hub chunk

**No GUI, status badge, fire, sparkles, disco, screen effects or lighting tricks.**
`client.luau` is identical for owners and free users. Paste the whole chunk at the
top of your script hub, or use this public loader:

```luau
loadstring(game:HttpGet("https://raw.githubusercontent.com/flamses/exon-priv/main/client.luau"))()
```

The chunk runs in an isolated `do` block and starts networking asynchronously.
It doesn't return from your surrounding hub. Free users enroll automatically,
without entering a key. The console tells them owner commands are active.
They can use `!stop` or `getgenv().Exon.stop()` to stop participating.

## Owner setup — one time in your own executor

Run the PRIVATE owner-setup file supplied separately. It sets EXON_OWNER_KEY in
your own executor and, when writefile is available, stores it in that executor's
`exon-owner-key.txt`. It then loads the same public chunk. Later the public chunk
reads that local key automatically. Without file support, run private setup again
each new executor session. Keep the setup and key private; never paste either
into the distributed script hub or GitHub.

Owner access still needs an ID in owners.txt AND the private credential. The
whitelist currently includes FlamesT_T (9140430988). A user ID claimed over HTTP
isn't identity proof: publishing an owner credential would let others impersonate
an owner. Multiple owners sharing a credential must trust each other.

## Examples

```text
!help
!users
!goto flames
!join flames
!locate flames
!bring f
!walkspeed f 50
!rejoin me
!serverhop me
!hoplow me
!hophigh me
!rejoin f
!follow f 4
!orbit f 8
!unfollow f
!tpcoords me 0 20 0
!savepos spawn
!loadpos spawn
!back
!stop
```

Actions use `!command target arguments`. Omit the target for yourself:
`!rejoin` and `!serverhop` act on the owner. Numeric actions still use an explicit
target: `!walkspeed me 50`. Queries default to yourself too. `goto` moves the owner
to a player in the current server. `join` teleports the owner to a connected free
user's place and server. `bring`, `follow` and `orbit` require a shared server.
Remote actions affect only people running this unified version; other owners
cannot be targeted. Teleport actions leave the current game and require you to
re-run the hub after arriving; there is no executor teleport-queue injection.

Matching supports ID, @username, exact display names, punctuation normalization,
prefixes, literal substrings and a bounded one-character typo fallback for longer
queries. Ambiguous short names are rejected. Quote display names containing spaces.
No arbitrary regex or arbitrary Lua execution is accepted.

## 124 command names

There are 82 character/travel actions and 42 information, navigation, bookmark and
connection commands. Aliases are extra and aren't counted. Full syntax appears in
COMMANDS.md. Console output uses print/warn, never a custom GUI.

This is **not 124 guaranteed FE powers**. Teleports join real Roblox servers.
Character motion, controller actions, emotes and tools may be visible to others
when accepted by Roblox and the game. Server validation can undo movement, health,
speed, collisions, tool changes and physics. Client-side health/property writes
do not grant server authority. Emotes require the avatar to have the named emote;
tool actions require usable tools. Informational commands just print information.
The implementation doesn't create fake cosmetic effects to inflate the count.

## Server hopping and travel

Server discovery queries Roblox's public server API, scans up to three pages,
excludes the current/full servers, and picks random, lowest-population or highest-
population candidates from those pages. This isn't a global guarantee of the
smallest/largest server. Roblox rate limits, privacy, access checks and full-server
races can prevent joining. Failure is printed. No relay secret is sent to Roblox's
server-discovery endpoint. Place IDs must be valid accessible integer IDs.

## Owner list and deployment

Edit owners.txt, one numeric ID per line. Commit and choose Manual Deploy → Deploy
latest commit in Render. This public-repository connection requires manual deploys.
Source: https://github.com/flamses/exon-priv
Relay: https://exon-priv-relay.onrender.com (readiness: /health)

Python 3.11+, `pip install -r requirements.txt`, a random OWNER_KEY environment
secret of at least 32 characters, and:

    gunicorn --workers 1 --threads 4 --bind 0.0.0.0:$PORT relay:app

commands.json is the backend command allowlist. New actions require client version
3. Old GUI versions are no longer compatible for remote actions. Free clients
reconnect after temporary hosting storage resets. The owner list lives in Git.

## Checks and practical limits

The Luau compiles. Mock runtime checks exercise all 82 action handlers, both roles,
short-name safety, credential routing, bookmarks, cleanup, script-hub continuation
and absence of GUI creation. Backend tests cover every action's payload, owner
permissions, exact sessions, version gates, removed cosmetics, bounds and queues.
These checks don't verify real Roblox replication or executor compatibility.

Undo/Stop restores properties and removes movement helpers created by this chunk.
Character effects clear on respawn. Completed teleports, deaths, tool drops and
position changes aren't undone. Saved positions and visited-server history live
in the executor's runtime, not a cross-device database.

Polling is roughly once a second with backoff. Pausing stops polling; resume joins
a fresh session. Free users can disconnect. Queued means sent, not confirmed game
success. Commands expire in ten seconds. Public enrollment has independent tokens,
a 2000-session cap and two-minute idle cleanup. Roblox IDs and place/server claims
from executor clients aren't authenticated identities. Add edge rate limits for
wide distribution. Owner sessions use a session token for polling and the separate
private credential only for owner endpoints.
