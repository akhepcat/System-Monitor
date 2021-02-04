#!/bin/bash
#
#  just a simple '[f]ping response' indexer, for when you have lots of [f]ping graphs and want to see them all in one page.
#

[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

# Timestamp for granular processing
HOUR=$(date +"%-H")	# we don't want zero-padded
MIN=$(date +"%-M")	# ^^^
TS=$(( ($HOUR * 3600) + ($MIN * 60) ))

#####################
PUSER="${USER}"
PROG="${0##*/}"
MYHOST="$(uname -n)"
MYHOST=${SERVERNAME:-$MYHOST}
PROGNAME=${PROG%%.*}
CMD="$1"
DATE=$(date)

RRDBASE="${RRDLIB:-.}/${PROGNAME}-"
GRAPHBASE="${WEBROOT:-.}/${PROGNAME}-"
IDX="${WEBROOT:-.}/${PROGNAME}.html"

html_head() {
	cat >${IDX} <<EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr">
	<head>
		<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
		<meta http-equiv="Content-Style-Type" content="text/css" />
		<meta http-equiv="Refresh" content="300" />
		<meta http-equiv="Pragma" content="no-cache" />
		<meta http-equiv="Cache-Control" content="no-cache" />
		<link rel="shortcut icon" href="favicon.ico" />
		<title> Real time Statistics </title>
	</head>
<body>
<p>
	I provide multiple statistics showing the general response health of the hosts below.<br />
	All statistics are gathered once a minute and the charts are redrawn every 5 minutes.
	Additionally, this page is automatically reloaded every 5 minutes.<br />
	Last updated at ${DATE}<br />
</p>
EOF

}

html_tail() {
	cat >>${IDX} <<EOF
<hr />
<p> (c) akhepcat - <a href="https://github.com/akhepcat/System-Monitor">System-Monitor Suite</a> on Github!</p>
</body>
</html>
EOF
}


case ${CMD} in
	(debug)
		echo "RRDLIB=${RRDLIB}"
		echo "WEBROOT=${WEBROOT}"
		echo "RRDs={${PINGS}}"
		echo "GRAPHs={"$(ls ${GRAPHBASE}*.png | sed "s^.*$GRAPHBASE^^g; s/\.png//g;")"}"

		;;

        (force-create|create)
        	echo "no-op" >/dev/null
		;;

	(update)
	        if [ 0 -eq $((TS % 300)) ]
	        then
		        echo "no-op" >/dev/null
	        fi
		;;

	(graph|graph-weekly|graph-monthly)
		# this would update the index too often, based on 'auto' scheduling
		echo "no-op" > /dev/null
		;;
	(graph-yearly|reindex)
		# this graphs just often enough, though could be longer

		html_head

		# menu header
		for RRD in ${PINGS} ;
		do
			echo "<a href=\"#${RRD}\">${RRD}</a>&nbsp;&nbsp;&nbsp;" >> ${IDX}
		done

		# Now the graphs
		for RRD in ${PINGS} ;
		do
			echo "<div name=\"${RRD}\">" >> ${IDX}
			echo "<a name=\"${RRD}\" />" >> ${IDX}

			if [ -r "${WEBROOT:-.}/${PROGNAME}-${RRD}.html" ]
			then
				echo "<h2><a href='${PROGNAME}-${RRD}.html'>${RRD}</a></h2>" >> ${IDX}
			else
				echo "<h2>${RRD}</h2>" >> ${IDX}
			fi
			# Table, 4 cols
			echo "<table>" >> ${IDX}
			# daily, weekly
			echo "<tr><th colspan='2'>Daily</th><th colspan='2'>Weekly</th></tr>" >> ${IDX}
			echo "<tr><td>&nbsp;</td>" >> ${IDX}
			graph="${PROGNAME}-${RRD}.png"
			echo "<td><img src=\"${graph}\" /></td>" >> ${IDX}
			echo "<td>&nbsp;</td>" >> ${IDX}
			graph="${PROGNAME}-${RRD}-week.png"
			echo "<td><img src=\"${graph}\" /></td>" >> ${IDX}
			echo "</tr>" >> ${IDX}

# this is now in the individual pages
#			# monthly, yearly
#			echo "<tr><th colspan='2'>Monthly</th><th colspan='2'>Yearly</th></tr>" >> ${IDX}
#			echo "<tr><td>&nbsp;</td>" >> ${IDX}
#			graph="${PROGNAME}-${RRD}-month.png"
#			echo "<td><img src=\"${graph}\" /></td>" >> ${IDX}
#			echo "<td>&nbsp;</td>" >> ${IDX}
#			graph="${PROGNAME}-${RRD}-year.png"
#			echo "<td><img src=\"${graph}\" /></td>" >> ${IDX}
#			echo "</tr>" >> ${IDX}
			echo "</table>" >> ${IDX}
			echo "</div>" >> ${IDX}
			echo "<p /><hr />" >> ${IDX}
		done
		html_tail
		;;
	(*)
		echo "Invalid option for ${PROGNAME}"
		echo "${PROG} (create|update|graph|debug)"
		exit 1
		;;
esac
