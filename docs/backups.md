# PBS backups and recovery

Verified against the live homelab on 2026-09-13. The canonical identifiers and
schedules are in [`infrastructure/inventory.json`](../infrastructure/inventory.json)
under `backups`. PBS and its NAS export are manually managed infrastructure,
outside the OpenTofu guest lifecycle and Kubernetes ownership boundaries.

## Storage layout

| Component | Configuration |
|---|---|
| Proxmox VE host | `proxmox`, `10.10.30.30` |
| PBS | Unprivileged LXC 102, `10.10.30.228:8007` |
| Synology export | `10.10.40.2:/volume1/pbs` |
| Host and container mount | `/mnt/pbs` |
| PBS datastore | `synology`, backing path `/mnt/pbs/datastore` |
| Proxmox VE storage | `pbs-synology` |
| Backup identity | `pve@pbs!proxmox`, scoped to `/datastore/synology` |

The host mounts NFS 4.1; LXC 102 receives it through `mp0`. The container's
`backup` UID/GID 34 maps to host UID/GID 100034. Synology UNIX permissions allow
that identity to manage the datastore. A displayed `777` mode alone did not
resolve the initial Synology ACL denial; applying UNIX directory permissions
and correct ownership resolved access. Do not recursively change an active
backup store's ownership or permissions.

The host `/etc/fstab` entry is:

```fstab
10.10.40.2:/volume1/pbs /mnt/pbs nfs4 rw,vers=4.1,_netdev,nofail 0 0
```

[`pbs-nfs.conf`](../infrastructure/backup/pbs-nfs.conf) is installed at
`/etc/systemd/system/pve-container@102.service.d/pbs-nfs.conf`. It requires the
NFS mount before starting PBS, checks the expected source, and binds container
service lifetime to the mount unit. A NAS outage while mounted can block NFS I/O;
these startup checks do not provide failover. PBS's IP currently comes from DHCP;
keep it stable with a reservation or update `pbs-synology` when it changes.

## Daily schedule and retention

Both schedules use **Africa/Dar_es_Salaam (EAT, UTC+3)**:

| Time | Scope | Scheduler |
|---|---|---|
| 01:30 EAT | Host files and recovery metadata | `proxmox-host-backup.timer` |
| 02:00 EAT | All VMs and LXCs on `proxmox` | PVE job `pbs-daily-guests` |

The half-hour spacing reduces overlap but is not a dependency; a slow host
backup can overlap guest backups. The host timer is persistent and the PVE job
has `repeat-missed` enabled, so missed schedules catch up after the scheduler
returns. The guest job uses snapshot mode and includes future guests because
its selection is `all`; managed additional disks still follow their backup flags.
Stopped guests stay stopped. VM templates were included in the initial backup.

PBS deduplicates and compresses chunks automatically. Daily backups create full
restore points while storing only new chunks; they do not require a separate
"incremental" switch. File backups can still read files to identify changes.
VM dirty bitmaps can reduce subsequent reads while available.

**Retention is keep-all; no scheduled pruning or automatic backup deletion is
configured.** Daily garbage collection only reclaims unreferenced chunks; it
is not retention. Set a deliberate retention policy as backup history grows.
New backups are automatically verified by PBS. Verification checks stored data,
not whether an application will function after a restore.

The initial host plus 19 guests used about **129 GiB** in the datastore, with
about **372 GiB** remaining on the NAS volume at measurement time. PBS snapshot
sizes show logical data, not unique compressed consumption. NAS free space is
shared with other data and changes independently of backups.

## What is covered

The first complete generation contains 11 LXCs, 8 VMs (including the CentOS
template), and the host. The PBS container is included; its datastore bind mount
is excluded, preventing recursive backup. Frigate's NAS-mounted recordings are
also excluded. Bind/device mounts and remote datasets need separate protection.

The host backup group is `host/proxmox`, produced by
[`scripts/proxmox-host-backup.py`](../scripts/proxmox-host-backup.py):

| Archive | Content |
|---|---|
| `root.pxar` | Root filesystem, local host files, package/repository configuration, local ISOs/templates |
| `pve-config.pxar` | `/etc/pve`, including guest, storage, firewall and cluster configuration |
| `efi.pxar` | `/boot/efi` |
| `recovery.pxar` | Consistent online SQLite copy of `config.db`, package/version inventory, disk/partition layout, guest inventory |

