#!/bin/sh

#Copyright © 2021 Eric Georgeaux (eric.georgeaux at gmail.com)

# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), 
# to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
# copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

script="sysinfo_MQTTtoHA"
version="1.0.0"

######################################
# Start of the configuration section #
######################################
# Connection to MQTT broker
mqtt_broker_ip="192.168.0.1"
#mqtt_broker_port=1883
#user="user"
#pwd="pwd"

# Topic for the JSON messages
mqtt_topic_prefix="computers"

# Discovery prefix for Home Assistant (defualt is homeassistant. See https://www.home-assistant.io/docs/mqtt/discovery/
discovery_prefix="homeassistant"
# If use_device=1, a device identifer is added in the discovery messages. The name of the device is built from the sub_topic above and the unique_id_suffix
# For instance: all sensors linked with a machine will be linked to the device "hostname_sysinfo_MQTTtoHA". It eases the integration in Home Assistant : by selected the device,
# in Home Assistant configuration, an entity card with all the sensors linked to the device si ready to be included in Lovelace interface.
use_device=1
# Name prefix of the sensors - Can be changed by argument -n "Other name"
name_prefix="Lab Computer"

# Default value for delay between messages (in seconds) - Can be overwritten by argument "-t nn"
update_rate=60
# Discovery messages are published by default (equivalent to argument "-d yes") - Can be changed by argument "-d no"
pub_discovery="yes"
# MQTT messages with system are published repeatidly by default (equivalent to argument "-r loop") - Can be changed by argument "-r once" or "-r no"
run_mode="loop"

####################################
# End of the configuration section #
####################################

# Arguments for mosquitto_pub calls
mosquittoArgs="`[ ! -z $mqtt_broker_ip ] && echo "-h $mqtt_broker_ip" || echo "-h localhost"` `[ ! -z $user ] && echo "-u $user -P $pwd"` `[ ! -z $port ] && echo "-p $port" || echo "-p 1883"`"

