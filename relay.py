"""Automatic free-client enrollment with separately authenticated owners."""
from contextlib import contextmanager
from pathlib import Path
import hashlib
import hmac
import json
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
OWNERS_FILE = Path(os.environ.get('OWNERS_FILE', str(Path(__file__).with_name('owners.txt'))))

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
    CREATE TABLE IF NOT EXISTS sessions (
      sid TEXT PRIMARY KEY, uid TEXT NOT NULL, name TEXT NOT NULL,
      token_hash TEXT UNIQUE NOT NULL, seen REAL NOT NULL, job TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS sessions_target ON sessions(uid,job,seen);
    CREATE TABLE IF NOT EXISTS inbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT, sid TEXT NOT NULL,
      body TEXT NOT NULL, expires REAL NOT NULL);
    ''')
    existing = {row['name'] for row in db.execute('PRAGMA table_info(sessions)')}
    for column, definition in {'place': 'INTEGER DEFAULT 0', 'game_name': "TEXT DEFAULT ''", 'display': "TEXT DEFAULT ''", 'version': 'INTEGER DEFAULT 1'}.items():
        if column not in existing:
            db.execute(f'ALTER TABLE sessions ADD COLUMN {column} {definition}')

def owners():
    try:
        lines = OWNERS_FILE.read_text().splitlines()
        return {line.split('#', 1)[0].strip() for line in lines
                if line.split('#', 1)[0].strip().isdigit()}
    except OSError:
        return set() # Missing file must never open owner access.

def bearer():
    value = request.headers.get('Authorization', '')
    if not value.startswith('Bearer '):
        abort(401)
    return value[7:]

def owner():
    if not hmac.compare_digest(bearer(), OWNER_KEY):
        abort(403)
    if request.headers.get('X-Owner-Id', '') not in owners():
        abort(403)

def client(db):
    token_hash = hashlib.sha256(bearer().encode()).hexdigest()
    row = db.execute('SELECT * FROM sessions WHERE token_hash=?', (token_hash,)).fetchone()
    if row is None:
        abort(403)
    return row

def data():
    value = request.get_json()
    if not isinstance(value, dict):
        abort(400)
    return value

def cleanup(db):
    now = time.time()
    db.execute('DELETE FROM inbox WHERE expires<?', (now,))
    db.execute('DELETE FROM sessions WHERE seen<?', (now-120,))
    db.execute('DELETE FROM inbox WHERE sid NOT IN (SELECT sid FROM sessions)')

@app.get('/health')
def health():
    with connect() as db:
        db.execute('SELECT 1').fetchone()
    return jsonify(ok=True)

@app.post('/role')
def role():
    return jsonify(owner=str(data().get('id', '')) in owners())

@app.post('/join')
def join():
    d = data()
    uid, name, job = str(d.get('id', '')), d.get('name'), d.get('job')
    if not uid.isdigit() or len(uid)>20 or not isinstance(name,str) or not 1<=len(name)<=32 or not isinstance(job,str) or not 1<=len(job)<=128:
        abort(400)
    place = d.get('place', 0)
    if type(place) is not int or not 0 <= place <= 10**16:
        abort(400)
    display = str(d.get('display', name))[:64]
    game_name = str(d.get('game_name', ''))[:160]
    version = d.get('version', 1)
    if type(version) is not int or not 1 <= version <= 100:
        abort(400)
    token, sid = secrets.token_urlsafe(32), secrets.token_urlsafe(18)
    with connect() as db:
        cleanup(db)
        # Bounded public registration; each client has a separate inbox. A new
        # registration never takes over somebody else's existing connection.
        if db.execute('SELECT count(*) FROM sessions').fetchone()[0] >= 2000:
            abort(429)
        db.execute('INSERT INTO sessions(sid,uid,name,token_hash,seen,job,place,game_name,display,version) VALUES(?,?,?,?,?,?,?,?,?,?)',
                   (sid,uid,name,hashlib.sha256(token.encode()).hexdigest(),time.time(),job,place,game_name,display,version))
    return jsonify(token=token)

@app.get('/clients')
def clients():
    owner()
    with connect() as db:
        cleanup(db)
        rows=db.execute('SELECT sid,uid AS id,name,seen,job,place,game_name,display,version FROM sessions WHERE seen>?', (time.time()-15,)).fetchall()
    return jsonify(clients=[dict(r, owner=r['id'] in owners()) for r in rows])

@app.delete('/clients/<sid>')
def revoke(sid):
    owner()
    with connect() as db:
        db.execute('DELETE FROM sessions WHERE sid=?', (sid,))
        db.execute('DELETE FROM inbox WHERE sid=?', (sid,))
    return jsonify(ok=True)

@app.post('/poll')
def poll():
    metadata = request.get_json(silent=True) or {}
    if not isinstance(metadata, dict):
        abort(400)
    with connect() as db:
        c = client(db)
        db.execute('UPDATE sessions SET seen=?,game_name=? WHERE sid=?', (time.time(),str(metadata.get('game_name', c['game_name']))[:160],c['sid']))
        cleanup(db)
        rows=db.execute('SELECT id,body FROM inbox WHERE sid=? ORDER BY id LIMIT 20', (c['sid'],)).fetchall()
    return jsonify(commands=[dict(id=r['id'],**json.loads(r['body'])) for r in rows])

@app.post('/ack')
def ack():
    ids=data().get('ids', [])
    if not isinstance(ids,list) or len(ids)>20 or any(type(i) is not int for i in ids):
        abort(400)
    with connect() as db:
        c=client(db)
        db.executemany('DELETE FROM inbox WHERE id=? AND sid=?',[(i,c['sid']) for i in ids])
    return jsonify(ok=True)

@app.post('/command')
def command():
    owner()
    d=data()
    uid,name=str(d.get('target','')),d.get('command')
    allowed={'bring','kill','fling','kick','freeze','unfreeze','walkspeed','jumppower',
             'disco','undisco','spin','unspin','sit','unsit','jump','heal','invisible','visible',
             'noclip','clip','blind','unblind','blur','unblur','fov','unfov','gravity','ungravity',
             'resetstats','day','night','fullbright','unfullbright','smoke','unsmoke',
             'sparkles','unsparkles','fire','unfire'}
    if not isinstance(name,str) or name not in allowed:
        abort(400)
    if uid in owners():
        return jsonify(error='Owners cannot be targeted'),403
    payload={'command':name}
    bounds = {'walkspeed': (0,200), 'jumppower': (0,200), 'spin': (0,50), 'blur': (0,56), 'fov': (20,120), 'gravity': (0,500)}
    if name in bounds:
        v=d.get('value')
        if type(v) not in (int,float) or not math.isfinite(v) or not bounds[name][0]<=v<=bounds[name][1]:
            abort(400)
        payload['value']=v
    if name=='bring':
        p=d.get('position')
        if not isinstance(p,list) or len(p)!=3 or any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>1000000 for v in p):
            abort(400)
        payload['position']=p
    with connect() as db:
        cleanup(db)
        targets=db.execute('SELECT sid,place,job,version FROM sessions WHERE uid=? AND job=? AND seen>?', (uid,d.get('job',''),time.time()-15)).fetchall()
        if d.get('session'):
            targets=[target for target in targets if target['sid']==d['session']]
        if not targets:
            registered=db.execute('SELECT job,seen FROM sessions WHERE uid=? ORDER BY seen DESC LIMIT 1',(uid,)).fetchone()
            reason = 'Free script is not connected. Run the free script on the target account.'
            if registered:
                reason = ('Target connection is stale. Re-run the free script.' if registered['seen'] < time.time()-15
                          else 'Target is connected in a different server. Refresh the user list.')
            return jsonify(error=reason),409
        if name == 'bring' and d.get('origin_job') is not None:
            if any(target['job'] != d['origin_job'] or target['place'] != d.get('origin_place') for target in targets):
                return jsonify(error='Join this user first before using Bring.'),409
        if name not in {'bring','kill','fling','kick','freeze','unfreeze','walkspeed','jumppower'} and any(t['version'] < 2 for t in targets):
            return jsonify(error='Target needs the new free script for this command.'),409
        for target in targets:
            count=db.execute('SELECT count(*) FROM inbox WHERE sid=?',(target['sid'],)).fetchone()[0]
            if count>=20:
                abort(429)
        for target in targets:
            db.execute('INSERT INTO inbox(sid,body,expires) VALUES(?,?,?)', (target['sid'],json.dumps(payload),time.time()+10))
    return jsonify(queued=True)

@app.errorhandler(400)
@app.errorhandler(401)
@app.errorhandler(403)
@app.errorhandler(413)
@app.errorhandler(429)
def error(err):
    return jsonify(error=err.name),err.code
