#!/bin/bash
#
# License:      GNU General Public License (GPL)
# Written by:   Pablo Ruiz <pablo.ruiz@gmail.com>
#
#   This script manages TCG/SSC SED disk unlocking
#
#   usage: $0 {start|stop|status|monitor|validate-all|meta-data|metadata}
#
#   The "start" arg unlocks disk(s).
#   The "stop" arg (optionally) locks disk(s).
#
#       OCF parameters are as follows
#       OCF_RESKEY_devices - A comma-separated list of devices to lock/unlock
#	OCF_RESKEY_password - SED locking/unlocking password
#	OCF_RESKEY_nolock - Do not lock on stop/disable
#
#   See: http://www.linux-ha.org/doc/dev-guides/ra-dev-guide.html
#
#######################################################################
# Initialization:

LC_ALL=C
LANG=C
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LC_ALL LANG PATH

: ${OCF_FUNCTIONS_DIR=${OCF_ROOT}/lib/heartbeat}
. ${OCF_FUNCTIONS_DIR}/ocf-shellfuncs
: ${HELPERS_DIR=/usr/share/cluster/sed-unlock.d}
: ${SEDUTIL=/usr/sbin/sedutil-cli}

: ${OCF_RESKEY_nolock=0}

USAGE="usage: $0 {start|stop|status|monitor|validate-all|meta-data|metadata}";

#######################################################################

meta_data() {
        cat <<END
<?xml version="1.0"?>
<!DOCTYPE resource-agent SYSTEM "ra-api-1.dtd">
<resource-agent name="zfs">
<version>1.0</version>
<longdesc lang="en">
This script manages locking/unlocking of TCG/SCC SED disks.
It can unlock a disk as resource start/enable, and re-lock it on stop/disable.
</longdesc>
<shortdesc lang="en">Manages TCG/SCC SED disk(s) locking/unlocking</shortdesc>

<parameters>
<parameter name="devices" unique="1" required="1" primary="1">
<longdesc lang="en">
A comma-separated list of devices to lock/unlock.
</longdesc>
<shortdesc lang="en">devices list</shortdesc>
<content type="string" default="" />
</parameter>
<parameter name="password" unique="1" required="1">
<longdesc lang="en">
SED locking/unlocking password
</longdesc>
<shortdesc lang="en">SED password</shortdesc>
<content type="string" default="" />
</parameter>
<parameter name="nolock" unique="1" required="0">
<longdesc lang="en">
Do not lock devices on stop/disable
</longdesc>
<shortdesc lang="en">Do not lock devices</shortdesc>
<content type="boolean" default="0" />
</parameter>
</parameters>

<actions>
<action name="start"   timeout="60s" />
<action name="stop"    timeout="60s" />
<action name="monitor" depth="0"  timeout="30s" interval="5s" />
<action name="validate-all"  timeout="30s" />
<action name="meta-data"  timeout="5s" />
</actions>
</resource-agent>
END
        exit $OCF_SUCCESS
}

sedutil() {
	"${SEDUTIL}" "$@"
}

device_is_locked() {
	local -r device="$1"
	local -r password="$OCF_RESKEY_password"

	sedutil --listLockingRange 0 "$password" "$device"|egrep -q '(Read|Write)Locked:[ ]*1'
}

device_locking_enabled() {
	local -r device="$1"
	local -r password="$OCF_RESKEY_password"

	sedutil --listLockingRange 0 "$password" "$device"|egrep -q '(Read|Write)LockEnabled:[ ]*1'
}

unlock_device() {
	local -r device="$1"
	local -r password="$OCF_RESKEY_password"

	if ! device_is_locked "$device"; then
		ocf_log info "unlock_device: device ${device} already unlocked, skipping."
		return $OCF_SUCCESS
	fi

	if ! device_locking_enabled "$device"; then
		ocf_log err "unlock_device: device ${device} locking not enabled."
		return $OCF_ERR_CONFIGURED
	fi

	sedutil --setLockingRange 0 rw "$password" "$device"
}

unlock_devices() {
	local -ar devices=(${OCF_RESKEY_devices//,/ })
	local -i result=$OCF_SUCCESS

	ocf_log debug "Unlocking devices..."

	for device in "${devices[@]}"; do
		ocf_log debug "Unlocking ${device}..."
		if ! unlock_device "$(readlink -f ${device})"; then
			ocf_log err "unlocking of ${device} failed: $?"
			result=$OCF_ERR_GENERIC
		fi
	done

	return $result
}

lock_device() {
	local -r device="$1"
	local -r password="$OCF_RESKEY_password"

	if ocf_is_true $OCF_RESKEY_nolock; then
		ocf_log warn "lock_device: not locking ${device} due to nolock."
		return $OCF_SUCCESS
	fi

	if device_is_locked "$device"; then
		ocf_log info "lock_device: device ${device} already locked, skipping."
		return $OCF_SUCCESS
	fi

	if ! device_locking_enabled "$device"; then
		ocf_log err "lock_device: device ${device} locking not enabled."
		return $OCF_ERR_CONFIGURED
	fi

	sedutil --setLockingRange 0 lk "$password" "$device"
}

lock_devices() {
	local -ar devices=(${OCF_RESKEY_devices//,/ })
	local -i result=$OCF_SUCCESS

	ocf_log debug "Locking devices..."

	for device in "${devices[@]}"; do
		ocf_log debug "locking ${device}..."
		if ! lock_device "$(readlink -f ${device})"; then
			ocf_log err "locking of ${device} failed: $?"
			result=$OCF_ERR_GENERIC
		fi
	done

	return $result
}

# Validates whether we can lock/unlock drives
validate () {
	local -ar devices=(${OCF_RESKEY_devices//,/ })
	local -i result=$OCF_SUCCESS

	# Check that the `sedutil-cli' command is available
	if ! [ -x "$SEDUTIL" ] > /dev/null; then
		return $OCF_ERR_INSTALLED
	fi

	if [ -z "$OCF_RESKEY_password" ]; then
		ocf_log err "validate: missing password parameter."
		return $OCF_ERR_CONFIGURED
	fi

	# Check wether all devices have locking enabled
	for device in "${devices[@]}"; do
		if ! device_locking_enabled "$(readlink -f $device)"; then
			ocf_log err "validate: device $device locking not enabled."
			result=$OCF_ERR_CONFIGURED
		fi
	done

	return $result
}

monitor () {
	local -ar devices=(${OCF_RESKEY_devices//,/ })
	local -i result=$OCF_SUCCESS

	validate || return $?

	for device in "${devices[@]}"; do
		if device_is_locked "$(readlink -f $device)"; then
			ocf_log info "monitor: device $device is locked."
			result=$OCF_NOT_RUNNING
		fi
	done

	return $result
}

usage () {
	echo $USAGE >&2
	return $1
}

if [ $# -ne 1 ]; then
	usage $OCF_ERR_ARGS
	exit $?
fi

case $1 in
	meta-data|metadata)	meta_data;;
	start)			unlock_devices;;
	stop)			lock_devices;;
	status|monitor)		monitor;;
	validate-all)		validate;;
	usage)			usage $OCF_SUCCESS;;
	*)			usage $OCF_ERR_UNIMPLEMENTED;;
esac

exit $?

# vim: set smartindent expandtab ai ts=4 sw=4 :
