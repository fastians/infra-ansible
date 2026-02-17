#!/usr/bin/env python3
"""Receive Alertmanager webhook POST and forward to Telegram. No deps beyond stdlib."""
import json
import os
import urllib.request
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler

TELEGRAM_API = "https://api.telegram.org/bot{token}/sendMessage"
PORT = int(os.environ.get("PORT", "5001"))
BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")


def send_telegram(text: str) -> bool:
    if not BOT_TOKEN or not CHAT_ID:
        return False
    url = TELEGRAM_API.format(token=BOT_TOKEN)
    data = urllib.parse.urlencode({"chat_id": CHAT_ID, "text": text, "disable_web_page_preview": "true"}).encode()
    req = urllib.request.Request(url, data=data, method="POST", headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status == 200
    except Exception:
        return False


def _one_alert_block(alert: dict, status: str, common_labels: dict) -> str:
    """Build one alert block. Use commonLabels + alert labels so we never miss service/target."""
    a = alert.get("annotations", {}) or {}
    l = alert.get("labels", {}) or {}
    # Merge commonLabels so Alertmanager grouping doesn't hide service/target
    merged = {**common_labels, **l}
    alertname = merged.get("alertname", "Alert")
    severity = merged.get("severity", "warning")
    service = merged.get("service") or merged.get("instance") or alertname
    instance = merged.get("target") or merged.get("instance") or "—"
    summary = a.get("summary") or f"{service} is down"
    desc = a.get("description") or summary
    lines = [
        f"Alert: {alertname}",
        f"Severity: {severity}",
        f"Service: {service}",
        f"Instance: {instance}",
        f"Description: {desc}",
    ]
    if status == "firing":
        lines.append(f"Started: {summary}")
    else:
        lines.append(f"Resolved: {service} is back UP")
    return "\n".join(lines)


def format_alerts(payload: dict) -> str:
    status = payload.get("status", "firing")
    common = payload.get("commonLabels") or {}
    header = "🔴 FIRING" if status == "firing" else "✅ RESOLVED"
    blocks = [_one_alert_block(alert, status, common) for alert in payload.get("alerts", [])]
    return header + "\n\n" + "\n\n".join(blocks) if blocks else header


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/webhook":
            self.send_response(404)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b""
        try:
            payload = json.loads(body.decode())
        except Exception:
            self.send_response(400)
            self.end_headers()
            return
        text = format_alerts(payload)
        ok = send_telegram(text)
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok" if ok else b"telegram send failed")

    def log_message(self, format, *args):
        pass


def main():
    if not BOT_TOKEN or not CHAT_ID:
        raise SystemExit("Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID")
    server = HTTPServer(("127.0.0.1", PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
