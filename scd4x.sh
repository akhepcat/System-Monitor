#!/bin/bash
#
#  currently called in a loop from do-updates;  should we move the loop here?
#

[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

#####################
PUSER="${USER}"
PROG="${0##*/}"
PROGNAME=${PROG%%.*}
MYHOST="$(uname -n)"
MYHOST=${SERVERNAME:-$MYHOST}
DATE=$(date)
PATH=${PATH}:/sbin:/usr/sbin

CMD=$1

RRDFILE="${RRDLIB:-.}/${MYHOST}-${PROGNAME}.rrd"
GRAPHBASE="${WEBROOT:-.}/${MYHOST}-${PROGNAME}.png"
IDX="${WEBROOT:-.}/${MYHOST}-${PROGNAME}.html"

STATS=""

# Choose your colors here
PCOL=44FF44
TCOL=000ccc

poll() {
	# STATS=$( $SCRIPTHOME/scd4x.py | sed 's/^.*:\([0-9.]\+\),\([0-9.]\+\),\([0-9.]\+\)/OK temp=\1 humid=\2 co2ppm=\3/;')
	STATS=$(sed 's/^.*: \([0-9.]\+\),\([0-9.]\+\),\([0-9.]\+\)/OK temp=\1 humid=\2 co2ppm=\3/;' scd4x.log)
	if [ -n "${STATS##*OK*}" ]
	then
		STATS="BAD temp=U humid=U co2ppm=U"
	fi
}

usage() {
	echo "Invalid option for ${PROGNAME}"
	echo "${PROG} (create|update|graph|graph-weekly|debug) <host>"
}

do_index() {
	if [ "${DONTRRD:-0}" = "1" ]
	then
		return
	fi
	WEBGRAPH=${GRAPHBASE##*/} ; WEBGRAPH=${WEBGRAPH%.*}
### HEAD

	cat >${IDX} <<EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr">
	<head>
		<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
		<meta http-equiv="Content-Style-Type" content="text/css" />
		<meta http-equiv="Refresh" content="300" />
		<meta http-equiv="Pragma" content="no-cache" />
		<meta http-equiv="Cache-Control" content="no-cache" />
		<link rel="shortcut icon" href="favicon.ico" />
		<title> Real time Statistics </title>
	</head>
<body>
EOF

### BODY
cat >>${IDX} <<EOF
<body>
<h2>Temperature stats: ${MYHOST}</h2>
<p>
	I provide multiple statistics showing the temperature, humidity, and CO2 from the SCD4x sensor below.<br />
	All statistics are gathered once a minute and the charts are redrawn every 5 minutes.<br />
	Additionally, this page is automatically reloaded every 5 minutes.
	<br />Index page last generated on ${DATE}<br />
</p>

<table>
  <tr><th colspan='2'>Daily</th><th colspan='2'>Weekly</th></tr>

  <tr>
    <td>&nbsp;</td>
    <td><img src="${WEBGRAPH}.png" /></td>
    <td>&nbsp;</td>
    <td><img src="${WEBGRAPH}-week.png" /></td>
  </tr>

  <tr><th colspan='2'>Monthly</th><th colspan='2'>Yearly</th></tr>

  <tr>
    <td>&nbsp;</td>
    <td><img src="${WEBGRAPH}-month.png" /></td>
    <td>&nbsp;</td>
    <td><img src="${WEBGRAPH}-year.png" /></td>
  </tr>
</table>
<p /><hr />
EOF

### TAIL
	cat >>${IDX} <<EOF
<hr />
<p> (c) akhepcat - <a href="https://github.com/akhepcat/System-Monitor">System-Monitor Suite</a> on Github!</p>
</body>
</html>
EOF

}

do_graph() {
	if [ "${DONTRRD:-0}" = "1" ]
	then
		return
	fi
	#defaults, overridden where needed
	SP='\t\t\t'	# nominal spacing
	XAXIS=""	# only the daily graph gets custom x-axis markers

	case $1 in
		day)
			GRAPHNAME="${GRAPHBASE}"
			TITLE="${MYHOST} last 24 hours' data for ${DATE}"
			START=""
			SCALE="--upper-limit 150 --alt-autoscale-min"
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

	# the Lowest CO2 reading is: 400 
	# the Average background CO2 is: 950
	# the Highest CO2 reading is: 2000

	# So to scale the data, we subtract 400 from the current value,
	# but change the range of the right axis to start at 400, which provides
	# a 1600ppm range...

	rrdtool graph ${GRAPHNAME} \
	        -v "${PROGNAME} temperature" -w 700 -h 300  -t "${TITLE}" \
		${SCALE} --alt-y-grid --units-length 2 \
	        --right-axis-label "${PROGNAME} CO2 PPM" \
	        --right-axis 400:2000 --right-axis-format %1.0lf \
		--color ARROW\#000000  ${START:+--end now} ${START:+--start $START}  ${XAXIS:+--x-grid $XAXIS} \
		DEF:temps=${RRDFILE}:temps:LAST \
		DEF:humid=${RRDFILE}:humid:LAST \
		DEF:co2=${RRDFILE}:co2ppm:LAST \
		CDEF:co2r=co2,400,- \
		COMMENT:"${SP}" \
		LINE2:temps\#${TCOL}:"Cur temp F${SP}" \
		LINE2:humid\#${PCOL}:"Cur humid %%${SP}" \
		LINE2:co2r\#${PCOL}:"Cur CO2 ppm${SP}" \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:temps:MIN:" min\: %3.02lf${SP}" \
		GPRINT:humid:MIN:" min\: %3.02lf${SP}" \
		GPRINT:co2r:MIN:" min\: %3.02lf${SP}" \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:temps:MAX:" max\: %3.02lf${SP}" \
		GPRINT:humid:MAX:" max\: %3.02lf${SP}" \
		GPRINT:co2:MAX:" max\: %3.02lf${SP}" \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:temps:AVERAGE:" avg\: %3.02lf${SP}" \
		GPRINT:humid:AVERAGE:" avg\: %3.02lf${SP}" \
		GPRINT:co2:AVERAGE:" avg\: %3.02lf${SP}" \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:temps:LAST:"last\: %3.02lf${SP}" \
		GPRINT:humid:LAST:"last\: %3.02lf${SP}" \
		GPRINT:co2:LAST:" last\: %3.02lf${SP}" \
		COMMENT:"\l"
}

case $CMD in
	debug)
		if [ "${DONTRRD:-0}" != "1" ]
		then
			echo "RRDLIB=${RRDLIB}"
			echo "WEBROOT=${WEBROOT}"
			echo "RRDFILE=${RRDFILE}"
			echo "GRAPHNAME=${GRAPHBASE}"
		fi
		poll
		if [ -z "${STATS##*BAD*}" ];
		then
			echo "no stats for cycle (host down)"
		else
			temps=${STATS##*temp=};  temps=${temps%% *}
			humid=${STATS##*humid=};  humid=${humid%% *}
			CO2=${STATS##*co2ppm=};  CO2=${CO2%% *}

			echo TEMP=${temps}
			echo HUMID=${humid}
			echo CO2=${CO2}
		fi
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

        force-create|create)
                if [ "${DONTRRD:-0}" != "1" -a \( "${CMD}" == "force-create" -o ! -r ${RRDFILE} \) ];
                then
		rrdtool create ${RRDFILE} -s 60 \
		DS:temps:GAUGE:180:U:U \
		DS:humid:GAUGE:180:U:U \
		DS:co2ppm:GAUGE:180:U:U \
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

	update)
		poll
		temps=${STATS##*temp=};  temps=${temps%% *}
		humid=${STATS##*humid=};  humid=${humid%% *}
		CO2=${STATS##*co2ppm=};  CO2=${CO2%% *}

		if [ "${DONTRRD:-0}" = "1" -a -z "${INFLUXURL}" ]
		then
			echo "${PROG}:FATAL: No datastore defined"
			exit 1
		fi

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
			status=$(curl -silent -i "${INFLUXURL}" --data-binary "${PROG//.sh/},host=${MYHOST} temp=${temps}
			${PROG//.sh/},host=${MYHOST} humid=${humid}
			${PROG//.sh/},host=${MYHOST} co2ppm=${CO2}")

			if [ -n "${status}" -a -n "${status##*204 No Content*}" ]
			then
				echo "${PROG}:FATAL: Can't write to InfluxDB"
				exit 1
			fi
		fi
		if [ "${DONTRRD:-0}" != "1" ]
		then
			rrdtool update ${RRDFILE} N:${temps}:${humid}:${CO2}
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
	reindex)	do_index
		;;
	xport)
		if [ "${DONTRRD:-0}" != "1" ]
		then
		    rrdtool xport --end now ${START:+--start $START} \
			DEF:temps=${RRDFILE}:temps:LAST DEF:press=${RRDFILE}:press:LAST \
			XPORT:temps:"farenheit" XPORT:press:"mbar"
		fi
		;;

	*)
		usage
		exit 1
		;;
esac