# Collect system information
collect_info() {
	#logger -t $script Collecting system information - Start
	#Hostname
	host=$(hostname)
	if [ -z "$host" ]; then
		echo "Hostname cannot be determined."
		exit
	fi
	# Model
	if [ -f /sys/firmware/devicetree/base/model ]; then
		model=$(cat /sys/firmware/devicetree/base/model)
	fi
	#Operating system
	if [ ! -z $(which hostnamectl) ]; then
		os=$(hostnamectl | grep "Operating System" | cut -d ' ' -f5-)
	elif [ ! -z $(which lsb_release) ]; then
		os=$(lsb_release -a | grep Description | cut -f2-)
	else
		os=$(uname -r)
	fi
	#Processor
	proc=$(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//')
	#Number of processors
	nproc=$(grep -c ^processor /proc/cpuinfo)
	# CPU load
	total_load=$(uptime | grep -o 'average: [0-9.,]*' | awk '{print $2}' | sed -e 's/.$//' | sed 's/,/./')
	cpu_load=$(echo "scale=1;100*$total_load/$nproc" | bc)
	#Memory usage
	memory=$(free -b | awk 'NR == 2  {print $0}' | awk  -F: '{print $2}' | awk '{printf "%2.1f", 100*$2/$1}' | sed s/,/./g)
	#Swap usage
	swap=$(free -b | awk 'NR == 3  {print $0}' | awk  -F: '{print $2}' | awk '{printf "%2.1f", 100*$2/$1}' | sed s/,/./g)
	#Disk size
	disk_size=$(df -Ph | grep /$ | awk '{ print $2;}' | sed s/%//g)
	#Disk usage
	disk_usage=$(df -Ph | grep /$ | awk '{ print $5;}' | sed s/%//g)
	#Uptime (seconds)
	uptime=$(cat /proc/uptime | cut -d ' ' -f 1)
	#Temperature
	temperature=$(echo "scale=1;$(cat /sys/class/thermal/thermal_zone0/temp)/1000" | bc)
	#IP address
	if [ ! -z "$(which ip)" ]; then
		ip=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
	elif [ ! -z "$(which ifconfig)" ]; then
		ip=$(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
	else
		ip="unknown"
	fi
	# Connection
	if [ ! -z "$(which iwgetid)" ]; then
		ssid=$(iwgetid -r)
		if [ ! -z "$ssid" ]; then
			connection="{\"type\":\"wireless\",\"ssid\":\"$ssid\"}"
		else
			connection="{\"type\":\"Ethernet\"}"
		fi
	else
		connection=''
	fi

	sysinfoMsg="{\"hostname\": \"$host\", \
\"os\": \"$os\", \
$([ ! -z "$model" ] && echo \"model\": \"$model\",) \
\"proc\": \"$proc\", \
\"nproc\": \"$nproc\", \
\"cpu_load\": \"$cpu_load\", \
\"disk_size\": \"$disk_size\", \
\"disk_usage\": \"$disk_usage\", \
\"memory\": \"$memory\" , \
\"swap\": \"$swap\" , \
\"uptime\": \"$uptime\", \
\"temperature\": \"$temperature\", \
$([ ! -z "$connection" ] && echo \"connection\": $connection,) \
\"ip\":\"$ip\" \
}"

	#logger -t $script Collecting system information - End
}


# Publish Home assistant MQTT discovery message
pubDiscoveryMessages() {
	logger -t $script Sending MQTT discovery messages
	if [ -z "$host" ]; then
		collect_info
	fi
	# Device
	local device="\\\"device\\\":{\\\"name\\\":\\\"$host\\\",\\\"identifiers\\\":\\\"${host}_${script}\\\",\\\"manufacturer\\\":\\\"$script\\\",\\\"sw_version\\\":\\\"$version\\\"}"

	if [ -z "$name_prefix" ]; then
		name_prefix="$host "
	fi

	# Hostname
	unique_id="${host}_hostname"
	name="$name_prefix Hostname"
	icon="mdi:lan-connect"
	template="{{value_json.hostname}}"
	topic="$discovery_prefix/sensor/$unique_id/config"
	msg="{\"name\":\"$name\",\"unique_id\":\"$unique_id\",\"icon\":\"$icon\",\"~\":\"$mqtt_topic_prefix/$host\",\"availability_topic\":\"~/status\",\"state_topic\":\"~\",\"value_template\":\"$template\"}"
	msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s/^(.*)[}]$/\1,$device}/"`
	#echo "Topic: $topic Message: $msg"
	cmd="mosquitto_pub $mosquittoArgs -r -t $topic -m '$msg'"
	eval "$cmd"

	# Operating system
	unique_id="${host}_os"
	name="$name_prefix OS"
	icon="mdi:linux"
	template="{{value_json.os}}"
	topic="$discovery_prefix/sensor/$unique_id/config"
	msg="{\"name\":\"$name\",\"unique_id\":\"$unique_id\",\"icon\":\"$icon\",\"~\":\"$mqtt_topic_prefix/$host\",\"availability_topic\":\"~/status\",\"state_topic\":\"~\",\"value_template\":\"$template\"}"
	msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s/^(.*)[}]$/\1,$device}/"`
	#echo "Topic: $topic Message: $msg"
	cmd="mosquitto_pub $mosquittoArgs -r -t $topic -m '$msg'"
	eval "$cmd"

	# Model
	if [ ! -z "$model" ]; then
		unique_id="${host}_model"
		name="$name_prefix Model"
		icon="mdi:raspberry-pi"
		template="{{value_json.model}}"
		topic="$discovery_prefix/sensor/$unique_id/config"
		msg="{\"name\":\"$name\",\"unique_id\":\"$unique_id\",\"icon\":\"$icon\",\"~\":\"$mqtt_topic_prefix/$host\",\"availability_topic\":\"~/status\",\"state_topic\":\"~\",\"value_template\":\"$template\"}"
		msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s/^(.*)[}]$/\1,$device}/"`
		#echo "Topic: $topic Message: $msg"
		cmd="mosquitto_pub $mosquittoArgs -r -t $topic -m '$msg'"
		eval "$cmd"
	fi

	# Processor
	unique_id="${host}_proc"
	name="$name_prefix Processor"
	icon="mdi:cpu-64-bit"
	template="{{value_json.proc}}"
	topic="$discovery_prefix/sensor/$unique_id/config"
	msg="{\"name\":\"$name\",\"unique_id\":\"$unique_id\",\"icon\":\"$icon\",\"~\":\"$mqtt_topic_prefix/$host\",\"availability_topic\":\"~/status\",\"state_topic\":\"~\",\"value_template\":\"$template\"}"
	msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s/^(.*)[}]$/\1,$device}/"`
	#echo "Topic: $topic Message: $msg"
	cmd="mosquitto_pub $mosquittoArgs -r -t $topic -m '$msg'"
	eval "$cmd"

	# Number of processors
	unique_id="${host}_nproc"
	name="$name_prefix Number of processor(s)"
	icon="mdi:cpu-64-bit"
	template="{{value_json.nproc}}"
	topic="$discovery_prefix/sensor/$unique_id/config"
	msg="{\"name\":\"$name\",\"unique_id\":\"$unique_id\",\"icon\":\"$icon\",\"~\":\"$mqtt_topic_prefix/$host\",\"availability_topic\":\"~/status\",\"state_topic\":\"~\",\"value_template\":\"$template\"}"
	msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s/^(.*)[}]$/\1,$device}/"`
	#echo "Topic: $topic Message: $msg"
	cmd="mosquitto_pub $mosquittoArgs -r -t $topic -m '$msg'"
	eval "$cmd"

	# CPU load
	unique_id="${host}_cpuload"
	name="$name_prefix CPU load"
	icon="mdi:gauge"
	template="{{value_json.cpu_load}}"
	topic="$discovery_prefix/sensor/$unique_id/config"
	msg="{\"name\":\"$name\",\"unique_id\":\"$unique_id\",\"icon\":\"$icon\",\"unit_of_measurement\":\"%\",\"~\":\"$mqtt_topic_prefix/$host\",\"availability_topic\":\"~/status\",\"state_topic\":\"~\",\"value_template\":\"$template\"}"
	msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s/^(.*)[}]$/\1,$device}/"`
	#echo "Topic: $topic Message: $msg"
	cmd="mosquitto_pub $mosquittoArgs -r -t $topic -m '$msg'"
	eval "$cmd"

	# Disk size
	unique_id="${host}_disksize"
	name="$name_prefix Disk size"
	icon="mdi:sd"
	template="{{value_json.disk_size}}"
	topic="$discovery_prefix/sensor/$unique_id/config"
	msg="{\"name\":\"$name\",\"unique_id\":\"$unique_id\",\"icon\":\"$icon\",\"~\":\"$mqtt_topic_prefix/$host\",\"availability_topic\":\"~/status\",\"state_topic\":\"~\",\"value_template\":\"$template\"}"
	msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s/^(.*)[}]$/\1,$device}/"`
	#echo "Topic: $topic Message: $msg"
	cmd="mosquitto_pub $mosquittoArgs -r -t $topic -m '$msg'"
	eval "$cmd"

	# Disk usage
	unique_id="${host}_diskusage"
	name="$name_prefix Disk usage"
	icon="mdi:gauge"
	template="{{value_json.disk_usage}}"
	topic="$discovery_prefix/sensor/$unique_id/config"
	msg="{\"name\":\"$name\",\"unique_id\":\"$unique_id\",\"icon\":\"$icon\",\"unit_of_measurement\":\"%\",\"~\":\"$mqtt_topic_prefix/$host\",\"availability_topic\":\"~/status\",\"state_topic\":\"~\",\"value_template\":\"$template\"}"
	msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s/^(.*)[}]$/\1,$device}/"`
	#echo "Topic: $topic Message: $msg"
	cmd="mosquitto_pub $mosquittoArgs -r -t $topic -m '$msg'"
	eval "$cmd"

	# Memory usage
	unique_id="${host}_memory"
	name="$name_prefix Memory usage"
	icon="mdi:gauge"
	template="{{value_json.memory}}"
	topic="$discovery_prefix/sensor/$unique_id/config"
	msg="{\"name\":\"$name\",\"unique_id\":\"$unique_id\",\"icon\":\"$icon\",\"unit_of_measurement\":\"%\",\"~\":\"$mqtt_topic_prefix/$host\",\"availability_topic\":\"~/status\",\"state_topic\":\"~\",\"value_template\":\"$template\"}"
	msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s/^(.*)[}]$/\1,$device}/"`
	#echo "Topic: $topic Message: $msg"
	cmd="mosquitto_pub $mosquittoArgs -r -t $topic -m '$msg'"
	eval "$cmd"

	# Swap usage
	unique_id="${host}_swap"
	name="$name_prefix Swap usage"
	icon="mdi:gauge"
	template="{{value_json.swap}}"
	topic="$discovery_prefix/sensor/$unique_id/config"
	msg="{\"name\":\"$name\",\"unique_id\":\"$unique_id\",\"icon\":\"$icon\",\"unit_of_measurement\":\"%\",\"~\":\"$mqtt_topic_prefix/$host\",\"availability_topic\":\"~/status\",\"state_topic\":\"~\",\"value_template\":\"$template\"}"
	msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s/^(.*)[}]$/\1,$device}/"`
	#echo "Topic: $topic Message: $msg"
	cmd="mosquitto_pub $mosquittoArgs -r -t $topic -m '$msg'"
	eval "$cmd"

	# Uptime
	unique_id="${host}_uptime"
	name="$name_prefix Uptime"
	icon="mdi:clock"
	template="{{timedelta(seconds=(value_json.uptime|int))}}"
	topic="$discovery_prefix/sensor/$unique_id/config"
	msg="{\"name\":\"$name\",\"unique_id\":\"$unique_id\",\"icon\":\"$icon\",\"~\":\"$mqtt_topic_prefix/$host\",\"availability_topic\":\"~/status\",\"state_topic\":\"~\",\"value_template\":\"$template\"}"
	msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s/^(.*)[}]$/\1,$device}/"`
	#echo "Topic: $topic Message: $msg"
	cmd="mosquitto_pub $mosquittoArgs -r -t $topic -m '$msg'"
	eval "$cmd"

	# Temperature
	unique_id="${host}_temperature"
	name="$name_prefix Temperature"
	icon="mdi:thermometer"
	template="{{value_json.temperature}}"
	topic="$discovery_prefix/sensor/$unique_id/config"
	msg="{\"name\":\"$name\",\"unique_id\":\"$unique_id\",\"icon\":\"$icon\",\"unit_of_measurement\":\"°C\",\"~\":\"$mqtt_topic_prefix/$host\",\"availability_topic\":\"~/status\",\"state_topic\":\"~\",\"value_template\":\"$template\"}"
	msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s/^(.*)[}]$/\1,$device}/"`
	#echo "Topic: $topic Message: $msg"
	cmd="mosquitto_pub $mosquittoArgs -r -t $topic -m '$msg'"
	eval "$cmd"

	# IP address
	unique_id="${host}_ipaddr"
	name="$name_prefix IP address"
	icon="mdi:ip-network-outline"
	template="{{value_json.ip}}"
	if [ -z "$connection" ]; then
		attr=''
	else
		attr=",\"json_attr_t\":\"~\",\"json_attr_tpl\":\"{{value_json.connection|tojson}}\""
	fi
	topic="$discovery_prefix/sensor/$unique_id/config"
	msg="{\"name\":\"$name\",\"unique_id\":\"$unique_id\",\"icon\":\"$icon\",\"~\":\"$mqtt_topic_prefix/$host\",\"availability_topic\":\"~/status\",\"state_topic\":\"~\",\"value_template\":\"$template\"$attr}"
	msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s/^(.*)[}]$/\1,$device}/"`
	#echo "Topic: $topic Message: $msg"
	cmd="mosquitto_pub $mosquittoArgs -r -t $topic -m '$msg'"
	eval "$cmd"

	#logger -t $script Sending MQTT discovery messages - End
}



