#!/bin/bash
#

[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

#####################
PUSER="${USER}"
PROG="${0##*/}"
PROGNAME=${PROG%%.*}
CMD="$1"
MYHOST="$(uname -n)"
MYHOST=${SERVERNAME:-$MYHOST}
DATE=$(date)


RRDFILE="${RRDLIB:-.}/${MYHOST}-mem.rrd"
GRAPHBASE="${WEBROOT:-.}/${MYHOST}-mem.png"

poll() {
	DATA=$( gawk '
		match($1,/^MemTotal:$/) { mt=$(NF-1)*1024 }; 
		match($1,/^MemFree:$/) { mf=$(NF-1)*1024 }; 
		match($1,/^MemAvailable:$/) { ma=$(NF-1)*1024 }; 
		match($1,/^SwapTotal:$/) { st=$(NF-1)*1024 };
		match($1,/^SwapFree:$/) { sf=$(NF-1)*1024  };

		END {
		 	 if (ma > mf) { fm=ma; } else { fm=mf };
			 print mt ":" (mt - fm) ":" fm ":" st ":" (st - sf) ":" sf
		};' /proc/meminfo )

	totalmem=${DATA%%:*}; DATA=${DATA//$totalmem:}
	usedmem=${DATA%%:*};  DATA=${DATA//$usedmem:}
	freemem=${DATA%%:*};  DATA=${DATA//$freemem:}

	totalswap=${DATA%%:*};  DATA=${DATA//$totalswap:}
	usedswap=${DATA%%:*};  DATA=${DATA//$usedswap:}
	freeswap=${DATA%%:*}
}

do_graph() {
	if [ "${DONTRRD:-0}" = "1" ]
	then
		return
	fi
	#defaults, overridden where needed
	SP='\t'	# nominal spacing
	XAXIS=""	# only the daily graph gets custom x-axis markers

	case $1 in
		day)
			GRAPHNAME="${GRAPHBASE}"
			TITLE="${MYHOST} last 24 hours' data for ${DATE}"
			START=""
			# SCALE="--upper-limit 150 --alt-autoscale-min"
			XAXIS="MINUTE:30:MINUTE:30:HOUR:1:0:%H"
		;;
		week)
			GRAPHNAME="${GRAPHBASE//.png/-week.png}"
			TITLE="${MYHOST} last 7 days' data for ${DATE}"
			START="end-$LASTWEEK"
		;;
		month)
	    		GRAPHNAME="${GRAPHBASE//.png/-month.png}"
			TITLE="${MYHOST} last months' data for ${DATE}"
	    		START="end-$LASTMONTH"
	    	;;
		year)
	    		GRAPHNAME="${GRAPHBASE//.png/-year.png}"
			TITLE="${MYHOST} last years' data for ${DATE}"
	    		START="end-$LASTYEAR"
	    	;;
	    	*) 	echo "broken graph call"
	    		exit 1
	    	;;
	esac

	if [ -z "${GRAPHNAME}" ]
	then
		echo "graphname is null"
		echo "graphbase is $GRAPHBASE"
		exit 1
	fi

	rrdtool graph ${GRAPHNAME} \
	        -v "${PROGNAME} Bytes" -w 700 -h 300  -t "${TITLE}" \
		--color ARROW\#000000  \
		${START:+--end now} ${START:+--start $START}  ${XAXIS:+--x-grid $XAXIS} \
		DEF:usedmem=${RRDFILE}:usedmem:AVERAGE \
		DEF:usedswap=${RRDFILE}:usedswap:AVERAGE \
		DEF:totalmem=${RRDFILE}:totalmem:AVERAGE \
		DEF:totalswap=${RRDFILE}:totalswap:AVERAGE \
		COMMENT:"${SP}\j" \
		COMMENT:"${SP}" \
		AREA:totalmem\#0000FF:"Total phys memory" \
		AREA:totalswap\#000000:"Total with swap":STACK \
		AREA:usedmem\#00FF00:"Memory used" \
		LINE:usedswap\#FF0000:"Swap used":STACK \
		COMMENT:"${SP}\j" \
		COMMENT:"${SP}" \
		GPRINT:usedmem:AVERAGE:"Memory used\: %.0lf%s bytes" \
		GPRINT:usedswap:AVERAGE:"Swap used\: %.0lf%s bytes" \
		COMMENT:"${SP}\j" \
		COMMENT:"${SP}" \
		GPRINT:totalmem:MAX:"Total memory available\: %.0lf%s bytes" \
		GPRINT:totalswap:MIN:"Total swap available\: %.0lf%s bytes" \
		COMMENT:"${SP}\j" 
}

case $CMD in
	(debug)
		if [ "${DONTRRD:-0}" != "1" ]
		then
			echo "RRDLIB=${RRDLIB}"
			echo "WEBROOT=${WEBROOT}"
			echo "RRDFILE=${RRDFILE}"
			echo "GRAPHBASE=${GRAPHBASE}"
		fi

		poll

		echo N:${totalmem}:${usedmem}:${freemem}:${totalswap}:${usedswap}:${freeswap}

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
		DS:totalmem:GAUGE:180:U:U \
		DS:usedmem:GAUGE:180:U:U \
		DS:freemem:GAUGE:180:U:U \
		DS:totalswap:GAUGE:180:U:U \
		DS:usedswap:GAUGE:180:U:U \
		DS:freeswap:GAUGE:180:U:U \
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
			# we successfully pinged the url, so try writing
			# we assume the URL already looks like http(s?)://host.name/write?db=foo&u=bar&p=baz
			# yes, the newline is required for each point written
			# we do not include the timestamp and let influx handle it as received.


			status=$(curl -silent -i "${INFLUXURL}" --data-binary """
			${PROG//.sh/},host=${MYHOST} totalmem=${totalmem}
			${PROG//.sh/},host=${MYHOST}  usedmem=${usedmem}
			${PROG//.sh/},host=${MYHOST}  freemem=${freemem}
			${PROG//.sh/},host=${MYHOST} totalswap=${totalswap}
			${PROG//.sh/},host=${MYHOST}  usedswap=${usedswap}
			${PROG//.sh/},host=${MYHOST}  freeswap=${freeswap}
			""")

			if [ -n "${status}" -a -n "${status##*204 No Content*}" ]
			then
				echo "${PROG}:FATAL: Can't write to InfluxDB"
				exit 1
			fi
		fi
		if [ "${DONTRRD:-0}" != "1" ]
		then
			rrdtool update ${RRDFILE} N:${totalmem}:${usedmem}:${freemem}:${totalswap}:${usedswap}:${freeswap}
		fi
		;;
	graph|graph-day)  do_graph day
		;;
	graph-weekly)   do_graph week
		;;
	graph-monthly)  do_graph month
		;;
	graph-yearly)   do_graph year
		;;
	graph-all) for i in day week month year; do
			echo "dbg: graphing ${i}"
			do_graph ${i}
		   done
		;;
	xport)
		if [ "${DONTRRD:-0}" != "1" ]
		then
		    rrdtool xport --end now ${START:+--start $START} \
			DEF:totalmem=${RRDFILE}:totalmem:LAST DEF:usedmem=${RRDFILE}:usedmem:LAST DEF:freemem=${RRDFILE}:freemem:LAST \
			DEF:totalswap=${RRDFILE}:totalswap:LAST DEF:usedswap=${RRDFILE}:usedswap:LAST DEF:freeswap=${RRDFILE}:freeswap:LAST \
			XPORT:totalmem:"total mem bytes" XPORT:usedmem:"used mem bytes" XPORT:freemem:"free mem bytes" \
			XPORT:totalswap:"total swap bytes" XPORT:usedswap:"used swap bytes" XPORT:freeswap:"free swap bytes" 
		fi
		;;

	(*)
		echo "Invalid option for ${PROGNAME}"
		echo "${PROG} (create|update|graph|graph-weekly|debug)"
		exit 1
		;;
esac
