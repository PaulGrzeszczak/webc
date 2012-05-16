#!/bin/sh

find / -xdev ! -uid 0 -exec chown root:root {} \;
chmod 1777 /tmp
