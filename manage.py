"""Owner terminal helper for inspecting or revoking temporary connections."""
import argparse
import getpass
import json
import urllib.request
p=argparse.ArgumentParser()
p.add_argument('url')
p.add_argument('action',choices=['list','revoke'])
p.add_argument('--owner-id',required=True)
p.add_argument('--session')
a=p.parse_args()
if a.action=='revoke' and not a.session: p.error('--session required')
key=getpass.getpass('Private owner key: ')
path='/clients'+('/'+a.session if a.action=='revoke' else '')
r=urllib.request.Request(a.url.rstrip('/')+path,method='DELETE' if a.action=='revoke' else 'GET',headers={'Authorization':'Bearer '+key,'X-Owner-Id':a.owner_id})
with urllib.request.urlopen(r,timeout=20) as response: print(json.dumps(json.load(response),indent=2))
