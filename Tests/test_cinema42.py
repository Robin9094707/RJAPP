"""Focused release checks for migration and the new shared-cinema behavior."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('rj_server',Path(__file__).resolve().parents[1]/'Backend/rj_love_server.py')
server=importlib.util.module_from_spec(spec);spec.loader.exec_module(server)
class Cinema42Tests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();root=Path(self.tmp.name);config=server.default_config();config['server'].update(host='127.0.0.1',port=0,data_directory=str(root/'data'))
  for i,u in enumerate(config['users']):u.update(username=f'viewer-{i}',password=f'cinema-password-{i}')
  self.app=server.RJLoveApplication(config,root/'config.json');self.http=server.build_server(self.app);self.thread=threading.Thread(target=self.http.serve_forever,daemon=True);self.thread.start();self.base=f'http://127.0.0.1:{self.http.server_port}'
  self.tokens=[self.request('/v1/auth/login',{'username':f'viewer-{i}','password':f'cinema-password-{i}','device_id':f'device-{i}'})['token'] for i in range(2)]
  self.user=config['users'][0]['id'];self.other=config['users'][1]['id'];self.app.cinema.bridge_stop.set();self.app.cinema.bridge_thread.join(timeout=2)
 def tearDown(self):
  self.http.shutdown();self.http.server_close();self.app.close();self.thread.join();self.tmp.cleanup()
 def request(self,path,body=None,who=None,version='4.2.0'):
  h={'X-RJ-App-Version':version,'X-RJ-Protocol':'5','Content-Type':'application/json'}
  if who is not None:h['Authorization']='Bearer '+self.tokens[who]
  r=urllib.request.Request(self.base+path,data=json.dumps(body).encode() if body is not None else None,headers=h)
  with urllib.request.urlopen(r,timeout=5) as response:return json.load(response)
 def room(self):return self.request('/v1/cinema/rooms',{'provider':'plex','media_id':'42','title':'Shared film'},0)
 def bridge(self):
  b={'base':'https://server.plex.direct:32400','token':'PRIVATE','account':'7','session':hashlib.sha256(self.tokens[0].encode()).hexdigest(),'machine':'server','name':'Cinema','expires':time.time()+3600,'error':None,'last_ok':time.time(),'command':0};self.app.cinema.bridges[self.user]=b;return b
 def test_additive_database_both_members_and_update_gate(self):
  before=self.request('/v1/bootstrap',who=0);room=self.room();self.assertEqual(set(room['members']),{self.user,self.other});server.Database(self.app.database.path);after=self.request('/v1/bootstrap',who=0)
  for key in ['records','me','partners','preferences']:self.assertEqual(before[key],after[key])
  with self.assertRaises(urllib.error.HTTPError) as failure:self.request('/v1/bootstrap',who=0,version='4.1.0')
  self.assertEqual(failure.exception.code,426)
 def test_reset_requires_confirmation_and_keeps_other_data(self):
  room=self.room();before=self.request('/v1/bootstrap',who=0)
  with self.app.database.connect() as db:db.execute('UPDATE cinema_stats SET seconds=120 WHERE room_id=?',(room['id'],))
  self.assertEqual(len(self.request('/v1/cinema/history',who=1)['items']),1)
  with self.assertRaises(urllib.error.HTTPError) as e:self.request('/v1/cinema/stats/reset',{},1)
  self.assertEqual(e.exception.code,400);self.assertTrue(self.request('/v1/cinema/stats/reset',{'confirmation':'RESET_CINEMA'},1)['reset']);self.assertEqual(self.request('/v1/cinema/history',who=0)['items'],[]);self.assertEqual(before['records'],self.request('/v1/bootstrap',who=0)['records'])
 def test_external_session_scope_privacy_presence_and_disconnect(self):
  bridge=self.bridge()
  def item(user,media):return {'ratingKey':media,'title':'Movie','duration':90000,'viewOffset':12000,'User':{'id':user},'Player':{'machineIdentifier':'tv','title':'TV','product':'Plex for Apple TV','state':'playing'},'Media':[{'Part':[{'key':'/library/parts/2/3/file.mkv'}]}]}
  data={'MediaContainer':{'Metadata':[item('99','99'),item('7','42')]}}
  with patch.object(self.app.cinema,'remote_json',return_value=data):self.app.cinema._poll_bridge(self.user,bridge)
  rooms=self.request('/v1/cinema/rooms',who=1)['rooms'];self.assertEqual(len(rooms),1);room=rooms[0];self.assertEqual(room['media_id'],'42');self.assertTrue(room['details']['external']);self.assertTrue(room['plex_shared']);self.assertNotIn('PRIVATE',json.dumps(rooms))
  self.request('/v1/cinema/rooms/'+room['id']+'/heartbeat',{'playing':False,'same_screen':True},1)
  with self.app.database.connect() as db:db.execute('UPDATE cinema_stats SET accounted=? WHERE room_id=?',(time.time()-5,room['id']))
  self.assertGreater(self.request('/v1/cinema/stats',who=0)['stats'][0]['seconds'],4)
  with self.app.database.connect() as db:
   db.execute('UPDATE cinema_members SET seen=? WHERE room_id=? AND user_id=?',(time.time()-60,room['id'],self.other));db.execute('UPDATE cinema_stats SET accounted=? WHERE room_id=?',(time.time()-4,room['id']))
  self.assertGreater(self.request('/v1/cinema/stats',who=0)['stats'][0]['seconds'],8)
  self.request('/v1/cinema/plex/disconnect',{},0);self.assertEqual(self.request('/v1/cinema/rooms',who=1)['rooms'],[])
 def test_server_sleep_timer_does_not_reopen_session(self):
  bridge=self.bridge();data={'MediaContainer':{'Metadata':[{'ratingKey':'42','title':'Movie','User':{'id':'7'},'Player':{'machineIdentifier':'tv','state':'playing'},'Media':[]}]}}
  with patch.object(self.app.cinema,'remote_json',return_value=data),patch.object(self.app.cinema,'_remote_control') as control:
   self.app.cinema._poll_bridge(self.user,bridge);room=self.request('/v1/cinema/rooms',who=0)['rooms'][0]
   with self.app.database.connect() as db:db.execute('UPDATE cinema_rooms SET sleep_until=? WHERE id=?',(time.time()-1,room['id']))
   self.app.cinema._check_external_timers();control.assert_called_once();self.app.cinema._poll_bridge(self.user,bridge);self.assertEqual(self.request('/v1/cinema/rooms',who=1)['rooms'],[])
if __name__=='__main__':unittest.main()
