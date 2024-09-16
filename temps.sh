#!/bin/bash
#
# Reads temperatures from the /sys/[...]/  directories
#   AUTOTEMP will pull from /sys/devices/virtual/thermal/  on ARM systems
#     otherwise place the full path to the input in the TEMPx vars and disable AUTOTEMP
#


AUTOTEMP=1					;# This "mostly" works on arm and x86 systems
TEMP0="/sys/class/hwmon/hwmon0/temp1_input"	;# path to first temp probe
TEMP1=""					;# path to second temp probe
TEMP2=""					;# path to third temp probe

[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

# Force no rrd writing
DONTRRD=1

#####################
PUSER="${USER}"
PROG="${0##*/}"
PROGNAME=${PROG%%.*}
MYHOST="$(uname -n)"
MYHOST=${SERVERNAME:-$MYHOST}
DATE=$(date)
PATH=${PATH}:/sbin:/usr/sbin

CMD=${1}

RRDFILE="${RRDLIB:-.}/${MYHOST}-${PROGNAME}.rrd"
GRAPHBASE="${WEBROOT:-.}/${MYHOST}-${PROGNAME}.png"
IDX="${WEBROOT:-.}/${MYHOST}-${PROGNAME}.html"

declare -a STATS
declare -a ZONES

# Choose your colors here
PCOL=44FF44
TCOL=000ccc

poll() {
	STATS=()
	if [ ${AUTOTEMP:-0} -eq 1 ]
	then
		i=0
		for t in 0 1 2
		do
			if [ -r /sys/devices/virtual/thermal/thermal_zone${t}/temp ]
			then
				TEMP=$(cat /sys/devices/virtual/thermal/thermal_zone${t}/temp)
				ZONE=$(cat /sys/devices/virtual/thermal/thermal_zone${t}/type 2>/dev/null)
			elif [ -r /sys/class/hwmon/hwmon${t}/temp1_input ]
			then
				TEMP=$(cat /sys/class/hwmon/hwmon${t}/temp1_input 2>/dev/null)
				ZONE=$(cat /sys/class/hwmon/hwmon${t}/name)
				[[ "${ZONE}" = "nvme" ]] && ZONE=$(cd /sys/class/hwmon/hwmon${t}/device && pwd -P)
				ZONE=${ZONE##*/}
				if [ -n "${ZONE}" -a \( -z "${ZONE##*:*}" -o -z "${ZONE//[0-9-]/}" \) ]
				then
					# device entry instead of name, so use the old lookup
					ZONE=$(cat /sys/class/hwmon/hwmon${t}/name 2>/dev/null)
				fi
			else
				TEMP=""
				ZONE=""
			fi
			# zone name corrections
			ZONE=${ZONE//-thermal/}
			ZONE=${ZONE//_temp/}

			if [ -n "${TEMP}" ]
			then
				STATS[i]="temp=${TEMP}"
				ZONES[i]="${ZONE:-zone$i}"
			fi

			i=$((i + 1))
		done
	else
		if [ -n "${TEMP0}" -a -r "${TEMP0}" ]
		then
			TEMP=$(cat "${TEMP0}" 2>/dev/null)
			STATS[0]="temp=${TEMP:-U}"
			ZONE=$(cat "${TEMP0%/*}/name" 2>/dev/null)
			ZONES[0]="${ZONE:-zone0}"
		else
			STATS[0]="temp=U"
			ZONES[0]="${ZONE:-zone0}"
		fi
		if [ -n "${TEMP1}" -a -r "${TEMP1}" ]
		then
			TEMP=$(cat "${TEMP1}")
			STATS[1]="temp=${TEMP:-U}"
			ZONE=$(cat "${TEMP1%/*}/name" 2>/dev/null)
			ZONES[1]="${ZONE:-zone1}"
		else
			STATS[1]="temp=U"
			ZONES[1]="${ZONE:-zone1}"
		fi
		if [ -n "${TEMP2}" -a -r "${TEMP2}" ]
		then
			TEMP=$(cat "${TEMP2}")
			STATS[2]="temp=${TEMP:-U}"
			ZONE=$(cat "${TEMP2%/*}/name" 2>/dev/null)
			ZONES[2]="${ZONE:-zone2}"
		else
			STATS[2]="temp=U"
			ZONES[2]="${ZONE:-zone2}"
		fi
	fi

}

usage() {
	echo "Invalid option for ${PROGNAME}"
	echo "${PROG} (create|update|graph|graph-weekly|debug) <host>"
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

		for i in $(seq 0 ${#STATS[@]})
		do
			if [ -n "${STATS[$i]}" ]
			then
				TEMPS="${TEMPS}thermals,host=${MYHOST},zone=${ZONES[$i]} ${STATS[$i]} \n"
#				TEMPS="${TEMPS}environmental,host=${MYHOST}  ${STATS[$i]}\n"
				tt=${STATS[$i]}

				temp=${tt##*=};  zone=${tt%%=*}
				if [ -z "${temp##*U*}" ];
					then
						echo "no stats for zone ${zone}"
					else

					echo "TEMP(${ZONES[$i]})=${temp}"
				fi
			fi
		done

		if [ "${DONTRRD:-0}" != "1" ]
		then
			echo "Datastore RRD is enabled"
		else
			echo "Datastore RRD is disabled"
		fi
		if [ -n "${INFLUXURL}" ]
		then
			echo "Datastore InfluxDB is enabled"
			echo "would send to influx:"
			echo -e "${TEMPS}"
		fi
		if [ "${DONTRRD:-0}" = "1" -a -z "${INFLUXURL}" ]
		then
			echo "FATAL: No datastore is defined"
		fi
		;;

        force-create|create)
                if [ "${DONTRRD:-0}" != "1" ];
                then
                	echo "This module is for influxdb polling only"
                	false
                fi
		;;

	update)
		poll
		# thermal_zoneX=Y
		for i in $(seq 0 ${#STATS[@]})
		do
			if [ -n "${STATS[$i]}" ]
			then
				TEMPS="${TEMPS}thermals,host=${MYHOST},zone=${ZONES[$i]} ${STATS[$i]} \n"
			fi
		done

		if [ "${DONTRRD:-0}" = "1" -a -z "${INFLUXURL}" ]
		then
			echo "${PROG}:FATAL: No datastore defined"
			exit 1
		fi

		if [ -n "${INFLUXURL}" ]
		then
			status=$(curl -silent -I "${INFLUXURL//write*/}ping"|grep -i X-Influxdb-Version)
			if [ -z "${status}" ]
			then
				echo "${PROG}:FATAL: Can't connect to InfluxDB"
				exit 1
			fi
			# we could ping the url so try writing
			# we assume the URL already looks like http(s?)://host.name/write?db=foo&u=bar&p=baz
			# yes, the newline is required for each point written
			# we do not include the timestamp and let influx handle it as received.
			status=$(echo -e "${TEMPS}" | curl -silent -i "${INFLUXURL}" --data-binary @- )

			if [ -n "${status}" -a -n "${status##*204 No Content*}" ]
			then
				echo "${PROG}:FATAL: Can't write to InfluxDB"
				exit 1
			fi
		fi
		if [ "${DONTRRD:-0}" != "1" ]
		then
			echo "This module is for influxdb polling only"
			false
		fi
		;;

	graph*)	false
		;;
	reindex) false
		;;
	xport) false
		;;

	*)
		usage
		exit 1
		;;
esac
