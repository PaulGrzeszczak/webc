#!/bin/bash
# Setting up Webconverger system as root user
. /etc/webc/webc.conf

cmdline_has debug && set -x

sub_literal() {
  awk -v str="$1" -v rep="$2" '
  BEGIN {
    len = length(str);
  }

  (i = index($0, str)) {
    $0 = substr($0, 1, i-1) rep substr($0, i + len);
  }

  1'
}

process_options()
{

# Create a Webconverger preferences to store dynamic FF options
cat > "$prefs" <<EOF
// This file is autogenerated based on cmdline options by live-config.sh. Do
// not edit this file, your changes will be overwriting on the next reboot!

EOF

# If printing support is not installed, prevent printing dialogs from being
# shown
if ! dpkg -s cups 2>/dev/null >/dev/null; then
	echo '// Print support not included, disable print dialogs' >> "$prefs"
	echo 'pref("print.always_print_silent", true);' >> "$prefs"
	echo 'pref("print.show_print_progress", false);' >> "$prefs"
fi

for x in $( cmdline ); do
	case $x in

	debug)
		echo "webc ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
		;;

	chrome=*)
		chrome=${x#chrome=}
		dir="/etc/webc/extensions/${chrome}"
		test -d $dir && {
			test -e "$link" && rm -f "$link"
			logs "switching chrome to ${chrome}"
			ln -s "$dir" "$link"
		}
		;;

	locale=*)
		locale=${x#locale=}
		echo "pref(\"general.useragent.locale\", \"${locale}\");" >> "$prefs"
		echo "pref(\"intl.accept_languages\", \"${locale}, en\");" >> "$prefs"
		;;

	cron=*)
		cron="$( echo ${x#cron=} | sed 's,%20, ,g' )"		
		cat <<EOC > /etc/cron.d/live-config
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
$cron
EOC
		;;

	homepage=*)
		homepage="$( echo ${x#homepage=} | sed 's,%20, ,g' )"
		echo "browser.startup.homepage=$(echo $homepage | awk '{print $1}')" > /opt/firefox/defaults/preferences/homepage.properties
		;;
	esac
done

if ! cmdline_has noclean
then
cat >> "$prefs" <<EOF
// Enable private browsing and enable all sanitize on shutdown features just
// to be sure we are wiping the slate clean.
pref("privateBrowsingEnabled", true);
pref("browser.privatebrowsing.autostart", true);
pref("privacy.sanitize.sanitizeOnShutdown", true);
pref("privacy.clearOnShutdown.offlineApps", true);
pref("privacy.clearOnShutdown.passwords", true);
pref("privacy.clearOnShutdown.siteSettings", true);
// cpd = Clear Private Data
pref("privacy.cpd.offlineApps", true);
pref("privacy.cpd.passwords", true);
pref("privacy.sanitize.sanitizeOnShutdown", true);
EOF
fi

# Make sure /home has noexec and nodev, for extra security.
# First, just try to remount, in case /home is already a separate filesystem
# (when using persistence, for example).
mount -o remount,noexec,nodev /home 2>/dev/null || (
	# Turn /home into a tmpfs. We use a trick here: after the mount, this
	# subshell will still have the old /home as its current directory, so
	# we can still read the files in the original /home. By passing -C to
	# the second tar invocation, it does a chdir, which causes it to end
	# up in the new filesystem. This enables us to easily copy the
	# existing files from /home into the new tmpfs.
	cd /home
	mount -o noexec,nodev -t tmpfs tmpfs /home
	tar -c . | tar -x -C /home
)

stamp=$( git show $webc_version | grep '^Date')

test -f ${link}/content/about.xhtml.bak || cp ${link}/content/about.xhtml ${link}/content/about.xhtml.bak
cat ${link}/content/about.xhtml.bak |
sub_literal 'OS not running' "${webc_version} ${stamp}" |
sub_literal 'var aboutwebc = "";' "var aboutwebc = \"$(echo ${install_qa_url} | sed 's,&,&amp;,g')\";" > ${link}/content/about.xhtml

} # end of process_options

update_cmdline() {
	SECONDS=0
	while true
	do
		wget --timeout=5 -t 1 -q -O /etc/webc/cmdline.tmp "$config_url" && break
		test $? = 8 && break # 404
		test $SECONDS -gt 15 && break
		sleep 1
	done
	
	# A configuration file always has a homepage
	grep -qs homepage /etc/webc/cmdline.tmp && mv /etc/webc/cmdline.tmp /etc/webc/cmdline
	touch /etc/webc/cmdline
}

wait_for $live_config_pipe 2>/dev/null

. "/etc/webc/webc.conf"
cmdline_has noconfig || update_cmdline
process_options

echo ACK > $live_config_pipe

# live-config should restart via inittab and get blocked 
# until $live_config_pipe is re-created
