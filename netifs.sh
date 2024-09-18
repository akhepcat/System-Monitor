#!/bin/bash
#
#  This will poll all local interfaces, and return stats for each active one
#

[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

#####################
PUSER="${USER}"
PROG="${0##*/}"
MYHOST="$(uname -n)"
MYHOST=${SERVERNAME:-$MYHOST}
DATE=$(date)
CMD="${1}"
if [ -z "$(command -v curl)" ]
then
	echo "Error: prerequisite not found.  Please install 'curl'"
	exit 1
fi

if [ ${NOLOOPBACK:-0} -eq 0 ]
then
	IFACES=$(ip link show | grep -vE '(docker|veth[a-f0-9]+@|br-[a-f0-9]|DOWN)' | grep -w UP | cut -f2 -d:)
else
	IFACES=$(ip link show | grep -vE '(lo|docker|veth[a-f0-9]+@|br-[a-f0-9]|DOWN)' | grep -w UP | cut -f2 -d:)
fi

do_debug() {
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

	if [ "${DONTRRD:-0}" != "1" ]
	then
		echo "RRDLIB=${RRDLIB}"
		echo "WEBROOT=${WEBROOT}"
		for IFACE in ${IFACES}
		do
			echo -n "${IFACE}: "

			RRDFILE="${RRDLIB:-.}/${MYHOST}-${IFACE}.rrd"
			GRAPHNAME="${WEBROOT:-.}/${MYHOST}-${IFACE}.png"

			echo "RRDFILE=${RRDFILE}"
			echo "GRAPHNAME=${GRAPHNAME}"

			DATA=$(gawk -v iface="${IFACE}" '{ if ($0 ~ iface) { print $2 ":" $10}; }' /proc/net/dev)

			echo N:${DATA}
		done
	elif [ -n "${INFLUXURL}" ]
	then
		echo "Would send to influxdb:"
		for IFACE in ${IFACES}
		do
			DATA=$(gawk -v iface="${IFACE}" '{ if ($0 ~ iface) { print $2 ":" $10}; }' /proc/net/dev)
			echo "net_xfer_rate,host=${MYHOST},interface=${IFACE} receive=${DATA%:*}"
			echo "net_xfer_rate,host=${MYHOST},interface=${IFACE} transmit=${DATA#*:}"
		done
	fi
}

createrrd() {
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

		for IFACE in ${IFACES}
		do
			RRDFILE="${RRDLIB:-.}/${MYHOST}-${IFACE}.rrd"

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
		done
	fi
}

updatedb() {
	if [ "${DONTRRD:-0}" = "1" -a -z "${INFLUXURL}" ]
	then
		echo "${PROG}:FATAL: No datastore defined"
		exit 1
	fi

	for IFACE in ${IFACES}
	do
		# remove ifconfig requirement with awk!
		DATA=$(gawk -v iface="${IFACE}" '{ if ($0 ~ iface) { print $2 ":" $10}; }' /proc/net/dev)

		if [ -n "${INFLUXURL}" ]
		then
			status=$(curl -silent -I "${INFLUXURL//write*/}ping"|grep -i X-Influxdb-Version)
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
			RRDFILE="${RRDLIB:-.}/${MYHOST}-${IFACE}.rrd"

			test -w "${RRDFILE}" && rrdtool update ${RRDFILE} \
				N:${DATA}
		fi
	done
}

dograph() {
	cycle=$1

	if [ "${DONTRRD:-0}" != "1" ]
	then
	    for IFACE in ${IFACES}
	    do
		RRDFILE="${RRDLIB:-.}/${MYHOST}-${IFACE}.rrd"
		GRAPHNAME="${WEBROOT:-.}/${MYHOST}-${IFACE}.png"

		if [ "${cycle}" = "daily" ]
		then
			gn=${GRAPHNAME}
			title="${MYHOST} last 24 hours network throughput - ${DATE}"
			startstop="-x MINUTE:30:MINUTE:30:HOUR:1:0:%H "
		elif [ "${cycle}" = "weekly" ]
		then
			gn=${GRAPHNAME//.png/-week.png}
			title="${MYHOST} last 7 days network throughput - ${DATE}"
			startstop="--end now --start end-$LASTWEEK"
		elif [ "${cycle}" = "monthly" ]
		then
			gn=${GRAPHNAME//.png/-month.png}
			title="${MYHOST} last month's network throughput - ${DATE}"
			startstop="--end now --start end-$LASTMONTH"
		elif [ "${cycle}" = "yearly" ]
		then
			gn=${GRAPHNAME//.png/-year.png}
			title="${MYHOST} last year's network throughput - ${DATE}"
			startstop="--end now --start end-$LASTYEAR"
		else
			echo "unknown graph period"
			exit 1
		fi

		rrdtool graph ${gn} \
			-v "Bits per second" -w 700 -h 300 -t "${title}" \
			${startstop} -c ARROW\#000000 \
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
	    done
	fi	
}

case ${CMD} in
	(debug) do_debug
		;;

        (force-create|create) createrrd
				;;
	(update) updatedb
		;;
	(graph) dograph daily
		;;
	(graph-weekly) dograph weekly
		;;
	(graph-monthly) dograph monthly
		;;
	(graph-yearly)
		;;
	(*)
		echo "Invalid option: ${CMD}"
		echo "${PROG} (create|update|graph|graph-weekly|debug)"
		exit 1
		;;
esac
