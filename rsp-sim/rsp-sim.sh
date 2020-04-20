#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause 
#

# Set the number of RSPs to simulate
if [ "$#" -lt 1 ]; then
    echo
    echo "This script simulates the API messages between the specified number of"
    echo "Intel RFID Sensor Platforms (RSP) and the Intel RSP SW Toolkit - RSP Controller."
    echo
    echo "Usage: rsp-sim.sh <count> [read_percent]"
    echo "where <count> is the number of RSP's to simulate."
    echo "where [read_percent] is the optional percent (1-100) of tag population to be read per inventory_data packet (500 ms). default: 100"
    echo
    echo "This script depends on the mosquitto-clients package being installed."
    echo "Run 'sudo apt install mosquitto-clients' to install."
    echo
    echo "NOTE: The Intel RSP SW Toolkit - RSP Controller must be running BEFORE"
    echo "      attempting to execute this script."
    echo
    exit 1
fi

MAX_RSPS=99
RSPS=$1
if [ $RSPS -gt $MAX_RSPS ]; then
    echo "$RSPS exceeds max allowed."
    echo "Setting RSP count to five."
    RSPS=5
fi

READ_PERCENT=$2
if [ -z $READ_PERCENT ] || [ $READ_PERCENT -gt 100 ]; then
    echo "Setting READ_PERCENT to 100."
    READ_PERCENT=100
fi

millis () {
    echo "$(($(date +%s%N)/1000000))"
}

# Customizable options
QUIET=${QUIET:-0}
DEBUG=${DEBUG:-0}
QOS=${QOS:-1}
COLOR=${COLOR:-1}
STYLE=${STYLE:-1}
DATE_FORMAT=${DATE_FORMAT:-}
RSP_CONTROLLER_IP="${RSP_CONTROLLER_IP:-127.0.0.1}"
MAX_DEBUG_BYTES=${MAX_DEBUG_BYTES:-2048}
ALWAYS_TRUE=${ALWAYS_TRUE:-0}
IN_RESET_SECONDS=${IN_RESET_SECONDS:-15}
REBOOT_SECONDS=${REBOOT_SECONDS:-60}
# By default auto-detect mqtt broker and port from the rsp controller
MQTT_BROKER=${MQTT_BROKER:-}
MQTT_PORT=${MQTT_PORT:-}

# rsp file array
DEVICE_ID_INDEX=0
FACILITY_ID_INDEX=1
READ_STATE_INDEX=2
TOKEN_INDEX=3
REGION_INDEX=4
STATUS_INDEX=5

DEFAULT_REGION="USA"
DEFAULT_TOKEN="D544DF3F42EA86BED3C3D15FC321B8E949D666C06B008C6357580BC3816E00DE"
ROOT_CERT_URL="http://$RSP_CONTROLLER_IP:8080/provision/root-ca-cert"
MQTT_CRED_URL="https://$RSP_CONTROLLER_IP:8443/provision/sensor-credentials"
HOST_BASE=150000
RSP_FILE_BASE="rsp_"
TAG_FILE_BASE="tags_in_view_of_rsp_"
START_TIME=$(millis)
AMBI_TEMP=30
RFID_TEMP=70
HCPU_TEMP=100
CPU_USAGE=25
MEM_USAGE=25
MEM_TOTAL=1017576
RfModuleError=100
HighAmbientTemp=101
HighCpuTemp=102
HighCpuUsage=103
HighMemoryUsage=104
DeviceMoved=151

# Check for the existence of flock command and if so if the --no-fork option is supported
FLOCK_AVAILABLE=$(type -P flock)
FLOCK_ARGS=""
if [ $FLOCK_AVAILABLE ] && [ ! -z "$(flock --help | grep -e '--no-fork')" ]; then
    FLOCK_ARGS="--no-fork"
fi

# Create a lookup map of RSP colors for logging: map[device_id] = color
declare -A rsp_colors

# Only define colors if COLOR is enabled (1)
if [ $COLOR -eq 1 ]; then
    # clear resets color and style back to defaults
    clear="\e[0m"
    # no_color clears the foreground color
    no_color="\e[39m"
    # normal colors
    red="\e[31m"; green="\e[32m"; yellow="\e[33m"; blue="\e[34m"; magenta="\e[35m"; cyan="\e[36m"
    # light colors
    lt_red="\e[91m"; lt_green="\e[92m"; lt_yellow="\e[93m"; lt_blue="\e[94m"; lt_magenta="\e[95m"; lt_cyan="\e[96m"
