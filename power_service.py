import win32serviceutil
import win32service
import win32event
import servicemanager
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
import threading
import socket

# === Configuration ===
HOST = "0.0.0.0"
PORT = 9191
SECRET = "control4"  # Change this
WAKE_MAC = "C8:D3:FF:B3:FE:50"  # Hardcoded MAC address for Wake-on-LAN

# === HTTP handler ===
class PowerHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.strip()
        if path == f"/sleep?key={SECRET}":
            self._respond_ok("Putting PC to sleep...")
            self.put_to_sleep()
        elif path == f"/restart?key={SECRET}":
            self._respond_ok("Restarting PC...")
            self.restart_pc()
        elif path == f"/wakeup?key={SECRET}":
            self._respond_ok(f"Sending Wake-on-LAN to {WAKE_MAC}...")
            self.send_wol(WAKE_MAC)
        else:
            self._respond_forbidden()

    def _respond_ok(self, msg):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(msg.encode())

    def _respond_forbidden(self):
        self.send_response(403)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Forbidden or invalid key.")

    def put_to_sleep(self):
        subprocess.run([
            "powershell",
            "-Command",
            "Add-Type -AssemblyName System.Windows.Forms;"
            "[System.Windows.Forms.Application]::SetSuspendState('Suspend',$false,$false)"
        ], shell=True)

    def restart_pc(self):
        subprocess.run(["shutdown", "/r", "/t", "0"], shell=True)

    def send_wol(self, macaddress):
        # Convert MAC to bytes
        macaddress = macaddress.replace("-", "").replace(":", "")
        if len(macaddress) != 12:
            return
        mac_bytes = bytes.fromhex(macaddress)
        packet = b'\xff' * 6 + mac_bytes * 16
        # Send to broadcast
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(packet, ('<broadcast>', 9))
        sock.close()

    def log_message(self, format, *args):
        return


# === Service definition ===
class PowerControlService(win32serviceutil.ServiceFramework):
    _svc_name_ = "PowerControlHTTP"
    _svc_display_name_ = "Power Control HTTP Service"
    _svc_description_ = "Listens for HTTP requests to sleep, restart, or wake a PC via Wake-on-LAN."

    def __init__(self, args):
        win32serviceutil.ServiceFramework.__init__(self, args)
        self.stop_event = win32event.CreateEvent(None, 0, 0, None)
        self.httpd = None
        self.thread = None

    def SvcStop(self):
        self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)
        if self.httpd:
            self.httpd.shutdown()
        win32event.SetEvent(self.stop_event)
        self.ReportServiceStatus(win32service.SERVICE_STOPPED)

    def SvcDoRun(self):
        servicemanager.LogInfoMsg("Starting Power Control HTTP service")
        self.httpd = HTTPServer((HOST, PORT), PowerHandler)
        self.thread = threading.Thread(target=self.httpd.serve_forever)
        self.thread.daemon = True
        self.thread.start()
        win32event.WaitForSingleObject(self.stop_event, win32event.INFINITE)
        self.httpd.server_close()


if __name__ == "__main__":
    win32serviceutil.HandleCommandLine(PowerControlService)
