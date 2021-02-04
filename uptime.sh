#!/bin/bash
[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

#####################
PUSER="${USER}"
PROG="${0##*/}"
PROGNAME=${PROG%%.*}
MYHOST="$(uname -n)"
MYHOST=${SERVERNAME:-$MYHOST}
CMD="$1"
GRAPHNAME="${WEBROOT:-.}/${MYHOST}-uptime.gif"

case ${CMD} in
	(debug)
		echo "WEBROOT=${WEBROOT}"
		echo "GRAPHNAME=${GRAPHNAME}"
		echo "UPTIME=$(uptime)"
		;;
	(update|graph|graph-weekly|graph-monthly|graph-yearly)
		if [ -n "$(which convert)" ]
		then
			uptime | convert -size 640x20 -font Liberation-Sans -pointsize 18 -unsharp 0x.5 -background none -trim +repage -fill black text:- ${GRAPHNAME}
		elif [ -n "$(which pbmtext)" ]
		then
			uptime | pbmtext | pnmcrop | pnmpad -white -left 2 -right 2 -top 2 -bottom 2 | pnmtopng > ${GRAPHNAME}
		else
			> ${GRAPHNAME}
			echo "no ImageMagick or NetPBM installed, can't convert uptime to png"
		fi
		;;
	(force-create|create)
		;;
	(*)
		echo "Invalid option for ${PROGNAME}"
		echo "${PROG} (update|graph|debug)"
		exit 1
		;;
esac
exit 0