fi

# Only define styles if STYLE is enabled (1):wq
if [ $STYLE -eq 1 ]; then
    # clear resets color and style back to defaults
    clear="\e[0m"
    # normal clears dim, bold, and underline
    normal="\e[22;24m"
    # styles
    dim="\e[2m"; bold="\e[1m"; uline="\e[4m"
fi

#
# Define all the functions up front
#

# This will cleanly shutdown the simulators and send rsp_status of shutting_down
clean_shutdown () {
    trap - INT
    printf "\n${lt_red}${bold}Shutting down simulated RSPs...${clear}\n"

    # This loop sends shutting_down rsp_status for each rsp and if the sensor
    # is in the STARTED state it will send an inventory_complete and set the state to STOPPED
    index=0
    while [ $index -lt $RSPS ]; do
        shutdown_rsp $index
        let index=index+1
    done

    exit 0
}

# Function outputs date in specified format for logging purposes
pretty_date() {
    if [ ! -z $DATE_FORMAT ]; then
      echo "$(date $DATE_FORMAT)"
    else
      echo "$(date +%X) | $(millis)"
    fi
}

# Function takes topic and message string as arguments
publish () {
    log_debug "[publish] topic: $1, msg: $2"
    mosquitto_pub -q $QOS -h $MQTT_BROKER -p $MQTT_PORT -t "$1" -m "$2"
    err_code=$?
    if [ ${err_code} -ne 0 ]; then
        log_error "Unable to publish to topic $1. Error code: ${err_code}"
    fi
}

# Function takes topic and filename as arguments
publish_file () {
    local bytes=$(wc --bytes < "$2")
    # only display the raw message if it is smaller than the MAX_DEBUG_BYTES or MAX_DEBUG_BYTES=-1
    local raw_msg=$(if [ $MAX_DEBUG_BYTES -lt 0 ] || [ $bytes -le $MAX_DEBUG_BYTES ]; then echo ", msg: $(cat $2)"; fi)
    log_debug "[publish] topic: $1, len: ${bytes} bytes${raw_msg}"
    mosquitto_pub -q $QOS -h $MQTT_BROKER -p $MQTT_PORT -t "$1" -f "$2"
    err_code=$?
    if [ ${err_code} -ne 0 ]; then
        log_error "Unable to publish to topic $1. Error code: ${err_code}"
    fi
}

# Function takes debug message as argument
log_debug () {
    if [ $QUIET -ne 1 ] && [ $DEBUG -eq 1 ]; then
        printf "${dim}[$(pretty_date)] [DEBUG] %s${clear}\n" "$1"
    fi
}

# Function takes device_id and message as argument
log_rsp_warning () {
    if [ $QUIET -ne 1 ]; then
        printf "${dim}[$(pretty_date)]${normal} ${bold}${rsp_colors[$1]}%s${clear} ${yellow}[WARNING] %s${clear}\n" "$1" "$2"
    fi
}

# Function takes device_id and message as argument
log_rsp_error () {
    if [ $QUIET -ne 1 ]; then
        printf "${dim}[$(pretty_date)]${normal} ${bold}${rsp_colors[$1]}%s${clear} ${red}[ERROR] %s${clear}\n" "$1" "$2"
    fi
}

# Function takes message as argument
log_error () {
    if [ $QUIET -ne 1 ]; then
        printf "${dim}[$(pretty_date)]${normal} ${red}[ERROR] %s${clear}\n" "$1"
    fi
}

# Function takes device_id, jsonrpc id, jsonrpc method and optional extra message as arguments
log_send_response () {
    if [ $QUIET -ne 1 ]; then
        local message="${4}"
        printf "${dim}[$(pretty_date)]${normal} ${bold}${rsp_colors[$1]}%s${clear} %-10.10s ${bold}--->>${normal} ${uline}%-20s${normal} ${dim}| ${lt_green}response${no_color}\t| ${message}${clear}\n" "$1" "id: $2" "$3"
    fi
}

# Function takes device_id, jsonrpc method and optional extra message as arguments
log_send_msg () {
    if [ $QUIET -ne 1 ]; then
        local message="$3"
        printf "${dim}[$(pretty_date)]${normal} ${bold}${rsp_colors[$1]}%s${clear} %-10.10s ${dim}--->>${normal} ${uline}%-20s${normal} ${dim}| ${message}${clear}\n" "$1" " " "$2"
    fi
}

