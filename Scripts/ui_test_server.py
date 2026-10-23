#!/usr/bin/env python3
"""Isolated real backend for the simulator UI regression test. Never ships in app."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import io
import wave
import uuid
import datetime

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('rj_ui_backend', root / 'Backend/rj_love_server.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
staging = tempfile.TemporaryDirectory()
config = module.default_config()
config['server'].update(host='127.0.0.1', port=8787, data_directory=str(Path(staging.name) / 'data'))
path = Path(staging.name) / 'rjapp_config.json'
path.write_text(json.dumps(config))
app = module.RJLoveApplication(config, path)
app.issue_session('robin', 'ui-test')
with app.database.connect() as db:
    db.execute('UPDATE sessions SET token_hash=? WHERE user_id=?', (hashlib.sha256(b'ui-test-token').hexdigest(), 'robin'))
with app.database.connect() as db:
    payload = json.dumps({"title": "Bitte lächeln · UI", "target_id": "robin", "completed": False})
    now = module.iso_now()
    db.execute("INSERT INTO records VALUES(?,?,?,?,?,?,?,NULL)", ("CA82F1DB-2379-4A43-8AD0-24AB34D089CE", "photo_request", "raphaela", payload, len(payload.encode()), now, now))
# Three actual audio files to verify automatic server playlist advancement.
with app.database.connect() as db:
    for index in range(3):
        buffer=io.BytesIO()
        with wave.open(buffer,"wb") as audio:
            audio.setnchannels(1);audio.setsampwidth(2);audio.setframerate(8000);audio.writeframes(b"\x00\x00"*8000*12)
        data=buffer.getvalue();stamp=(module.utc_now()+datetime.timedelta(seconds=index)).isoformat()
        db.execute("INSERT INTO fart_clips(id,owner_id,title,caption,category,duration,waveform,audio,size_bytes,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)",(str(uuid.uuid4()),"robin" if index!=1 else "raphaela","UI-Abend "+str(index+1),"Isolierte Testaufnahme","Klassiker",12,"[0.1]",data,len(data),stamp))
try:
    class CompatibilityTestHandler(module.RJLoveRequestHandler):
        def do_GET(self):
            if self.path == '/old/health':
                self.send_json(200,{'status':'ok','version':'2.3.0'})
            elif self.path == '/future/health':
                self.send_json(200,{'status':'ok','version':'4.0.0','minimum_app_version':'4.0.0','minimum_protocol':5,'maximum_protocol':5})
            else:
                super().do_GET()
    server = module.build_server(app)
    server.RequestHandlerClass = CompatibilityTestHandler
    server.serve_forever()
finally:
    app.close()
    staging.cleanup()
