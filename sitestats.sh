#!/bin/bash

#WEBROOT="/var/www/sitestats"

#####################
PUSER="${USER}"
PROG="${0##*/}"
PROGNAME=${PROG%%.*}
MYHOST="$(uname -n)"
CMD="$1"
PLUGBOXEN=$(find ${WEBROOT} -maxdepth 1 -type d -iname "plug*")

case ${CMD} in
	(debug)
		echo "WEBROOT=${WEBROOT}"
		echo "PLUGBOXES=${PLUGBOXEN}"
		;;
	(graph|graph-weekly|graph-monthly|graph-yearly)
		for PATH in ${PLUGBOXEN}
		do
			HOST=$(/usr/bin/basename ${PATH})
			echo "<a href='/sitestats/${HOST}'>${HOST}</a>&nbsp;&nbsp;&nbsp;"
		done
		;;
	(update|force-create|create)
		;;
	(*)
		echo "Invalid option for ${PROGNAME}"
		echo "${PROG} (graph|debug)"
		exit 1
		;;
esac
exit 0