# Function takes device_id, jsonrpc id, jsonrpc method and request message as arguments
log_receive_msg () {
    if [ $QUIET -ne 1 ]; then
        local bytes="${lt_blue}$(wc --bytes <<< "$4") bytes"
        printf "${dim}[$(pretty_date)]${normal} ${bold}${rsp_colors[$1]}%s${clear} ${bold}<<---${normal} %10.10s ${uline}%-20s${normal} ${dim}| ${lt_blue}request${no_color}\t| ${bytes}${clear}\n" "$1" "id: $2" "$3"
    fi
}

# Function takes device_id and token as arguments
get_mqtt_credentials () {
    echo "$1 requesting mqtt credentials from $MQTT_CRED_URL"
    RAW=$(curl --insecure --progress-bar --header "Content-type: application/json" --request POST --data '{"username":"'$1'","token":"'$2'","generatedTimestamp":'$(millis)',"expirationTimestamp":-1}' $MQTT_CRED_URL)
    if [ "$RAW" = "" ]; then
        echo "Cannot access MQTT Credentials REST endpoint!"
        exit 1
    fi
    log_debug "[response] $RAW"
    IFS='/' read -ra ARRAY <<< "$RAW"
    RAW=${ARRAY[2]}
    IFS=':' read -ra ARRAY <<< "$RAW"
    if [ -z "${MQTT_BROKER}" ]; then
        MQTT_BROKER=${ARRAY[0]}
    fi
    if [ -z "${MQTT_PORT}" ]; then
        IFS='"' read -ra ARRAY <<< "${ARRAY[1]}"
        MQTT_PORT=${ARRAY[0]}
    fi
    log_debug "Using MQTT broker: tcp://${MQTT_BROKER}:${MQTT_PORT}"
}

# Function takes device_id and rsp index as arguments
send_connect_request () {
    log_send_msg "$1" "connect"
    publish "rfid/rsp/connect" '{"jsonrpc":"2.0","id":"1","method":"connect","params":{"hostname":"'$1'","hwaddress":"98:4f:ee:15:00:'$2'","app_version":"19.7.sim","module_version":"none","num_physical_ports":2,"motion_sensor":true,"camera":false,"wireless":false,"configuration_state":"unknown","operational_state":"unknown"}}'
}

# Function takes device_id, facility_id, status, and rsp index as arguments
send_status_indication () {
    local status="$3"
    local index=$4
    set_rsp_field $index $STATUS_INDEX $status

    local color=""
    if [ "$status" == "ready" ]; then
        color="${normal}${lt_green}";
    elif [ "$status" == "in_reset" ]; then
        color="${normal}${lt_red}"
    elif [ "$status" == "shutting_down" ]; then
        color="${normal}${lt_red}"
    fi

    log_send_msg "$1" "status_update" "${color}${status}"
    publish "rfid/rsp/rsp_status/$1" '{"jsonrpc":"2.0","method":"status_update","params":{"sent_on":'$(millis)',"device_id":"'$1'","facility_id":"'$2'","status":"'$status'"}}'
}

# Function takes device_id and facility_id as arguments
send_heartbeat_indication () {
    log_send_msg "$1" "heartbeat"
    publish "rfid/rsp/rsp_status/$1" '{"jsonrpc":"2.0","method":"heartbeat","params":{"sent_on":'$(millis)',"device_id":"'$1'","facility_id":"'$2'","location":null,"video_url":null}}'
}

# Function takes device_id, facility_id, alert_number, alert_description, serverity and optional as arguments
send_device_alert_indication () {
    log_send_msg "$1" "device_alert"
    publish "rfid/rsp/rsp_status/$1" '{"jsonrpc":"2.0","method":"device_alert","params":{"sent_on":'$(millis)',"device_id":"'$1'","facility_id":"'$2'","alert_number":'$3',"alert_description":"'$4'","severity":"'$5'","optional":'$6'}}'
}

# Function takes device_id and facility_id as arguments
send_inventory_complete_indication () {
    log_send_msg "$1" "inventory_complete"
    publish "rfid/rsp/rsp_status/$1" '{"jsonrpc":"2.0","method":"inventory_complete","params":{"sent_on":'$(millis)',"device_id":"'$1'","facility_id":"'$2'"}}'
}

