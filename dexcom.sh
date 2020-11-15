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

# Values are in seconds, for  "--end now --start end-${DATE}"
# yesterday, plus 4 hours
YESTERDAY=90000
# last week, plus a 6h
LASTWEEK=648000
# last month, plus a week
LASTMONTH=3234543
# last year, plus a month
LASTYEAR=34819200

# Dexcom only updates every 5 minutes, so we use this to cache data except on the 5-minute mark
HOUR=$(date +"%-H")	# we don't want zero-padded
MIN=$(date +"%-M")	# ^^^
TS=$(( ($HOUR * 3600) + ($MIN * 60) ))

#####################
PUSER="${USER}"
PROG="${0##*/}"
MYHOST="$(uname -n)"
PROGNAME=${PROG%%.*}
CMD="$1"
DATE=$(date)

# We invert the trends, since that data looks better on the graphs
#          0         1           2             3            4           5            6           7             8              9
# Orig=( 'None' 'DoubleUp'   'SingleUp'   'FortyFiveUp'   'Flat'  'FortyFiveDown' 'SingleDown' 'DoubleDown' 'NotComputable' 'OutOfRange' )
Trends=( 'None' 'DoubleDown' 'SingleDown' 'FortyFiveDown' 'Flat'  'FortyFiveUp'   'SingleUp'   'DoubleUp'   'NotComputable' 'OutOfRange' )

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

	if [ -z "${result}" -o -n "${result##*Trend*Value*}" ]
	then
		# looks invalid, so refresh the cache
		sess_update
		if [ -z "${session}" ]
		then
			# don't know why, but refreshing the session didn't work
			Value=U
			Trend=U
			return
		else
			# save the session, because now it's valid!
			echo "${session}" > "${scache}"
		fi
		get_data
	fi
	# if we get here, the session is valid, whether new or old
	# so we parse the JSON data... horrible code follows:
	WT=${result##*,}; WT=${WT##*\(}; WT=${WT%%\)*}
	DT=${result%%,*}; DT=${DT##*\(}; DT=${DT%%\)*}
	result="\"ST${result##*ST}"
	result=${result%%,\"WT*}
	ST=${result%%,\"Tren*}; ST=${ST##*\(}; ST=${ST%%\)*}
	Value=${result##*,\"Value\":}
	result=${result%%,\"Value*}
	Trend=${result##*Trend\":}

	if [ $Trend -lt 8 -a $Trend -gt 0 ]
	then
		# invert for better visualization of the trends, leaving 0 and 8-9 alone
		Trend=$(( 8 - Trend ))
	fi

	# the formula for converting:
	#    int(json_glucose_reading["WT"][6:][:-2]) / 1000.0
	#    WT=${WT%%+*}; WT=$((WT/1000)); WT=$(date --date="@${WT}")
	#    DT=${DT%%+*}; DT=$((DT/1000)); DT=$(date --date="@${DT}")
	#    ST=${ST%%+*}; ST=$((ST/1000)); ST=$(date --date="@${ST}")
		
	# This is just for debugging:
	#    echo "WT=$WT,  Value=${Value}, Trend=${Trend} == ${Trends[$Trend]}"

}

case ${CMD} in
	(debug)
		echo "RRDLIB=${RRDLIB}"
		echo "WEBROOT=${WEBROOT}"
		echo "RRDFILE=${RRDFILE}"
		echo "GRAPHNAME=${GRAPHNAME}"

		dex_update

		echo N=${Value}:${Trend}
		;;

        (force-create|create)
                if [ "${CMD}" == "force-create" -o ! -r ${RRDFILE} ];
                then
		rrdtool create ${RRDFILE} -s 60 \
		DS:bgl:GAUGE:180:0:U \
		DS:trend:GAUGE:180:0:U \
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

	(graph)
	    rrdtool graph ${GRAPHNAME} \
		-Y -u 1.1 -l 0 -L 2 -v "Blood-Glucose level" -w 700 -h 300 -t "${dexcom_username} last 24 hours Blood-Glucose level - ${DATE}" \
		-c ARROW\#000000 -x MINUTE:30:MINUTE:30:HOUR:1:0:%H \
		DEF:bgl=${RRDFILE}:bgl:AVERAGE \
		DEF:trend=${RRDFILE}:trend:AVERAGE \
		COMMENT:"\t" \
		LINE1:bgl\#${Bcolor}:" BGL average\t\t\t" \
		LINE2:trend\#${Tcolor}:" Trend average\t" \
		COMMENT:"Trending Legend\:" \
		COMMENT:"\l" \
		COMMENT:"\t" \
		GPRINT:bgl:MIN:"  1 min min\: %3.0lf\t\t" \
		GPRINT:trend:MIN:"  1 min min\: %1.0lf\t\t" \
		COMMENT:"1-3\: Trending lower" \
		COMMENT:"\l" \
		COMMENT:"\t" \
		GPRINT:bgl:MAX:"  1 min max\: %3.0lf\t\t" \
		GPRINT:trend:MAX:"  1 min max\: %1.0lf\t\t" \
		COMMENT:"4\: Trending flat" \
		COMMENT:"\l" \
		COMMENT:"\t" \
		GPRINT:bgl:AVERAGE:"  1 min avg\: %3.0lf\t\t" \
		GPRINT:trend:AVERAGE:"  1 min avg\: %1.0lf\t\t" \
		COMMENT:"5-7\: Trending higher" \
		COMMENT:"\l" \
		COMMENT:"\t" \
		GPRINT:bgl:LAST:"    current\: %3.0lf\t\t" \
		GPRINT:trend:LAST:"    current\: %1.0lf\t" \
		COMMENT:"\l"
		;;
	(graph-weekly)
	    rrdtool graph ${GRAPHNAME//.png/-week.png} \
		-Y -u 1.1 -l 0 -L 2 -v "Blood-Glucose level" -w 700 -h 300 -t "${dexcom_username} last 7 days Blood-Glucose level - ${DATE}" \
                --end now --start end-$LASTWEEK -c ARROW\#000000  \
		DEF:bgl=${RRDFILE}:bgl:AVERAGE \
		DEF:trend=${RRDFILE}:trend:AVERAGE \
		COMMENT:"\t\t" \
		LINE1:bgl\#${Bcolor}:" BGL average\t\t\t" \
		LINE2:trend\#${Tcolor}:" Trend average\t" \
		COMMENT:"\l" \
		COMMENT:"\t\t" \
		GPRINT:bgl:MIN:"  5 min min\: %3.0lf\t\t" \
		GPRINT:trend:MIN:"  5 min min\: %1.0lf\t" \
		COMMENT:"\l" \
		COMMENT:"\t\t" \
		GPRINT:bgl:MAX:"  5 min max\: %3.0lf\t\t" \
		GPRINT:trend:MAX:"  5 min max\: %1.0lf\t" \
		COMMENT:"\l" \
		COMMENT:"\t\t" \
		GPRINT:bgl:AVERAGE:"  5 min avg\: %3.0lf\t\t" \
		GPRINT:trend:AVERAGE:"  5 min avg\: %1.0lf\t" \
		COMMENT:"\l"
		;;
	(graph-monthly)
	    rrdtool graph ${GRAPHNAME//.png/-month.png} \
		-Y -u 1.1 -l 0 -L 2 -v "Blood-Glucose level" -w 700 -h 300 -t "${dexcom_username} last month's Blood-Glucose level - ${DATE}" \
                --end now --start end-$LASTMONTH -c ARROW\#000000  \
		DEF:bgl=${RRDFILE}:bgl:AVERAGE \
		DEF:trend=${RRDFILE}:trend:AVERAGE \
		COMMENT:"\t\t" \
		LINE1:bgl\#${Bcolor}:" BGL average\t\t\t" \
		LINE2:trend\#${Tcolor}:" Trend average\t" \
		COMMENT:"\l" \
		COMMENT:"\t\t" \
		GPRINT:bgl:MIN:" 30 min min\: %3.0lf\t\t" \
		GPRINT:trend:MIN:" 30 min min\: %1.0lf\t" \
		COMMENT:"\l" \
		COMMENT:"\t\t" \
		GPRINT:bgl:MAX:" 30 min max\: %3.0lf\t\t" \
		GPRINT:trend:MAX:" 30 min max\: %1.0lf\t" \
		COMMENT:"\l" \
		COMMENT:"\t\t" \
		GPRINT:bgl:AVERAGE:" 30 min avg\: %3.0lf\t\t" \
		GPRINT:trend:AVERAGE:" 30 min avg\: %1.0lf\t" \
		COMMENT:"\l"
		;;
	(graph-yearly)
	    rrdtool graph ${GRAPHNAME//.png/-year.png} \
		-Y -u 1.1 -l 0 -L 2 -v "Blood-Glucose level" -w 700 -h 300 -t "${dexcom_username} last year's Blood-Glucose level - ${DATE}" \
                --end now --start end-$LASTYEAR -c ARROW\#000000  \
		DEF:bgl=${RRDFILE}:bgl:AVERAGE \
		DEF:trend=${RRDFILE}:trend:AVERAGE \
		COMMENT:"\t\t" \
		LINE1:bgl\#${Bcolor}:" BGL average\t\t\t" \
		LINE2:trend\#${Tcolor}:" Trend average\t" \
		COMMENT:"\l" \
		COMMENT:"\t\t" \
		GPRINT:bgl:MIN:" 2h min\: %3.0lf\t\t\t" \
		GPRINT:trend:MIN:" 2h min\: %1.0lf\t" \
		COMMENT:"\l" \
		COMMENT:"\t\t" \
		GPRINT:bgl:MAX:" 2h max\: %3.0lf\t\t\t" \
		GPRINT:trend:MAX:" 2h max\: %1.0lf\t" \
		COMMENT:"\l" \
		COMMENT:"\t\t" \
		GPRINT:bgl:AVERAGE:" 2h avg\: %3.0lf\t\t\t" \
		GPRINT:trend:AVERAGE:" 2h avg\: %1.0lf\t" \
		COMMENT:"\l"
		;;
	(*)
		echo "Invalid option for ${PROGNAME}"
		echo "${PROG} (create|update|graph|debug)"
		exit 1
		;;
esac
