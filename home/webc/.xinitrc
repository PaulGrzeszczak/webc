#!/bin/bash

. /etc/webc/webc.conf

if cmdline_has debug
then
	/etc/webc/logbot.sh /home/webc/webc.sh
else
	bash /home/webc/webc.sh
fi
