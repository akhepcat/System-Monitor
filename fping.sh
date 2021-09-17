#!/bin/bash
#
#  currently called in a loop from do-updates;  should we move the loop here?
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

RRDBASE="${RRDLIB:-.}/response-"
GRAPHBASE="${WEBROOT:-.}/response-"


CMD=$1
IP=$2

IDX="${WEBROOT:-.}/response-${IP}.html"
RRDFILE="${RRDBASE}${IP}.rrd"
GRAPHNAME="${GRAPHBASE}${IP}.png"

STATS=""

# Choose your colors here
PMINC=44FF44
PMAXC=000ccc
JITRC=ccc000
LOSSC=FF0000

if [ -z "$(which fping 2>&1 | grep -v which:)" -a -z "$(which ping 2>&1 | grep -v which:)" ]
then
	exit 1
elif [ ${USE_FPING} -eq 1 -a -z "$(which fping 2>&1 | grep -v which:)" ]
then
		USE_FPING=0
fi

# Good
#      PING OK|xmt=3 rcv=3 loss=0 min=1.05 avg=1.16 max=1.37
# Bad
#      PING BAD|xmt=3 rcv=0 loss=100 min=0 avg=0 max=0 

# 20 seconds max for good results.
# 1 ping every 1/5 sec, wait max a double-sat hop for response
poll() {
	MYIP=$1

	if [ ${USE_FPING} -eq 1 ]
	then

		if [ "${CMD}" == "debug" ]
		then
			count=3
	       	else
	       		count=25
	       	fi
       	
		STATS=$(fping -p 200 -t 1300 -qc ${count} ${MYIP} 2>&1 | \
		  sed 's/.*loss = \([0-9]*\)\/\([0-9]*\)\/\([0-9]*\)%/PING OK|xmt=\1 rcv=\2 loss=\3 #/;
		     s/#.*= \([0-9]*.[0-9]*\)\/\([0-9].*\)\/\([0-9].*\)/min=\1 avg=\2 max=\3/;
		     s/.*|\(.*loss=100\).*#/PING BAD|\1 min=0 avg=0 max=0/;' )
	else
		STATS=$(ping -W 2 -i 0.2 -qc 3 ${MYIP} 2>&1 | \
		  sed 's/.*statistics.*$//; s/.*data\.$//; /^$/d; {N; s/\n/ /; }; 
		       s/\([0-9]*\) packets transmitted, \([0-9]\) received, \([0-9]\)%.*mdev = \([0-9\.]*\)\/\([0-9\.]*\)\/\([0-9\.]*\)\/\([0-9\.]*\).*/min=\4 avg=\5 max=\6 xmt=\1 rcv=\2 loss=\3/;
		       s/\([0-9]\{1,5\}\) packets trans.*100% packet.*/PING BAD|xmt=\1 rcv=0 loss=100 min=0 avg=0 max=0/;' )
	fi
}

usage() {
	echo "Invalid option for ${PROGNAME}"
	echo "${PROG} (create|update|graph|graph-weekly|debug) <host>"
}

do_index() {
### HEAD
	PROGNAME="response"

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
<h2>fping response stats: ${IP}</h2>
<p>
	I provide multiple statistics showing the general response health of the hosts below.<br />
	All statistics are gathered once a minute and the charts are redrawn every 5 minutes.<br />
	Additionally, this page is automatically reloaded every 5 minutes.
	<br />Index page last generated on ${DATE}<br />
</p>

<table>
  <tr><th colspan='2'>Daily</th><th colspan='2'>Weekly</th></tr>

  <tr>
    <td>&nbsp;</td>
    <td><img src="${PROGNAME}-${IP}.png" /></td>
    <td>&nbsp;</td>
    <td><img src="${PROGNAME}-${IP}-week.png" /></td>
  </tr>

  <tr><th colspan='2'>Monthly</th><th colspan='2'>Yearly</th></tr>

  <tr>
    <td>&nbsp;</td>
    <td><img src="${PROGNAME}-${IP}-month.png" /></td>
    <td>&nbsp;</td>
    <td><img src="${PROGNAME}-${IP}-year.png" /></td>
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
	SP='\t    '	# nominal spacing
	XAXIS=""	# only the daily graph gets custom x-axis markers

	case $1 in
		day)
			TITLE="${MYHOST} last 24 hours ping stats for ${IP} - ${DATE}"
			START=""
			XAXIS="MINUTE:30:MINUTE:30:HOUR:1:0:%H"
		;;
		week)
			GRAPHNAME="${GRAPHNAME//.png/-week.png}"
			TITLE="${MYHOST} last 24 hours ping stats for ${IP} - ${DATE}"
			START="end-$LASTWEEK"
		;;
		month)
	    		GRAPHNAME="${GRAPHNAME//.png/-month.png}"
			TITLE="${MYHOST} last 24 hours ping stats for ${IP} - ${DATE}"
	    		START="end-$LASTMONTH"
	    	;;
		year)
	    		GRAPHNAME="${GRAPHNAME//.png/-year.png}"
			TITLE="${MYHOST} last 24 hours ping stats for ${IP} - ${DATE}"
	    		START="end-$LASTYEAR"
	    	;;
	    	*) 	echo "broken graph call"
	    		exit 1
	    	;;
	esac
	rrdtool graph ${GRAPHNAME} \
	        -v "${PROGNAME} stats" -w 700 -h 300  -t "${TITLE}" \
		--upper-limit 1.1 --lower-limit 0 --alt-y-grid --units-length 2 \
	        --right-axis-label "fping trends" \
	        --right-axis 0.02:0 --right-axis-format %1.0lf \
	        --use-nan-for-all-missing-data \
		-c ARROW\#000000  --end now \
		${START:+--start $START}  ${XAXIS:+-x $XAXIS} \
		DEF:pingmin=${RRDFILE}:pingmin:AVERAGE \
		DEF:pingmax=${RRDFILE}:pingmax:AVERAGE \
		DEF:jitter=${RRDFILE}:jitter:AVERAGE \
		DEF:pktloss=${RRDFILE}:pktloss:AVERAGE \
		CDEF:lossinv=0,pktloss,- \
		CDEF:jittinv=0,jitter,- \
		COMMENT:"${SP}" \
		LINE2:pingmin\#${PMINC}:"min RTT ms\t    " \
		LINE2:pingmax\#${PMAXC}:"max RTT ms\t    " \
		LINE1:jitter\#${JITRC}:" jitter ms\t    " \
		LINE1:lossinv\#${LOSSC}:"pkt loss %" \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:pingmin:MIN:" min\: %3.03lf\t    " \
		GPRINT:pingmax:MIN:" min\: %3.03lf\t    " \
		GPRINT:jitter:MIN:" min\: %3.03lf\t    " \
		GPRINT:pktloss:MIN:" min\: %3.03lf" \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:pingmin:MAX:" max\: %3.03lf\t    " \
		GPRINT:pingmax:MAX:" max\: %3.03lf\t    " \
		GPRINT:jitter:MAX:" max\: %3.03lf\t    " \
		GPRINT:pktloss:MAX:" max\: %3.03lf" \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:pingmin:AVERAGE:" avg\: %3.03lf\t    " \
		GPRINT:pingmax:AVERAGE:" avg\: %3.03lf\t    " \
		GPRINT:jitter:AVERAGE:" avg\: %3.03lf\t    " \
		GPRINT:pktloss:AVERAGE:" avg\: %3.03lf" \
		COMMENT:"\l" \
		COMMENT:"${SP}" \
		GPRINT:pingmin:LAST:"last\: %3.03lf\t    " \
		GPRINT:pingmax:LAST:"last\: %3.03lf\t    " \
		GPRINT:jitter:LAST:"last\: %3.03lf\t    " \
		GPRINT:pktloss:LAST:"last\: %3.03lf" \
		COMMENT:"\l"
}


