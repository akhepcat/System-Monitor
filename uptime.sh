#!/bin/bash
[[ -r "/etc/default/sysmon.conf" ]] && source /etc/default/sysmon.conf

#####################
PUSER="${USER}"
PROG="${0##*/}"
PROGNAME=${PROG%%.*}
MYHOST="$(uname -n)"
MYHOST=${SERVERNAME:-$MYHOST}
CMD="$1"
GRAPHNAME="${WEBROOT:-.}/${MYHOST}-uptime.gif"

poll() {
	startup=$(date --date="$(uptime -s)" '+%s')
	now=$(date '+%s')
	uptime=$((now - startup))
	uptimestr=$(uptime -s)
}

case ${CMD} in
	(debug)
		poll
		echo "WEBROOT=${WEBROOT}"
		echo "GRAPHNAME=${GRAPHNAME}"
		echo "UPTIME=${uptime}"
		;;
	(update|graph|graph-weekly|graph-monthly|graph-yearly)
		poll
		if [ "${DONTRRD:-0}" != "1" ]
		then
			if [ -n "$(which convert)" ]
			then
				echo "$uptimestr" | convert -size 640x20 -font Liberation-Sans -pointsize 18 -unsharp 0x.5 -background none -trim +repage -fill black text:- ${GRAPHNAME}
			elif [ -n "$(which pbmtext)" ]
			then
				echo "$uptimestr" | pbmtext | pnmcrop | pnmpad -white -left 2 -right 2 -top 2 -bottom 2 | pnmtopng > ${GRAPHNAME}
			else
				> ${GRAPHNAME}
				echo "no ImageMagick or NetPBM installed, can't convert uptime to png"
			fi
		else
			# use Influx
			DATA="system,host=${MYHOST} uptime=${uptime}\n"
			if [ -z "${INFLUXURL}" ]
			then
				echo "FATAL: No datastore is defined"
				exit
			fi
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
			status=$(echo -e "${DATA}" | curl -silent -i "${INFLUXURL}" --data-binary @- )

			if [ -n "${status}" -a -n "${status##*204 No Content*}" ]
			then
				echo "${PROG}:FATAL: Can't write to InfluxDB"
				exit 1
			fi
		fi

		;;
	(force-create|create)
		;;
	(*)
		echo "Invalid option for ${PROGNAME}"
		echo "${PROG} (update|graph|debug)"
		exit 1
		;;
esac
exit 0