# Function takes device_id, facility_id, tag count and tagdata as arguments
# tagdata is an array of json epc read objects without the beginning and ending [ ]
# example: {"epc":"1234ABC","tid":null,"antenna_id":0,"last_read_on":123456,"rssi":-654,"phase":32,"frequency":915250},{...},{...}
send_inventory_data_indication () {
    log_send_msg "$1" "inventory_data" "${lt_cyan}$3 tags${no_color}\t| ${lt_cyan}$2"
    # tag data may be too large to pass over command line and should be stored in a temp file
    tmpfile=$(mktemp)
    echo -n '{"jsonrpc":"2.0","method":"inventory_data","params":{"sent_on":'$(millis)',"period":500,"device_id":"'$1'","facility_id":"'$2'","location":null,"motion_detected":true,"data":['$4']}}' > $tmpfile
    publish_file "rfid/rsp/data/$1" "$tmpfile"
    rm -f $tmpfile
}

# Function takes device_id, request id, request method, and result json value
send_command_response () {
    local device_id=$1
    local request_id=$2
    local method=$3
    local result=$4

    local message="$(if [ "$result" == "true" ]; then echo "${lt_green}true"; else echo "${lt_green}$(wc --bytes <<< "$result") bytes"; fi)"
    log_send_response "$device_id" "$request_id" "$method" "$message"
    publish "rfid/rsp/response/$device_id" '{"jsonrpc":"2.0","result":'$result',"id":"'$request_id'"}'
}

# Function takes device_id, request id, and request method as arguments
send_bist_results_response () {
    send_command_response "$@" '{"rf_module_error":false,"rf_status_code":0,"rf_module_temp":'$RFID_TEMP',"ambient_temp":'$AMBI_TEMP',"time_alive":'$(($(millis) - $START_TIME))',"cpu_usage":'$CPU_USAGE',"mem_used_percent":'$MEM_USAGE',"mem_total_bytes":'$MEM_TOTAL',"camera_installed":false,"temp_sensor_installed":true,"accelerometer_installed":true,"region":"USA","rf_port_statuses":[{"port":0,"forward_power_dbm10":280,"reverse_power_dbm10":0,"connected":true},{"port":0,"forward_power_dbm10":280,"reverse_power_dbm10":0,"connected":true}],"device_moved":false}'
}

# Function takes device_id, request id and request method as arguments
send_sw_version_response () {
    send_command_response "$@" '{"app_version":"19.7.sim","module_version":"none"}'
}

# Function takes device_id, request id, request method, and device index as arguments
send_state_response () {
    mac=$(printf "98:4f:ee:15:00:%02d" $4)
    send_command_response "$1" "$2" "$3" '{"device_id":"'$1'","hwaddress":"'$mac'","app_version":"19.7.sim","module_version":"none","num_physical_ports":2,"motion_sensor":true,"camera":false,"wireless":false,"configuration_state":"unknown","operational_state":"unknown"}'
}

# Function takes rsp index as an argument
wait_for_connect_response () {
    index=$1
    eval "$(rsp_array ${index})"

    MSG=$(mosquitto_sub -h $MQTT_BROKER -p $MQTT_PORT -t rfid/rsp/connect/${rsp[$DEVICE_ID_INDEX]} -C 1 -q $QOS)
    log_debug "[receive] topic: rfid/rsp/connect/${rsp[$DEVICE_ID_INDEX]}, msg: $MSG"
    # Split the message into individual parameters
    IFS=',' read -ra SP1 <<< "$MSG"
    # Parse out the facility_id
    IFS=':' read -ra SP2 <<< "${SP1[2]}"
    FACID="${SP2[2]}"
    FACID="${FACID%\"}"
    FACID="${FACID#\"}"
    # and store it in the rsp array
    set_rsp_field $index $FACILITY_ID_INDEX $FACID
}

# Function takes rsp index as an argument
wait_for_command () {
    index=$1

    # Loop forever
    while true; do
        eval "$(rsp_array ${index})"
        # Wait for the MQTT command (block)
        CMD=$(mosquitto_sub -h $MQTT_BROKER -p $MQTT_PORT -t rfid/rsp/command/${rsp[$DEVICE_ID_INDEX]} -C 1 -q $QOS)
        err_code=$?
        if [ ${err_code} -ne 0 ]; then
            log_rsp_error "${rsp[$DEVICE_ID_INDEX]}" "Unable to subscribe to mqtt broker at tcp://${MQTT_BROKER}:${MQTT_PORT}. Error code: ${err_code}"
            # wait a bit before trying again
            sleep 1
        elif [ -z "$CMD" ]; then
            log_rsp_warning "${rsp[$DEVICE_ID_INDEX]}" "Received empty mqtt message, ignoring!"
        else
            log_debug "[receive] topic: rfid/rsp/command/${rsp[$DEVICE_ID_INDEX]}, msg: $CMD"
            process_command $index $CMD &
        fi
    done
}

