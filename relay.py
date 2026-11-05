"""Single-process relay. Run behind an HTTPS reverse proxy."""
import hashlib
from contextlib import contextmanager
import hmac
import math
import os
import secrets
import sqlite3
import time
from flask import Flask, request, jsonify, abort

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 8192
OWNER_KEY = os.environ.get('OWNER_KEY', '')
if len(OWNER_KEY) < 32:
    raise RuntimeError('Set OWNER_KEY to a random secret of at least 32 characters')
DB = os.environ.get('DATABASE_PATH', 'relay.sqlite3')

@contextmanager
def connect():
    db = sqlite3.connect(DB, timeout=10)
    db.row_factory = sqlite3.Row
    try:
        with db:
            yield db
    finally:
        db.close()

with connect() as db:
    db.executescript('''
    CREATE TABLE IF NOT EXISTS clients (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, token_hash TEXT NOT NULL,
      seen REAL DEFAULT 0, job TEXT DEFAULT '');
    CREATE TABLE IF NOT EXISTS commands (
      id INTEGER PRIMARY KEY AUTOINCREMENT, client TEXT NOT NULL,
      body TEXT NOT NULL, expires REAL NOT NULL, ack INTEGER DEFAULT 0);
    ''')

def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()

def bearer():
    value = request.headers.get('Authorization', '')
    if not value.startswith('Bearer '):
        abort(401)
    return value[7:]

def owner():
    if not hmac.compare_digest(bearer(), OWNER_KEY):
        abort(403)

def client(db):
    row = db.execute('SELECT * FROM clients WHERE token_hash=?', (digest(bearer()),)).fetchone()
    if row is None:
        abort(403)
    return row

@app.get('/health')
def health():
    return jsonify(ok=True)

@app.route('/clients', methods=['GET', 'POST'])
def clients():
    owner()
    with connect() as db:
        if request.method == 'GET':
            return jsonify(clients=[dict(r) for r in db.execute('SELECT id,name,seen,job FROM clients')])
        data = request.get_json()
        uid, name = str(data.get('id', '')), str(data.get('name', ''))
        if not uid.isdigit() or len(uid) > 20 or not 1 <= len(name) <= 32:
            abort(400)
        token = secrets.token_urlsafe(32)
        db.execute('INSERT INTO clients(id,name,token_hash) VALUES(?,?,?) '
                   'ON CONFLICT(id) DO UPDATE SET name=excluded.name,token_hash=excluded.token_hash,seen=0,job=\'\'',
                   (uid, name, digest(token)))
        db.execute('DELETE FROM commands WHERE client=?', (uid,))
    return jsonify(id=uid, token=token)

@app.delete('/clients/<uid>')
def revoke(uid):
    owner()
    with connect() as db:
        db.execute('DELETE FROM clients WHERE id=?', (uid,))
        db.execute('DELETE FROM commands WHERE client=?', (uid,))
    return jsonify(ok=True)

@app.post('/poll')
def poll():
    data = request.get_json()
    with connect() as db:
        c = client(db)
        job = str(data.get('job', ''))[:128]
        if str(data.get('id')) != c['id'] or not job:
            abort(403)
        # Drop commands from an old server session.
        if c['job'] != job:
            db.execute('DELETE FROM commands WHERE client=?', (c['id'],))
        db.execute('UPDATE clients SET seen=?,job=? WHERE id=?', (time.time(), job, c['id']))
        db.execute('DELETE FROM commands WHERE expires<?', (time.time(),))
        rows = db.execute('SELECT id,body FROM commands WHERE client=? AND ack=0 ORDER BY id LIMIT 20', (c['id'],)).fetchall()
    import json
    return jsonify(commands=[dict(id=r['id'], **json.loads(r['body'])) for r in rows])

@app.post('/ack')
def ack():
    data = request.get_json()
    ids = data.get('ids', [])
    if not isinstance(ids, list) or len(ids) > 20 or any(type(i) is not int for i in ids):
        abort(400)
    with connect() as db:
        c = client(db)
        db.executemany('DELETE FROM commands WHERE id=? AND client=?', [(i, c['id']) for i in ids])
    return jsonify(ok=True)

@app.post('/command')
def command():
    owner()
    data = request.get_json()
    uid, name = str(data.get('target', '')), data.get('command')
    allowed = {'bring', 'kill', 'fling', 'kick', 'freeze', 'unfreeze', 'walkspeed', 'jumppower'}
    if name not in allowed:
        abort(400)
    payload = {'command': name}
    if name in {'walkspeed', 'jumppower'}:
        value = data.get('value')
        if type(value) not in (int, float) or not math.isfinite(value) or not 0 <= value <= 200:
            abort(400)
        payload['value'] = value
    if name == 'bring':
        pos = data.get('position')
        if not isinstance(pos, list) or len(pos) != 3 or any(type(v) not in (int, float) or not math.isfinite(v) or abs(v) > 1000000 for v in pos):
            abort(400)
        payload['position'] = pos
    import json
    with connect() as db:
        c = db.execute('SELECT * FROM clients WHERE id=?', (uid,)).fetchone()
        if not c or c['seen'] < time.time() - 15:
            return jsonify(error='Target is offline'), 409
        if not data.get('job') or data['job'] != c['job']:
            return jsonify(error='Target is in a different Roblox server'), 409
        count = db.execute('SELECT count(*) FROM commands WHERE client=? AND expires>?', (uid, time.time())).fetchone()[0]
        if count >= 20:
            abort(429)
        db.execute('INSERT INTO commands(client,body,expires) VALUES(?,?,?)', (uid, json.dumps(payload), time.time()+10))
    return jsonify(queued=True)

@app.errorhandler(400)
@app.errorhandler(401)
@app.errorhandler(403)
@app.errorhandler(413)
@app.errorhandler(429)
def error(err):
    return jsonify(error=err.name), err.code
