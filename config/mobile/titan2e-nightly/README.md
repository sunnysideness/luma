# Titan 2 Elite — generic ARM nightly inputs

These files are what the generic ARM image + alpha device payload combination
needs on the Titan 2 Elite. They are **not** wired into a build yet; they are
the reviewed inputs for the new-model (generic image + device kit) migration
described in `docs/titan2e-nightly.md`.

| file | install to |
| --- | --- |
| `initramfs-init` | `/init` in the kernel's built-in initramfs |
| `healthcheck.sh` | `/etc/luma-titan2e-healthcheck` (mode 0755) |
| `etc/greenboot-healthcheck-60-titan2e-nightly.conf` | `/etc/systemd/system/greenboot-healthcheck.service.d/60-titan2e-nightly.conf` |
| `etc/var.mount` | `/etc/systemd/system/var.mount` + wanted by `local-fs.target` |
| `etc/logind-10-luma-bringup.conf` | `/etc/systemd/logind.conf.d/10-luma-bringup.conf` |
| `etc/systemd-99-no-watchdog.conf` | `/etc/systemd/system.conf.d/99-no-watchdog.conf` |

The watchdog override is a bring-up workaround, not a release fix; see
`docs/titan2e-nightly.md` for why it exists and what should replace it.
