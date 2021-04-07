#!/bin/bash
#
#  Just hardlink this file to the name of your drives, and it'll auto-set
#

[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

#####################
PUSER="${USER}"
PROG="${0##*/}"
MYHOST="$(uname -n)"
MYHOST=${SERVERNAME:-$MYHOST}
PROGNAME=${PROG%%.*}
CMD="$1"
LDRIVE="${PROG%%.*}"
DRIVE=${LDRIVE}	#we might overload this later...

DATE=$(date)


if [ -n "${LDRIVE##[hms]d*}" -a -n "${LDRIVE##nvme*}" -a -n "${LDRIVE##mmcblk*}" ]
then
   # if it's standard drive, fall through, otherwise...
	if [ "${LDRIVE}" == "rootfs" ]
	then
		#faked logical drive, we need to find it
		PDRIVE=$(grep -w / /proc/mounts | grep -v rootfs | awk '{print $1}')
		# /dev/sdb3
		LDRIVE=${PDRIVE//\/dev\//}
	elif [ -e "/dev/mapper/${LDRIVE}" ]
	then
		PDRIVE=$(readlink -f "/dev/mapper/${LDRIVE}" )
		LDRIVE=${PDRIVE//\/dev\//}
	else
		# we could add support for UUID's or other labels, but for now...
		echo "unknown drive identifier"
		exit 1
	fi
fi
if [ -z "$(grep -E ${LDRIVE}\[\ \\t\] /proc/diskstats)" ];
then
	echo "invalid drive"
	exit 1
fi


RRDFILE="${RRDLIB:-.}/${MYHOST}-${DRIVE}.rrd"
GRAPHNAME="${WEBROOT:-.}/${MYHOST}-${DRIVE}.png"
MOUNT="$(mount | grep -w ${LDRIVE} | awk '{print $3}')"
[[ -z "${MOUNT}" ]] && MOUNT="$(mount | grep -w ${DRIVE} | awk '{print $3}')"

case ${CMD} in
	(debug)
		if [ "${DONTRRD:-0}" != "1" ]
		then
			echo "RRDLIB=${RRDLIB}"
			echo "WEBROOT=${WEBROOT}"
			echo "RRDFILE=${RRDFILE}"
			echo "GRAPHNAME=${GRAPHNAME}"
			echo "MOUNT=${MOUNT}"
		fi

		echo N=$(grep -E ${LDRIVE}\[\ \\t\] /proc/diskstats | gawk '{ print $6":"$10 ; }')

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
	      ;;
	(update)
		if [ "${DONTRRD:-0}" = "1" -a -z "${INFLUXURL}" ]
		then
			echo "${PROG}:FATAL: No datastore defined"
			exit 1
		fi

		DATA=$(grep -E ${LDRIVE}\[\ \\t\] /proc/diskstats | gawk '{ print $6":"$10 ; }')

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
			status=$(curl -silent -i "${INFLUXURL}" --data-binary "disk_xfer_rate,host=${MYHOST},drive=${DRIVE},mount=${MOUNT} read=${DATA%:*}
			disk_xfer_rate,host=${MYHOST},drive=${DRIVE},mount=${MOUNT} write=${DATA#*:}")

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
	    rrdtool graph ${GRAPHNAME} \
		-v "Bits per second" -w 700 -h 300 -t "${MYHOST} last 24 hours throughput on ${MOUNT} - ${DATE}" \
		-c ARROW\#000000 -x MINUTE:30:MINUTE:30:HOUR:1:0:%H \
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
		;;

	(graph-weekly)
	    rrdtool graph ${GRAPHNAME//.png/-week.png} \
		-v "Bits per second" -w 700 -h 300 -t "${MYHOST} last 7 days throughput on ${MOUNT} - ${DATE}" \
                --end now --start end-$LASTWEEK -c ARROW\#000000  \
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
		;;
	(graph-monthly)
	    rrdtool graph ${GRAPHNAME//.png/-month.png} \
		-v "Bits per second" -w 700 -h 300 -t "${MYHOST} last month's throughput on ${MOUNT} - ${DATE}" \
                --end now --start end-$LASTMONTH -c ARROW\#000000  \
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
		;;
	(graph-yearly)
	    rrdtool graph ${GRAPHNAME//.png/-year.png} \
		-v "Bits per second" -w 700 -h 300 -t "${MYHOST} last year's throughput on ${MOUNT} - ${DATE}" \
                --end now --start end-$LASTYEAR -c ARROW\#000000  \
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
		;;
	(*)
		echo "Invalid option for drive ${DRIVE}"
		echo "${PROG} (create|update|graph|debug)"
		exit 1
		;;
esac
exit 0