# Function takes rsp index as an argument
shutdown_rsp () {
    local index=$1
    eval "$(rsp_array ${index})"

    # Stop any currently running read cycles
    if [ "${rsp[$READ_STATE_INDEX]}" == "STARTED" ]; then
        send_inventory_complete_indication ${rsp[$DEVICE_ID_INDEX]} ${rsp[$FACILITY_ID_INDEX]}
        set_rsp_field $index $READ_STATE_INDEX "STOPPED"
    fi

    # Let RSP Controller know we are shutting down
    send_status_indication ${rsp[$DEVICE_ID_INDEX]} ${rsp[$FACILITY_ID_INDEX]} "shutting_down" $index
}

# Function takes rsp index as an argument
connect_rsp() {
    local index=$1
    eval "$(rsp_array ${index})"

    get_mqtt_credentials ${rsp[$DEVICE_ID_INDEX]} ${rsp[$TOKEN_INDEX]}
    if [ "$MQTT_BROKER" = "" ]; then
        echo "Invalid MQTT Broker address!"
        exit 1
    fi

    wait_for_connect_response $index &
    send_connect_request ${rsp[$DEVICE_ID_INDEX]} $index
    send_status_indication ${rsp[$DEVICE_ID_INDEX]} ${rsp[$FACILITY_ID_INDEX]} "ready" $index
}

