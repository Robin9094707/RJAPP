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
        self.request('/v1/records','POST',{'id':str(uuid.uuid4()),'kind':'chat','payload':{'text':text}},partner)
        with self.app.database.connect() as db:
            event=db.execute("SELECT title,body FROM events WHERE kind='record_chat' AND target_id='robin' ORDER BY created_at DESC LIMIT 1").fetchone()
        self.assertIn('Raphaela',event['title']); self.assertIn(text.strip(),event['body'])
        self.assertGreater(len(event['body']),500)

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
