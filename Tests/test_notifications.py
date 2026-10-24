"""External push integration checks. No requests to Apple/ntfy are made."""
import datetime as dt
import json
import uuid
from unittest import TestCase
from unittest.mock import patch
from Tests import test_backend as backend
SERVER = backend.SERVER


class ExternalPushTests(TestCase):
    setUp = backend.RJLoveBackendTests.setUp
    tearDown = backend.RJLoveBackendTests.tearDown
    request = backend.RJLoveBackendTests.request
    request_error = backend.RJLoveBackendTests.request_error
    login = backend.RJLoveBackendTests.login
    upload_asset = backend.RJLoveBackendTests.upload_asset
    upload_clip = backend.RJLoveBackendTests.upload_clip

    def pause_worker(self):
        hub = self.app.notification_hub
        hub.stop.set(); hub.wake.set(); hub.thread.join(timeout=3)
        hub.stop.clear()
        return hub

    def register(self, token, user='robin'):
        result = self.request('/bark/register', 'POST', {'device_token': 'ab'*32})[1]
        key = result['data']['key']
        status = self.request('/v1/notifications/settings', 'POST', {'bark_device_key': key}, token)[1]
        return key, status

    def schedule(self, start='20:00', end='06:00', days=None):
        return {'id': str(uuid.uuid4()), 'enabled': True, 'label': 'Schlafe 😴', 'start': start, 'end': end, 'days': [0] if days is None else days, 'timezone': 'Europe/Berlin'}

    def test_account_isolation_registration_and_old_database_upgrade(self):
        self.pause_worker()
        robin = self.login(); partner = self.login('raphaela', 'raphaela-test-password')
        key, own = self.register(robin)
        self.assertEqual(own['settings']['provider'], 'bark')
        self.assertEqual(own['bark_server_url'], 'https://love.rjuhas.eu/bark')
        self.assertEqual(self.request('/bark/register/'+key)[0], 200)
        other = self.request('/v1/notifications/settings', token=partner)[1]
        self.assertEqual(other['settings']['bark_device_key'], '')
        self.assertNotIn(key, json.dumps(other['partners']))
        self.assertNotIn(own['integration_url'], json.dumps(other))
        self.assertEqual(self.request_error('/v1/notifications/settings', 'POST', {'bark_device_key': key}, partner)[0], 409)
        old = self.app.database.path
        original = SERVER.Database(old)
        with original.connect() as db:
            self.assertTrue(db.execute('SELECT 1 FROM notification_settings WHERE user_id=?', ('robin',)).fetchone())
        self.assertEqual(self.request_error('/v1/notifications/settings')[0], 401)

    def test_overnight_weekdays_boundaries_dst_and_validation(self):
        hub = self.pause_worker(); token = self.login()
        self.request('/v1/notifications/settings', 'POST', {'quiet_schedules': [self.schedule()]}, token)
        # Monday 20:00 CEST to Tuesday 06:00 CEST, anchored to Monday.
        for stamp in ['2026-10-19T18:00:00Z','2026-10-19T23:00:00Z','2026-10-20T03:59:59Z']:
            self.assertTrue(hub.quiet('robin', SERVER.parse_iso(stamp))['active'])
        for stamp in ['2026-10-19T17:59:59Z','2026-10-20T04:00:00Z','2026-10-20T18:00:00Z']:
            self.assertFalse(hub.quiet('robin', SERVER.parse_iso(stamp))['active'])
        self.request('/v1/notifications/settings', 'POST', {'quiet_schedules': [self.schedule(days=[5])]}, token)
        self.assertTrue(hub.quiet('robin', SERVER.parse_iso('2026-10-25T01:30:00Z'))['active'])
        self.assertFalse(hub.quiet('robin', SERVER.parse_iso('2026-10-25T05:00:00Z'))['active'])
        for change in [{'provider':'both'}, {'volume':11}, {'allow_critical':'yes'}, {'ntfy_server_url':'http://localhost'}, {'quiet_schedules':[self.schedule(start='25:00')]}, {'quiet_schedules':[self.schedule(days=[])]}]:
            self.assertEqual(self.request_error('/v1/notifications/settings','POST', change, token)[0],400)

    def test_rich_content_unicode_chunks_and_ntfy_full_text(self):
        hub = self.pause_worker(); token = self.login(); key, _ = self.register(token)
        text = 'Hallo 💗\nDeine Nachricht: äää! ' * 140
        event = {'id':str(uuid.uuid4()),'kind':'record_chat','title':'Raphaela hat dir geschrieben 💌','body':text,'payload':{}}
        sent=[]
        hub.bark.push=lambda key,params,user: (sent.append(params) or True,'ok')
        self.assertEqual(hub.send('robin',event),'sent')
        self.assertEqual(''.join(p['body'] for p in sent), text)
        self.assertTrue(all(p['title']==event['title'] for p in sent))
        self.assertIn('/push-icons/chat.png',sent[0]['icon'])
        self.request('/v1/notifications/settings','POST',{'provider':'ntfy'},token)
        captured=[]
        class Response:
            status=200
            def __enter__(self): return self
            def __exit__(self,*args): pass
        class Opener:
            def open(self,req,timeout): captured.append(json.loads(req.data)); return Response()
        with patch.object(SERVER.urllib.request,'build_opener',return_value=Opener()):
            self.assertEqual(hub.send('robin',event),'sent')
        self.assertEqual(''.join(p['message'] for p in captured),text)
        self.assertTrue(all(p['title']==event['title'] for p in captured))
        self.assertTrue(all(p['priority']==3 for p in captured))

    def test_bark_apns_payload_uses_official_topic_and_bounded_size(self):
        import types
        hub=self.pause_worker(); token=self.login(); key,_=self.register(token)
        with patch.object(hub.bark,'provider_token',return_value='test-jwt'), patch.object(SERVER.subprocess,'run',return_value=types.SimpleNamespace(returncode=0,stdout=b'\n200',stderr=b'')) as run:
            self.assertTrue(hub.bark.push(key,{'title':'Weckruf','body':'Hallo 💗','level':'critical','call':'1','volume':'10','sound':'alarm'},'robin')[0])
            args,kwargs=run.call_args; payload=json.loads(kwargs['input'])
            self.assertIn('apns-topic: me.fin.bark',args[0])
            self.assertEqual(payload['aps']['mutable-content'],1)
            self.assertEqual(payload['aps']['sound']['critical'],1)
            self.assertEqual(payload['call'],'1')
            self.assertLessEqual(len(kwargs['input']),4096)
        self.assertFalse(hub.bark.push(key,{'body':'💗'*4000},'robin')[0])
        jwt=hub.bark.provider_token()
        self.assertEqual(len(jwt.split('.')),3) # Real OpenSSL signing with upstream public self-host credential.

    def test_due_time_persistent_repeat_ack_and_quiet_no_fallback(self):
        hub=self.pause_worker(); token=self.login(); key,_=self.register(token)
        now=SERVER.utc_now(); sent=[]
        hub.bark.push=lambda key,p,user:(sent.append(p) or True,'ok')
        event={'id':str(uuid.uuid4()),'kind':'wake_request','title':'Aufstehen','body':'Hallo','payload':{}}
        hub.enqueue('robin',event,due=now+dt.timedelta(minutes=1),repeat_seconds=45)
        hub.tick(now); self.assertEqual(sent,[])
        hub.tick(now+dt.timedelta(minutes=1)); self.assertEqual(len(sent),1)
        hub.tick(now+dt.timedelta(minutes=1,seconds=44)); self.assertEqual(len(sent),1)
        hub.tick(now+dt.timedelta(minutes=1,seconds=45)); self.assertEqual(len(sent),2)
        self.request('/v1/notifications/'+event['id']+'/ack','POST',{},token)
        hub.tick(now+dt.timedelta(minutes=4)); self.assertEqual(len(sent),2)
        self.request('/v1/notifications/settings','POST',{'quiet_schedules':[self.schedule(start='00:00',end='00:00',days=list(range(7)))], 'fallback_ntfy':True},token)
        hub.send_ntfy=lambda *args:self.fail('quiet must never fall back')
        self.assertEqual(hub.send('robin',event),'suppressed')
        self.assertEqual(len(sent),2)
        # Ordinary Bark messages during scheduled night mode are passive.
        self.assertEqual(hub.send('robin',event|{'kind':'record_chat'}),'sent')
        self.assertEqual(sent[-1]['level'],'passive');self.assertNotIn('call',sent[-1])

    def test_ack_url_requires_post_and_recipient_credentials(self):
        hub=self.pause_worker(); token=self.login(); partner=self.login('raphaela','raphaela-test-password')
        event={'id':str(uuid.uuid4()),'kind':'wake_request','title':'Aufstehen','body':'Hallo','payload':{}}
        hub.enqueue('robin',event,repeat_seconds=45)
        self.assertEqual(self.request_error('/v1/notifications/'+event['id']+'/ack','POST',{},partner)[0],404)
        path='/push-ack/'+event['id']+'?token='+hub.ack_token(event['id'],'robin')
        with SERVER.urllib.request.urlopen(self.base+path) as response:
            self.assertIn(b'<form method="post">',response.read())
        with self.app.database.connect() as db:
            self.assertEqual(db.execute('SELECT stopped FROM push_jobs WHERE id=?',(event['id'],)).fetchone()[0],0)
        data=SERVER.urllib.parse.urlencode({'token':hub.ack_token(event['id'],'robin')}).encode()
        request=SERVER.urllib.request.Request(self.base+path.split('?')[0],data=data,headers={'Content-Type':'application/x-www-form-urlencoded'})
        with SERVER.urllib.request.urlopen(request) as response:self.assertEqual(response.status,200)
        with self.app.database.connect() as db:self.assertEqual(db.execute('SELECT stopped FROM push_jobs WHERE id=?',(event['id'],)).fetchone()[0],1)

    def test_private_integration_and_real_chat_events(self):
        hub=self.pause_worker(); token=self.login(); partner=self.login('raphaela','raphaela-test-password')
        own=self.request('/v1/notifications/settings',token=token)[1]
        path=own['integration_url'].replace('https://love.rjuhas.eu','')
        self.assertEqual(self.request(path,'POST',{'title':'Guten Morgen','body':'Kompletter Inhalt','alarm':True,'repeat_until_ack':True})[0],202)
        self.assertEqual(self.request_error(path+'bad','POST',{'body':'x'})[0],401)
        text='Meine vollständige Nachricht 💗\n' * 60
        self.request('/v1/records','POST',{'id':str(uuid.uuid4()),'kind':'chat','payload':{'text':text,'urgency':1}},partner)
        with self.app.database.connect() as db:
            event=db.execute("SELECT title,body,payload FROM events WHERE kind='record_chat' AND target_id='robin' ORDER BY created_at DESC LIMIT 1").fetchone()
        self.assertIn('Raphaela',event['title']); self.assertIn(text.strip(),event['body'])
        self.assertGreater(len(event['body']),500)
        self.assertNotIn('critical',json.loads(event['payload'])) # Audio playback volume is not alarm urgency.

    def test_ntfy_never_repeats_and_fallback_not_double_send(self):
        hub=self.pause_worker(); token=self.login(); self.register(token)
        event={'id':str(uuid.uuid4()),'kind':'wake_request','title':'Hallo','body':'Text','payload':{}}
        calls=[];hub.bark.push=lambda *args:(True,'ok');hub.send_ntfy=lambda *args: calls.append('ntfy') or True
        self.request('/v1/notifications/settings','POST',{'fallback_ntfy':True},token)
        hub.enqueue('robin',event,repeat_seconds=45);hub.tick();self.assertEqual(calls,[])
        self.request('/v1/notifications/settings','POST',{'provider':'ntfy'},token)
        hub.tick(SERVER.utc_now()+dt.timedelta(seconds=46));self.assertEqual(calls,['ntfy'])
        hub.tick(SERVER.utc_now()+dt.timedelta(minutes=3));self.assertEqual(calls,['ntfy'])

    def test_preview_scope_expiry_recall_and_icons(self):
        import base64
        hub=self.pause_worker(); token=self.login(); image=base64.b64decode(SERVER.PUSH_ICONS['heart'])
        record=self.request('/v1/records','POST',{'id':str(uuid.uuid4()),'kind':'moment','payload':{'image_base64':base64.b64encode(image).decode(),'mime_type':'image/png','caption':'Privat'}},token)[1]
        event={'payload':{'record_id':record['id']}}
        url=hub.image_url(event,'robin').replace('https://love.rjuhas.eu',self.base)
        with SERVER.urllib.request.urlopen(url) as response:self.assertEqual(response.read(),image)
        with self.assertRaises(SERVER.urllib.error.HTTPError):SERVER.urllib.request.urlopen(url+'bad')
        self.request('/v1/records/'+record['id'],'DELETE',token=token)
        with self.assertRaises(SERVER.urllib.error.HTTPError):SERVER.urllib.request.urlopen(url)
        with SERVER.urllib.request.urlopen(self.base+'/push-icons/poop.png') as response:self.assertEqual(response.headers['Content-Type'],'image/png')

    def test_reminder_runs_without_app_and_is_deduplicated_across_restart(self):
        hub=self.pause_worker(); token=self.login(); self.register(token)
        due=SERVER.utc_now()+dt.timedelta(seconds=20)
        self.request('/v1/records','POST',{'id':str(uuid.uuid4()),'kind':'reminder','payload':{'title':'Wasser trinken','message':'Jetzt ein Glas 💧','due_at':due.isoformat(),'target_id':'robin','alarm_enabled':True}},token)
        with self.app.database.connect() as db:db.execute('DELETE FROM push_jobs')
        captured=[];hub.bark.push=lambda key,p,user:(captured.append(p) or True,'ok')
        hub.tick(due-dt.timedelta(seconds=1));self.assertEqual(captured,[])
        hub.tick(due+dt.timedelta(seconds=1));self.assertEqual(len(captured),1)
        self.assertEqual(captured[0]['title'],'Wasser trinken');self.assertEqual(captured[0]['body'],'Jetzt ein Glas 💧')
        hub.tick(due+dt.timedelta(seconds=4));self.assertEqual(len(captured),1)
        restarted=SERVER.RJLoveApplication(self.config,self.config_path)
        try:
            restarted.notification_hub.stop.set();restarted.notification_hub.wake.set();restarted.notification_hub.thread.join(timeout=3);restarted.notification_hub.stop.clear()
            restarted.notification_hub.bark.push=lambda *args:self.fail('completed reminder must survive restart')
            restarted.notification_hub.tick(due+dt.timedelta(seconds=8))
        finally:restarted.close()

    def test_recipient_repeat_limit_and_pending_legacy_alarm_migration(self):
        hub=self.pause_worker(); token=self.login(); self.register(token)
        self.request('/v1/notifications/settings','POST',{'repeat_limit_minutes':15},token)
        now=SERVER.utc_now();event={'id':str(uuid.uuid4()),'kind':'wake_request','title':'Hallo','body':'Aufwachen','payload':{}}
        sent=[];hub.bark.push=lambda key,p,user:(sent.append(p) or True,'ok')
        hub.enqueue('robin',event,due=now,repeat_seconds=45);hub.tick(now);self.assertEqual(len(sent),1)
        hub.tick(now+dt.timedelta(minutes=16));self.assertEqual(len(sent),1)
        command_id=str(uuid.uuid4());due=now+dt.timedelta(hours=8)
        with self.app.database.connect() as db:
            db.execute('INSERT INTO commands(id,owner_id,target_id,kind,payload,due_at,created_at) VALUES(?,?,?,?,?,?,?)',(command_id,'raphaela','robin','wake',json.dumps({'message':'Alter geplanter Weckruf'}),due.isoformat(),now.isoformat()))
        hub.migrate_commands()
        with self.app.database.connect() as db:
            command=json.loads(db.execute('SELECT payload FROM commands WHERE id=?',(command_id,)).fetchone()[0])
            rows=[json.loads(r[0]) for r in db.execute('SELECT event FROM push_jobs')]
        self.assertEqual(command['transport'],'bark')
        self.assertEqual(sum(r['payload'].get('command_id')==command_id for r in rows),1)
        hub.migrate_commands()
        with self.app.database.connect() as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM push_jobs').fetchone()[0],2)

    def test_photo_wishes_stay_in_app_and_old_jobs_never_spoil(self):
        hub=self.pause_worker(); token=self.login()
        hub.bark.push=lambda *args:self.fail('A photo wish must not leave the app')
        hub.send_ntfy=lambda *args:self.fail('No ntfy spoiler for a photo wish')
        record=self.request('/v1/photo-requests','POST',{'id':str(uuid.uuid4()),'title':'Bitte lächeln'},token)[1]
        with self.app.database.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM push_jobs').fetchone()[0],0)
            row=db.execute("SELECT * FROM events WHERE kind='record_photo_request'").fetchone()
            old=dict(row);old['payload']=json.loads(row['payload'])
        self.assertTrue(any(r['id']==record['id'] for r in self.app.bootstrap('raphaela')['records']))
        hub.enqueue('raphaela',old);hub.tick()
        with self.app.database.connect() as db:self.assertEqual(db.execute('SELECT reason FROM push_jobs WHERE id=?',(old['id'],)).fetchone()[0],'hidden')
        self.app.apns._send_worker('raphaela',old)

    def test_bark_exact_comment_chat_and_alarm_routes(self):
        hub=self.pause_worker();token=self.login();partner=self.login('raphaela','raphaela-test-password');self.register(token)
        _,(_,clip),_=self.upload_clip(token)
        comment_id=str(uuid.uuid4())
        self.request('/v1/farts/'+clip['id']+'/comments','POST',{'id':comment_id,'text':'Dieser Furz ist legendär'},partner)
        with self.app.database.connect() as db:
            row=db.execute("SELECT * FROM events WHERE kind='fart_comment'").fetchone()
            event=dict(row);event['payload']=json.loads(row['payload'])
        captured=[];hub.bark.push=lambda key,p,user:(captured.append(p) or True,'ok')
        hub.send('robin',event)
        link=SERVER.urlparse(captured[0]['url']);query=SERVER.parse_qs(link.query)
        self.assertEqual((link.scheme,link.netloc),('rjlove','open'))
        self.assertEqual(query['target'],['fart-comments']);self.assertEqual(query['id'],[clip['id']]);self.assertEqual(query['comment'],[comment_id]);self.assertEqual(query['account'],['robin'])
        record=str(uuid.uuid4())
        self.assertEqual(hub.navigation({'kind':'record_chat','payload':{'record_id':record}}),{'target':'chat','id':record})
        alarm=str(uuid.uuid4())
        self.assertEqual(hub.navigation({'kind':'wake_request'},job={'id':alarm})['target'],'alarms')

    def test_navigation_auth_old_content_recall_and_web_fallback(self):
        hub=self.pause_worker();token=self.login();partner=self.login('raphaela','raphaela-test-password')
        record=self.request('/v1/records','POST',{'id':str(uuid.uuid4()),'kind':'note','payload':{'title':'Ein alter Beitrag','text':'Noch vollständig lesbar'}},token)[1]
        query=SERVER.urlencode({'target':'record','id':record['id'],'account':'robin'})
        endpoint='/v1/navigation?'+query
        self.assertEqual(self.request_error(endpoint)[0],401)
        self.assertEqual(self.request_error(endpoint,token=partner)[0],403)
        loaded=self.request(endpoint,token=token)[1]
        self.assertEqual(loaded['record']['payload']['text'],'Noch vollständig lesbar')
        with SERVER.urllib.request.urlopen(self.base+'/open?'+query) as response:
            page=response.read().decode()
            self.assertIn('rjlove://open?',page);self.assertIn('window.location.replace',page)
            self.assertIn('script-src',response.headers['Content-Security-Policy'])
            self.assertNotIn('Noch vollständig lesbar',page)
        self.request('/v1/records/'+record['id'],'DELETE',token=token)
        self.assertEqual(self.request_error(endpoint,token=token)[0],410)
        for bad in ['/open?target=delete','/open?target=record&id=javascript%3Aalert(1)','/open?target=chat&target=alarms','/open?target=chat&url=https://evil.example']:
            self.assertEqual(self.request_error(bad)[0],400)

    def test_comment_focus_loads_window_after_bootstrap_boundary(self):
        hub=self.pause_worker();token=self.login();_,(_,clip),_=self.upload_clip(token)
        ids=[str(uuid.uuid4()) for _ in range(450)]
        with self.app.database.connect() as db:
            for index,identifier in enumerate(ids):
                db.execute('INSERT INTO fart_comments VALUES(?,?,?,?,?)',(identifier,clip['id'],'robin',str(index),(SERVER.utc_now()+dt.timedelta(seconds=index)).isoformat()))
        result=self.request('/v1/farts/'+clip['id']+'/comments?focus='+ids[400],token=token)[1]
        self.assertIn(ids[400],[c['id'] for c in result['comments']])
        self.assertEqual(len(result['comments']),70)
        self.assertEqual(result['comments'][20]['id'],ids[400])