# Function takes rsp index and command as arguments
process_command () {
    index=$1
    eval "$(rsp_array ${index})"

    # todo: some messages should return WRONG_STATE when status is "in_reset"
    if [ "${rsp[$STATUS_INDEX]}" == "shutting_down" ]; then
        log_rsp_warning "${rsp[$DEVICE_ID_INDEX]}" "RSP is in simulated shutdown state. Ignoring message!"
        return
    fi

    # Split the command into individual parameters
    IFS=',' read -ra CMD <<< "$2"

    json_value_regex='\s*"([^"]+)"\s*}*'
    # Extract the id and parse out the actual id value
    ID=$(sed -r 's/"id":'${json_value_regex}'/\1/g' <<< ${CMD[1]})
    # Extract the method and parse out the actual method value
    METHOD=$(sed -r 's/"method":'${json_value_regex}'/\1/g' <<< ${CMD[2]})

    # Base arguments to send to the response handler functions
    response_args=(${rsp[$DEVICE_ID_INDEX]} $ID $METHOD)

    log_receive_msg ${response_args[@]} "$2"

    if [ "$METHOD" = "apply_behavior" ]; then
        ACTION=${CMD[3]}
        REPEAT=${CMD[26]}
        if [ "$ACTION" = '"params":{"action":"STOP"' ]; then
            send_command_response ${response_args[@]} true
            set_rsp_field $index $READ_STATE_INDEX "STOPPED"
            send_inventory_complete_indication ${rsp[$DEVICE_ID_INDEX]} ${rsp[$FACILITY_ID_INDEX]}
        elif [ "$REPEAT" = '"auto_repeat":false' ]; then
            send_command_response ${response_args[@]} true
            set_rsp_field $index $READ_STATE_INDEX "STARTED"
            DUR=${CMD[19]}
            IFS=':' read -ra MILLIS <<< "$DUR"
            sleep $((${MILLIS[1]} / 1000))
            set_rsp_field $index $READ_STATE_INDEX "STOPPED"
            send_inventory_complete_indication ${rsp[$DEVICE_ID_INDEX]} ${rsp[$FACILITY_ID_INDEX]}
        else
            send_command_response ${response_args[@]} true
            set_rsp_field $index $READ_STATE_INDEX "STARTED"
        fi
    elif [ "$METHOD" = "get_sw_version" ]; then
        send_sw_version_response ${response_args[@]}

    elif [ "$METHOD" = "get_state" ]; then
        send_state_response ${response_args[@]} $index

    elif [ "$METHOD" = "get_bist_results" ]; then
        send_bist_results_response ${response_args[@]}

    elif [ "$METHOD" = "ack_alert" ]; then
        # Do nothing
        send_command_response ${response_args[@]} true

    elif [ "$METHOD" = "set_alert_threshold" ]; then
        # Extract the alert number
        IFS=':' read -ra ARRAY <<< "${CMD[3]}"
        number=${ARRAY[2]}
        if [ $number -eq $RfModuleError ]; then
            description="RfModuleError"
            option='{"string":"code","number":769}'
        elif [ $number -eq $HighAmbientTemp ]; then
            description="HighAmbientTemp"
            option='{"string":"degrees","number":'$AMBI_TEMP'}'
        elif [ $number -eq $HighCpuTemp ]; then
            description="HighCpuTemp"
            option='{"string":"degrees","number":'$HCPU_TEMP'}'
        elif [ $number -eq $HighCpuUsage ]; then
            description="HighCpuUsage"
            option='{"string":"percent","number":'$CPU_USAGE'}'
        elif [ $number -eq $HighMemoryUsage ]; then
            description="HighMemoryUsage"
            option='{"string":"percent","number":'$MEM_USAGE'}'
        elif [ $number -eq $DeviceMoved ]; then
            description="DeviceMoved"
            option="{ }"
        else
            description="UnknownError"
            option="{ }"
        fi
        # Extract the alert severity
        IFS=':' read -ra ARRAY <<< "${CMD[4]}"
        severity=${ARRAY[1]}
        severity="${severity%\"}"
        severity="${severity#\"}"
        # Extract the alert threshold
        IFS=':' read -ra ARRAY <<< "${CMD[5]}"
        threshold=${ARRAY[1]}
        IFS='}' read -ra ARRAY <<< "$threshold"
        threshold=${ARRAY[0]}
        # Send the command response
        send_command_response ${response_args[@]} true
        sleep 1
        send_device_alert_indication ${rsp[$DEVICE_ID_INDEX]} ${rsp[$FACILITY_ID_INDEX]} $number $description $severity $option

    elif [ "$METHOD" = "set_facility_id" ]; then
        # Extract the new facility_id
        FACILITY=${CMD[3]}
        IFS='\"' read -ra FAC <<< "$FACILITY"
        FACID=${FAC[3]}
        set_rsp_field $index $FACILITY_ID_INDEX $FACID
        # Send the command response
        send_command_response ${response_args[@]} true

    elif [ "$METHOD" = "reset" ]; then
        # Send the command response
        send_command_response ${response_args[@]} true
        log_rsp_warning "${rsp[$DEVICE_ID_INDEX]}" "RSP-Controller has requested a reset of the RFID module"
        # Alert of the in_reset state
        send_status_indication ${rsp[$DEVICE_ID_INDEX]} ${rsp[$FACILITY_ID_INDEX]} "in_reset" $index
        # wait some time, pretend we are resetting
        sleep $IN_RESET_SECONDS
        # send status of ready
        send_status_indication ${rsp[$DEVICE_ID_INDEX]} ${rsp[$FACILITY_ID_INDEX]} "ready" $index

    elif [ "$METHOD" = "reboot" ]; then
        # Send a true response
        send_command_response ${response_args[@]} true
        log_rsp_warning "${rsp[$DEVICE_ID_INDEX]}" "RSP-Controller has requested a reboot"
        # Virtually shutdown the sensor
        shutdown_rsp $index
        # wait some time, pretend we are rebooting
        sleep $REBOOT_SECONDS
        # instead of just sending status of "ready" perform connect routine again
        connect_rsp $index

    elif [ "$METHOD" = "shutdown" ]; then
        # Send a true response
        send_command_response ${response_args[@]} true
        log_rsp_warning "${rsp[$DEVICE_ID_INDEX]}" "RSP-Controller has requested a shutdown"
        # Virtually shutdown the sensor
        shutdown_rsp $index

    elif [ "$METHOD" = "set_led" ]; then
        # Do nothing
        send_command_response ${response_args[@]} true

    elif [ "$METHOD" = "set_motion_event" ]; then
        # Do nothing
        send_command_response ${response_args[@]} true

    elif [ "$METHOD" = "software_update" ]; then
        # Send a true response
        send_command_response ${response_args[@]} true

    elif [ "$METHOD" = "set_geo_region" ]; then
        local region=$(sed -nr 's/.+"region":'${json_value_regex}'.*/\1/p' <<< ${2})
        set_rsp_field $index $REGION_INDEX $region
        # Send a true response
        send_command_response ${response_args[@]} true

    elif [ "$METHOD" = "get_geo_region" ]; then
        # Send simple response
        send_command_response ${response_args[@]} '{"region":"'${rsp[$REGION_INDEX]}'"}'

    else
        if [ $ALWAYS_TRUE -eq 1 ]; then
            send_command_response ${response_args[@]} true
        else
            log_rsp_warning "${rsp[$DEVICE_ID_INDEX]}" "Received request with unhandled method: ${METHOD}"
        fi
    fi
}

