"""HTTP regressions: names/moves preserve assets, permissions, old clients and sessions."""
import hashlib
import json
import urllib.error
import urllib.request
import unittest
from Tests import test_cinema42 as old

server=old.server

class Documents431Tests(unittest.TestCase):
    setUp=old.Cinema42Tests.setUp
    tearDown=old.Cinema42Tests.tearDown
    request=old.Cinema42Tests.request

    def folder(self,name,parent=None,who=0):
        library=self.request('/v1/documents/folders',{'name':name,'parent_id':parent},who)
        return next(f for f in library['folders'] if f['name']==name and f['parent_id']==parent)['id']

    def upload(self):
        data=b'%PDF-1.4\nKeep the original bytes'
        asset=self.request('/v1/assets',{'filename':'Original.pdf','mime_type':'application/pdf','size_bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()},0)['id']
        headers={'Authorization':'Bearer '+self.tokens[0],'X-RJ-App-Version':server.APP_VERSION,'X-RJ-Protocol':'5','Content-Type':'application/pdf'}
        with urllib.request.urlopen(urllib.request.Request(self.base+'/v1/assets/'+asset,data=data,headers=headers,method='PUT')) as response:self.assertEqual(response.status,200)
        document=self.request('/v1/documents/files',{'asset_id':asset},0)['files'][0]
        return document,data

    def change(self,action,kind,identifier,**values):
        return self.request('/v1/documents/'+action,{'kind':kind,'id':identifier,**values},0)

    def test_rename_move_preserves_original_and_old_client_access(self):
        before=self.request('/v1/bootstrap',who=0)
        document,data=self.upload();destination=self.folder('Ablage')
        library=self.change('rename','files',document['id'],name='Unser Brief.pdf')
        self.assertEqual(library['files'][0]['filename'],'Unser Brief.pdf')
        self.change('move','files',document['id'],folder_id=destination)
        # Retry is idempotent; it must neither duplicate nor lose the file.
        self.change('move','files',document['id'],folder_id=destination)
        server.Database(self.app.database.path)
        other=self.request('/v1/documents',who=1,version='4.3.0')['files']
        self.assertEqual(len(other),1);self.assertEqual(other[0]['folder_id'],destination)
        self.assertEqual(other[0]['asset_id'],document['asset_id'])
        self.assertEqual(other[0]['filename'],'Unser Brief.pdf')
        headers={'Authorization':'Bearer '+self.tokens[1],'X-RJ-App-Version':'4.3.0','X-RJ-Protocol':'5'}
        with urllib.request.urlopen(urllib.request.Request(self.base+'/v1/assets/'+document['asset_id'],headers=headers)) as response:self.assertEqual(response.read(),data)
        after=self.request('/v1/bootstrap',who=0)
        for key in ('me','partners','records','preferences'):self.assertEqual(before[key],after[key])
        with self.app.database.connect() as db:self.assertEqual(db.execute('SELECT filename FROM assets WHERE id=?',(document['asset_id'],)).fetchone()[0],'Original.pdf')

    def test_owner_checks_and_invalid_names(self):
        document,_=self.upload();folder=self.folder('Privat')
        for kind,identifier in [('files',document['id']),('folders',folder)]:
            for action,values in [('rename',{'name':'Fremd'}),('move',{'folder_id':None})]:
                with self.assertRaises(urllib.error.HTTPError) as failure:self.request('/v1/documents/'+action,{'kind':kind,'id':identifier,**values},1)
                self.assertEqual(failure.exception.code,403)
            for name in ('..','/tmp/file','a\\b','x\x00y'):
                with self.assertRaises(urllib.error.HTTPError) as failure:self.change('rename',kind,identifier,name=name)
                self.assertEqual(failure.exception.code,400)
        self.assertEqual(self.request('/v1/documents',who=0)['files'][0]['filename'],'Original.pdf')

    def test_folder_cycles_collisions_favorites_and_delete(self):
        root=self.folder('Start');child=self.folder('Kind',root);other=self.folder('Ziel')
        self.request('/v1/documents/favorite',{'folder_id':child,'favorite':True},1)
        for destination in (root,child):
            with self.assertRaises(urllib.error.HTTPError) as failure:self.change('move','folders',root,folder_id=destination)
            self.assertEqual(failure.exception.code,409)
        self.change('rename','folders',child,name='Neue Unterlagen')
        self.change('move','folders',child,folder_id=other)
        self.assertEqual(self.request('/v1/documents',who=1)['favorites'],[child])
        self.folder('Neue Unterlagen',root)
        with self.assertRaises(urllib.error.HTTPError) as failure:self.change('move','folders',child,folder_id=root)
        self.assertEqual(failure.exception.code,409)
        self.change('move','folders',child,folder_id=None)
        self.app.delete_document(self.user,'folders',child)
        self.assertEqual(self.request('/v1/documents',who=1)['favorites'],[])

    def test_additive_migration_existing_database_and_deleted_file(self):
        document,_=self.upload()
        with self.app.database.connect() as db:db.execute('DROP TABLE document_names')
        server.Database(self.app.database.path)
        self.assertEqual(self.request('/v1/documents',who=0)['files'][0]['filename'],'Original.pdf')
        self.change('rename','files',document['id'],name='Erhalten.pdf')
        self.app.delete_document(self.user,'files',document['id'])
        with self.assertRaises(urllib.error.HTTPError) as failure:self.change('rename','files',document['id'],name='Weg.pdf')
        self.assertEqual(failure.exception.code,404)
        with self.app.database.connect() as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM document_names').fetchone()[0],0)

if __name__=='__main__':unittest.main()
