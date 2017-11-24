#!/bin/bash
#

EVERY=5	# Change this to poll every  X minutes: RRD still based on 1-minute polls,
		# with in-between samples cached in $POLLCACHE

[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

#####################
PUSER="${USER}"
PROG="${0##*/}"
MYHOST="$(uname -n)"
PROGNAME=${PROG%%.*}
DATE=$(date)
# Values are in seconds, for  "--end now --start end-${DATE}"
# yesterday, plus 4 hours
YESTERDAY=90000
# last week, plus a 6h
LASTWEEK=648000
# last month, plus a week
LASTMONTH=3234543
# last year, plus a month
LASTYEAR=34819200
POLLCACHE=/tmp/webspeed.cache
CACHE=$(cat ${POLLCACHE} 2>/dev/null)
CMD=$1


TIME=$(date '+%M')
NOW=$(( (${TIME} + 1) % ${EVERY} == 0 ))   # will be 1 if it's time to poll, otherwise 0

usage() {
	echo "Invalid option for ${PROGNAME}"
	echo "${PROG} (create|update|graph|graph-weekly|debug)"
}

RRDFILE="${RRDLIB:-.}/${MYHOST}-webspeed.rrd"
GRAPHNAME="${WEBROOT:-.}/${MYHOST}-webspeed.png"

case $CMD in
	(debug)
		echo "RRDLIB=${RRDLIB}"
		echo "WEBROOT=${WEBROOT}"
		echo "RRDFILE=${RRDFILE}"
		echo "GRAPHNAME=${GRAPHNAME}"
		echo "Polling every ${EVERY} minutes"
		if [ $NOW -eq 1 ];
		then
			echo "Generating poll..."
			echo "BPS=$(page_load_time.pl ${SITECACHE})"
		else
			echo "Cached poll...."
			echo "BPS=${CACHE:-0}"
		fi
		;;

	(force-create|create)
		if [ "${CMD}" == "force-create" -o ! -r ${RRDFILE} ];
		then
		rrdtool create ${RRDFILE} -s 60 \
		DS:seconds:GAUGE:180:U:U \
		RRA:AVERAGE:0.5:1:1440 \
		RRA:MIN:0.5:1:1440 \
		RRA:MAX:0.5:1:1440 \
		RRA:AVERAGE:0.5:5:2016 \
		RRA:MIN:0.5:5:2016 \
		RRA:MAX:0.5:5:2016 \
		RRA:AVERAGE:0.5:30:1488 \
		RRA:MIN:0.5:30:1488 \
		RRA:MAX:0.5:30:1488 \
		RRA:AVERAGE:0.5:120:4380 \
		RRA:MIN:0.5:120:4380 \
		RRA:MAX:0.5:120:4380 \
		RRA:AVERAGE:0.5:1440:1
		fi
		;;

	(update)
		if [ $NOW -eq 1 ];
		then
			BPS=$(page_load_time.pl ${SITECACHE})
			echo ${BPS} > ${POLLCACHE} 2>/dev/null
		else
			BPS=${CACHE:-0}
		fi
		rrdtool update ${RRDFILE} N:${BPS}
		;;

	(graph)
#	        -Y -u 1.1 -l 0 -L 2 \
	    rrdtool graph ${GRAPHNAME} \
	        -Y -L 2 \
		-v "Page Load Time" -w 700 -h 300 -t "last 24h pageload times for ${MYHOST} - ${DATE}" \
		-c ARROW\#000000 -x MINUTE:30:MINUTE:30:HOUR:1:0:%H \
		DEF:seconds=${RRDFILE}:seconds:AVERAGE \
		DEF:avgsec=${RRDFILE}:seconds:AVERAGE:step=1800 \
		COMMENT:"	" \
		LINE1:seconds\#000000:"sec" \
		LINE2:avgsec\#0000cc:"avg sec": \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:seconds:MIN:"sec minimum\: %lf" \
		GPRINT:seconds:MAX:"sec maximum\: %lf" \
		GPRINT:seconds:AVERAGE:"sec average\: %lf" \
		COMMENT:"	\j"
		;;

	(graph-weekly)
            rrdtool graph ${GRAPHNAME//.png/-week.png} \
		-Y -L 2 \
		-v "bps stats" -w 700 -h 300 -t "last 7 days bps stats for ${MYHOST} - ${DATE}" \
                --end now --start end-$LASTWEEK -c ARROW\#000000  \
                DEF:seconds=${RRDFILE}:seconds:AVERAGE \
		DEF:avgsec=${RRDFILE}:seconds:AVERAGE:step=1800 \
		COMMENT:"	" \
		LINE1:seconds\#000000:"sec" \
		LINE2:avgsec\#0000cc:"avg sec": \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:seconds:MIN:"sec minimum\: %lf" \
		GPRINT:seconds:MAX:"sec maximum\: %lf" \
		GPRINT:seconds:AVERAGE:"sec average\: %lf" \
		COMMENT:"	\j"
		;;

	(graph-monthly)
            rrdtool graph ${GRAPHNAME//.png/-month.png} \
		-Y -L 2 \
		-v "bps stats" -w 700 -h 300 -t "last month's bps stats for ${MYHOST} - ${DATE}" \
                --end now --start end-$LASTMONTH -c ARROW\#000000  \
                DEF:seconds=${RRDFILE}:seconds:AVERAGE \
		DEF:avgsec=${RRDFILE}:seconds:AVERAGE:step=1800 \
		COMMENT:"	" \
		LINE1:seconds\#000000:"sec" \
		LINE2:avgsec\#0000cc:"avg sec": \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:seconds:MIN:"sec minimum\: %lf" \
		GPRINT:seconds:MAX:"sec maximum\: %lf" \
		GPRINT:seconds:AVERAGE:"sec average\: %lf" \
		COMMENT:"	\j"
		;;

	(graph-yearly)
            rrdtool graph ${GRAPHNAME//.png/-year.png} \
		-Y -L 2 \
		-v "bps stats" -w 700 -h 300 -t "last year's bps stats for ${MYHOST} - ${DATE}" \
                --end now --start end-$LASTYEAR -c ARROW\#000000  \
                DEF:seconds=${RRDFILE}:seconds:AVERAGE \
		DEF:avgsec=${RRDFILE}:seconds:AVERAGE:step=1800 \
		COMMENT:"	" \
		LINE1:seconds\#000000:"sec" \
		LINE2:avgsec\#0000cc:"avg sec": \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:seconds:MIN:"sec minimum\: %lf" \
		GPRINT:seconds:MAX:"sec maximum\: %lf" \
		GPRINT:seconds:AVERAGE:"sec average\: %lf" \
		COMMENT:"	\j"
		;;

	(*)
		usage
		exit 1
		;;
esac

