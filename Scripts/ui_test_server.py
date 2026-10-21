#!/usr/bin/env python3
"""Isolated real backend for the simulator UI regression test. Never ships in app."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile

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
try:
    module.build_server(app).serve_forever()
finally:
    app.close()
    staging.cleanup()
