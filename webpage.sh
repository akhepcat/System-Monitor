#!/bin/bash
#

[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

#####################
PUSER="${USER}"
PROG="${0##*/}"
MYHOST="$(uname -n)"
MYHOST=${SERVERNAME:-$MYHOST}
PROGNAME=${PROG%%.*}
DATE=$(date)

week=$((43200 * 15))
# Values are in seconds, for  "--end now --start end-${DATE}"
# yesterday, plus 4 hours
YESTERDAY=90000
# last week, plus a 6h
LASTWEEK=648000
# last month, plus a week
LASTMONTH=3234543
# last year, plus a month
LASTYEAR=34819200



CMD=$1
URL=$2


# Good
#      wget OK|xmt=3 rcv=3 loss=0 min=1.05 avg=1.16 max=1.37
# Bad
#      wget BAD|xmt=3 rcv=0 loss=100 min=0 avg=0 max=0 

# 20 seconds max for good results.
# 1 wget every 1/5 sec, wait max a double-sat hop for response
poll() {
	MYURL=$1

	TEMP=$(mktemp -d)
	MYSECONDS=$( (time wget --quiet --directory-prefix=${TEMP} -p ${MYURL}) 2>&1 | grep real | sed 's/.*\([0-9]\{1,5\}\)m\([0-9].*\)s/\1 \2/' | awk '{print $1 * 60 + $2}')
	rm -rf ${TEMP}
}

usage() {
	echo "Invalid option for ${PROGNAME}"
	echo "${PROG} (create|update|graph|graph-weekly|graph-monthly|graph-yearly|debug)"
}

if [ -z "$URLS" ];
then
	usage
	exit 1
fi

for URL in ${URLS}
do

	URLHOST=${URL##*//}
	URLHOST=${URLHOST%%/*}
	PAGE=${URL##*/}
	PAGE=${PAGE//./}
	RRDFILE="${RRDLIB:-.}/webpage-${URLHOST}-${PAGE}.rrd"
	GRAPHNAME="${WEBROOT:-.}/webpage-${URLHOST}-${PAGE}.png"

    case $CMD in
	(debug)
		echo "RRDLIB=${RRDLIB}"
		echo "WEBROOT=${WEBROOT}"
		echo "RRDFILE=${RRDFILE}"
		echo "GRAPHNAME=${GRAPHNAME}"
		poll $URL
		echo MYSECONDS=${MYSECONDS}
		;;

	(force-create|create)
		if [ "${CMD}" == "force-create" -o ! -r ${RRDFILE} ];
		then
		rrdtool create ${RRDFILE} -s 60 \
		DS:seconds:GAUGE:180:0:100 \
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
		poll $URL

		rrdtool update ${RRDFILE} N:${MYSECONDS}
		;;

	(graph)
#	        -Y -u 1.1 -l 0 -L 2 \
	    rrdtool graph ${GRAPHNAME} \
	        -Y -L 2 \
		-v "wget stats" -w 700 -h 300 -t "last 24 hours wget stats for ${URL} - ${DATE}" \
		-c ARROW\#000000 -x MINUTE:30:MINUTE:30:HOUR:1:0:%H \
		DEF:seconds=${RRDFILE}:seconds:AVERAGE \
		DEF:avgsec=${RRDFILE}:seconds:AVERAGE \
		COMMENT:"	" \
		LINE1:seconds\#000000:"page load time" \
		LINE2:avgsec\#0000cc:"avg load time" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:seconds:MIN:"page-load minimum\: %lf" \
		GPRINT:seconds:MAX:"page-load maximum\: %lf" \
		GPRINT:seconds:AVERAGE:"page-load average\: %lf" \
		COMMENT:"	\j"
		;;

	(graph-weekly)
#	        -Y -u 1.1 -l 0 -L 2 \
            rrdtool graph ${GRAPHNAME//.png/-week.png} \
		-Y -L 2 \
		-v "wget stats" -w 700 -h 300 -t "last 7 days wget stats for ${URL} - ${DATE}" \
                --end now --start end-${LASTWEEK} -c ARROW\#000000  \
                DEF:seconds=${RRDFILE}:seconds:AVERAGE \
		DEF:avgsec=${RRDFILE}:seconds:AVERAGE \
		COMMENT:"	" \
		LINE1:seconds\#000000:"page load time" \
		LINE2:avgsec\#0000cc:"avg load time" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:seconds:MIN:"page-load minimum\: %lf" \
		GPRINT:seconds:MAX:"page-load maximum\: %lf" \
		GPRINT:seconds:AVERAGE:"page-load average\: %lf" \
		COMMENT:"	\j"
		;;

	(graph-monthly)
            rrdtool graph ${GRAPHNAME//.png/-month.png} \
		-v "wget stats" -w 700 -h 300 -t "last month's stats for ${URL} - ${DATE}" \
                --end now --start end-${LASTMONTH} -c ARROW\#000000  \
                DEF:seconds=${RRDFILE}:seconds:AVERAGE \
		DEF:avgsec=${RRDFILE}:seconds:AVERAGE \
		COMMENT:"	" \
		LINE1:seconds\#000000:"page load time" \
		LINE2:avgsec\#0000cc:"avg load time" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:seconds:MIN:"page-load minimum\: %lf" \
		GPRINT:seconds:MAX:"page-load maximum\: %lf" \
		GPRINT:seconds:AVERAGE:"page-load average\: %lf" \
		COMMENT:"	\j"
		;;

	(graph-yearly)
            rrdtool graph ${GRAPHNAME//.png/-year.png} \
		-v "wget stats" -w 700 -h 300 -t "last year's stats for ${URL} - ${DATE}" \
                --end now --start end-${LASTYEAR} -c ARROW\#000000  \
                DEF:seconds=${RRDFILE}:seconds:AVERAGE \
		DEF:avgsec=${RRDFILE}:seconds:AVERAGE \
		COMMENT:"	" \
		LINE1:seconds\#000000:"page load time" \
		LINE2:avgsec\#0000cc:"avg load time" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:seconds:MIN:"page-load minimum\: %lf" \
		GPRINT:seconds:MAX:"page-load maximum\: %lf" \
		GPRINT:seconds:AVERAGE:"page-load average\: %lf" \
		COMMENT:"	\j"
		;;

	(*)
		usage
		exit 1
		;;
    esac

done
