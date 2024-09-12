#!/bin/bash
#
#  This will poll all mounted partitions, and return stats for each physical one
#

[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

#####################
PUSER="${USER}"
PROG="${0##*/}"
MYHOST="$(uname -n)"
MYHOST=${SERVERNAME:-$MYHOST}
PROGNAME=${PROG%%.*}
CMD="$1"

DATE=$(date)

## global vars, shhhhh
DATA=0
SPACE=0
MOUNT=""

if [ -z "$(command -v lsblk)" -a -z "${DISKS}" ]
then
	# this looks clean but may not catch every variation, and is only as portable as /proc/diskstats is...
	DISKS=$(awk '{print $3}' /proc/diskstats | grep -E '[0-9]p[0-9]$|^[hs]d.[0-9]+$'| sort -u)
else
	# this should work well on modern linuxes, but it's not as portable
	DISKS=$(lsblk -io KNAME,TYPE --exclude 7 | grep -i part | awk '{print $1}' | sort -u)
fi

poll() {
	local LDRIVE=${1}
	local DFDRIVE

	MOUNT="$(mount | grep -w ${LDRIVE} | awk '{print $3}' | head -1)"
	[[ -z "${MOUNT}" ]] && MOUNT="$(mount | grep -w ${DRIVE} | grep -vw snap | awk '{print $3}' | head -1)"
	DFDRIVE=$(df -k | grep -wE "[[:space:]]${MOUNT}" | awk '{print $1}')

	DATA=$(gawk -v drive="${LDRIVE}" '{ if ($0 ~ drive"[ \t]") { print $6":"$10 }; }' /proc/diskstats )
	SPACE=$(df -k | gawk -v drive="${DFDRIVE}" '{if ($0 ~ drive) {printf $2 ":" $3} }')
}

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
		for DRIVE in ${DISKS}
		do
			echo -n "${DRIVE}: "

			RRDFILE="${RRDLIB:-.}/${MYHOST}-${DRIVE}.rrd"
			GRAPHNAME="${WEBROOT:-.}/${MYHOST}-${DRIVE}.png"

			echo "RRDFILE=${RRDFILE}"
			echo "GRAPHNAME=${GRAPHNAME}"

			poll ${DRIVE}

			if [ -n "${MOUNT}" ]
			then
				echo throughput=${DATA}
				echo utilization=${SPACE}
			fi

		done
	elif [ -n "${INFLUXURL}" ]
	then
		echo "Would send to influxdb:"
		for DRIVE in ${DISKS}
		do
			poll ${DRIVE}
			if [ -n "${MOUNT}" ]
			then
				echo "disk_xfer_rate,host=${MYHOST},drive=${DRIVE},mount=${MOUNT} read=${DATA%:*}"
				echo "disk_xfer_rate,host=${MYHOST},drive=${DRIVE},mount=${MOUNT} write=${DATA#*:}"
				echo "disk_usage,host=${MYHOST},drive=${DRIVE},mount=${MOUNT} size=${SPACE%:*}"
				echo "disk_usage,host=${MYHOST},drive=${DRIVE},mount=${MOUNT} free=${SPACE#*:}"
			fi
		done
	fi
}

