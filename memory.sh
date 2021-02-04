#!/bin/bash
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
PROGNAME=${PROG%%.*}
CMD="$1"
MYHOST="$(uname -n)"
MYHOST=${SERVERNAME:-$MYHOST}


RRDFILE="${RRDLIB:-.}/${MYHOST}-mem.rrd"
GRAPHNAME="${WEBROOT:-.}/${MYHOST}-mem.png"

case $CMD in
	(debug)
		echo "RRDLIB=${RRDLIB}"
		echo "WEBROOT=${WEBROOT}"
		echo "RRDFILE=${RRDFILE}"
		echo "GRAPHNAME=${GRAPHNAME}"
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
	(graph|graph-day)
    rrdtool graph ${GRAPHNAME} \
		-v "Bytes" -w 700 -h 300 -t "${MYHOST} last 24 hours memory usage- ${DATE}" \
		-c ARROW\#000000 -x MINUTE:30:MINUTE:30:HOUR:1:0:%H \
		DEF:usedmem=${RRDFILE}:usedmem:AVERAGE \
		DEF:usedswap=${RRDFILE}:usedswap:AVERAGE \
		DEF:totalmem=${RRDFILE}:totalmem:AVERAGE \
		DEF:totalswap=${RRDFILE}:totalswap:AVERAGE \
		COMMENT:"	" \
		AREA:totalmem\#0000FF:"Total phys memory" \
		AREA:totalswap\#000000:"Total with swap":STACK \
		AREA:usedmem\#00FF00:"Memory used" \
		LINE:usedswap\#FF0000:"Swap used":STACK \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:usedmem:AVERAGE:"Memory used\: %.0lf%s bytes" \
		GPRINT:usedswap:AVERAGE:"Swap used\: %.0lf%s bytes" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:totalmem:MAX:"Total memory available\: %.0lf%s bytes" \
		GPRINT:totalswap:MIN:"Total swap available\: %.0lf%s bytes" \
		COMMENT:"	\j"
		;;
	(graph-weekly)
	    rrdtool graph ${GRAPHNAME//.png/-week.png} \
		-v "Bytes" -w 700 -h 300 -t "${MYHOST} last 7 days memory usage- ${DATE}" \
		--end now --start end-$LASTWEEK -c ARROW\#000000  \
		DEF:usedmem=${RRDFILE}:usedmem:AVERAGE \
		DEF:usedswap=${RRDFILE}:usedswap:AVERAGE \
		DEF:totalmem=${RRDFILE}:totalmem:AVERAGE \
		DEF:totalswap=${RRDFILE}:totalswap:AVERAGE \
		COMMENT:"	" \
		AREA:totalmem\#0000FF:"Total phys memory" \
		AREA:totalswap\#000000:"Total with swap":STACK \
		AREA:usedmem\#00FF00:"Memory used" \
		LINE:usedswap\#FF0000:"Swap used":STACK \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:usedmem:MAX:"Maximum memory used\: %.0lf%s bytes" \
		GPRINT:usedswap:MAX:"Maximum swap used\: %.0lf%s bytes" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:totalmem:MAX:"Total memory available\: %.0lf%s bytes" \
		GPRINT:totalswap:MIN:"Total swap available\: %.0lf%s bytes" \
		COMMENT:"	\j"
		;;
	(graph-monthly)
	    rrdtool graph ${GRAPHNAME//.png/-month.png} \
		-v "Bytes" -w 700 -h 300 -t "${MYHOST} last month's memory usage- ${DATE}" \
		--end now --start end-$LASTMONTH -c ARROW\#000000  \
		DEF:usedmem=${RRDFILE}:usedmem:AVERAGE \
		DEF:usedswap=${RRDFILE}:usedswap:AVERAGE \
		DEF:totalmem=${RRDFILE}:totalmem:AVERAGE \
		DEF:totalswap=${RRDFILE}:totalswap:AVERAGE \
		COMMENT:"	" \
		AREA:totalmem\#0000FF:"Total phys memory" \
		AREA:totalswap\#000000:"Total with swap":STACK \
		AREA:usedmem\#00FF00:"Memory used" \
		LINE:usedswap\#FF0000:"Swap used":STACK \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:usedmem:MAX:"Maximum memory used\: %.0lf%s bytes" \
		GPRINT:usedswap:MAX:"Maximum swap used\: %.0lf%s bytes" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:totalmem:MAX:"Total memory available\: %.0lf%s bytes" \
		GPRINT:totalswap:MIN:"Total swap available\: %.0lf%s bytes" \
		COMMENT:"	\j"
		;;
	(graph-yearly)
	    rrdtool graph ${GRAPHNAME//.png/-year.png} \
		-v "Bytes" -w 700 -h 300 -t "${MYHOST} last year's memory usage- ${DATE}" \
		--end now --start end-$LASTYEAR -c ARROW\#000000  \
		DEF:usedmem=${RRDFILE}:usedmem:AVERAGE \
		DEF:usedswap=${RRDFILE}:usedswap:AVERAGE \
		DEF:totalmem=${RRDFILE}:totalmem:AVERAGE \
		DEF:totalswap=${RRDFILE}:totalswap:AVERAGE \
		COMMENT:"	" \
		AREA:totalmem\#0000FF:"Total phys memory" \
		AREA:totalswap\#000000:"Total with swap":STACK \
		AREA:usedmem\#00FF00:"Memory used" \
		LINE:usedswap\#FF0000:"Swap used":STACK \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:usedmem:MAX:"Maximum memory used\: %.0lf%s bytes" \
		GPRINT:usedswap:MAX:"Maximum swap used\: %.0lf%s bytes" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:totalmem:MAX:"Total memory available\: %.0lf%s bytes" \
		GPRINT:totalswap:MIN:"Total swap available\: %.0lf%s bytes" \
		COMMENT:"	\j"
		;;
	(*)
		echo "Invalid option for ${PROGNAME}"
		echo "${PROG} (create|update|graph|graph-weekly|debug)"
		exit 1
		;;
esac