# Function takes rsp index, field index and field value as arguments
set_rsp_field() {
    rsp_file="${RSP_FILE_BASE}${1}"

    if [ $FLOCK_AVAILABLE ]; then
        # write the changes using an exclusive lock
        flock --exclusive $FLOCK_ARGS ${rsp_file} -c "rsp=(\$(cat ${rsp_file})); rsp[${2}]=${3}; echo \"\${rsp[@]}\" > ${rsp_file}"
    else
        # write the changes un-synchronized
       local rsp=($(cat ${rsp_file}))
       rsp[${2}]=${3}
       echo "${rsp[@]}" > ${rsp_file}
    fi
}

# Function takes rsp_file as argument
# Returns array declaration for use with eval which when called will define an array variable called "rsp"
# example: eval "$(rsp_array ${index})"
rsp_array () {
    rsp_file="${RSP_FILE_BASE}${1}"

    if [ $FLOCK_AVAILABLE ]; then
        # read the contents using a shared lock
        local rsp=($(flock --shared $FLOCK_ARGS ${rsp_file} -c "cat ${rsp_file}"))
    else
        # read the contents un-synchronized
        local rsp=($(cat ${rsp_file}))
    fi
    
    # print it out to be consumed by eval
    declare -p rsp
}

# Function takes rsp index as an argument
generate_tag_reads_from_file () {
    index=$1
    tag_file="$TAG_FILE_BASE""$index"

    # Check to make sure these files exist
    if [ -f $rsp_file ] && [ -f $tag_file ]; then
        # Loop forever
        while true; do
            # Get the state of this rsp
            eval "$(rsp_array ${index})"
            if [ "${rsp[$READ_STATE_INDEX]}" == "STARTED" ]; then
                tag_count=$(wc -w < $tag_file)
                reads=$(($tag_count * $READ_PERCENT / 100))

                if [ $reads -eq 0 ]; then
                    log_rsp_warning "${rsp[$DEVICE_ID_INDEX]}" "No tags available to read for sensor"
                else
                    tagdata=$(
                      shuf -n $reads -e $(cat $tag_file) \
                        | paste -s -d ',' \
                          | sed -r 's/([0-9a-fA-F]+)/{"epc":"\1","tid":null,"antenna_id":0,"last_read_on":'$(millis)',"rssi":-654,"phase":32,"frequency":915250}/g'
                    )
                    send_inventory_data_indication ${rsp[$DEVICE_ID_INDEX]} ${rsp[$FACILITY_ID_INDEX]} $reads $tagdata &
                fi
            fi
            sleep 0.5
        done
    fi
}

verify_rsp_file_fields() {
    local index=$1
    local device_id=$2

    eval "$(rsp_array ${index})"

    # Make sure every field has a value
    if [ "${rsp[$DEVICE_ID_INDEX]}" == "" ]; then
        log_rsp_warning $device_id "Device ID for RSP was missing. Setting to $device_id."
        set_rsp_field $index $DEVICE_ID_INDEX $device_id
        # Set it here as well in case it is needed below
        rsp[$DEVICE_ID_INDEX]=$device_id
    fi
    if [ "${rsp[$FACILITY_ID_INDEX]}" == "" ]; then
        log_rsp_warning "${rsp[$DEVICE_ID_INDEX]}" "Facility ID for RSP was missing. Setting to UNKNOWN."
        set_rsp_field $index $FACILITY_ID_INDEX "UNKNOWN"
    fi
    if [ "${rsp[$READ_STATE_INDEX]}" == "" ]; then
        log_rsp_warning "${rsp[$DEVICE_ID_INDEX]}" "Read state for RSP was missing. Setting to STOPPED."
        set_rsp_field $index $READ_STATE_INDEX "STOPPED"
    fi
    if [ "${rsp[$TOKEN_INDEX]}" == "" ]; then
        log_rsp_warning "${rsp[$DEVICE_ID_INDEX]}" "Provision token for RSP was missing. Setting to $DEFAULT_TOKEN."
        set_rsp_field $index $TOKEN_INDEX "$DEFAULT_TOKEN"
    fi
    if [ "${rsp[$REGION_INDEX]}" == "" ]; then
        log_rsp_warning "${rsp[$DEVICE_ID_INDEX]}" "Region information for RSP was missing. Setting to $DEFAULT_REGION."
        set_rsp_field $index $REGION_INDEX $DEFAULT_REGION
    fi
    if [ "${rsp[$STATUS_INDEX]}" == "" ]; then
        log_rsp_warning "${rsp[$DEVICE_ID_INDEX]}" "Status information for RSP was missing. Setting to unknown."
        set_rsp_field $index $STATUS_INDEX "unknown"
    fi
}

