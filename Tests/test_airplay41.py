"""AirPlay collaboration, automatic YouTube rooms and HLS proxy boundaries."""
import hashlib
import io
import json
import time
import unittest
import urllib.error
import urllib.request
import uuid
from unittest.mock import patch
from Tests import test_backend as fixture
SERVER=fixture.SERVER

class AirPlay41Tests(unittest.TestCase):
    setUp=fixture.RJLoveBackendTests.setUp
    tearDown=fixture.RJLoveBackendTests.tearDown
    request=fixture.RJLoveBackendTests.request
    request_error=fixture.RJLoveBackendTests.request_error
    login=fixture.RJLoveBackendTests.login

    def tv(self,token,action,**values):
        current=self.request('/v1/cinema/tv',token=token)[1]
        body={'id':str(uuid.uuid4()),'action':action,'revision':current['revision'],**values}
        return self.request('/v1/cinema/tv/action','POST',body,token)[1]

    def test_old_installed_app_requires_update_before_mutation(self):
        token=self.login()
        self.assertEqual(self.request('/health')[1]['minimum_app_version'],'4.1.0')
        for method,path,body in [('GET','/v1/bootstrap',None),('POST','/v1/cinema/rooms',{'provider':'youtube','media_id':'dQw4w9WgXcQ'})]:
            with self.assertRaises(urllib.error.HTTPError) as failure:self.request(path,method,body,token,version='4.0.0')
            self.assertEqual(failure.exception.code,426)
            self.assertEqual(json.loads(failure.exception.read())['compatibility']['minimum_app_version'],'4.1.0')
        self.assertEqual(self.request('/v1/cinema/rooms',token=token)[1]['rooms'],[])

    def test_single_youtube_room_both_can_select_and_pause(self):
        first=self.login();second=self.login('raphaela','raphaela-test-password')
        room=self.request('/v1/cinema/rooms','POST',{'provider':'youtube','media_id':'dQw4w9WgXcQ','title':'A'},first)[1]
        path='/v1/cinema/rooms/'+room['id']
        selected=self.request(path+'/select','POST',{'revision':room['revision'],'media_id':'M7lc1UVf-VE','title':'B'},second)[1]
        self.assertEqual(selected['media_id'],'M7lc1UVf-VE');self.assertFalse(selected['playing']);self.assertTrue(selected['joined'])
        same=self.request('/v1/cinema/rooms','POST',{'provider':'youtube','media_id':'dQw4w9WgXcQ','title':'C'},second)[1]
        self.assertEqual(same['id'],room['id']);self.assertEqual(len(self.request('/v1/cinema/rooms',token=first)[1]['rooms']),1)
        playing=self.request(path+'/control','POST',{'revision':same['revision'],'action':'play'},second)[1]
        paused=self.request(path+'/control','POST',{'revision':playing['revision'],'action':'pause'},first)[1]
        self.assertFalse(paused['playing'])

    def test_drawings_are_additive_idempotent_and_epoch_guarded(self):
        first=self.login();second=self.login('raphaela','raphaela-test-password')
        initial=self.request('/v1/cinema/tv',token=first)[1]
        self.assertIsNone(self.request('/v1/cinema/tv?after='+str(initial['revision']),token=first)[1]['state'])
        action={'id':str(uuid.uuid4()),'action':'stroke','epoch':initial['state']['epoch'],'points':[[0.1,0.2],[0.5,0.8]],'color':'#D74C87','width':4}
        one=self.request('/v1/cinema/tv/action','POST',action,first)[1]
        again=self.request('/v1/cinema/tv/action','POST',action,first)[1]
        self.assertEqual(one['revision'],again['revision']);self.assertEqual(len(again['state']['strokes']),1)
        action2=action|{'id':str(uuid.uuid4())}
        two=self.request('/v1/cinema/tv/action','POST',action2,second)[1]
        self.assertEqual(len(two['state']['strokes']),2)
        cleared=self.tv(first,'clear');self.assertEqual(cleared['state']['strokes'],[])
        self.assertEqual(self.request_error('/v1/cinema/tv/action','POST',action|{'id':str(uuid.uuid4())},second)[0],409)
        bad=action|{'id':str(uuid.uuid4()),'epoch':cleared['state']['epoch'],'points':[[float('nan'),0],[1,1]]}
        self.assertEqual(self.request_error('/v1/cinema/tv/action','POST',bad,second)[0],400)

    def test_tictactoe_turns_winner_and_signal(self):
        first=self.login();second=self.login('raphaela','raphaela-test-password')
        self.tv(first,'new_game')
        self.assertEqual(self.request_error('/v1/cinema/tv/action','POST',{'id':str(uuid.uuid4()),'action':'move','index':4,'revision':self.request('/v1/cinema/tv',token=first)[1]['revision']},second)[0],409)
        for who,index in [(first,0),(second,3),(first,1),(second,4),(first,2)]:last=self.tv(who,'move',index=index)
        self.assertEqual(last['state']['winner'],'X')
        final=self.tv(second,'signal',symbol='heart');self.assertEqual(final['state']['signals'][-1]['symbol'],'heart')
        self.assertEqual(final['state']['winner'],'X')

    def test_hls_playlist_rewrites_only_authorized_session(self):
        service=self.app.cinema
        value={'routes':{},'root':None};base='https://machine.plex.direct:32400'
        grant={'base':base}
        initial=base+'/video/:/transcode/universal/start.m3u8'
        text='#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nsession/session-a/base/index.m3u8?X-Plex-Token=TOPSECRET\n'
        data=service._hls_playlist(text,initial,'ticket',value,grant,True).decode()
        self.assertNotIn('TOPSECRET',data);self.assertNotIn('plex.direct',data)
        route=data.splitlines()[-1].split('/')[-1];self.assertIn(route,value['routes'])
        child=value['routes'][route]
        media='#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:4,\n00000.ts\n'
        rewritten=service._hls_playlist(media,child,'ticket',value,grant,False).decode()
        self.assertIn('URI="',rewritten);self.assertEqual(len(value['routes']),3)
        for bad in ['https://attacker.example/secret.ts','/library/parts/123/456/file.mp4','../../../../../../library/metadata/3','/video/:/transcode/universal/session/another/0.ts']:
            with self.assertRaises(SERVER.APIError):service._hls_playlist('#EXTM3U\n'+bad+'\n',child,'ticket',value,grant,False)

    def test_native_hls_requests_preserve_revocation(self):
        token=self.login();room=self.request('/v1/cinema/rooms','POST',{'provider':'plex','media_id':'42','title':'Film'},token)[1]
        path='/v1/cinema/rooms/'+room['id']
        base='https://machine.plex.direct:32400'
        self.app.cinema.grants[room['id']]={'url':base+'/library/parts/1/2/file.mkv','base':base,'media_id':'42','mode':'compatible','token':'PRIVATE','expires':time.time()+300,'id':'g'}
        ticket=self.request(path+'/playback','POST',{},token)[1]['path']
        class Response(io.BytesIO):
            status=200
            headers={'Content-Type':'application/vnd.apple.mpegurl'}
        owner=self
        class Opener:
            def open(self,request,timeout):
                owner.assertEqual(request.get_header('X-plex-token'),'PRIVATE')
                return Response(b'#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nsession/safe/base/index.m3u8\n')
        client=urllib.request.OpenerDirector();client.add_handler(urllib.request.HTTPHandler());client.add_handler(urllib.request.HTTPDefaultErrorHandler());client.add_handler(urllib.request.HTTPErrorProcessor())
        with patch.object(SERVER.urllib.request,'build_opener',return_value=Opener()):
            with client.open(self.base+ticket,timeout=5) as response:data=response.read().decode()
        self.assertNotIn('PRIVATE',data);self.assertIn(ticket.split('/')[-1]+'/',data)
        self.request(path+'/control','POST',{'revision':room['revision'],'action':'revoke'},token)
        with self.assertRaises(urllib.error.HTTPError) as failure:client.open(self.base+ticket,timeout=5)
        self.assertEqual(failure.exception.code,410)

if __name__=='__main__':unittest.main()
