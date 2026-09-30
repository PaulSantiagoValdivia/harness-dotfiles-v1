#!/usr/bin/env python3
"""Real hook process fixtures; no native messages or sessions are fabricated."""
import json
from pathlib import Path
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
HOOK=ROOT/'files/claude/hooks/receipt-dispatch-guard.sh'
base={'hook_event_name':'Stop','stop_hook_active':False,
      'cwd':'/repo/.claude/worktrees/triangulate-qa-modulos-parity',
      'last_assistant_message':'¿Front y app: pasame vuestros receipts de qa-modulos-parity?'}
def run(value):
    raw=value if isinstance(value,str) else json.dumps(value)
    p=subprocess.run(['bash',str(HOOK)],input=raw,text=True,capture_output=True,timeout=3)
    assert p.returncode==0,p.stderr
    return json.loads(p.stdout) if p.stdout else {}
r=run(base)
assert r.get('decision')=='block',r
assert 'SendMessage' in r['reason'] and 'No reenvíes' in r['reason']
for change in ({'stop_hook_active':True},{'hook_event_name':'StopFailure'},
               {'cwd':'/repo/normal'},{'last_assistant_message':'¿Confirmas que funciona en tu dispositivo?'},
               {'last_assistant_message':'Solicitudes enviadas por SendMessage; espero las respuestas.'},
               {'last_assistant_message':'```text\n'+base['last_assistant_message']+'\n```'},
               {'last_assistant_message':'> '+base['last_assistant_message']},
               {'last_assistant_message':None}):
    assert run(dict(base,**change))=={},change
for raw in ('{broken','[]','x'*1048577): assert run(raw)=={}
for text in ('Front and app: please send your receipts?',
             '¿Backend: pásame tu receipt?',
             '**Front y app:** pasame vuestros receipts?'):
    assert run(dict(base,last_assistant_message=text)).get('decision')=='block',text
settings=json.loads((ROOT/'files/claude/settings.json').read_text())
hooks=[h for g in settings['hooks']['Stop'] for h in g['hooks']]
assert sum(h.get('command')=='bash ~/.claude/hooks/receipt-dispatch-guard.sh' for h in hooks)==1
assert next(h for h in hooks if 'receipt-dispatch-guard' in h['command'])['timeout']==2
start=time.monotonic()
for _ in range(10):run(dict(base,stop_hook_active=True))
print(f'PASS: relay case, bounded safety/variant cases, one configured hook; ten no-op processes {time.monotonic()-start:.3f}s')
