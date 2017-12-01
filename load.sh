#!/bin/bash
#
#  graphs the system load
#

[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

# Values are in seconds, for  "--end now --start end-${DATE}"
# yesterday, plus 4 hours
YESTERDAY=90000
# last week, plus a 6h
LASTWEEK=648000
# last month, plus a week
LASTMONTH=3234543
# last year, plus a month
LASTYEAR=34819200


#####################
PUSER="${USER}"
PROG="${0##*/}"
MYHOST="$(uname -n)"
PROGNAME=${PROG%%.*}
CMD="$1"
DATE=$(date)

RRDFILE="${RRDLIB:-.}/${MYHOST}-load.rrd"
GRAPHNAME="${WEBROOT:-.}/${MYHOST}.png"

case ${CMD} in
	(debug)
		echo "RRDLIB=${RRDLIB}"
		echo "WEBROOT=${WEBROOT}"
		echo "RRDFILE=${RRDFILE}"
		echo "GRAPHNAME=${GRAPHNAME//.png/-load.png}"
		echo "GRAPHNAME=${GRAPHNAME//.png/-cpu.png}"

		echo N=$(sed "s/\([0-9]\\.[0-9]\\{2\\}\)\ \([0-9]\\.[0-9]\\{2\\}\)\ \([0-9]\\.[0-9]\\{2\\}\).*/\1:\2:\3/" < /proc/loadavg):$(head -n 1 /proc/stat | sed "s/^cpu\ \+\([0-9]*\)\ \([0-9]*\)\ \([0-9]*\).*/\1:\2:\3/")
		;;

        (force-create|create)
                if [ "${CMD}" == "force-create" -o ! -r ${RRDFILE} ];
                then
		rrdtool create ${RRDFILE} -s 60 \
		DS:load1:GAUGE:180:0:U \
		DS:load5:GAUGE:180:0:U \
		DS:load15:GAUGE:180:0:U \
		DS:cpuuser:COUNTER:180:0:100 \
		DS:cpunice:COUNTER:180:0:100 \
		DS:cpusystem:COUNTER:180:0:100 \
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
		rrdtool update ${RRDFILE} \
		N:$(sed "s/\([0-9]\\.[0-9]\\{2\\}\)\ \([0-9]\\.[0-9]\\{2\\}\)\ \([0-9]\\.[0-9]\\{2\\}\).*/\1:\2:\3/" < /proc/loadavg):$(head -n 1 /proc/stat | sed "s/^cpu\ \+\([0-9]*\)\ \([0-9]*\)\ \([0-9]*\).*/\1:\2:\3/")
		;;

	(graph)
	    rrdtool graph ${GRAPHNAME//.png/-load.png} \
		-Y -u 1.1 -l 0 -L 2 -v "CPU load" -w 700 -h 300 -t "${MYHOST} last 24 hours CPU load - ${DATE}" \
		-c ARROW\#000000 -x MINUTE:30:MINUTE:30:HOUR:1:0:%H \
		DEF:load1=${RRDFILE}:load1:AVERAGE \
		DEF:load5=${RRDFILE}:load5:AVERAGE \
		DEF:load15=${RRDFILE}:load15:AVERAGE \
		COMMENT:"	" \
		LINE1:load1\#44FF44:"Load average 1 min" \
		LINE2:load5\#000ccc:"Load average 5 min" \
		LINE3:load15\#000000:"Load average 15 min" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:load1:MIN:"Load  1 min minimum\: %lf" \
		GPRINT:load1:MAX:"Load  1 min maximum\: %lf" \
		GPRINT:load1:AVERAGE:"Load  1 min average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:load5:MIN:"Load  5 min minimum\: %lf" \
		GPRINT:load5:MAX:"Load  5 min maximum\: %lf" \
		GPRINT:load5:AVERAGE:"Load  5 min average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:load15:MIN:"Load 15 min minimum\: %lf" \
		GPRINT:load15:MAX:"Load 15 min maximum\: %lf" \
		GPRINT:load15:AVERAGE:"Load 15 min average\: %lf" \
		COMMENT:"	\j"
	    #		
	    rrdtool graph ${GRAPHNAME//.png/-cpu.png} \
		-Y -r -u 100 -l 0 -L 2 -v "CPU usage in %" -w 700 -h 300 -t "${MYHOST} last 24 hours CPU usage - ${DATE}" \
		-c ARROW\#000000 -x MINUTE:30:MINUTE:30:HOUR:1:0:%H \
		DEF:user=${RRDFILE}:cpuuser:AVERAGE \
		DEF:nice=${RRDFILE}:cpunice:AVERAGE \
		DEF:sys=${RRDFILE}:cpusystem:AVERAGE \
		COMMENT:"	" \
		AREA:user\#FF0000:"CPU user" \
		STACK:nice\#000099:"CPU nice" \
		STACK:sys\#FFFF00:"CPU system" \
		CDEF:cpu=user,nice,sys,+,+ \
		COMMENT:"	\j" \
		GPRINT:cpu:MIN:"CPU usage minimum\: %lf%%" \
		GPRINT:cpu:MAX:"CPU usage maximum\: %lf%%" \
		GPRINT:cpu:AVERAGE:"CPU usage average\: %lf%%"
		;;
	(graph-weekly)
	    rrdtool graph ${GRAPHNAME//.png/-load-week.png} \
		-Y -u 1.1 -l 0 -L 2 -v "CPU load" -w 700 -h 300 -t "${MYHOST} last 7 days CPU load - ${DATE}" \
                --end now --start end-$LASTWEEK -c ARROW\#000000  \
                DEF:load1=${RRDFILE}:load1:AVERAGE \
		DEF:load5=${RRDFILE}:load5:AVERAGE \
		DEF:load15=${RRDFILE}:load15:AVERAGE \
		COMMENT:"	" \
		LINE1:load1\#44FF44:"Load average 1 min" \
		LINE2:load5\#000ccc:"Load average 5 min" \
		LINE3:load15\#000000:"Load average 15 min" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:load1:MIN:"Load  1 min minimum\: %lf" \
		GPRINT:load1:MAX:"Load  1 min maximum\: %lf" \
		GPRINT:load1:AVERAGE:"Load  1 min average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:load5:MIN:"Load  5 min minimum\: %lf" \
		GPRINT:load5:MAX:"Load  5 min maximum\: %lf" \
		GPRINT:load5:AVERAGE:"Load  5 min average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:load15:MIN:"Load 15 min minimum\: %lf" \
		GPRINT:load15:MAX:"Load 15 min maximum\: %lf" \
		GPRINT:load15:AVERAGE:"Load 15 min average\: %lf" \
		COMMENT:"	\j"
	    #		
	    rrdtool graph ${GRAPHNAME//.png/-cpu-week.png} \
		-Y -r -u 100 -l 0 -L 2 -v "CPU usage in %" -w 700 -h 300 -t "${MYHOST} last 7 days CPU usage - ${DATE}" \
                --end now --start end-$LASTWEEK -c ARROW\#000000  \
                DEF:user=${RRDFILE}:cpuuser:AVERAGE \
		DEF:nice=${RRDFILE}:cpunice:AVERAGE \
		DEF:sys=${RRDFILE}:cpusystem:AVERAGE \
		COMMENT:"	" \
		AREA:user\#FF0000:"CPU user" \
		STACK:nice\#000099:"CPU nice" \
		STACK:sys\#FFFF00:"CPU system" \
		CDEF:cpu=user,nice,sys,+,+ \
		COMMENT:"	\j" \
		GPRINT:cpu:MIN:"CPU usage minimum\: %lf%%" \
		GPRINT:cpu:MAX:"CPU usage maximum\: %lf%%" \
		GPRINT:cpu:AVERAGE:"CPU usage average\: %lf%%"
		;;
	(graph-monthly)
	    rrdtool graph ${GRAPHNAME//.png/-load-month.png} \
		-Y -u 1.1 -l 0 -L 2 -v "CPU load" -w 700 -h 300 -t "${MYHOST} last month's CPU load - ${DATE}" \
                --end now --start end-$LASTMONTH -c ARROW\#000000  \
                DEF:load1=${RRDFILE}:load1:AVERAGE \
		DEF:load5=${RRDFILE}:load5:AVERAGE \
		DEF:load15=${RRDFILE}:load15:AVERAGE \
		COMMENT:"	" \
		LINE1:load1\#44FF44:"Load average 1 min" \
		LINE2:load5\#000ccc:"Load average 5 min" \
		LINE3:load15\#000000:"Load average 15 min" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:load1:MIN:"Load  1 min minimum\: %lf" \
		GPRINT:load1:MAX:"Load  1 min maximum\: %lf" \
		GPRINT:load1:AVERAGE:"Load  1 min average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:load5:MIN:"Load  5 min minimum\: %lf" \
		GPRINT:load5:MAX:"Load  5 min maximum\: %lf" \
		GPRINT:load5:AVERAGE:"Load  5 min average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:load15:MIN:"Load 15 min minimum\: %lf" \
		GPRINT:load15:MAX:"Load 15 min maximum\: %lf" \
		GPRINT:load15:AVERAGE:"Load 15 min average\: %lf" \
		COMMENT:"	\j"
	    #		
	    rrdtool graph ${GRAPHNAME//.png/-cpu-month.png} \
		-Y -r -u 100 -l 0 -L 2 -v "CPU usage in %" -w 700 -h 300 -t "${MYHOST} last month's CPU usage - ${DATE}" \
                --end now --start end-$LASTMONTH -c ARROW\#000000  \
                DEF:user=${RRDFILE}:cpuuser:AVERAGE \
		DEF:nice=${RRDFILE}:cpunice:AVERAGE \
		DEF:sys=${RRDFILE}:cpusystem:AVERAGE \
		COMMENT:"	" \
		AREA:user\#FF0000:"CPU user" \
		STACK:nice\#000099:"CPU nice" \
		STACK:sys\#FFFF00:"CPU system" \
		CDEF:cpu=user,nice,sys,+,+ \
		COMMENT:"	\j" \
		GPRINT:cpu:MIN:"CPU usage minimum\: %lf%%" \
		GPRINT:cpu:MAX:"CPU usage maximum\: %lf%%" \
		GPRINT:cpu:AVERAGE:"CPU usage average\: %lf%%"
		;;
	(graph-yearly)
	    rrdtool graph ${GRAPHNAME//.png/-load-year.png} \
		-Y -u 1.1 -l 0 -L 2 -v "CPU load" -w 700 -h 300 -t "${MYHOST} last year's CPU load - ${DATE}" \
                --end now --start end-$LASTYEAR -c ARROW\#000000  \
                DEF:load1=${RRDFILE}:load1:AVERAGE \
		DEF:load5=${RRDFILE}:load5:AVERAGE \
		DEF:load15=${RRDFILE}:load15:AVERAGE \
		COMMENT:"	" \
		LINE1:load1\#44FF44:"Load average 1 min" \
		LINE2:load5\#000ccc:"Load average 5 min" \
		LINE3:load15\#000000:"Load average 15 min" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:load1:MIN:"Load  1 min minimum\: %lf" \
		GPRINT:load1:MAX:"Load  1 min maximum\: %lf" \
		GPRINT:load1:AVERAGE:"Load  1 min average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:load5:MIN:"Load  5 min minimum\: %lf" \
		GPRINT:load5:MAX:"Load  5 min maximum\: %lf" \
		GPRINT:load5:AVERAGE:"Load  5 min average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:load15:MIN:"Load 15 min minimum\: %lf" \
		GPRINT:load15:MAX:"Load 15 min maximum\: %lf" \
		GPRINT:load15:AVERAGE:"Load 15 min average\: %lf" \
		COMMENT:"	\j"
	    #		
	    rrdtool graph ${GRAPHNAME//.png/-cpu-year.png} \
		-Y -r -u 100 -l 0 -L 2 -v "CPU usage in %" -w 700 -h 300 -t "${MYHOST} last year's CPU usage - ${DATE}" \
                --end now --start end-$LASTYEAR -c ARROW\#000000  \
                DEF:user=${RRDFILE}:cpuuser:AVERAGE \
		DEF:nice=${RRDFILE}:cpunice:AVERAGE \
		DEF:sys=${RRDFILE}:cpusystem:AVERAGE \
		COMMENT:"	" \
		AREA:user\#FF0000:"CPU user" \
		STACK:nice\#000099:"CPU nice" \
		STACK:sys\#FFFF00:"CPU system" \
		CDEF:cpu=user,nice,sys,+,+ \
		COMMENT:"	\j" \
		GPRINT:cpu:MIN:"CPU usage minimum\: %lf%%" \
		GPRINT:cpu:MAX:"CPU usage maximum\: %lf%%" \
		GPRINT:cpu:AVERAGE:"CPU usage average\: %lf%%"
		;;
	(*)
		echo "Invalid option for ${PROGNAME}"
		echo "${PROG} (create|update|graph|debug)"
		exit 1
		;;
esac
