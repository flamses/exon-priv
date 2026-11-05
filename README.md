# Exon private / free relay

Public script: `client.luau`. Anyone can run it without entering a key or being
registered manually. It registers a temporary session automatically and reconnects
if hosting storage is reset. Free users receive the owner's commands while the
script is running. The script announces this in the executor console and provides
`getgenv().OwnerRelay.stop()` to disconnect.

## Owner whitelist

Edit `owners.txt`, one Roblox numeric user ID per line. Comments after # are fine.
Commit your changes to main; Render redeploys the file automatically.
FlamesT_T (9140430988) is already listed.

Owners use the private configured script provided separately. Keep it private:
it contains OWNER_KEY. To prepare a copy yourself, copy client.luau and set its
OWNER_KEY to your Render secret. No key is entered by free users. The script
selects owner mode when its Roblox ID is whitelisted AND its copy has the private
credential. Both conditions are checked for owner API calls. A whitelisted user
running the public script must switch to their private copy for commands.
Removing a user ID from owners.txt removes that ID's owner authorization after
deployment. Whitelisted IDs cannot be targeted by the relay.

An executor can falsify the user ID it sends over HTTP. A text whitelist alone
cannot authenticate ownership. Anyone who obtains the shared owner credential
can impersonate an allowed owner ID; do not distribute it with the public script.
Use separate credentials per owner or Roblox OAuth if you need stronger identity
verification for multiple mutually untrusted owners.

## Commands

    !users
    !bring username
    !kill username
    !fling username
    !kick username
    !freeze username
    !unfreeze username
    !walkspeed username 50
    !jumppower username 100
    !stop

Targets must run the free script in your Roblox server. Numeric IDs and
unambiguous username prefixes work. If executor chat events do not work:

    getgenv().OwnerRelay.command("bring username")

## Hosting

The deployment is https://exon-priv-relay.onrender.com with /health for readiness.
Source: https://github.com/flamses/exon-priv

For another deployment, use Python 3.11+, install requirements.txt, configure
OWNER_KEY as a secret random value of at least 32 characters, then start:

    gunicorn --workers 1 --threads 4 --bind 0.0.0.0:$PORT relay:app

Configure the public HTTPS URL in client.luau. Optional DATABASE_PATH and
OWNERS_FILE override local paths. The database stores short-lived sessions, not
owner grants. The committed owners.txt survives deploys; free clients reconnect
automatically after an ephemeral database reset. Free hosting may sleep when idle.

## Limits

Requires executor request, http_request, or syn.request. Actual executor behavior
has not been tested. The target client runs actions on itself; game servers can
undo health, movement, speed, jump, or physics changes. This grants no server
permissions. Fling changes the receiving player's velocity only. Character
changes aren't automatically reapplied after respawn. Stop unfreezes a character
frozen by this script; it does not restore previous speed or jump values.

Commands expire in ten seconds and target sessions active within fifteen seconds.
Polling is about once per second, with backoff during failures. Acknowledgment
means attempted execution, not verified game success. Commands aren't arbitrary
Lua: only the fixed command allowlist is accepted.

Sessions have independent tokens generated automatically in memory. A duplicate
registration cannot replace an existing inbox. IDs and server IDs claimed by free
clients aren't verified Roblox identities. A modified client can create fake
sessions. Public registration is bounded to 2000 recent sessions; add hosting-edge
rate limits for wider distribution. Idle sessions expire after two minutes.
Public registration is open: revoking a session is not a permanent ban.