# Usage
usage() {
    echo "Usage: $0 [-d <yes|no>] [-r <loop|once|no>] [-t rate_s] [-h]\n\n\
-d <yes|no>: MQTT Discovery messages are published (-d yes) or not pulbished (-d no)\n\
-r <once|loop|no>: MQTT message with system information \n\
   - is pulished once (-r once) before the script exits\n\
   - is published periodically (-r loop) in an endless loop \n\
   - is not published (-r no) \n\
-t rate_s: rate_s shall be a numeric value. It defines the periodicity of the publishing of MQTT messages with system infomation
-n name_prefix: the string name_prefix will be used for as prefix for the name the sensors. For instance -n 'Lab Computer' will 
                result of sensors in Home Assistant named 'Lab Computer Hostname', 'Lab Computer IP'...
                If name_prefix is not set, the hostname of the machine will be used.
-h display this help"  1>&2; exit 1;
}


# Called when SIGINT or EXIT signals are detected to change the status of the sensors in Home Assistant to unavailable
changeStatus() {
	logger -t $script Signal caught: set status to "offline" and exit
	mosquitto_pub $mosquittoArgs -r -t $mqtt_topic_prefix/$host/status -m "offline"
	exit
}

#logger -t $script Start
while getopts ":d:r:t:n:h" o; do
	case "${o}" in
        d)
		pub_discovery=$(echo ${OPTARG}| tr '[:upper:]' '[:lower:]')
		[ $pub_discovery != "yes" ] && [ $pub_discovery != "no" ] && usage
		;;
	r)
		run_mode=$(echo ${OPTARG}| tr '[:upper:]' '[:lower:]')
		[ $run_mode != "loop" ] && [ $run_mode != "once" ] && [ $run_mode != "no" ] && usage
		;;
	t)
		update_rate=${OPTARG}
		if [ -n "$update_rate" ] && [ "$update_rate" -eq "$update_rate" ] 2>/dev/null; then
			echo "Update rate: $update_rate seconds"
		else
			echo "Argument after -t shall be a number (update rate in seconds)"
			usage
		fi
		;;
	n)
		name_prefix=${OPTARG}
		;;
	h)
		usage
		;;
	:)
		echo "ERROR: Option -$OPTARG requires an argument"
		usage
		;;
	\?)
		echo "ERROR: Invalid option -$OPTARG"
		usage
		;;
	esac
done
shift $((OPTIND-1))

#echo "Discovery: $pubDiscovery - run Mode: $runMode"

logger -t $script Starting with args: discovery: $pub_discovery  run: $run_mode update rate: $update_rate


if [ "$pub_discovery" = "yes" ]; then
	pubDiscoveryMessages
fi
if [ "$run_mode" = "no" ]; then
	exit
elif [ "$run_mode" = "once" ]; then
	if [ -z "$sysinfoMsg" ]; then
		collect_info
	fi
	mosquitto_pub $mosquittoArgs -r -t $mqtt_topic_prefix/$host/status -m "online"
	cmd="mosquitto_pub $mosquittoArgs -t $mqtt_topic_prefix/$host -m '$sysinfoMsg'"
	eval "$cmd"
else # $run_mode="loop"
	# trap script termination to update the status to "offline"
	trap changeStatus INT TERM KILL
	while true; do
		collect_info
		mosquitto_pub $mosquittoArgs -r -t $mqtt_topic_prefix/$host/status -m "online"
		cmd="mosquitto_pub $mosquittoArgs -t $mqtt_topic_prefix/$host -m '$sysinfoMsg'"
		eval "$cmd"
		sleep $update_rate
	done
fi