#
# Here is where the fun begins
#

# Get the root certificate
echo "requesting root certificate from $ROOT_CERT_URL"
RAW=$(curl --progress-bar --request GET $ROOT_CERT_URL)
IFS='\"' read -ra ARRAY <<< "$RAW"
ROOT_CERT=${ARRAY[3]}
if [ "$ROOT_CERT" = "" ]; then
    echo "Cannot access Root Cert REST endpoint!"
    exit 1
fi

echo "Creating default rsp data..."
index=0
while [ $index -lt $RSPS ]; do
    rsp_file="${RSP_FILE_BASE}${index}"
    device_id="RSP-$(($HOST_BASE+$index))"

    if [ $COLOR -ne 1 ]; then
        rsp_colors[$device_id]=""
    else
        # compute a color for each rsp
        # starting with light colors (91-96)
        # and then use regular colors (31-36)  // 91-60 = 31 :)
        # once all available colors used, start over
        rsp_colors[$device_id]="\e[$(( 91 + ($index % 6) - (60 * (($index / 6) % 2)) ))m"
    fi

    if [ ! -f $rsp_file ]; then
        # the file does not exist yet, so do not care about using flock
        declare -a rsp
        rsp[$DEVICE_ID_INDEX]=$device_id
        rsp[$FACILITY_ID_INDEX]="UNKNOWN"
        rsp[$READ_STATE_INDEX]="STOPPED"
        rsp[$TOKEN_INDEX]=$DEFAULT_TOKEN
        rsp[$REGION_INDEX]=$DEFAULT_REGION
        rsp[$STATUS_INDEX]="unknown"
        echo "${rsp[@]}" > $rsp_file
    else
        verify_rsp_file_fields $index $device_id
    fi

    let index=index+1
done

# Create a tags_in_view file for each rsp
index=0
while [ $index -lt $RSPS ]; do
    FILE="tags_in_view_of_rsp_$index"
    touch $FILE
    let index=index+1
done


# This loop connects the RSPs to the RSP Controller
# assuming the RSP Controller is already running.
index=0
while [ $index -lt $RSPS ]; do
    connect_rsp $index
    let index=index+1
done


# This loop starts a command listener
# in a separate process for each rsp.
index=0
while [ $index -lt $RSPS ]; do
    wait_for_command $index &
    let index=index+1
done


# This loop starts a tag read generator
# in a separate process for each rsp.
index=0
while [ $index -lt $RSPS ]; do
    generate_tag_reads_from_file $index &
    let index=index+1
done

if [ $QUIET -ne 1 ]; then
    printf "\n\n${bold}"
    printf "******************************************\n"
    printf "*     ${lt_green}Connected to RSP Controller${no_color}        *\n"
    printf "******************************************\n"
    printf "*                                        *\n"
    printf "*     ${lt_red}Press CTRL-C to disconnect${no_color}         *\n"
    printf "*                                        *\n"
    printf "******************************************\n"
    printf "${clear}\n\n"
fi


# close connections when Ctrl-C is pressed
trap clean_shutdown INT
# Note: Do not move this trap any higher, as we do not want to do this unless
#       the RSP-Controller connection has already been established!

# This loop sends heartbeat_indications
# to the RSP Controller every 30 seconds, forever.
while true; do
    index=0
    while [ $index -lt $RSPS ]; do
        eval "$(rsp_array ${index})"

        # todo: should we send for "in_reset" or not?
        if [ "${rsp[$STATUS_INDEX]}" == "shutting_down" ]; then
            # Do not send heartbeat
            log_debug "Skip sending heartbeat for rsp in shutdown state ${rsp[$DEVICE_ID_INDEX]}"
            break
        fi

        send_heartbeat_indication ${rsp[$DEVICE_ID_INDEX]} ${rsp[$FACILITY_ID_INDEX]}
        let index=index+1
    done
    sleep 30
done
