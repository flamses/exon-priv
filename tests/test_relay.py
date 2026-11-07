import os,sys,tempfile,unittest,json
from pathlib import Path
scratch=tempfile.TemporaryDirectory()
os.environ['OWNER_KEY']='test-key-'+'x'*40
os.environ['DATABASE_PATH']=scratch.name+'/db.sqlite3'
os.environ['OWNERS_FILE']=scratch.name+'/owners.txt'
Path(os.environ['OWNERS_FILE']).write_text('9140430988 # owner\n')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from relay import app,connect,COMMANDS
class Tests(unittest.TestCase):
 def setUp(self):
  self.c=app.test_client();self.owner={'Authorization':'Bearer '+os.environ['OWNER_KEY'],'X-Owner-Id':'9140430988'}
  with connect() as db:db.execute('DELETE FROM sessions');db.execute('DELETE FROM inbox')
 def join(self,uid='123',version=3):
  r=self.c.post('/join',json={'id':uid,'name':'Target','display':'Display','job':'server-A','place':999,'game_name':'Game','version':version})
  self.assertEqual(r.status_code,200);return {'Authorization':'Bearer '+r.json['token']}
 def cmd(self,headers=None,**kw):
  return self.c.post('/command',headers=self.owner if headers is None else headers,json={'target':'123','command':'freeze','job':'server-A',**kw})
 def test_permissions(self):
  free=self.join('9140430988')
  self.assertEqual(self.cmd(free).status_code,403)
  self.assertEqual(self.cmd({'Authorization':self.owner['Authorization']}).status_code,403)
  self.assertEqual(self.cmd({**self.owner,'X-Owner-Id':'123'}).status_code,403)
  self.assertEqual(self.cmd(target='9140430988').status_code,403)
 def test_independent_inboxes_and_ack(self):
  a=self.join();b=self.join();self.assertEqual(self.cmd().status_code,200)
  first=self.c.post('/poll',headers=a).json['commands'];second=self.c.post('/poll',headers=b).json['commands']
  self.assertEqual(len(first),1);self.assertEqual(len(second),1);self.assertNotEqual(first[0]['id'],second[0]['id'])
  self.c.post('/ack',headers=a,json={'ids':[second[0]['id']]})
  self.assertEqual(self.c.post('/poll',headers=b).json['commands'],second)
  self.c.post('/ack',headers=a,json={'ids':[first[0]['id']]})
  self.assertEqual(self.c.post('/poll',headers=a).json['commands'],[])
 def test_catalog_actions_and_payloads(self):
  free=self.join();count=0
  for name,spec in COMMANDS.items():
   if spec['kind']!='action':continue
   args={'command':name,'origin_job':'server-A','origin_place':999}
   if spec.get('arg')=='number':args['value']=spec.get('default') or spec['min']
   if spec.get('arg')=='vector' or name=='bring':args['position']=[1,2,3]
   if name in ('follow','orbit'):args['reference']='9140430988'
   self.assertEqual(self.cmd(**args).status_code,200,name)
   messages=self.c.post('/poll',headers=free).json['commands'];self.assertEqual(messages[0]['command'],name)
   self.c.post('/ack',headers=free,json={'ids':[m['id']for m in messages]});count+=1
  self.assertGreaterEqual(len(COMMANDS),100);self.assertEqual(count,82)
 def test_removed_cosmetics_and_utilities_not_relayable(self):
  self.join()
  for name in ['disco','fire','sparkles','blind','blur','fov','fullbright','help','goto','join','eval']:
   self.assertEqual(self.cmd(command=name).status_code,400,name)
 def test_bounds_and_vectors(self):
  self.join()
  for args in [{'command':'walkspeed','value':True},{'command':'spin','value':1000},{'command':'velocity','position':[999,0,0]},{'command':'tpcoords','position':[1,2]},{'command':'joinplace','value':1.5},{'command':'follow','reference':'bad','origin_job':'server-A','origin_place':999}]:
   self.assertEqual(self.cmd(**args).status_code,400)
 def test_session_scope_and_origin_guard(self):
  self.join();self.join();sid=self.c.get('/clients',headers=self.owner).json['clients'][0]['sid']
  self.assertEqual(self.cmd(session=sid).status_code,200)
  with connect()as db:self.assertEqual(db.execute('SELECT count(*)FROM inbox').fetchone()[0],1)
  self.assertEqual(self.cmd(session='bad').status_code,409)
  for name in ['bring','follow','orbit']:
   args={'command':name,'position':[1,2,3],'reference':'9140430988','origin_job':'wrong','origin_place':999,'value':4}
   self.assertEqual(self.cmd(**args).status_code,409)
 def test_versions_and_metadata(self):
  free=self.join(version=2);self.assertEqual(self.cmd().status_code,409)
  self.c.post('/poll',headers=free,json={'game_name':'Updated'})
  u=self.c.get('/clients',headers=self.owner).json['clients'][0]
  self.assertEqual(u['game_name'],'Updated');self.assertEqual(u['place'],999)
 def test_expiry_and_capacity(self):
  free=self.join()
  for _ in range(20):self.assertEqual(self.cmd().status_code,200)
  self.assertEqual(self.cmd().status_code,429)
  with connect()as db:db.execute('UPDATE inbox SET expires=0')
  self.assertEqual(self.c.post('/poll',headers=free).json['commands'],[])
 def test_whitelist_removal(self):
  path=Path(os.environ['OWNERS_FILE']);path.write_text('')
  try:self.assertEqual(self.cmd().status_code,403)
  finally:path.write_text('9140430988\n')
 def test_rejoin_after_storage_reset(self):
  old=self.join()
  with connect()as db:db.execute('DELETE FROM sessions')
  self.assertEqual(self.c.post('/poll',headers=old).status_code,403)
  self.assertEqual(self.c.post('/poll',headers=self.join()).status_code,200)
if __name__=='__main__':unittest.main(verbosity=2)
