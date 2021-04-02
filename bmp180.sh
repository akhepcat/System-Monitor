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

for iio in /sys/bus/iio/devices/*
do
	for sub in $(find ${iio}/ -iname name)
	do
		if [ "$(cat ${sub})" = "bmp180" ]
		then
			BMP=${sub%name}
		fi
	done
done


poll() {
	if [ -n "${BMP}" ]
	then
		# {Traw} is Temperature_in_Centigrade, so convert here
		# {Praw} is Pressure_in_Millibars * 10, so fix-up here
		#
		Traw=$(cat ${BMP}/in_temp_input)
		Praw=$(cat ${BMP}/in_pressure_input)
		TF=$( echo "scale=2; (($Traw/1000) * 9/5) + 32" | bc)
		PM=$( echo "scale=2; ($Praw * 10)/1" | bc)
		STATS="OK temp=${TF} pres=${PM}"
	else
		STATS="BAD temp=U pres=U"
	fi
}

usage() {
	echo "Invalid option for ${PROGNAME}"
	echo "${PROG} (create|update|graph|graph-weekly|debug) <host>"
}

do_index() {
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
	I provide multiple statistics showing the temperature and air pressure from the BMP180 below.<br />
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

	# the Lowest recorded pressure was: 870 hpa(mbar)
	# the Average Mean Sea-Level pressure  is 1013.25 hPa(mbar)
	# the Highest recorded pressure was: 1084.8 hPa(mbar)

	# So to scale the data, we subtract 850 from the current value,
	# but change the range of the right axis to start at 850, whic provides
	# a 250mbar range from 850-1100. Which mostly works here.

	rrdtool graph ${GRAPHNAME} \
	        -v "${PROGNAME} temperature" -w 700 -h 300  -t "${TITLE}" \
		${SCALE} --alt-y-grid --units-length 2 \
	        --right-axis-label "${PROGNAME} air pressure" \
	        --right-axis 1:850 --right-axis-format %1.0lf \
	        --use-nan-for-all-missing-data \
		--color ARROW\#000000  ${START:+--end now} ${START:+--start $START}  ${XAXIS:+--x-grid $XAXIS} \
		DEF:temps=${RRDFILE}:temps:LAST \
		DEF:press=${RRDFILE}:press:LAST \
		CDEF:bigp=press,850,- \
		COMMENT:"${SP}" \
		LINE2:temps\#${TCOL}:"Cur temp F${SP}" \
		LINE2:bigp\#${PCOL}:"Cur pres mbar${SP}" \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:temps:MIN:" min\: %3.02lf${SP}" \
		GPRINT:press:MIN:" min\: %3.02lf${SP}" \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:temps:MAX:" max\: %3.02lf${SP}" \
		GPRINT:press:MAX:" max\: %3.02lf${SP}" \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:temps:AVERAGE:" avg\: %3.02lf${SP}" \
		GPRINT:press:AVERAGE:" avg\: %3.02lf${SP}" \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:temps:LAST:"last\: %3.02lf${SP}" \
		GPRINT:press:LAST:"last\: %3.02lf${SP}" \
		COMMENT:"\l"
}

case $CMD in
	debug)
		echo "RRDLIB=${RRDLIB}"
		echo "WEBROOT=${WEBROOT}"
		echo "RRDFILE=${RRDFILE}"
		echo "GRAPHNAME=${GRAPHBASE}"
		poll
		if [ -z "${STATS##*BAD*}" ];
		then
			echo "no stats for cycle (host down)"
		else
			temps=${STATS##*temp=};  temps=${temps%% *}
			press=${STATS##*pres=};  press=${press%% *}

			echo TEMP=${temps}
			echo PRES=${press}
		fi
		if [ "${DONTRRD:-0}" != "1" ]
		then
			echo "Datastore RRD is enabled"
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
		DS:press:GAUGE:180:U:U \
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
		press=${STATS##*pres=};  press=${press%% *}

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
			${PROG//.sh/},host=${MYHOST} press=${press}")

			if [ -n "${status}" -a -n "${status##*204 No Content*}" ]
			then
				echo "${PROG}:FATAL: Can't write to InfluxDB"
				exit 1
			fi
		fi
		if [ "${DONTRRD:-0}" != "1" ]
		then
			rrdtool update ${RRDFILE} N:${temps}:${press}
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
		rrdtool xport --end now ${START:+--start $START} \
			DEF:temps=${RRDFILE}:temps:LAST DEF:press=${RRDFILE}:press:LAST \
			XPORT:temps:"farenheit" XPORT:press:"mbar"
		;;

	*)
		usage
		exit 1
		;;
esac
