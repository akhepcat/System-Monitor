#!/bin/bash
#
#  plots the time it takes to perform a name query to each provided authoritative DNS server
#  uses the code from https://docs.cacti.net/_media/userscript:dnsresponsetimeping-latest.tar.gz
#

[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

USE_FPING=${USE_FPING:-1}

#####################
PUSER="${USER}"
PROG="${0##*/}"
MYHOST="$(uname -n)"
MYHOST=${SERVERNAME:-$MYHOST}
PROGNAME=${PROG%%.*}
DATE=$(date)
PATH=${PATH}:/sbin:/usr/sbin

RRDBASE="${RRDLIB:-.}/${PROGNAME}-"
GRAPHBASE="${WEBROOT:-.}/${PROGNAME}-"
IDX="${WEBROOT:-.}/${PROGNAME}.html"

CMD=$1

STATS=""

poll() {
	MYNS=$1
	MYHOST=$2

	STATS=$(perl -w -- ${SCRIPTHOME}/dnsResponseTimePing.pl -r -s ${MYNS} -h ${MYHOST} 2>/dev/null )
	#0:12	#[good=0,bad=1]:[response-time in hundredths of a second]
}

usage() {
	echo "${PROG} (create|update|graph|debug) <host>"
}

do_index() {
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
<p>
	I provide multiple statistics showing the general response health of the hosts below.<br />
	All statistics are gathered once a minute and the charts are redrawn every 5 minutes.<br />
	Additionally, this page is automatically reloaded every 5 minutes.
	<br />Index page last generated on ${DATE}<br />
</p>
EOF

### BODY
	# menu header
	for H in ${RESOLVERS}
	do
		echo "<a href=\"#${H%%:*}\">${H%%:*}</a>&nbsp;&nbsp;&nbsp;" >> ${IDX}
	done

	# Now the graphs
	for H in ${RESOLVERS}
	do
		RRD=${H%%:*}

		echo "<div name=\"${RRD}\">" >> ${IDX}
		echo "<a name=\"${RRD}\" />" >> ${IDX}
		echo "<h2>${RRD}</h2>" >> ${IDX}
		# Table, 4 cols
		echo "<table>" >> ${IDX}
		# daily, weekly
		echo "<tr><th colspan='2'>Daily</th><th colspan='2'>Weekly</th></tr>" >> ${IDX}
		echo "<tr><td>&nbsp;</td>" >> ${IDX}
		graph="${PROGNAME}-${RRD}.png"
		echo "<td><img src=\"${graph}\" /></td>" >> ${IDX}
		echo "<td>&nbsp;</td>" >> ${IDX}
		graph="${PROGNAME}-${RRD}-week.png"
		echo "<td><img src=\"${graph}\" /></td>" >> ${IDX}
		echo "</tr>" >> ${IDX}
		# monthly, yearly
		echo "<tr><th colspan='2'>Monthly</th><th colspan='2'>Yearly</th></tr>" >> ${IDX}
		echo "<tr><td>&nbsp;</td>" >> ${IDX}
		graph="${PROGNAME}-${RRD}-month.png"
		echo "<td><img src=\"${graph}\" /></td>" >> ${IDX}
		echo "<td>&nbsp;</td>" >> ${IDX}
		graph="${PROGNAME}-${RRD}-year.png"
		echo "<td><img src=\"${graph}\" /></td>" >> ${IDX}
		echo "</tr>" >> ${IDX}
		echo "</table>" >> ${IDX}
		echo "</div>" >> ${IDX}
		echo "<p /><hr />" >> ${IDX}
	done


### TAIL
	cat >>${IDX} <<EOF
<hr />
<p> (c) akhepcat - <a href="https://github.com/akhepcat/System-Monitor">System-Monitor Suite</a> on Github!</p>
</body>
</html>
EOF

}

do_graph() {
	for H in ${RESOLVERS}
	do
		Q=${H%%:*}
		RRDFILE="${RRDBASE}${Q}.rrd"
		GRAPHNAME="${GRAPHBASE}${Q}.png"

		dns1=${H//$Q:/}; dns1=${dns1%%,*}
		dns2=${H//*:$dns1,/}; dns2=${dns2%%,*} 
		dns3=${H//*$dns2,/}; dns3=${dns3%%,*}
		dns4=${H//*$dns3,/}; dns4=${dns4%%,*}

		case $1 in
			day)
				TITLE="${MYHOST} last 24 hours DNS stats for ${Q} <br> ${DATE}"
				START=""
				EXTRA="MINUTE:30:MINUTE:30:HOUR:1:0:%H"
			;;
			week)
				GRAPHNAME="${GRAPHNAME//.png/-week.png}"
				TITLE="${MYHOST} last 7 days DNS stats for ${Q} <br> ${DATE}"
				START="end-$LASTWEEK"
				EXTRA=""
			;;
			month)
		    		GRAPHNAME="${GRAPHNAME//.png/-month.png}"
		    		TITLE="${MYHOST} last month's DNS stats for ${Q} <br> ${DATE}"
		    		START="end-$LASTMONTH"
				EXTRA=""
		    	;;
			year)
		    		GRAPHNAME="${GRAPHNAME//.png/-year.png}"
		    		TITLE="${MYHOST} last year's DNS stats for ${Q} <br> ${DATE}"
		    		START="end-$LASTYEAR"
				EXTRA=""
		    	;;
		    	*) 	echo "broken graph call"
		    		exit 1
		    	;;
		esac

		PreSP="    "
		PostSP="\t"
		ldns1=${#dns1}
		ldns2=${#dns2}
		ldns3=${#dns3}
		if [ $ldns1 -le 20 ]
		then
			SP1="\t\t"
		elif [ $ldns1 -gt 20 ]
		then
			SP1="\t"
		else
			SP1=" "
		fi

		if [ $ldns2 -le 20 ]
		then
			SP2="\t\t"
		elif [ $ldns2 -gt 20 ]
		then
			SP2="\t"
		else
			SP2=" "
		fi

		if [ $ldns3 -le 20 ]
		then
			SP3="\t\t"
		elif [ $ldns3 -gt 20 ]
		then
			SP3="\t"
		else
			SP3=" "
		fi
		
		rrdtool graph ${GRAPHNAME} \
			-v "response time in ms" -w 700 -h 300  -t "${TITLE}" \
			--upper-limit 1.1 --lower-limit 0 --alt-y-grid --units-length 2 \
		        --use-nan-for-all-missing-data \
			-c ARROW\#000000  --end now \
			${START:+--start $START}  ${EXTRA:+-x $EXTRA} \
			DEF:dns1=${RRDFILE}:dns1:AVERAGE \
			DEF:dns2=${RRDFILE}:dns2:AVERAGE \
			DEF:dns3=${RRDFILE}:dns3:AVERAGE \
			DEF:dns4=${RRDFILE}:dns4:AVERAGE \
			COMMENT:"\l" \
			COMMENT:"${PreSP}" \
			LINE1:dns1\#44FF44:"${dns1:-adns1}${SP1}" \
			LINE1:dns2\#000ccc:"${dns2:-adns2}${SP2}" \
			LINE1:dns3\#ccc000:"${dns3:-adns3}${SP3}" \
			LINE1:dns4\#FF0000:"${dns4:-adns4}" \
			COMMENT:"\l" \
			COMMENT:"${PreSP}" \
			GPRINT:dns1:MIN:" min\: %3.03lf ms\t\t" \
			GPRINT:dns2:MIN:" min\: %3.03lf ms\t\t" \
			GPRINT:dns3:MIN:" min\: %3.03lf ms\t" \
			GPRINT:dns4:MIN:" min\: %3.03lf ms" \
			COMMENT:"\l" \
			COMMENT:"${PreSP}" \
			GPRINT:dns1:MAX:" max\: %3.03lf ms\t\t" \
			GPRINT:dns2:MAX:" max\: %3.03lf ms\t\t" \
			GPRINT:dns3:MAX:" max\: %3.03lf ms\t" \
			GPRINT:dns4:MAX:" max\: %3.03lf ms" \
			COMMENT:"\l" \
			COMMENT:"${PreSP}" \
			GPRINT:dns1:AVERAGE:" avg\: %3.03lf ms\t\t" \
			GPRINT:dns2:AVERAGE:" avg\: %3.03lf ms\t\t" \
			GPRINT:dns3:AVERAGE:" avg\: %3.03lf ms\t" \
			GPRINT:dns4:AVERAGE:" avg\: %3.03lf ms" \
			COMMENT:"\l" \
			COMMENT:"${PreSP}" \
			GPRINT:dns1:LAST:"last\: %3.03lf ms\t\t" \
			GPRINT:dns2:LAST:"last\: %3.03lf ms\t\t" \
			GPRINT:dns3:LAST:"last\: %3.03lf ms\t" \
			GPRINT:dns4:LAST:"last\: %3.03lf ms" \
			COMMENT:"\l"
	done
}

if [ -z "${RESOLVERS}" ];
then
	echo "missing resolver host:server array in config file"
	usage
	exit 1
fi

case $CMD in
	debug)
		echo "RRDLIB=${RRDLIB}"
		echo "WEBROOT=${WEBROOT}"

		for H in ${RESOLVERS}
		do
			Q=${H%%:*}
			NS=${H##*:}

			echo "RRDFILE=${RRDBASE}${Q}.rrd"
			echo "IMGNAME=${GRAPHBASE}${Q}.png"

			for ADNS in ${NS//,/ }
			do
				echo "ADNS=${ADNS}"
				poll $ADNS $Q

				if [ -z "${STATS}" ]
				then
					STATS="1:U"
				fi

				if [ "${STATS%%:*}" -eq 1 ];
				then
					echo "Query unsuccessful"
				else
					echo "Query successful"
				fi

				echo ERR=${STATS%%:*}
				echo MS=${STATS##*:}
			done
			echo "--"
		done
		;;

        force-create|create)
		for H in ${RESOLVERS}
		do
			Q=${H%%:*}
			NS=${H##*:}

			RRDFILE="${RRDBASE}${Q}.rrd"
			
			if [ ! -r "${RRDFILE}" -o "${CMD}" == "force-create" ]
			then
			    rrdtool create ${RRDFILE} -s 60 \
				DS:dns1:GAUGE:180:0:250 \
				DS:dns2:GAUGE:180:0:250 \
				DS:dns3:GAUGE:180:0:250 \
				DS:dns4:GAUGE:180:0:250 \
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
		;;

	update)
		for H in ${RESOLVERS}
		do
			Q=${H%%:*}
			NS=${H##*:}

			RRDFILE="${RRDBASE}${Q}.rrd"

			MSTATS=""
			hc=0
			for ADNS in ${NS//,/ }
			do
				hc=$((hc+1))

				poll $ADNS $Q

				if [ -z "${STATS}" -o "${STATS%%:*}" -eq 1 ]
				then
					STATS="U"
				else
					STATS="${STATS##*:}"
				fi
				MSTATS="${MSTATS}:${STATS}"
			done

			if [ ${hc:-0} -lt 4 ]
			then
				for i in $(seq $((hc+1)) 4)
				do
					MSTATS="${MSTATS}:U"
				done
			fi
			rrdtool update ${RRDFILE} N${MSTATS}
		done
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

	*)
		echo "Invalid option for ${PROGNAME}"
		usage
		exit 1
		;;
esac
