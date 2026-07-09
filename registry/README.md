# Registry (legacy standalone)

The registry is now included in **`kestra/docker-compose.yml`** on network `kestra-net` (DNS name: `registry:5000`).

Do **not** run this folder and Kestra registry at the same time — both bind port **5000**.

## If you see "port is already allocated"

```powershell
.\scripts\fix-registry-port.ps1
```

Or manually:

```powershell
cd D:\platform-poc\registry
docker compose down
docker rm -f local-registry
cd ..\kestra
docker compose up -d
```
