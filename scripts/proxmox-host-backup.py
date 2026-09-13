#!/usr/bin/env python3
"""Back up the PVE host to its configured PBS storage (run as root)."""
import fcntl
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile

STORAGE = "pbs-synology"
EXCLUDES = [
    "/dev", "/proc", "/sys", "/run", "/tmp", "/var/tmp", "/mnt", "/media",
    "/var/lib/vz/images", "/var/lib/vz/dump", "/var/lib/lxc",
    "/var/lib/pve-cluster/config.db", "/var/lib/pve-cluster/config.db-*",
    "/root/pbs-backup-20260913",
]


def main():
    if os.geteuid() != 0:
        raise SystemExit("Run as root on the Proxmox host")
    os.umask(0o077)
    with open("/run/lock/proxmox-host-backup.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        subprocess.run([
            "findmnt", "-rn", "-M", "/mnt/pbs", "-t", "nfs,nfs4",
            "-S", "10.10.40.2:/volume1/pbs",
        ], check=True, stdout=subprocess.DEVNULL)
        config = json.loads(subprocess.check_output([
            "pvesh", "get", f"/storage/{STORAGE}", "--output-format", "json",
        ], text=True))
        if config["type"] != "pbs":
            raise SystemExit("Expected PBS storage")
        env = os.environ.copy()
        env["PBS_PASSWORD_FILE"] = f"/etc/pve/priv/storage/{STORAGE}.pw"
        # The password-file setting must not be shadowed by inherited credentials.
        for key in ("PBS_PASSWORD", "PBS_PASSWORD_FD", "PBS_PASSWORD_CMD"):
            env.pop(key, None)
        env["PBS_REPOSITORY"] = (
            f'{config["username"]}@{config["server"]}:{config["datastore"]}'
        )
        env["PBS_FINGERPRINT"] = config["fingerprint"]
        with tempfile.TemporaryDirectory(prefix="proxmox-recovery-", dir="/run") as tmp:
            recovery = Path(tmp)
            with sqlite3.connect(
                "file:/var/lib/pve-cluster/config.db?mode=ro", uri=True
            ) as source, sqlite3.connect(recovery / "config.db") as target:
                source.backup(target)
                if target.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                    raise RuntimeError("Configuration database integrity check failed")
            commands = {
                "pveversion.txt": ["pveversion", "-v"],
                "packages.txt": ["dpkg-query", "-W"],
                "block-devices.json": ["lsblk", "-J", "-o", "NAME,SIZE,TYPE,FSTYPE,UUID,MOUNTPOINTS"],
                "lvm.txt": ["lvs", "-a", "-o", "+devices"],
                "mounts.txt": ["findmnt"],
                "guests.json": ["pvesh", "get", "/cluster/resources", "--type", "vm", "--output-format", "json"],
                "partition-table.txt": ["sfdisk", "--dump", "/dev/nvme0n1"],
            }
            for name, args in commands.items():
                with (recovery / name).open("w") as out:
                    subprocess.run(args, stdout=out, check=True)
            (recovery / "README.txt").write_text(
                "File backup, not a bootable disk image. Reinstall compatible PVE; "
                "restore reviewed configuration and local files, then guests from PBS. "
                "config.db is an online SQLite backup of the PVE cluster database. "
                "Separate archives contain /etc/pve and /boot/efi. NAS shares, "
                "guest disk storage and pseudo filesystems are excluded. "
                "Keep NAS/PBS access credentials available independently.\n"
            )
            args = [
                "proxmox-backup-client", "backup", "root.pxar:/",
                "pve-config.pxar:/etc/pve", "efi.pxar:/boot/efi",
                f"recovery.pxar:{recovery}", "--backup-id", "proxmox",
                "--crypt-mode", "none",
            ]
            for path in EXCLUDES:
                args.extend(["--exclude", path])
            subprocess.run(args, env=env, check=True)


if __name__ == "__main__":
    main()
