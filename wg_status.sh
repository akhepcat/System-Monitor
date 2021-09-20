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

RRDFILE="${RRDLIB:-.}/${MYHOST}-wireguard.rrd"
GRAPHNAME="${WEBROOT:-.}/${MYHOST}-wireguard.png"

# Choose your colors here
ONLC=44FF44
AWAC=000ccc
OFFC=ccc000

MAXU=25

poll() {
	status=$(${SCRIPTHOME}/wgstats.pl)
	online=${status%%:*}
	offline=${status##*:}
	away=${status%:*}; away=${away##*:}

	MAXU=$(( (away + online + offline) * 100 / 75 ))
}

do_graph() {
    if [ "${DONTRRD:-0}" != "1" ]
    then
	#defaults, overridden where needed
	SP='\t\t'	# nominal spacing
	XAXIS=""	# only the daily graph gets custom x-axis markers

	case $1 in
		day)
			TITLE="${MYHOST} last 24 hours wireguard stats - ${DATE}"
			START=""
			XAXIS="MINUTE:30:MINUTE:30:HOUR:1:0:%H"
		;;
		week)
			GRAPHNAME="${GRAPHNAME//.png/-week.png}"
			TITLE="${MYHOST} last 24 hours wireguard stats - ${DATE}"
			START="end-$LASTWEEK"
		;;
		month)
	    		GRAPHNAME="${GRAPHNAME//.png/-month.png}"
			TITLE="${MYHOST} last 24 hours wireguard stats - ${DATE}"
	    		START="end-$LASTMONTH"
	    	;;
		year)
	    		GRAPHNAME="${GRAPHNAME//.png/-year.png}"
			TITLE="${MYHOST} last 24 hours wireguard stats - ${DATE}"
	    		START="end-$LASTYEAR"
	    	;;
	    	*) 	echo "broken graph call"
	    		exit 1
	    	;;
	esac

#	        --right-axis-label "user count" \
#	        --right-axis 0.02:0 --right-axis-format %1.0lf \
#		--upper-limit 1.1 
	poll	# to get an updated MAXU

	rrdtool graph ${GRAPHNAME} \
	        -v "user count" -w 700 -h 300  -t "${TITLE}" \
		--lower-limit 0 --alt-y-grid --units-length 2 \
		--alt-autoscale-min --upper-limit $MAXU \
		-c ARROW\#000000  --end now \
		${START:+--start $START}  ${XAXIS:+-x $XAXIS} \
		DEF:online=${RRDFILE}:online:AVERAGE \
		DEF:away=${RRDFILE}:away:AVERAGE \
		DEF:offline=${RRDFILE}:offline:AVERAGE \
		COMMENT:"${SP}" \
		LINE2:online\#${ONLC}:"online users\t    " \
		LINE2:away\#${AWAC}:"away users\t    " \
		LINE1:offline\#${OFFC}:" offline users\t    " \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:online:MIN:" min\: %3.0lf\t\t    " \
		GPRINT:away:MIN:" min\: %3.0lf\t\t    " \
		GPRINT:offline:MIN:" min\: %3.0lf\t\t    " \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:online:MAX:" max\: %3.0lf\t\t    " \
		GPRINT:away:MAX:" max\: %3.0lf\t\t    " \
		GPRINT:offline:MAX:" max\: %3.0lf\t\t    " \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:online:AVERAGE:" avg\: %3.0lf\t\t    " \
		GPRINT:away:AVERAGE:" avg\: %3.0lf\t\t    " \
		GPRINT:offline:AVERAGE:" avg\: %3.0lf\t\t    " \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:online:LAST:"last\: %3.0lf\t\t    " \
		GPRINT:away:LAST:"last\: %3.0lf\t\t    " \
		GPRINT:offline:LAST:"last\: %3.0lf\t    " \
		COMMENT:"\l"
    #DONTRRD
    fi
}
case ${CMD} in
	(debug)
		if [ "${DONTRRD:-0}" != "1" ]
		then
			echo "RRDLIB=${RRDLIB}"
			echo "WEBROOT=${WEBROOT}"
			echo "RRDFILE=${RRDFILE}"
			echo "GRAPHNAME=${GRAPHNAME}"
		fi

		poll
		echo "N:$online:$away:$offline"
		
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
		DS:online:GAUGE:180:0:U \
		DS:away:GAUGE:180:0:U \
		DS:offline:GAUGE:180:0:U \
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
			status=$(curl -silent -i "${INFLUXURL}" --data-binary "wireguard,host=${MYHOST} onlinem=${online}
				wireguard,host=${MYHOST} awaym=${away}
				wireguard,host=${MYHOST} offlinem=${offline}")

			if [ -n "${status}" -a -n "${status##*204 No Content*}" ]
			then
				echo "${PROG}:FATAL: Can't write to InfluxDB"
				exit 1
			fi
		fi
		if [ "${DONTRRD:-0}" != "1" ]
		then
			rrdtool update ${RRDFILE} "N:$online:$away:$offline"
		fi
		;;

	graph|graph-day)  do_graph day
		;;
	graph-weekly)   do_graph week
		;;
	graph-monthly)  do_graph month
		;;
	graph-yearly)   do_graph year
			do_index
		;;
	graph-all) for i in day week month year; do
			echo "dbg: graphing ${i}"
			do_graph ${i}
		   done
		;;
	(*)
		echo "Invalid option for ${PROGNAME}"
		echo "${PROG} (create|update|graph|debug)"
		exit 1
		;;
esac
