#!/bin/bash
#
#  graphs the system load
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

RRDFILE="${RRDLIB:-.}/${MYHOST}-load.rrd"
GRAPHNAME="${WEBROOT:-.}/${MYHOST}.png"

poll() {
	cpu=$(sed "s/\([0-9]\\.[0-9]\\{2\\}\)\ \([0-9]\\.[0-9]\\{2\\}\)\ \([0-9]\\.[0-9]\\{2\\}\).*/\1:\2:\3/" /proc/loadavg)
	cpu1=${cpu%%:*}
	cpu5=${cpu##*:}
	cpu15=${cpu%:*}; cpu15=${cpu15##*:}

	load=$(sed -n 's/^cpu\ \+\([0-9]*\)\ \([0-9]*\)\ \([0-9]*\).*/\1:\2:\3/p' /proc/stat)
	user=${load%%:*}
	sys=${load##*:}
	nice=${load%:*}; nice=${nice##*:}
}

case ${CMD} in
	(debug)
		if [ "${DONTRRD:-0}" != "1" ]
		then
			echo "RRDLIB=${RRDLIB}"
			echo "WEBROOT=${WEBROOT}"
			echo "RRDFILE=${RRDFILE}"
			echo "GRAPHNAME=${GRAPHNAME//.png/-load.png}"
			echo "GRAPHNAME=${GRAPHNAME//.png/-cpu.png}"
		fi

		poll
		echo "N:$cpu1:$cpu5:$cpu15:$user:$nice:$sys"
		
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
		if [ "${DONTRRD:-0}" = "1" -a -z "${INFLUXURL}" ]
		then
			echo "${PROG}:FATAL: No datastore defined"
			exit 1
		fi

		poll

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
			status=$(curl -silent -i "${INFLUXURL}" --data-binary "cpu,host=${MYHOST} cpu1m=${cpu1}
				cpu,host=${MYHOST} cpu5m=${cpu5}
				cpu,host=${MYHOST} cpu15m=${cpu15}
				load,host=${MYHOST} user=${user}
				load,host=${MYHOST} nice=${nice}
				load,host=${MYHOST} system=${sys}")

			if [ -n "${status}" -a -n "${status##*204 No Content*}" ]
			then
				echo "${PROG}:FATAL: Can't write to InfluxDB"
				exit 1
			fi
		fi
		if [ "${DONTRRD:-0}" != "1" ]
		then
			rrdtool update ${RRDFILE} "N:$cpu1:$cpu5:$cpu15:$user:$nice:$sys"
		fi
		;;

	(graph)
	    rrdtool graph ${GRAPHNAME//.png/-load.png} \
		-Y -u 1.1 -l 0 -L 2 -v "CPU load" -w 700 -h 300 -t "${MYHOST} last 24 hours CPU load - ${DATE}" \
		-c ARROW\#000000 -x MINUTE:30:MINUTE:30:HOUR:1:0:%H \
		DEF:load1=${RRDFILE}:load1:AVERAGE \
		DEF:load5=${RRDFILE}:load5:AVERAGE \
		DEF:load15=${RRDFILE}:load15:AVERAGE \
		COMMENT:"\t" \
		LINE1:load1\#44FF44:"Load average 1 min" \
		LINE2:load5\#000ccc:"Load average 5 min" \
		LINE3:load15\#000000:"Load average 15 min" \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:load1:MIN:"  1 min\: %2.2lf" \
		GPRINT:load5:MIN:"  5 min\: %2.2lf" \
		GPRINT:load15:MIN:" 15 min\: %2.2lf" \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:load1:MAX:"  1 max\: %2.2lf" \
		GPRINT:load5:MAX:"  5 max\: %2.2lf" \
		GPRINT:load15:MAX:" 15 max\: %2.2lf" \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:load1:AVERAGE:"  1 avg\: %2.2lf" \
		GPRINT:load5:AVERAGE:"  5 avg\: %2.2lf" \
		GPRINT:load15:AVERAGE:" 15 avg\: %2.2lf" \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:load1:LAST:"current\: %2.2lf" \
		GPRINT:load5:LAST:"current\: %2.2lf" \
		GPRINT:load15:LAST:"current\: %2.2lf" \
		COMMENT:"\t\j"
	    #		
	    rrdtool graph ${GRAPHNAME//.png/-cpu.png} \
		-Y -r -u 100 -l 0 -L 2 -v "CPU usage in %" -w 700 -h 300 -t "${MYHOST} last 24 hours CPU usage - ${DATE}" \
		-c ARROW\#000000 -x MINUTE:30:MINUTE:30:HOUR:1:0:%H \
		DEF:user=${RRDFILE}:cpuuser:AVERAGE \
		DEF:nice=${RRDFILE}:cpunice:AVERAGE \
		DEF:sys=${RRDFILE}:cpusystem:AVERAGE \
		COMMENT:"\t" \
		AREA:user\#FF0000:"CPU user" \
		STACK:nice\#000099:"CPU nice" \
		STACK:sys\#FFFF00:"CPU system" \
		CDEF:cpu=user,nice,sys,+,+ \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:cpu:MIN:"min usage\: %2.02lf%%" \
		GPRINT:cpu:MAX:"max usage\: %2.02lf%%" \
		GPRINT:cpu:AVERAGE:"avg usage\: %2.02lf%%" \
		COMMENT:"\t\j"
		;;
	(graph-weekly)
	    rrdtool graph ${GRAPHNAME//.png/-load-week.png} \
		-Y -u 1.1 -l 0 -L 2 -v "CPU load" -w 700 -h 300 -t "${MYHOST} last 7 days CPU load - ${DATE}" \
                --end now --start end-$LASTWEEK -c ARROW\#000000  \
                DEF:load1=${RRDFILE}:load1:AVERAGE \
		DEF:load5=${RRDFILE}:load5:AVERAGE \
		DEF:load15=${RRDFILE}:load15:AVERAGE \
		COMMENT:"\t" \
		LINE1:load1\#44FF44:"Load average 1 min" \
		LINE2:load5\#000ccc:"Load average 5 min" \
		LINE3:load15\#000000:"Load average 15 min" \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:load1:MIN:"  1 min\: %2.2lf" \
		GPRINT:load5:MIN:"  5 min\: %2.2lf" \
		GPRINT:load15:MIN:" 15 min\: %2.2lf" \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:load1:MAX:"  1 max\: %2.2lf" \
		GPRINT:load5:MAX:"  5 max\: %2.2lf" \
		GPRINT:load15:MAX:" 15 max\: %2.2lf" \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:load1:AVERAGE:"  1 avg\: %2.2lf" \
		GPRINT:load5:AVERAGE:"  5 avg\: %2.2lf" \
		GPRINT:load15:AVERAGE:" 15 avg\: %2.2lf" \
		COMMENT:"\t\j"
	    #		
	    rrdtool graph ${GRAPHNAME//.png/-cpu-week.png} \
		-Y -r -u 100 -l 0 -L 2 -v "CPU usage in %" -w 700 -h 300 -t "${MYHOST} last 7 days CPU usage - ${DATE}" \
                --end now --start end-$LASTWEEK -c ARROW\#000000  \
                DEF:user=${RRDFILE}:cpuuser:AVERAGE \
		DEF:nice=${RRDFILE}:cpunice:AVERAGE \
		DEF:sys=${RRDFILE}:cpusystem:AVERAGE \
		COMMENT:"\t" \
		AREA:user\#FF0000:"CPU user" \
		STACK:nice\#000099:"CPU nice" \
		STACK:sys\#FFFF00:"CPU system" \
		CDEF:cpu=user,nice,sys,+,+ \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:cpu:MIN:"min usage\: %2.02lf%%" \
		GPRINT:cpu:MAX:"max usage\: %2.02lf%%" \
		GPRINT:cpu:AVERAGE:"avg usage\: %2.02lf%%" \
		COMMENT:"\t\j"
		;;
	(graph-monthly)
	    rrdtool graph ${GRAPHNAME//.png/-load-month.png} \
		-Y -u 1.1 -l 0 -L 2 -v "CPU load" -w 700 -h 300 -t "${MYHOST} last month's CPU load - ${DATE}" \
                --end now --start end-$LASTMONTH -c ARROW\#000000  \
                DEF:load1=${RRDFILE}:load1:AVERAGE \
		DEF:load5=${RRDFILE}:load5:AVERAGE \
		DEF:load15=${RRDFILE}:load15:AVERAGE \
		COMMENT:"\t" \
		LINE1:load1\#44FF44:"Load average 1 min" \
		LINE2:load5\#000ccc:"Load average 5 min" \
		LINE3:load15\#000000:"Load average 15 min" \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:load1:MIN:"  1 min\: %2.2lf" \
		GPRINT:load5:MIN:"  5 min\: %2.2lf" \
		GPRINT:load15:MIN:" 15 min\: %2.2lf" \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:load1:MAX:"  1 max\: %2.2lf" \
		GPRINT:load5:MAX:"  5 max\: %2.2lf" \
		GPRINT:load15:MAX:" 15 max\: %2.2lf" \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:load1:AVERAGE:"  1 avg\: %2.2lf" \
		GPRINT:load5:AVERAGE:"  5 avg\: %2.2lf" \
		GPRINT:load15:AVERAGE:" 15 avg\: %2.2lf" \
		COMMENT:"\t\j"
	    #		
	    rrdtool graph ${GRAPHNAME//.png/-cpu-month.png} \
		-Y -r -u 100 -l 0 -L 2 -v "CPU usage in %" -w 700 -h 300 -t "${MYHOST} last month's CPU usage - ${DATE}" \
                --end now --start end-$LASTMONTH -c ARROW\#000000  \
                DEF:user=${RRDFILE}:cpuuser:AVERAGE \
		DEF:nice=${RRDFILE}:cpunice:AVERAGE \
		DEF:sys=${RRDFILE}:cpusystem:AVERAGE \
		COMMENT:"\t" \
		AREA:user\#FF0000:"CPU user" \
		STACK:nice\#000099:"CPU nice" \
		STACK:sys\#FFFF00:"CPU system" \
		CDEF:cpu=user,nice,sys,+,+ \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:cpu:MIN:"min usage\: %2.02lf%%" \
		GPRINT:cpu:MAX:"max usage\: %2.02lf%%" \
		GPRINT:cpu:AVERAGE:"avg usage\: %2.02lf%%" \
		COMMENT:"\t\j"
		;;
	(graph-yearly)
	    rrdtool graph ${GRAPHNAME//.png/-load-year.png} \
		-Y -u 1.1 -l 0 -L 2 -v "CPU load" -w 700 -h 300 -t "${MYHOST} last year's CPU load - ${DATE}" \
                --end now --start end-$LASTYEAR -c ARROW\#000000  \
                DEF:load1=${RRDFILE}:load1:AVERAGE \
		DEF:load5=${RRDFILE}:load5:AVERAGE \
		DEF:load15=${RRDFILE}:load15:AVERAGE \
		COMMENT:"\t" \
		LINE1:load1\#44FF44:"Load average 1 min" \
		LINE2:load5\#000ccc:"Load average 5 min" \
		LINE3:load15\#000000:"Load average 15 min" \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:load1:MIN:"  1 min\: %2.2lf" \
		GPRINT:load5:MIN:"  5 min\: %2.2lf" \
		GPRINT:load15:MIN:" 15 min\: %2.2lf" \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:load1:MAX:"  1 max\: %2.2lf" \
		GPRINT:load5:MAX:"  5 max\: %2.2lf" \
		GPRINT:load15:MAX:" 15 max\: %2.2lf" \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:load1:AVERAGE:"  1 avg\: %2.2lf" \
		GPRINT:load5:AVERAGE:"  5 avg\: %2.2lf" \
		GPRINT:load15:AVERAGE:" 15 avg\: %2.2lf" \
		COMMENT:"\t\j"
	    #		
	    rrdtool graph ${GRAPHNAME//.png/-cpu-year.png} \
		-Y -r -u 100 -l 0 -L 2 -v "CPU usage in %" -w 700 -h 300 -t "${MYHOST} last year's CPU usage - ${DATE}" \
                --end now --start end-$LASTYEAR -c ARROW\#000000  \
                DEF:user=${RRDFILE}:cpuuser:AVERAGE \
		DEF:nice=${RRDFILE}:cpunice:AVERAGE \
		DEF:sys=${RRDFILE}:cpusystem:AVERAGE \
		COMMENT:"\t" \
		AREA:user\#FF0000:"CPU user" \
		STACK:nice\#000099:"CPU nice" \
		STACK:sys\#FFFF00:"CPU system" \
		CDEF:cpu=user,nice,sys,+,+ \
		COMMENT:"\t\j" \
		COMMENT:"\t" \
		GPRINT:cpu:MIN:"min usage\: %2.02lf%%" \
		GPRINT:cpu:MAX:"max usage\: %2.02lf%%" \
		GPRINT:cpu:AVERAGE:"avg usage\: %2.02lf%%" \
		COMMENT:"\t\j"
		;;
	(*)
		echo "Invalid option for ${PROGNAME}"
		echo "${PROG} (create|update|graph|debug)"
		exit 1
		;;
esac
