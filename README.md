# Owner / free-user Luau relay

Status: backend and client files built; backend checks tested locally. NOT hosted,
NOT tested in Roblox or any executor. Requires an executor exposing request,
http_request, or syn.request. Chat delivery differs between executors; a console
command function is provided. No Studio server scripts are needed.

## Start the backend

Use Python 3.11+ in this folder:

    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt
    export OWNER_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
    gunicorn --workers 1 --threads 4 --bind 0.0.0.0:8000 relay:app

Store the generated OWNER_KEY in a private password manager before closing this
terminal. Retrieve it locally from your environment; do not send it in chat or
commit it. Never give it to free users. The server refuses short/missing keys.
On a host, configure OWNER_KEY as a secret environment variable and use:

    gunicorn --workers 1 --threads 4 --bind 0.0.0.0:$PORT relay:app

Use a public HTTPS address for remote clients. Localhost only reaches the same
computer. A live URL requires hosting; nothing in this folder creates one.
Keep DATABASE_PATH on a persistent disk for durable enrollments. The default
SQLite file is relative to the working directory; ephemeral hosts may erase it.
Run one instance; this SQLite design is intended for a small deployment.

## Enroll a free user

From another terminal in this folder:

    python3 manage.py https://YOUR-RELAY-HOST add --id 123456 --name TheirUsername

The helper privately prompts for the owner key and prints a new client token.
Give ONLY that token to that free user. Re-adding their ID rotates their token.

    python3 manage.py https://YOUR-RELAY-HOST list
    python3 manage.py https://YOUR-RELAY-HOST revoke --id 123456

## Configure the same client file for each role

In client.luau set URL to the public HTTPS address.

Your private copy: ROLE = "owner", KEY = your OWNER_KEY.
Their copy: ROLE = "free", KEY = their individual client token.

Keep the owner copy private. Selecting ROLE="owner" without the owner key does
not grant access. Client keys can only poll/ack their own assigned inbox.
Token-to-user-ID binding prevents accidental use by another account in the
unmodified client; it is NOT proof of Roblox identity. Modified clients can lie
about their ID or JobId. Do not use this relay as a purchase/license verifier.

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

Commands target one enrolled user in your current Roblox server. Username
prefixes must be unambiguous; numeric user IDs also work. This version doesn't
include all-player commands. The owner is a sender, not a receiving client.

If your executor does not deliver LocalPlayer.Chatted, use its console:

    getgenv().OwnerRelay.command("bring username")

A free user can stop participating:

    getgenv().OwnerRelay.stop()

Re-running the client stops the previous polling loop and chat listener.

## Behavior and limitations

The target client performs the command on itself. Kick calls LocalPlayer:Kick;
bring moves their character to the owner's transmitted position. Fling applies
velocity to the target character, not other characters. Server checks can undo
movement, health, speed, jump, or physics changes. No server authority is gained.
Freeze/speed/jump changes aren't reapplied after respawn. Stop unanchors a root
frozen by this script, but doesn't reset speed/jump or reverse completed actions.

Poll interval is approximately one second, with backoff on errors. Commands
expire after ten seconds; offline targets are rejected. Queues are bounded,
commands are retried until acknowledged/expired, and the running client remembers
recent command IDs to suppress duplicates. Restarting the client before an ack
can repeat a command. Acknowledged means attempted, not verified game success;
there is no owner-facing execution receipt yet. Kick can disconnect before ack.

Only the fixed command allowlist is supported; no remote Lua evaluation or
arbitrary downloaded code. Run HTTPS through your hosting platform and add edge
rate limits for a public deployment. SQLite enrollments survive process restarts
when the disk is persistent. Credentials remain inspectable by anyone who has
the client copy containing them.

Reference: https://create.roblox.com/docs/reference/engine/classes/Player#Kick
