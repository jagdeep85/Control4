# Power Control HTTP Service

A lightweight Python HTTP server for Windows that allows remote **Sleep**, **Restart**, and **Wake-on-LAN** commands over HTTP.  
Designed to run as a **Windows Service** for always-on remote PC power control.

---

## Features

- **Sleep** – Puts the PC into true Sleep mode (not Hibernate)  
- **Restart** – Restarts the PC immediately  
- **Wake** – Sends a Wake-on-LAN packet to a hardcoded MAC address  
- **Windows Service** – Runs in the background automatically at startup  
- **Secure** – Requires a secret key for remote commands  

---

## Requirements

- Windows 10 or newer  
- Python 3.7+  
- Administrator privileges (for sleep/restart and service installation)  
- `pywin32` Python module (for Windows Service support)

Install `pywin32`:

```bash
pip install pywin32
```

Initialize pywin32:

```bash
python Scripts/pywin32_postinstall.py -install
```

---

## Setup Instructions

### 1. Configure the Script

Open `power_service.py` and set your secret key, port, and the MAC address to wake:

```python
SECRET = "mysleepkey"  # Change to a strong secret key
PORT = 8080             # HTTP port for incoming requests
WAKE_MAC = "AA:BB:CC:DD:EE:FF"  # Hardcoded MAC address for Wake-on-LAN
```

---

### 2. Install the Windows Service

Open an **elevated Command Prompt** and run:

```bash
python power_service.py install
python power_service.py start
```

**Service Details:**

- Name: `Power Control HTTP Service`  
- Startup Type: `Automatic`  

You can also manage it via **Services** (`services.msc`).

---

### 3. Test the Endpoints

From another PC or device on the same network:

- **Sleep:**

```
http://<PC_IP>:8080/sleep?key=mysleepkey
```

- **Restart:**

```
http://<PC_IP>:8080/restart?key=mysleepkey
```

- **Wake (hardcoded MAC):**

```
http://<PC_IP>:8080/wakeup?key=mysleepkey
```

Replace `<PC_IP>` with the target PC's LAN IP address.

---

## Security Recommendations

- Use a **strong, unique secret key**.  
- Make sure **Windows Firewall** allows inbound traffic on the chosen port.  
- For internet access, use a **VPN or reverse proxy**; do **not expose directly**.  

---

## Optional Enhancements

- Add `/shutdown` endpoint  
- Add `/lock` endpoint  
- Enable logging of commands to a text file  
- Add HTTPS support for secure remote access  

---

## Troubleshooting

- **Port already in use:** Change the `PORT` variable in the script  
- **Sleep goes to Hibernate:** Disable hibernation:

```powershell
powercfg /hibernate off
```

- **Service won’t start:** Ensure you are running as Administrator and have `pywin32` installed  
- **Wake-on-LAN not working:** Make sure the target PC supports Wake-on-LAN and the MAC is correct  

---

## License

MIT License – use at your own risk. Only for PCs you control.

---

## Author

Created by [Your Name]
