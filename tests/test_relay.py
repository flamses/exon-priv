import os, sys, tempfile, unittest
from pathlib import Path
root=tempfile.TemporaryDirectory()
os.environ['OWNER_KEY']='test-key-'+'x'*40
os.environ['DATABASE_PATH']=root.name+'/db.sqlite3'
os.environ['OWNERS_FILE']=root.name+'/owners.txt'
Path(os.environ['OWNERS_FILE']).write_text('9140430988 # owner\n')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from relay import app,connect
class Tests(unittest.TestCase):
 def setUp(self):
  self.c=app.test_client()
  self.owner={'Authorization':'Bearer '+os.environ['OWNER_KEY'],'X-Owner-Id':'9140430988'}
  with connect() as db:
   db.execute('DELETE FROM sessions');db.execute('DELETE FROM inbox')
 def join(self,uid='123'):
  r=self.c.post('/join',json={'id':uid,'name':'Target','job':'server-A'})
  self.assertEqual(r.status_code,200)
  return {'Authorization':'Bearer '+r.json['token']}
 def cmd(self,headers=None,**kw):
  return self.c.post('/command',headers=self.owner if headers is None else headers,json={'target':'123','command':'freeze','job':'server-A',**kw})
 def test_public_join_and_no_owner_escalation(self):
  free=self.join('9140430988')
  self.assertTrue(self.c.post('/role',json={'id':'9140430988'}).json['owner'])
  self.assertEqual(self.cmd(free).status_code,403)
  self.assertEqual(self.cmd({'Authorization':self.owner['Authorization']}).status_code,403)
  self.assertEqual(self.cmd({**self.owner,'X-Owner-Id':'123'}).status_code,403)
  self.assertEqual(self.cmd(target='9140430988').status_code,403)
 def test_independent_inboxes_retry_ack(self):
  a=self.join();b=self.join()
  self.assertEqual(self.cmd().status_code,200)
  first=self.c.post('/poll',headers=a).json['commands']
  second=self.c.post('/poll',headers=b).json['commands']
  self.assertEqual(len(first),1);self.assertEqual(len(second),1)
  self.assertNotEqual(first[0]['id'],second[0]['id'])
  self.c.post('/ack',headers=a,json={'ids':[second[0]['id']]})
  self.assertEqual(self.c.post('/poll',headers=b).json['commands'],second)
  self.c.post('/ack',headers=a,json={'ids':[first[0]['id']]})
  self.assertEqual(self.c.post('/poll',headers=a).json['commands'],[])
 def test_validation_offline_and_bounds(self):
  self.assertEqual(self.cmd().status_code,409)
  self.join()
  self.assertEqual(self.cmd(job='other').status_code,409)
  self.assertEqual(self.cmd(command='walkspeed',value=True).status_code,400)
  self.assertEqual(self.cmd(command='eval').status_code,400)
  self.assertEqual(self.cmd(command=[]).status_code,400)
  self.assertEqual(self.c.post('/join',json=[]).status_code,400)
  for _ in range(20): self.assertEqual(self.cmd().status_code,200)
  self.assertEqual(self.cmd().status_code,429)
 def test_expiry_and_whitelist_revocation(self):
  a=self.join(); self.cmd()
  with connect() as db: db.execute('UPDATE inbox SET expires=0')
  self.assertEqual(self.c.post('/poll',headers=a).json['commands'],[])
  path=Path(os.environ['OWNERS_FILE']);path.write_text('')
  try:self.assertEqual(self.cmd().status_code,403)
  finally:path.write_text('9140430988\n')
 def test_rejoin_after_database_reset(self):
  a=self.join()
  with connect() as db:db.execute('DELETE FROM sessions')
  self.assertEqual(self.c.post('/poll',headers=a).status_code,403)
  b=self.join()
  self.assertEqual(self.c.post('/poll',headers=b).status_code,200)

 def test_game_details_and_heartbeat(self):
  r=self.c.post('/join',json={'id':'123','name':'Target','display':'Display Name','job':'server-A','place':999,'game_name':'Before','version':2})
  free={'Authorization':'Bearer '+r.json['token']}
  self.c.post('/poll',headers=free,json={'game_name':'Resolved Game'})
  user=self.c.get('/clients',headers=self.owner).json['clients'][0]
  self.assertEqual(user['place'],999);self.assertEqual(user['game_name'],'Resolved Game');self.assertEqual(user['version'],2)
  self.assertEqual(user['display'],'Display Name')
 def test_new_command_version_gate_and_validation(self):
  self.join()
  self.assertEqual(self.cmd(command='disco').status_code,409)
  with connect() as db:db.execute('UPDATE sessions SET version=2')
  for command in ['disco','undisco','noclip','clip','heal','blind','unblind','day','night','resetstats','spin','blur','fov','gravity']:
   extra={'value':25} if command in ['spin','blur','fov','gravity'] else {}
   self.assertEqual(self.cmd(command=command,**extra).status_code,200,command)
  self.assertEqual(self.cmd(command='spin',value=51).status_code,400)
  self.assertEqual(self.cmd(command='fov',value=0).status_code,400)
 def test_exact_session_and_cross_server_bring(self):
  a=self.join();b=self.join()
  rows=self.c.get('/clients',headers=self.owner).json['clients']
  sid=rows[0]['sid']
  self.assertEqual(self.cmd(session=sid).status_code,200)
  with connect() as db:
   self.assertEqual(db.execute('SELECT count(*) FROM inbox').fetchone()[0],1)
   self.assertEqual(db.execute('SELECT sid FROM inbox').fetchone()[0],sid)
  self.assertEqual(self.cmd(session='wrong').status_code,409)
  self.assertEqual(self.cmd(command='bring',position=[1,2,3],origin_job='other',origin_place=0).status_code,409)
  self.assertEqual(self.cmd(command='bring',position=[1,2,3],origin_job='server-A',origin_place=0).status_code,200)

unittest.main(verbosity=2)
