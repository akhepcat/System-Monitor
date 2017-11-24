#!/bin/bash
#
#  Just hardlink this file to the name of your drives, and it'll auto-set
#

USE_FPING=1
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
MYHOST="$(uname -n)"
PROGNAME=${PROG%%.*}
DATE=$(date)
PATH=${PATH}:/sbin:/usr/sbin

CMD=$1
IP=$2

STATS=""

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

if [ -z "$IP" ];
then
	echo "missing host"
	usage
	exit 1
fi

RRDFILE="${RRDLIB:-.}/response-${IP}.rrd"
GRAPHNAME="${WEBROOT:-.}/response-${IP}.png"

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
		DS:pingmin:GAUGE:180:0:100 \
		DS:pingmax:GAUGE:180:0:100 \
		DS:pktloss:GAUGE:180:0:100 \
		DS:jitter:GAUGE:180:0:100 \
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

	graph|graph-day)
#	        -Y -u 1.1 -l 0 -L 2 \
	    rrdtool graph ${GRAPHNAME} \
	        -Y -L 2  \
		-v "Ping stats" -w 700 -h 300 -t "${MYHOST} last 24 hours ping stats for ${IP} - ${DATE}" \
		-c ARROW\#000000 -x MINUTE:30:MINUTE:30:HOUR:1:0:%H \
		DEF:pingmin=${RRDFILE}:pingmin:AVERAGE \
		DEF:pingmax=${RRDFILE}:pingmax:AVERAGE \
		DEF:pktloss=${RRDFILE}:pktloss:AVERAGE \
		DEF:jitter=${RRDFILE}:jitter:AVERAGE \
		CDEF:lossinv=0,pktloss,- \
		CDEF:jittinv=0,jitter,- \
		COMMENT:"	" \
		LINE2:pingmin\#44FF44:"minimum RTT" \
		LINE2:pingmax\#000ccc:"maximum RTT" \
		LINE3:lossinv\#FF0000:"packet loss" \
		LINE1:jitter\#ccc000:"packet jitter" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:pingmin:MIN:"abs min-RTT minimum\: %lf" \
		GPRINT:pingmin:MAX:"abs min-RTT maximum\: %lf" \
		GPRINT:pingmin:AVERAGE:"min-RTT average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:pingmax:MIN:"abs max-RTT minimum\: %lf" \
		GPRINT:pingmax:MAX:"abs max-RTT maximum\: %lf" \
		GPRINT:pingmax:AVERAGE:"max-RTT average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:pktloss:MIN:"abs pkt-loss minimum\: %lf" \
		GPRINT:pktloss:MAX:"abs pkt-loss maximum\: %lf" \
		GPRINT:pktloss:AVERAGE:"pkt-loss average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:jitter:MIN:"abs jitter minimum\: %lf" \
		GPRINT:jitter:MAX:"abs jitter maximum\: %lf" \
		GPRINT:jitter:AVERAGE:"jitter average\: %lf" \
		COMMENT:"	\j"
		;;

	graph-weekly)
    rrdtool graph ${GRAPHNAME//.png/-week.png} \
		-v "Bytes" -w 700 -h 300 -t "${MYHOST} last 7 days memory usage- ${DATE}" \
		--end now --start end-$LASTWEEK -c ARROW\#000000  \
		DEF:pingmin=${RRDFILE}:pingmin:AVERAGE \
		DEF:pingmax=${RRDFILE}:pingmax:AVERAGE \
		DEF:pktloss=${RRDFILE}:pktloss:AVERAGE \
		DEF:jitter=${RRDFILE}:jitter:AVERAGE \
		CDEF:lossinv=0,pktloss,- \
		CDEF:jittinv=0,jitter,- \
		COMMENT:"	" \
		LINE2:pingmin\#44FF44:"minimum RTT" \
		LINE2:pingmax\#000ccc:"maximum RTT" \
		LINE3:lossinv\#FF0000:"packet loss" \
		LINE1:jitter\#ccc000:"packet jitter" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:pingmin:MIN:"abs min-RTT minimum\: %lf" \
		GPRINT:pingmin:MAX:"abs min-RTT maximum\: %lf" \
		GPRINT:pingmin:AVERAGE:"min-RTT average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:pingmax:MIN:"abs max-RTT minimum\: %lf" \
		GPRINT:pingmax:MAX:"abs max-RTT maximum\: %lf" \
		GPRINT:pingmax:AVERAGE:"max-RTT average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:pktloss:MIN:"abs pkt-loss minimum\: %lf" \
		GPRINT:pktloss:MAX:"abs pkt-loss maximum\: %lf" \
		GPRINT:pktloss:AVERAGE:"pkt-loss average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:jitter:MIN:"abs jitter minimum\: %lf" \
		GPRINT:jitter:MAX:"abs jitter maximum\: %lf" \
		GPRINT:jitter:AVERAGE:"jitter average\: %lf" \
		COMMENT:"	\j"
		;;
	graph-monthly)
    rrdtool graph ${GRAPHNAME//.png/-month.png} \
		-v "Bytes" -w 700 -h 300 -t "${MYHOST} last month's memory usage- ${DATE}" \
		--end now --start end-$LASTMONTH -c ARROW\#000000  \
		DEF:pingmin=${RRDFILE}:pingmin:AVERAGE \
		DEF:pingmax=${RRDFILE}:pingmax:AVERAGE \
		DEF:pktloss=${RRDFILE}:pktloss:AVERAGE \
		DEF:jitter=${RRDFILE}:jitter:AVERAGE \
		CDEF:lossinv=0,pktloss,- \
		CDEF:jittinv=0,jitter,- \
		COMMENT:"	" \
		LINE2:pingmin\#44FF44:"minimum RTT" \
		LINE2:pingmax\#000ccc:"maximum RTT" \
		LINE3:lossinv\#FF0000:"packet loss" \
		LINE1:jitter\#ccc000:"packet jitter" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:pingmin:MIN:"abs min-RTT minimum\: %lf" \
		GPRINT:pingmin:MAX:"abs min-RTT maximum\: %lf" \
		GPRINT:pingmin:AVERAGE:"min-RTT average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:pingmax:MIN:"abs max-RTT minimum\: %lf" \
		GPRINT:pingmax:MAX:"abs max-RTT maximum\: %lf" \
		GPRINT:pingmax:AVERAGE:"max-RTT average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:pktloss:MIN:"abs pkt-loss minimum\: %lf" \
		GPRINT:pktloss:MAX:"abs pkt-loss maximum\: %lf" \
		GPRINT:pktloss:AVERAGE:"pkt-loss average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:jitter:MIN:"abs jitter minimum\: %lf" \
		GPRINT:jitter:MAX:"abs jitter maximum\: %lf" \
		GPRINT:jitter:AVERAGE:"jitter average\: %lf" \
		COMMENT:"	\j"
		;;
	graph-yearly)
    rrdtool graph ${GRAPHNAME//.png/-year.png} \
		-v "Bytes" -w 700 -h 300 -t "${MYHOST} last year's memory usage- ${DATE}" \
		--end now --start end-$LASTYEAR -c ARROW\#000000  \
		DEF:pingmin=${RRDFILE}:pingmin:AVERAGE \
		DEF:pingmax=${RRDFILE}:pingmax:AVERAGE \
		DEF:pktloss=${RRDFILE}:pktloss:AVERAGE \
		DEF:jitter=${RRDFILE}:jitter:AVERAGE \
		CDEF:lossinv=0,pktloss,- \
		CDEF:jittinv=0,jitter,- \
		COMMENT:"	" \
		LINE2:pingmin\#44FF44:"minimum RTT" \
		LINE2:pingmax\#000ccc:"maximum RTT" \
		LINE3:lossinv\#FF0000:"packet loss" \
		LINE1:jitter\#ccc000:"packet jitter" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:pingmin:MIN:"abs min-RTT minimum\: %lf" \
		GPRINT:pingmin:MAX:"abs min-RTT maximum\: %lf" \
		GPRINT:pingmin:AVERAGE:"min-RTT average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:pingmax:MIN:"abs max-RTT minimum\: %lf" \
		GPRINT:pingmax:MAX:"abs max-RTT maximum\: %lf" \
		GPRINT:pingmax:AVERAGE:"max-RTT average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:pktloss:MIN:"abs pkt-loss minimum\: %lf" \
		GPRINT:pktloss:MAX:"abs pkt-loss maximum\: %lf" \
		GPRINT:pktloss:AVERAGE:"pkt-loss average\: %lf" \
		COMMENT:"	\j" \
		COMMENT:"	" \
		GPRINT:jitter:MIN:"abs jitter minimum\: %lf" \
		GPRINT:jitter:MAX:"abs jitter maximum\: %lf" \
		GPRINT:jitter:AVERAGE:"jitter average\: %lf" \
		COMMENT:"	\j"
		;;
	*)
		usage
		exit 1
		;;
esac
