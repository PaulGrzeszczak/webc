#!/bin/bash
. /etc/webc/webc.conf

! cmdline_has debug && { bash "$@"; exit 0; }

bash -x "$@" 2>&1 | while read line; do
	logger -t $1 -p syslog.debug -- "$line"
done
