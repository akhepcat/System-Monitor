#!/bin/bash
#
#  Just hardlink this file to the name of your interface, and it'll auto-set
#

[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

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

if [ -z "$(command -v curl)" ]
then
	echo "Error: prerequisite not found.  Please install 'curl'"
	exit 1
fi

RRDFILE="${RRDLIB:-.}/${MYHOST}-${IFACE}.rrd"
GRAPHNAME="${WEBROOT:-.}/${MYHOST}-${IFACE}.png"

case ${CMD} in
	(debug)
		if [ "${DONTRRD:-0}" != "1" ]
		then
			echo "RRDLIB=${RRDLIB}"
			echo "WEBROOT=${WEBROOT}"
			echo "RRDFILE=${RRDFILE}"
			echo "GRAPHNAME=${GRAPHNAME}"
		fi

		DATA=$(awk "{ if (/${IFACE}/) { print \$2 \":\" \$10};}" /proc/net/dev)

		echo N:${DATA}

		if [ "${DONTRRD:-0}" != "1" ]
		then
			echo "Datastore RRD is enabled"
		else
			echo "Datastore RRD is disabled"
		fi
		if [ -n "${INFLUXURL}" ]
		then
			echo "Datastore InfluxDB is enabled"
		fi
		if [ "${DONTRRD:-0}" = "1" -a -z "${INFLUXURL}" ]
		then
			echo "FATAL: No datastore is defined"
		fi
		;;

        (force-create|create)
                if [ "${DONTRRD:-0}" != "1" -a \( "${CMD}" == "force-create" -o ! -r ${RRDFILE} \) ];
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
		if [ "${DONTRRD:-0}" = "1" -a -z "${INFLUXURL}" ]
		then
			echo "${PROG}:FATAL: No datastore defined"
			exit 1
		fi

		# remove ifconfig requirement with awk!
		DATA=$(awk "{ if (/${IFACE}/) { print \$2 \":\" \$10};}" /proc/net/dev)

		if [ -n "${INFLUXURL}" ]
		then
			status=$(curl -silent -I "${INFLUXURL//write*/}/ping"|grep -i X-Influxdb-Version)
			if [ -z "${status}" ]
			then
				echo "${PROG}:FATAL: Can't connect to InfluxDB"
				exit 1
			fi
			# we could ping the url so try writing
			# we assume the URL already looks like http(s?)://host.name/write?db=foo&u=bar&p=baz
			# yes, the newline is required for each point written
			# we do not include the timestamp and let influx handle it as received.
			status=$(curl -silent -i "${INFLUXURL}" --data-binary "net_xfer_rate,host=${MYHOST},interface=${IFACE} receive=${DATA%:*}
			net_xfer_rate,host=${MYHOST},interface=${IFACE} transmit=${DATA#*:}")

			if [ -n "${status}" -a -n "${status##*204 No Content*}" ]
			then
				echo "${PROG}:FATAL: Can't write to InfluxDB"
				exit 1
			fi
		fi
		if [ "${DONTRRD:-0}" != "1" ]
		then
			rrdtool update ${RRDFILE} \
				N:${DATA}
		fi

		;;
	(graph)
		if [ "${DONTRRD:-0}" != "1" ]
		then
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
		fi
		;;
	(graph-weekly)
		if [ "${DONTRRD:-0}" != "1" ]
		then
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
		fi
		;;
	(graph-monthly)
		if [ "${DONTRRD:-0}" != "1" ]
		then
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
		fi
		;;
	(graph-yearly)
		if [ "${DONTRRD:-0}" != "1" ]
		then
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
		fi
		;;
	(*)
		echo "Invalid option for IFACE ${IFACE}"
		echo "${PROG} (create|update|graph|graph-weekly|debug)"
		exit 1
		;;
esac
