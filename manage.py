"""Owner-only terminal helper. Keys are prompted without echo."""
import argparse
import getpass
import json
import urllib.request

p = argparse.ArgumentParser()
p.add_argument('url')
p.add_argument('action', choices=['add', 'list', 'revoke'])
p.add_argument('--id')
p.add_argument('--name')
a = p.parse_args()
if a.action in ('add', 'revoke') and not (a.id and a.id.isdigit()):
    p.error('--id must be a Roblox numeric user ID')
if a.action == 'add' and not a.name:
    p.error('--name is required')
key = getpass.getpass('Owner key: ')
method = {'add': 'POST', 'list': 'GET', 'revoke': 'DELETE'}[a.action]
path = '/clients' + ('/' + a.id if a.action == 'revoke' else '')
body = json.dumps({'id': a.id, 'name': a.name}).encode() if a.action == 'add' else None
req = urllib.request.Request(a.url.rstrip('/') + path, data=body, method=method,
    headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
with urllib.request.urlopen(req, timeout=20) as response:
    print(json.dumps(json.load(response), indent=2))
