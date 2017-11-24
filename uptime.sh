#!/bin/bash

if [ -r /usr/share/fonts/misc/unifont.bdf ]
then
	FONT="-font /usr/share/fonts/misc/unifont.bdf"
fi

#####################
PUSER="${USER}"
PROG="${0##*/}"
PROGNAME=${PROG%%.*}
MYHOST="$(uname -n)"
CMD="$1"
GRAPHNAME="${WEBROOT:-.}/${MYHOST}-uptime.gif"
UPTIME=$(uptime 2>/dev/null)

case ${CMD} in
	(debug)
		echo "WEBROOT=${WEBROOT}"
		echo "GRAPHNAME=${GRAPHNAME}"
		echo "UPTIME=${UPTIME}"
		;;
	(update|graph|graph-weekly|graph-monthly|graph-yearly)
		echo ${UPTIME} | pbmtext ${FONT} | pnmcrop | pnmpad -white -left 2 -right 2 -top 2 -bottom 2 | pnmtopng > ${GRAPHNAME}
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
