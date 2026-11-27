# Windows reference (preview)

A real Windows x64 VM managed by Docker Compose, complementing the
[Linux report reference](../report-app/README.md). Use it first for native
CMDOP installation, IPC, lifecycle and update acceptance; a working Windows
showcase is a later outcome.

## First boot

- Linux x86-64 Docker Engine with KVM/TUN. Not Docker Desktop on macOS.
- Four CPU cores, 8 GiB guest RAM (10 GiB container limit), 80 GiB virtual
  disk. Reserve 110 GiB free on the storage filesystem before provisioning.
- Official Windows 11 x64 ISO, valid license or applicable evaluation
  entitlement. Verify the installation media hash. The VM wrapper does
  not license Windows. Manual installation requires your authorized account
  and acceptance of applicable terms; no embedded activation or unattended
  credentials.

The image is pinned to the amd64 manifest of
[dockur/windows v6.06](https://github.com/dockur/windows/releases/tag/v6.06).

Create a new, dedicated, empty storage directory outside Git on the Linux
Docker host. Never reuse an unrelated folder or VM disk. Keep the ISO
separate. Set actual canonical paths and the verified media hash:

~~~sh
export CMDOP_WINDOWS_STORAGE=/absolute/path/to/dedicated-windows-storage
export CMDOP_WINDOWS_ISO=/absolute/path/to/Windows11-x64.iso
export CMDOP_WINDOWS_ISO_SHA256=YOUR_VERIFIED_64_HEX_SHA256
python3 doctor.py
~~~

Run the first-provisioning preflight on the Docker host (it refuses nonempty storage). Confirm that KVM can create a VM,
not merely that its device exists. Then start this standalone project:

~~~sh
docker compose up -d windows
docker compose logs -f windows
~~~

The web console binds to 127.0.0.1:18006 by default. On a remote host use
an authenticated SSH tunnel. Do not expose the console, RDP or Samba
publicly. KVM, TUN and NET_ADMIN are needed; no privileged mode, Docker
socket, host networking or source/home bind mount. Verify actual hardware
acceleration and successful guest boot. Container status is not guest readiness.

Stop only this VM with `docker compose stop windows`. Restart an existing guest with `docker compose start windows`. Its persistent disk
preserves Windows and CMDOP identity. Use a separate storage directory and
Compose project name for another VM or clean-install trial.

## Native acceptance, then showcase

Use a disposable Windows user and explicitly authorized test contour. Copy
only the exact hash-matched candidate bundle from the Rust release maintainer.
The upstream image can expose a dedicated `shared` subdirectory under the
VM storage. Treat this as guest-accessible exchange, never a trusted source
or secrets directory. Verify the artifact hashes inside Windows. Run the
candidate PowerShell installer with explicit ArtifactPath and a fresh isolated
InstallDir, then the matching IPC and startup-control test executables.
Do not use Setup or enroll automatically before those tests. No production
credentials, source checkout or signing key enter the VM.

After the native provider and published release are accepted:

1. Install CMDOP using the actual released PowerShell installer.
2. Complete setup and verify native control, running version, online state,
   repeated install, logon/restart, signed update/recovery and uninstall.
3. Run the same simple read-only report task on Linux and Windows using
   explicit machine IDs and actually supported tools.
4. Record OS and release versions, artifact hashes and a clean re-run.

Windows report fixture and SDK integration remain follow-up work. Do not
claim verified Windows installation or optional feature parity yet.

See [Windows 11 requirements](https://learn.microsoft.com/en-us/windows/whats-new/windows-11-requirements)
and [Windows 11 Enterprise evaluation](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise).