The script excludes pseudo filesystems, temporary directories, `/mnt`, `/media`,
guest disk directories, existing vzdump archives, the live cluster database,
and the initial one-time backup's working directory. The consistent database
copy is included separately. Recovery staging uses a private temporary directory
under `/run` and is removed on completion. A process lock prevents concurrent
host script executions.

Host backups are file archives, not bootable disk images. Running guest snapshots
are not a substitute for application-specific database recovery procedures.
Preserve the PostgreSQL/Fintrack consistency and restore requirements in the
[upgrade runbook](runbooks/proxmox-9-upgrade.md).

## Authentication and deployment

The script reads server, datastore, identity and TLS fingerprint from the live
PVE `pbs-synology` storage configuration. The API secret stays in
`/etc/pve/priv/storage/pbs-synology.pw`; never copy its contents into Git or logs.
TLS uses the configured certificate fingerprint. Client-side archive encryption
is currently disabled, matching the guest storage configuration; access to NAS
backup files therefore needs to be restricted.

From this repository, install the host automation on Proxmox:

```bash
scp scripts/proxmox-host-backup.py infrastructure/backup/proxmox-host-backup.{service,timer} root@10.10.30.30:/root/
ssh root@10.10.30.30
install -m 0750 /root/proxmox-host-backup.py /usr/local/sbin/proxmox-host-backup
install -m 0644 /root/proxmox-host-backup.service /etc/systemd/system/
install -m 0644 /root/proxmox-host-backup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now proxmox-host-backup.timer
```

The PVE job's desired fields are in
[`guest-job.json`](../infrastructure/backup/guest-job.json). Inspect existing jobs
before creating or updating `pbs-daily-guests` through `/cluster/backup` or
**Datacenter → Backup**; do not install a second overlapping job. Its
`prune-backups=keep-all=1` explicitly preserves existing snapshots.

The one-time runners under `/root/pbs-*-20260913.py` are historical, not the daily
scheduler. The initial runner failed for unprivileged containers because it
inherited umask 077; the successful retry used 022. Do not invoke guest `vzdump`
from a wrapper with restrictive inherited directory permissions. The host-only
service runs as root and intentionally uses umask 077 for recovery material.

## Operations and verification

On Proxmox:

```bash
pvesh get /cluster/backup --output-format json
systemctl list-timers proxmox-host-backup.timer
systemctl start proxmox-host-backup.service  # manual host backup
journalctl -u proxmox-host-backup.service --since today
pvesm status --storage pbs-synology
pct exec 102 -- proxmox-backup-manager task list --all true
pct exec 102 -- proxmox-backup-debug api get /admin/datastore/synology/snapshots --output-format json
```

Guest job results use PVE's configured notification system. Host failures appear
in the systemd service status and journal; no external host-backup alert target
is configured. Check both schedulers. Keep the NFS export available and monitor
NAS free space. No guest restart is needed to enable these schedules.

## Recovery

1. Keep independent NAS/PBS credentials and installer access available. PBS runs
   on the same physical host, so host loss also removes the running backup server.
2. On host loss, bring up a replacement PBS instance (a separate machine or fresh
   instance on rebuilt PVE). Mount the existing NAS datastore and reuse it; do not
   format or reinitialize it. Only one PBS instance should operate the datastore.
3. Reinstall compatible Proxmox VE. Restore host archives into a staging directory,
   review network/storage/boot differences, and apply the needed configuration.
   Restore `config.db` only using the PVE recovery procedure with `pve-cluster`
   stopped; do not overwrite a live cluster database.
4. Reconnect PVE to PBS and restore guests onto appropriate storage. Recover data
   services before their dependent workloads. Use isolated networking and unused
   IDs for restore tests to avoid duplicate production identities.
5. Separately recover required NAS datasets and application-specific backups.
   Validate applications, then re-enable the daily jobs on the recovered host.

The first host recovery archive was restored into a temporary directory; its
SQLite database matched the source copy and passed `PRAGMA integrity_check`.
A small test archive also round-tripped successfully. These checks do not claim
a full bare-metal recovery or application-level restore test.

References: [PBS client and incremental backups](https://pbs.proxmox.com/docs/backup-client.html),
[Proxmox backup coverage](https://github.com/proxmox/pve-docs/blob/master/vzdump.adoc),
[PBS datastore configuration](https://pbs.proxmox.com/docs/storage.html).
