"""Small HTTP regressions for portable settings, document sharing and layout migration."""
import base64
import hashlib
import json
import plistlib
import urllib.request
import urllib.error
import unittest
from Tests import test_cinema42 as old
server=old.server

class Dashboard43Tests(unittest.TestCase):
    setUp=old.Cinema42Tests.setUp
    tearDown=old.Cinema42Tests.tearDown
    request=old.Cinema42Tests.request

    def test_settings_are_private_revisioned_and_persistent(self):
        encoded=base64.b64encode(plistlib.dumps({'value':True})).decode()
        one=self.request('/v1/settings',{'values':{'rjlove.live-battery':encoded},'revision':0},0)
        self.assertEqual(one['revision'],1)
        self.assertEqual(self.request('/v1/settings',who=1)['values'],{})
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.request('/v1/settings',{'values':{},'revision':0},0)
        self.assertEqual(error.exception.code,409)
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.request('/v1/settings',{'values':{'token':'secret'},'revision':1},0)
        self.assertEqual(error.exception.code,400)
        server.Database(self.app.database.path)
        self.assertEqual(self.request('/v1/settings',who=0),one)

    def test_documents_upload_share_favorite_retention_and_deeplink(self):
        folder=self.request('/v1/documents/folders',{'name':'Unterlagen'},0)['folders'][0]['id']
        self.request('/v1/documents/favorite',{'folder_id':folder,'favorite':True},1)
        self.assertEqual(self.request('/v1/documents',who=0)['favorites'],[])
        self.assertEqual(self.request('/v1/documents',who=1)['favorites'],[folder])
        data=b'%PDF-1.4\nRJ document';asset=self.request('/v1/assets',{'filename':'Brief.pdf','mime_type':'application/pdf','size_bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()},0)['id']
        headers={'Authorization':'Bearer '+self.tokens[0],'X-RJ-App-Version':server.APP_VERSION,'X-RJ-Protocol':'5','Content-Type':'application/pdf'}
        with urllib.request.urlopen(urllib.request.Request(self.base+'/v1/assets/'+asset,data=data,headers=headers,method='PUT')) as response:self.assertEqual(response.status,200)
        file=self.request('/v1/documents/files',{'asset_id':asset,'folder_id':folder},0)['files'][0]
        self.request('/v1/documents/files',{'asset_id':asset,'folder_id':folder},0) # idempotent retry
        self.assertEqual(self.request('/v1/documents',who=1)['files'][0]['filename'],'Brief.pdf')
        with self.app.database.connect() as db:
            db.execute("UPDATE assets SET created_at='2000-01-01T00:00:00Z' WHERE id=?",(asset,))
            event=dict(db.execute("SELECT * FROM events WHERE target_id=? AND kind='document_uploaded'",(self.other,)).fetchone());event['payload']=json.loads(event['payload'])
            self.assertEqual(db.execute("SELECT COUNT(*) FROM events WHERE kind='document_uploaded'").fetchone()[0],1)
        self.app.cleanup_assets()
        other=headers|{'Authorization':'Bearer '+self.tokens[1]}
        with urllib.request.urlopen(urllib.request.Request(self.base+'/v1/assets/'+asset,headers=other)) as response:self.assertEqual(response.read(),data)
        nav=server.NotificationHub.navigation(event,self.other)
        self.assertEqual(nav['target'],'documents')
        target=self.request('/v1/navigation?target=documents&id='+file['id']+'&account='+self.other,who=1)
        self.assertEqual(target['folder_id'],folder)
        with self.assertRaises(server.APIError) as error:self.app.delete_document(self.other,'files',file['id'])
        self.assertEqual(error.exception.status,403)
        self.app.delete_document(self.user,'files',file['id'])
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(urllib.request.Request(self.base+'/v1/assets/'+asset,headers=other))
        self.assertEqual(error.exception.code,404)

    def test_old_layout_migrates_once_and_every_card_can_be_removed(self):
        previous={'cards':[{'kind':'heart','size':'compact'}],'theme':'ocean','title':'Meine Seite','shortcuts':[]}
        with self.app.database.connect() as db:db.execute('INSERT INTO user_preferences VALUES(?,?,?,?)',(self.user,json.dumps(previous),3,server.iso_now()))
        value=self.request('/v1/preferences',who=0)
        self.assertEqual(value['dashboard']['title'],'Meine Seite')
        self.assertIn('homeKit',[c['kind'] for c in value['dashboard']['cards']])
        value['dashboard']['cards']=[]
        value['dashboard']['tabs']=[{'id':server.default_tabs()[0]['id'],'action':'documents','title':'Meine Dateien'}]
        saved=self.request('/v1/preferences',value,0)
        self.assertEqual(self.request('/v1/preferences',who=0),saved)
        self.assertEqual(saved['dashboard']['cards'],[])
        with self.assertRaises(urllib.error.HTTPError) as error:self.request('/v1/bootstrap',who=0,version='4.2.1')
        self.assertEqual(error.exception.code,426)

if __name__=='__main__':unittest.main()