updatedb() {
		if [ "${DONTRRD:-0}" = "1" -a -z "${INFLUXURL}" ]
		then
			echo "${PROG}:FATAL: No datastore defined"
			exit 1
		fi

		if [ -n "${INFLUXURL}" ]
		then
			status=$(curl -silent -I "${INFLUXURL//write*/}ping"|grep -i X-Influxdb-Version)
			if [ -z "${status}" ]
			then
				echo "${PROG}:FATAL: Can't connect to InfluxDB"
				exit 1
			fi

			for DRIVE in ${DISKS}
			do
				poll ${DRIVE}
				if [ -n "${MOUNT}" ]
				then

					# we could ping the url so try writing
					# we assume the URL already looks like http(s?)://host.name/write?db=foo&u=bar&p=baz
					# yes, the newline is required for each point written
					# we do not include the timestamp and let influx handle it as received.
					status=$(curl -silent -i "${INFLUXURL}" --data-binary "disk_xfer_rate,host=${MYHOST},drive=${DRIVE},mount=${MOUNT} read=${DATA%:*}
					disk_xfer_rate,host=${MYHOST},drive=${DRIVE},mount=${MOUNT} write=${DATA#*:}
					disk_usage,host=${MYHOST},drive=${DRIVE},mount=${MOUNT} size=${SPACE%:*}
					disk_usage,host=${MYHOST},drive=${DRIVE},mount=${MOUNT} free=${SPACE#*:}")

					if [ -n "${status}" -a -n "${status##*204 No Content*}" ]
					then
						echo "${PROG}:FATAL: Can't write to InfluxDB"
						exit 1
					fi
				fi
			done
		fi
		if [ "${DONTRRD:-0}" != "1" ]
		then

			# We don't put freespace into the RRD right now.... 
			for DRIVE in ${DISKS}
			do
				poll ${DRIVE}
				if [ -n "${MOUNT}" ]
				then
					rrdtool update ${RRDFILE} \
						N:${DATA}
				fi
			done
		fi

}

createdb() {
	if [ "${DONTDRRD:-0}" != "1" ];
	then
		for DRIVE in ${DISKS}
		do
			MOUNT=$(grep -w "${DRIVE}" /proc/mounts)
			RRDFILE="${RRDLIB:-.}/${MYHOST}-${DRIVE}.rrd"

			if [ -n "${MOUNT}" -a \( "${CMD}" == "force-create" -o ! -r "${RRDFILE}" \) ]
			then
	
				rrdtool create ${RRDFILE} -s 60 \
					DS:sectorread:COUNTER:180:U:U \
					DS:sectorwrite:COUNTER:180:U:U \
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
		done
	fi
}

dograph() {
	cycle=$1

	if [ ${DONTRRD:-0} -ne 1 ]
	then
	    for DRIVE in ${DISKS}
	    do
		RRDFILE="${RRDLIB:-.}/${MYHOST}-${DRIVE}.rrd"
		GRAPHNAME="${WEBROOT:-.}/${MYHOST}-${DRIVE}.png"
		MOUNT="$(grep -w ${DRIVE} /proc/mounts | awk '{print $2}' | head -1)"

		if [ "${cycle}" = "daily" ]
		then
			gn=${GRAPHNAME}
			title="${MYHOST} last 24 hours throughput on ${MOUNT} - ${DATE}"
			startstop="-x MINUTE:30:MINUTE:30:HOUR:1:0:%H "
		elif [ "${cycle}" = "weekly" ]
		then
			gn=${GRAPHNAME//.png/-week.png}
			title="${MYHOST} last 7 days throughput on ${MOUNT} - ${DATE}"
			startstop="--end now --start end-$LASTWEEK"
		elif [ "${cycle}" = "monthly" ]
		then
			gn=${GRAPHNAME//.png/-month.png}
			title="${MYHOST} last month's throughput on ${MOUNT} - ${DATE}"
			startstop="--end now --start end-$LASTMONTH"
		elif [ "${cycle}" = "yearly" ]
		then
			gn=${GRAPHNAME//.png/-year.png}
			title="${MYHOST} last year's throughput on ${MOUNT} - ${DATE}"
			startstop="--end now --start end-$LASTYEAR"
		else
			echo "unknown graph period"
			exit 1
		fi

		rrdtool graph ${gn} \
			-v "Bits per second" -w 700 -h 300 -t "${title}" \
			${startstop} -c ARROW\#000000 \
			DEF:sread=${RRDFILE}:sectorread:AVERAGE \
			DEF:swrite=${RRDFILE}:sectorwrite:AVERAGE \
			CDEF:readbits=sread,4096,* \
			CDEF:writebits=swrite,4096,* \
			CDEF:invwritebits=0,writebits,- \
			COMMENT:"	" \
			AREA:readbits\#00FF00:"Read" \
			AREA:invwritebits\#0000FF:"Write" \
			HRULE:0#000000 \
			COMMENT:"	\j" \
			COMMENT:"	" \
			GPRINT:readbits:MAX:"Read  maximum\: %.0lf%s bits/sec" \
			GPRINT:writebits:MAX:"Write maximum\: %.0lf%s bits/sec" \
			COMMENT:"	\j" 
	    done
	fi

}

case ${CMD} in
	(debug) do_debug
		;;
        (force-create|create) createdb
			      ;;
	(update) updatedb
		;;
	(graph) dograph daily
		;;
	(graph-weekly) dograph weekly
		;;
	(graph-monthly) dograph monthly
		;;
	(graph-yearly) dograph yearly
		;;
	(*)
		echo "Invalid option for disks: ${CMD}"
		echo "${PROG} (create|update|graph|debug)"
		exit 1
		;;
esac
exit 0
