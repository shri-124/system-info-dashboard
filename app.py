from flask import Flask, request, jsonify, send_from_directory
from uuid import uuid4
from datetime import datetime
from threading import Lock

app = Flask(__name__, static_url_path="", static_folder="static")

# in-memory store (swap for Redis/DB in prod)
STORE = {}
LOCK = Lock()

@app.route("/api/new-run", methods=["POST"])
def new_run():
    run_id = uuid4().hex
    with LOCK:
        STORE[run_id] = {"created_at": datetime.utcnow().isoformat(), "payload": None}
    return jsonify({"run_id": run_id})

@app.route("/api/ingest/<run_id>", methods=["POST"])
def ingest(run_id):
    data = request.get_json(silent=True) or {}
    with LOCK:
        if run_id not in STORE:
            return jsonify({"error": "invalid run_id"}), 404
        STORE[run_id]["payload"] = data
        STORE[run_id]["updated_at"] = datetime.utcnow().isoformat()
    return jsonify({"ok": True})

@app.route("/api/results/<run_id>", methods=["GET"])
def results(run_id):
    with LOCK:
        item = STORE.get(run_id)
    if not item:
        return jsonify({"error": "invalid run_id"}), 404
    return jsonify(item)

# serve index.html
@app.route("/")
def index():
    return send_from_directory("static", "index.html")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