if [ -z "$IP" ];
then
	echo "missing host"
	usage
	exit 1
fi

case $CMD in
	debug)
		echo "RRDLIB=${RRDLIB}"
		echo "WEBROOT=${WEBROOT}"
		echo "RRDFILE=${RRDFILE}"
		echo "GRAPHNAME=${GRAPHNAME}"
		poll $IP
		if [ -z "${STATS##*BAD*}" ];
		then
			echo "no stats for cycle (host down)"
		else
			LOSS=${STATS##*loss=};	LOSS="${LOSS%% *}"
			MIN=${STATS##*min=};	MIN=${MIN%% *}
			MAX=${STATS##*max=};	MAX=${MAX%% *}

			JITTER=$(echo "scale = 6; print ${MAX} - ${MIN}" | bc)
			JITTER=$(printf "%03.03f" $JITTER)
			echo LOSS=${LOSS}
			echo JITTER=${JITTER}
			echo MIN=${MIN}
			echo MAX=${MAX}
		fi
		;;

        force-create|create)
                if [ "${CMD}" == "force-create" -o ! -r ${RRDFILE} ];
                then
		rrdtool create ${RRDFILE} -s 60 \
		DS:pingmin:GAUGE:180:0:300 \
		DS:pingmax:GAUGE:180:0:300 \
		DS:pktloss:GAUGE:180:0:300 \
		DS:jitter:GAUGE:180:0:300 \
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
		poll $IP
		LOSS=${STATS##*loss=};	LOSS="${LOSS%% *}"
		MIN=${STATS##*min=};	MIN=${MIN%% *}
		MAX=${STATS##*max=};	MAX=${MAX%% *}
		JITTER=$(echo "scale = 6; print ${MAX} - ${MIN}" | bc)
		JITTER=$(printf "%03.03f" $JITTER)

		rrdtool update ${RRDFILE} N:${MIN}:${MAX}:${LOSS}:${JITTER}
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
		usage
		exit 1
		;;
esac
