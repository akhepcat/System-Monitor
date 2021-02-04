#!/bin/bash
#
#  Just hardlink this file to the name of your interface, and it'll auto-set
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
MYHOST=${SERVERNAME:-$MYHOST}
IFACE="${PROG%%.*}"
DATE=$(date)
CMD="$1"

if [ -z "$(grep -E ${IFACE}: /proc/net/dev)" ];
then
	echo "invalid IFACE"
	exit 1
fi

RRDFILE="${RRDLIB:-.}/${MYHOST}-${IFACE}.rrd"
GRAPHNAME="${WEBROOT:-.}/${MYHOST}-${IFACE}.png"

case ${CMD} in
	(debug)
		echo "RRDLIB=${RRDLIB}"
		echo "WEBROOT=${WEBROOT}"
		echo "RRDFILE=${RRDFILE}"
		echo "GRAPHNAME=${GRAPHNAME}"
		echo N:$(/sbin/ifconfig ${IFACE} | gawk 'match($0,/RX bytes:/) { print $(NF-6)":"$(NF-2) }; match($0,/RX.*bytes /) { print $(NF-2) }; match($0,/TX.*bytes /) { print $(NF-2) };' | tr '\n' ':' | sed 's/:$//g; s/bytes://g;')
		;;

        (force-create|create)
                if [ "${CMD}" == "force-create" -o ! -r ${RRDFILE} ];
                then
	# Decoded:
	# -s 60   ==   60 second "step", or one poll per minute for each datasource
	#
	# DS:name:TYPE:Heartbeat:min:max   heartbeat is 3* step, or 180 sec, or 3 minutes
	# Here, the RRA's are broken down into 3.3 groups
	# min/max/avg with a .5 consolidation (i.e., 50% can be "unknown")
	# steps are how many datapoints are consolidated into the row.  (1m, 5m, 30m "avgs")
	# rows is how many datapoint segment rows are available (1440 = 24h, 2016 = 1w, 1488=1M
	# new: 4380 @ 120 = 1Y

		rrdtool create ${RRDFILE} -s 60 \
		DS:rxbytes:COUNTER:180:U:U \
		DS:txbytes:COUNTER:180:U:U \
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
		N:$(/sbin/ifconfig ${IFACE} | gawk 'match($0,/RX bytes:/) { print $(NF-6)":"$(NF-2) }; match($0,/RX.*bytes /) { print $(NF-2) }; match($0,/TX.*bytes /) { print $(NF-2) };' | tr '\n' ':' | sed 's/:$//g; s/bytes://g;')
		;;
	(graph)
    rrdtool graph ${GRAPHNAME} \
		-v "Bits per second" -w 700 -h 300 -t "${MYHOST} last 24 hours network throughput - ${DATE}" \
		-c ARROW\#000000 -x MINUTE:30:MINUTE:30:HOUR:1:0:%H \
		DEF:rxbytes=${RRDFILE}:rxbytes:AVERAGE \
		DEF:txbytes=${RRDFILE}:txbytes:AVERAGE \
		CDEF:rx=8,rxbytes,\* \
		CDEF:tx=8,txbytes,\* \
		CDEF:txinv=0,tx,- \
		COMMENT:"   " \
		AREA:rx\#00FF00:"Receive" \
		AREA:txinv\#0000FF:"Transmit" \
		HRULE:0#000000 \
		COMMENT:"   \j" \
		COMMENT:"   " \
		GPRINT:rx:MAX:"Receive  maximum\: %.0lf%s Bits/sec" \
		GPRINT:tx:MAX:"Transmit maximum\: %.0lf%s Bits/sec" \
		COMMENT:"	\j" \
		COMMENT:"   " \
		GPRINT:rx:AVERAGE:"Receive  average\: %.0lf%s Bits/sec" \
		GPRINT:tx:AVERAGE:"Transmit average\: %.0lf%s Bits/sec" \
		COMMENT:"	\j"
		;;
	(graph-weekly)
	    rrdtool graph ${GRAPHNAME//.png/-week.png} \
		-v "Bits per second" -w 700 -h 300 -t "${MYHOST} last 7 days network throughput - ${DATE}" \
                --end now --start end-$LASTWEEK -c ARROW\#000000  \
		DEF:rxbytes=${RRDFILE}:rxbytes:AVERAGE \
		DEF:txbytes=${RRDFILE}:txbytes:AVERAGE \
		CDEF:rx=8,rxbytes,\* \
		CDEF:tx=8,txbytes,\* \
		CDEF:txinv=0,tx,- \
		COMMENT:"   " \
		AREA:rx\#00FF00:"Receive" \
		AREA:txinv\#0000FF:"Transmit" \
		HRULE:0#000000 \
		COMMENT:"   \j" \
		COMMENT:"   " \
		GPRINT:rx:MAX:"Receive  maximum\: %.0lf%s Bits/sec" \
		GPRINT:tx:MAX:"Transmit maximum\: %.0lf%s Bits/sec" \
		COMMENT:"	\j" \
		COMMENT:"   " \
		GPRINT:rx:AVERAGE:"Receive  average\: %.0lf%s Bits/sec" \
		GPRINT:tx:AVERAGE:"Transmit average\: %.0lf%s Bits/sec" \
		COMMENT:"	\j"
		;;
	(graph-monthly)
	    rrdtool graph ${GRAPHNAME//.png/-month.png} \
		-v "Bits per second" -w 700 -h 300 -t "${MYHOST} last month's network throughput - ${DATE}" \
                --end now --start end-$LASTMONTH -c ARROW\#000000  \
		DEF:rxbytes=${RRDFILE}:rxbytes:AVERAGE \
		DEF:txbytes=${RRDFILE}:txbytes:AVERAGE \
		CDEF:rx=8,rxbytes,\* \
		CDEF:tx=8,txbytes,\* \
		CDEF:txinv=0,tx,- \
		COMMENT:"   " \
		AREA:rx\#00FF00:"Receive" \
		AREA:txinv\#0000FF:"Transmit" \
		HRULE:0#000000 \
		COMMENT:"   \j" \
		COMMENT:"   " \
		GPRINT:rx:MAX:"Receive  maximum\: %.0lf%s Bits/sec" \
		GPRINT:tx:MAX:"Transmit maximum\: %.0lf%s Bits/sec" \
		COMMENT:"	\j" \
		COMMENT:"   " \
		GPRINT:rx:AVERAGE:"Receive  average\: %.0lf%s Bits/sec" \
		GPRINT:tx:AVERAGE:"Transmit average\: %.0lf%s Bits/sec" \
		COMMENT:"	\j"
		;;
	(graph-yearly)
	    rrdtool graph ${GRAPHNAME//.png/-year.png} \
		-v "Bits per second" -w 700 -h 300 -t "${MYHOST} last year's network throughput - ${DATE}" \
                --end now --start end-$LASTYEAR -c ARROW\#000000  \
		DEF:rxbytes=${RRDFILE}:rxbytes:AVERAGE \
		DEF:txbytes=${RRDFILE}:txbytes:AVERAGE \
		CDEF:rx=8,rxbytes,\* \
		CDEF:tx=8,txbytes,\* \
		CDEF:txinv=0,tx,- \
		COMMENT:"   " \
		AREA:rx\#00FF00:"Receive" \
		AREA:txinv\#0000FF:"Transmit" \
		HRULE:0#000000 \
		COMMENT:"   \j" \
		COMMENT:"   " \
		GPRINT:rx:MAX:"Receive  maximum\: %.0lf%s Bits/sec" \
		GPRINT:tx:MAX:"Transmit maximum\: %.0lf%s Bits/sec" \
		COMMENT:"	\j" \
		COMMENT:"   " \
		GPRINT:rx:AVERAGE:"Receive  average\: %.0lf%s Bits/sec" \
		GPRINT:tx:AVERAGE:"Transmit average\: %.0lf%s Bits/sec" \
		COMMENT:"	\j"
		;;
	(*)
		echo "Invalid option for IFACE ${IFACE}"
		echo "${PROG} (create|update|graph|graph-weekly|debug)"
		exit 1
		;;
esac
