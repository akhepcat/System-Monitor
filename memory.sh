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

DONTRRD=0	#override for now

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
	        --use-nan-for-all-missing-data \
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
		echo "RRDLIB=${RRDLIB}"
		echo "WEBROOT=${WEBROOT}"
		echo "RRDFILE=${RRDFILE}"
		echo "GRAPHBASE=${GRAPHBASE}"
		echo N=$(
			grep -E '^(Mem|Buff|Cache)' /proc/meminfo | \
			    gawk 'match($1,/^MemTotal:$/) { print $(NF-1)*1024 }; match($1,/^Buffers:$/) { print $(NF-1)*1024 }; match($1,/^Cached:$/) { print $(NF-1)*1024 };' | tr '\n' ':')$(
		        grep 'Swap[TF]' /proc/meminfo | \
                           sed  'N; {s/SwapTotal://; s/kB.*SwapFree://; s/kB//;}'| \
                           gawk '{ print ($1 * 1024) ":" (($1 - $2) * 1024) ":" ($2 * 1024) }')
		;;

        (force-create|create)
                if [ "${CMD}" == "force-create" -o ! -r ${RRDFILE} ];
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
		rrdtool update ${RRDFILE} \
		N:$(
			grep -E '^(Mem|Buff|Cache)' /proc/meminfo | \
			    gawk 'match($1,/^MemTotal:$/) { print $(NF-1)*1024 }; match($1,/^Buffers:$/) { print $(NF-1)*1024 }; match($1,/^Cached:$/) { print $(NF-1)*1024 };' | tr '\n' ':')$(
		        grep Swap[TF] /proc/meminfo | \
			    sed  'N; {s/SwapTotal://; s/kB.*SwapFree://; s/kB//;}'| \
			    gawk '{ print ($1 * 1024) ":" (($1 - $2) * 1024) ":" ($2 * 1024) }')
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
	(*)
		echo "Invalid option for ${PROGNAME}"
		echo "${PROG} (create|update|graph|graph-weekly|debug)"
		exit 1
		;;
esac
