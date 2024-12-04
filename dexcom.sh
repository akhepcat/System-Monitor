#!/bin/bash
#
#  graphs the blood-glucose level from dexcom share.
#    * if you're not using dexcom share, this won't work for you.
#    * you must have at least one 'share' account for this to work.
#    * this uses the account-owner's credentials, not one of the shared people
#

[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

# either change the 'my_username/my_password' below, or you can define these in the above file
dexcom_username=${dexcom_username:-my_username}
dexcom_password=${dexcom_password:-my_password}

# Dexcom only updates every 5 minutes, so we use this to cache data except on the 5-minute mark
HOUR=$(date +"%-H")	# we don't want zero-padded
MIN=$(date +"%-M")	# ^^^
TS=$(( ($HOUR * 3600) + ($MIN * 60) ))

#####################
PUSER="${USER}"
PROG="${0##*/}"
MYHOST="$(uname -n)"
MYHOST=${SERVERNAME:-$MYHOST}
PROGNAME=${PROG%%.*}
RRDBASE="${RRDLIB:-.}/${PROGNAME}-"
GRAPHBASE="${WEBROOT:-.}/${PROGNAME}-"
IDX="${WEBROOT:-.}/${PROGNAME}.html"

CMD="$1"
DATE=$(date)

declare -a Trends
declare -A rTrends
# We invert the trends, since that data looks better on the graphs
#          0         1           2             3            4           5            6           7             8              9
# Orig=( 'None' 'DoubleUp'   'SingleUp'   'FortyFiveUp'   'Flat'  'FortyFiveDown' 'SingleDown' 'DoubleDown' 'NotComputable' 'OutOfRange' )
Trends=( 'None' 'DoubleDown' 'SingleDown' 'FortyFiveDown' 'Flat'  'FortyFiveUp'   'SingleUp'   'DoubleUp'   'NotComputable' 'OutOfRange' )
rTrends=( [None]=0 [DoubleDown]=1 [SingleDown]=2 [FortyFiveDown]=3 [Flat]=4  [FortyFiveUp]=5   [SingleUp]=6   [DoubleUp]=7   [NotComputable]=8 [OutOfRange]=9 )

useragent='Dexcom Share/3.0.2.11 CFNetwork/672.0.2 Darwin/14.0.0'

baseurl='https://share2.dexcom.com/ShareWebServices/Services'
appID="d8665ade-9673-4e27-9ff6-92db4ce13d13"

RRDFILE="${RRDLIB:-.}/${PROGNAME}-${dexcom_username}.rrd"
GRAPHNAME="${WEBROOT:-.}/${PROGNAME}-${dexcom_username}.png"

bglcache=/run/dexcom-${dexcom_username}.cache
scache=/run/dexcom-data.cache

# Graph colors
Bcolor=cc0c00
Tcolor=000ccc

Value=89
Trend=4

if [ -r "${scache}" ]
then
	session=$(cat "${scache}")
else
	session=""
fi

sess_update() {
	# Activate a session
	session=$( curl --silent \
	        --header "Content-Type: application/json" \
		--header "User-Agent: ${useragent}" \
		--request POST \
		--data "{\"accountName\":\"${dexcom_username}\",\"applicationId\":\"${appID}\",\"password\":\"${dexcom_password}\"}" \
		"${baseurl}/General/AuthenticatePublisherAccount" )  
	###  this query returns a bogus session id, but better errors.  if used, call login afterward for the actual session id

	if [ -n "${session}" ]
	then
	    result=$( curl --silent \
	        --header "Content-Type: application/json" \
		--header "User-Agent: ${useragent}" \
		--request POST \
		--data "{\"accountName\":\"${dexcom_username}\",\"applicationId\":\"${appID}\",\"password\":\"${dexcom_password}\"}" \
		"${baseurl}/General/LoginPublisherAccountByName" )
	
	    session=${result//\"/}
	fi
}

# Returns JSON formatted data like:
# [{"DT":"\/Date(1603540578000+0000)\/","ST":"\/Date(1603569378000)\/","Trend":4,"Value":94,"WT":"\/Date(1603569378000)\/"}]
get_data() {
	result=$( curl --silent\
	      --header "Accept: application/json" \
	      --header "User-Agent: ${useragent}" \
	      --request POST \
	      "${baseurl}/Publisher/ReadPublisherLatestGlucoseValues?sessionId=${session}&minutes=1440&maxCount=1")
}

dex_update() {
	# Can we get valid data?
	get_data

	Value=""
	if [ -z "${result}" -o -n "${result##*Value*}" ]
	then
		# looks invalid, so refresh the cache
		sess_update
		if [ -z "${session}" ]
		then
			# don't know why, but refreshing the session didn't work
			Value=U
			Trend=9
			return
		else
			# save the session, because now it's valid!
			echo "${session}" > "${scache}"
		fi
		get_data
	fi
	# if we get here, the session is valid, whether new or old
	# so we parse the JSON data... horrible, but better code follows:

	WT=${result##*WT}; WT=${WT#*\(}; WT=${WT%%\)*}
	DT=${result##*DT}; DT=${DT#*\(}; DT=${DT%%\)*}
	ST=${result##*ST}; ST=${ST#*\(}; ST=${ST%%\)*}

	Value=${result##*,\"Value\":}
	Value=${Value%%:*}; Value=${Value%%\}*}; Value=${Value%%,*}

	# work around bad json data
	Value=${Value//[^0-9]/}
	Value=${Value:-U}
	if [ $Value -gt 500 ]
	then
		# Cap the max value at 500 for extreme highs (the controller caps at 400 anyway, displaying only "HIGH")
		Value=500
	fi

	Trend=${result##*Trend\":}
	Trend=${Trend%%:*}; Trend=${Trend%%\}*}; Trend=${Trend%%,*}
	Trend=${Trend//\"/}

	if [ -z "${Trend//[^0-9]/}" ]
	then
		#it's a name, convert straight to our preferred numbers
		
		Trend=${rTrends[$Trend]}	# replace the text with the number
	else
		# it's a number, so we need to fix it up


		# work around bad json data
		Trend=${Trend//[^0-9]/}

		if [ -n "${Trend}" -a \( ${Trend:-0} -lt 8 -a ${Trend:-0} -gt 0 \) ]
		then
			# invert for better visualization of the trends, leaving 0 and 8-9 alone
			Trend=$(( 8 - Trend ))
		fi

		Trend=${Trend:-U}

	fi

	# the formula for converting:
	#    int(json_glucose_reading["WT"][6:][:-2]) / 1000.0
	#    WT=${WT%%+*}; WT=$((WT/1000)); WT=$(date --date="@${WT}")
	#    DT=${DT%%+*}; DT=$((DT/1000)); DT=$(date --date="@${DT}")
	#    ST=${ST%%+*}; ST=$((ST/1000)); ST=$(date --date="@${ST}")
		
	# This is just for debugging:
#	    echo "WT=$WT,  Value=${Value}, Trend=${Trend} == ${Trends[$Trend]}"

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
EOF

### BODY
cat >>${IDX} <<EOF
<body>
<h2>dexcom Blood-Glucose Level stats</h2>
<p>
	All statistics are gathered once a minute and the charts are redrawn every 5 minutes.<br />
	Additionally, this page is automatically reloaded every 5 minutes.
	<br />Index page last generated on ${DATE}<br />
</p>

<table>
  <tr><th colspan='2'>Daily</th><th colspan='2'>Weekly</th></tr>

  <tr>
    <td>&nbsp;</td>
    <td><img src="${PROGNAME}-${dexcom_username}.png" /></td>
    <td>&nbsp;</td>
    <td><img src="${PROGNAME}-${dexcom_username}-week.png" /></td>
  </tr>

  <tr><th colspan='2'>Monthly</th><th colspan='2'>Yearly</th></tr>

  <tr>
    <td>&nbsp;</td>
    <td><img src="${PROGNAME}-${dexcom_username}-month.png" /></td>
    <td>&nbsp;</td>
    <td><img src="${PROGNAME}-${dexcom_username}-year.png" /></td>
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
	GRAPHNAME="${WEBROOT:-.}/${PROGNAME}-${dexcom_username}.png"
	T1=""; T2=""; T3=""; T4=""; T5=""; T6=""; T7=""; T8="";

	TREND="trend,50,*"	# fixup the trendline so it plots in the middle of the graph
	SP='\t\t'	# nominal spacing
	XAXIS=""	# only the daily graph gets custom x-axis markers
	T5='COMMENT:\l'	# Two extra lines for the WMY graphs to make 'em closer to the same size
	T6='COMMENT:  ' # ""
	mTcolor=""	# hide the BGL trendline on non-daily graphs

	case $1 in
		day)
			TITLE="${dexcom_username} last 24 hours Blood-Glucose level - ${DATE}"
			START=""
			XAXIS="MINUTE:30:MINUTE:30:HOUR:1:0:%H"
			TIMING="1 min"
			SP='\t'
			T5='COMMENT:\t'
			T6='GPRINT:bgl:LAST:  current\: %3.0lf\t\t'
			T7='GPRINT:trend:LAST:\t  current\: %1.0lf\t'
			T8='COMMENT:\t9\: Signal Loss/No Data'
			mTcolor=${Tcolor}
		;;
		week)
			GRAPHNAME="${GRAPHNAME//.png/-week.png}"
			TITLE="${dexcom_username} last 7 days Blood-Glucose level - ${DATE}"
			START="end-$LASTWEEK"
			TIMING="5 min"
		;;
		month)
	    		GRAPHNAME="${GRAPHNAME//.png/-month.png}"
			TITLE="${dexcom_username} last month's Blood-Glucose level - ${DATE}"
	    		START="end-$LASTMONTH"
			TIMING="30 min"
	    	;;
		year)
	    		GRAPHNAME="${GRAPHNAME//.png/-year.png}"
			TITLE="${dexcom_username} last year's Blood-Glucose level - ${DATE}"
	    		START="end-$LASTYEAR"
			TIMING="2 hour"
			# TREND="trend,LOG,3.8,*,EXP"	# we don't usually print this, but just in case, this widens the compressed data
	    	;;
	    	*) 	echo "broken graph call"
	    		exit 1
	    	;;
	esac

	rrdtool graph ${GRAPHNAME} \
	        -v "Blood-Glucose level" -w 700 -h 300  -t "${TITLE}" \
		--upper-limit 1.1 --lower-limit 0 --alt-y-grid --units-length 2 \
	        --right-axis-label "Glucose trends" \
	        --right-axis 0.02:0 --right-axis-format %1.0lf \
		-c ARROW\#000000  --end now \
		${START:+--start $START}  ${XAXIS:+-x $XAXIS} \
		DEF:bgl=${RRDFILE}:bgl:AVERAGE \
		DEF:trend=${RRDFILE}:trend:AVERAGE \
		CDEF:bigt=${TREND} \
		\
		COMMENT:"${SP}" \
		LINE2:bgl${Bcolor:+\#$Bcolor}:" BGL average\t\t\t" \
		LINE1:bigt${mTcolor:+\#$mTcolor}:" Trend average\t" \
		COMMENT:"Trending Legend\:" \
		COMMENT:"\l" \
		\
		COMMENT:"${SP}" \
		GPRINT:bgl:MIN:"${TIMING} min\: %3.0lf\t\t\t" \
		GPRINT:trend:MIN:"${TIMING} min\: %1.0lf\t" \
		COMMENT:"\t1-3\: Trending lower" \
		COMMENT:"\l" \
		\
		COMMENT:"${SP}" \
		GPRINT:bgl:MAX:"${TIMING} max\: %3.0lf\t\t\t" \
		GPRINT:trend:MAX:"${TIMING} max\: %1.0lf\t" \
		COMMENT:"\t4\: Trending flat" \
		COMMENT:"\l" \
		\
		COMMENT:"${SP}" \
		GPRINT:bgl:AVERAGE:"${TIMING} avg\: %3.0lf\t\t\t" \
		GPRINT:trend:AVERAGE:"${TIMING} avg\: %1.0lf\t" \
		COMMENT:"\t5-7\: Trending higher" \
		COMMENT:"\l" \
		\
		${T5:+"$T5"} \
		${T6:+"$T6"} \
		${T7:+"$T7"} \
		${T8:+"$T8"} \
		COMMENT:"\l"
}

case ${CMD} in
	(debug)
		echo "RRDLIB=${RRDLIB}"
		echo "WEBROOT=${WEBROOT}"
		echo "RRDFILE=${RRDFILE}"
		echo "IMGNAME=${GRAPHNAME}"

		dex_update

		echo N=${Value}:${Trend}
		;;

        (force-create|create)
                if [ "${CMD}" == "force-create" -o ! -r ${RRDFILE} ];
                then
		rrdtool create ${RRDFILE} -s 60 \
		DS:bgl:GAUGE:180:0:450 \
		DS:trend:GAUGE:180:0:10 \
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
	        if [ 0 -eq $((TS % 300)) ]
	        then
			dex_update
			echo "${Value}:${Trend}" > "${bglcache}"
		else
			if [ -r "${bglcache}" ]
			then
				data=$(cat "${bglcache}")
				Value=${data%%:*}
				Trend=${data##*:}
			else
				Value=U
				Trend=U
			fi
	        fi

		rrdtool update ${RRDFILE} \
		N:${Value}:${Trend}
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
	(*)
		echo "Invalid option for ${PROGNAME}"
		echo "${PROG} (create|update|graph|debug)"
		exit 1
		;;
esac
