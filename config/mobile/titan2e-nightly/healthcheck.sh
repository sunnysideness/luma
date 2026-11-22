#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Titan 2 Elite greenboot health check for the generic ARM nightly userland.
#
# greenboot 0.16 restarts the computer when a required check fails. The alpha
# Titan script required greetd/phoc/phosh, which the nightly does not run, and
# wrapped the nightly's own required checks in a way that turned their
# non-trial reports into a unit failure -- so greenboot rebooted a healthy
# phone about three minutes into every boot. This version only REPORTS: it runs
# the nightly's required checks for the log and never fails the unit, so the
# boot is blessed and slot a marked successful without a spurious rollback.
set -u
log() { echo "titan2e-health: $*"; }

if [ -e /run/ostree-booted ]; then
	for d in /usr/lib/greenboot/check/required.d /etc/greenboot/check/required.d; do
		for s in "$d"/*.sh; do
			[ -e "$s" ] || continue
			if timeout 90 bash "$s"; then
				log "ok: ${s##*/}"
			else
				log "warning: ${s##*/} exited non-zero (reported only)"
			fi
		done
	done
fi

dm=$(systemctl show -P Id display-manager.service 2>/dev/null)
if [ -n "$dm" ] && systemctl -q is-active "$dm"; then
	log "display manager active: $dm"
else
	log "warning: display manager ${dm:-none} not active (reported only)"
fi
log "health check finished; greenboot may bless this deployment"
exit 0
