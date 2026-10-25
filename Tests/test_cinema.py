"""Compatibility, access control and playback timing for the additive cinema API."""
import hashlib
import io
import json
import time
import socket
import unittest
import urllib.request
from unittest.mock import patch
from Tests import test_backend as fixture

SERVER = fixture.SERVER

class CinemaTests(unittest.TestCase):
    setUp = fixture.RJLoveBackendTests.setUp
    tearDown = fixture.RJLoveBackendTests.tearDown
    request = fixture.RJLoveBackendTests.request
    request_error = fixture.RJLoveBackendTests.request_error
    login = fixture.RJLoveBackendTests.login

    def room(self, token, provider="youtube", media="dQw4w9WgXcQ"):
        return self.request("/v1/cinema/rooms","POST",{"provider":provider,"media_id":media,"title":"Unser Abend"},token)[1]

    def test_data_unchanged_and_additive_tables(self):
        token=self.login()
        original=self.request("/v1/bootstrap",token=token,version="4.1.0")[1]
        self.room(token)
        after=self.request("/v1/bootstrap",token=token,version="4.1.0")[1]
        for key in ["records","me","partners","preferences"]:self.assertEqual(original[key],after[key])
        self.assertEqual(SERVER.MINIMUM_APP_VERSION,"4.1.0")
        self.assertEqual(SERVER.PROTOCOL_VERSION,5)
        # Reopening the existing DB retains legacy data alongside the new tables.
        SERVER.Database(self.app.database.path)
        self.assertEqual(self.request("/v1/bootstrap",token=token,version="4.1.0")[0],200)

    def test_auth_and_explicit_membership(self):
        robin=self.login();partner=self.login("raphaela","raphaela-test-password")
        self.assertEqual(self.request_error("/v1/cinema/rooms")[0],401)
        room=self.room(robin);path="/v1/cinema/rooms/"+room["id"]
        self.assertEqual(len(room["members"]),2) # The partner is automatically a member in 4.1.
        guest=self.request(path+"/join","POST",{},partner)[1]
        self.assertTrue(guest["joined"]);self.assertEqual(len(guest["members"]),2)
        changed=self.request(path+"/control","POST",{"revision":1,"action":"play","position":32},partner)[1]
        self.assertTrue(changed["playing"]);self.assertGreaterEqual(changed["position"],32)
        self.assertEqual(self.request_error(path+"/control","POST",{"revision":1,"action":"pause"},robin)[0],409)
        self.assertEqual(self.request_error(path+"/control","POST",{"revision":True,"action":"pause"},robin)[0],409)

    def test_invalid_video_and_timer(self):
        token=self.login()
        self.assertEqual(self.request_error("/v1/cinema/rooms","POST",{"provider":"youtube","media_id":"<script>","title":"x"},token)[0],400)
        room=self.room(token);path="/v1/cinema/rooms/"+room["id"]+"/control"
        for bad in [-1,100000,float("inf"),True,"300"]:
            self.assertEqual(self.request_error(path,"POST",{"revision":1,"action":"timer","seconds":bad},token)[0],400)
        timed=self.request(path,"POST",{"revision":1,"action":"timer","seconds":3600,"mode":"direct"},token)[1]
        self.assertAlmostEqual(timed["sleep_until"]-timed["server_time"],3600,delta=1)

    def test_expired_room_cannot_resume(self):
        token=self.login();room=self.room(token)
        with self.app.database.connect() as db:db.execute("UPDATE cinema_rooms SET sleep_until=? WHERE id=?",(time.time()-1,room["id"]))
        closed=self.request("/v1/cinema/rooms/"+room["id"],token=token)[1]
        self.assertTrue(closed["closed"]);self.assertFalse(closed["playing"])
        self.assertEqual(self.request_error("/v1/cinema/rooms/"+room["id"]+"/join","POST",{},token)[0],410)

    def test_stats_only_overlap_and_bound_disconnected_devices(self):
        token=self.login();other=self.login("raphaela","raphaela-test-password")
        room=self.room(token);path="/v1/cinema/rooms/"+room["id"]
        self.request(path+"/join","POST",{},other)
        self.request(path+"/control","POST",{"revision":1,"action":"play"},token)
        self.request(path+"/heartbeat","POST",{"playing":True},token)
        self.request(path+"/heartbeat","POST",{"playing":False},other)
        now=time.time()
        with self.app.database.connect() as db:
            db.execute("UPDATE cinema_stats SET accounted=? WHERE room_id=?",(now-10,room["id"]))
        self.assertEqual(self.request("/v1/cinema/stats",token=token)[1]["stats"][0]["seconds"],0)
        self.request(path+"/heartbeat","POST",{"playing":True},other)
        with self.app.database.connect() as db:
            db.execute("UPDATE cinema_stats SET accounted=? WHERE room_id=?",(now-7,room["id"]))
        seconds=self.request("/v1/cinema/stats",token=token)[1]["stats"][0]["seconds"]
        self.assertGreaterEqual(seconds,7);self.assertLess(seconds,9)
        with self.app.database.connect() as db:
            db.execute("UPDATE cinema_stats SET accounted=? WHERE room_id=?",(now-100,room["id"]))
            db.execute("UPDATE cinema_members SET seen=? WHERE room_id=?",(now-200,room["id"]))
        self.assertEqual(self.request("/v1/cinema/stats",token=token)[1]["stats"][0]["seconds"],seconds)

    def test_plex_selected_file_only_revocable_and_no_tokens_in_rooms(self):
        token=self.login();other=self.login("raphaela","raphaela-test-password")
        room=self.room(token,"plex","42");path="/v1/cinema/rooms/"+room["id"]
        base="https://192-168-1-2.machine.plex.direct:32400"
        resources=[{"clientIdentifier":"machine","provides":"server","accessToken":"private-owner-token","connections":[{"uri":base}]}]
        metadata={"MediaContainer":{"Metadata":[{"Media":[{"Part":[{"key":"/library/parts/99/123/file.mp4"}]}]}]}}
        body={"token":"secret","machine_id":"machine","connection":base,"seconds":3600,"mode":"direct"}
        original_resolve = socket.getaddrinfo
        def resolve(host,*args,**kwargs):
            if host == "192-168-1-2.machine.plex.direct": return [(2,1,6,"",("192.168.1.2",32400))]
            return original_resolve(host,*args,**kwargs)
        with patch.object(SERVER.CinemaService,"remote_json",side_effect=[resources,metadata]),patch("socket.getaddrinfo",side_effect=resolve):
            result=self.request(path+"/plex-share","POST",body,token)[1]
        self.assertTrue(result["plex_shared"]);self.assertNotIn("token",json.dumps(result))
        self.assertNotIn("private-owner-token",self.app.database.path.read_bytes().decode(errors="ignore"))
        self.request(path+"/join","POST",{},other)
        ticket=self.request(path+"/playback","POST",{},other)[1]["path"]
        # Native range/HEAD requests have no app headers or bearer login.
        class Response(io.BytesIO):
            status=206
            headers={"Content-Type":"video/mp4","Content-Length":"4","Content-Range":"bytes 0-3/10","Accept-Ranges":"bytes"}
        class Opener:
            def open(inner,request,timeout):
                self.assertEqual(request.full_url,base+"/library/parts/99/123/file.mp4")
                self.assertEqual(request.get_header("X-plex-token"),"private-owner-token")
                return Response(b"test")
        with patch.object(SERVER.urllib.request,"build_opener",return_value=Opener()):
            # Avoid mocking the test client's own urlopen opener by constructing it first.
            client=urllib.request.OpenerDirector();client.add_handler(urllib.request.HTTPHandler());client.add_handler(urllib.request.HTTPDefaultErrorHandler())
            req=urllib.request.Request(self.base+ticket,headers={"Range":"bytes=0-3"})
            with client.open(req,timeout=5) as response:self.assertEqual(response.read(),b"test")
        self.assertEqual(self.request_error(path+"/control","POST",{"revision":1,"action":"revoke"},other)[0],403)
        self.request(path+"/control","POST",{"revision":1,"action":"revoke"},token)
        self.assertEqual(self.request_error(ticket)[0],410)

    def test_plex_does_not_proxy_arbitrary_urls_or_paths(self):
        token=self.login();room=self.room(token,"plex","42");path="/v1/cinema/rooms/"+room["id"]+"/plex-share"
        body={"token":"x","machine_id":"m","connection":"http://169.254.169.254/","seconds":60}
        resources=[{"clientIdentifier":"m","provides":"server","connections":[{"uri":body["connection"]}]}]
        with patch.object(SERVER.CinemaService,"remote_json",return_value=resources):
            self.assertEqual(self.request_error(path,"POST",body,token)[0],400)

    def test_logout_invalidates_plex_ticket(self):
        token=self.login();room=self.room(token,"plex","42");path="/v1/cinema/rooms/"+room["id"]
        self.app.cinema.grants[room["id"]]={"url":"https://not-requested.plex.direct/file","token":"x","expires":time.time()+60,"id":"test"}
        ticket=self.request(path+"/playback","POST",{},token)[1]["path"]
        self.request("/v1/auth/logout","POST",{},token)
        self.assertEqual(self.request_error(ticket)[0],410)

    def test_optional_google_configuration_and_account_isolation(self):
        token=self.login();other=self.login("raphaela","raphaela-test-password")
        self.assertEqual(self.request_error("/v1/cinema/youtube/search","POST",{"query":"music"},token)[0],503)
        self.assertEqual(self.request_error("/v1/cinema/youtube/connect","POST",{},token)[0],503)
        self.app.config["cinema"]={"youtube_oauth":{"client_id":"client","client_secret":"secret","redirect_uri":"https://example.org/cinema-oauth/youtube"}}
        flow=self.request("/v1/cinema/youtube/connect","POST",{},token)[1]
        self.assertIn("code_challenge",flow["url"])
        self.assertEqual(self.request_error("/v1/cinema/youtube/claim","POST",{"state":flow["state"]},other)[0],404)
        self.app.cinema.oauth[flow["state"]]["tokens"]={"access_token":"mine","refresh_token":"private"}
        claimed=self.request("/v1/cinema/youtube/claim","POST",{"state":flow["state"]},token)[1]
        self.assertEqual(claimed["access_token"],"mine")
        self.assertEqual(self.request_error("/v1/cinema/youtube/claim","POST",{"state":flow["state"]},token)[0],404)

if __name__ == "__main__":unittest.main()
