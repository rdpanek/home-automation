#!/bin/bash

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin

ELASTICCLUSTER_URI=
ELASTIC_AUTH=

HUE_URI=192.168.1.138
HUE_USER=

NETATMO_USER=
NETATMO_PASS=
NETATMO_CLIENT_ID=
NETATMO_SECRET=
# device_id is mac address of station
NETATMO_DEVICE_ID=

TEMPERATURE_LIMIT=24
CO2_LIMIT=1100
HUMIDITY_LIMIT=53

#{"place":"Pracovna","ip":"192.168.1.203"},
#{"place":"Kuchyn","ip":"192.168.1.106"},
#{"place":"Obyvak","ip":"192.168.1.181"},
#{"place":"Loznice","ip":"192.168.1.166"}

SMARWIS=$(cat <<EOF
[
  {"place":"Obyvak","ip":"192.168.1.181"},
  {"place":"Loznice","ip":"192.168.1.166"}
  ]
EOF
)

# prepare date for index and for timestamp
elastic_index_date=$(date '+%Y.%m.%d')
dt=$(date +"%Y-%m-%dT%H:%M:%S")
echo $dt

# +-------------------------------+
# |          PHILIPS HUE          |
# +-------------------------------+

# get list of lights
list_of_lights=$(curl -X GET ${HUE_URI}/api/${HUE_USER}/lights)
echo $list_of_lights
# parse json and send to elasitc
for row in $(echo "${list_of_lights}" | jq -r '.[] | @base64'); do
    _jq() {
     echo ${row} | base64 --decode | jq -r ${1}
    }

   echo $(_jq '.name') $(_jq '.state.on') ${lightState}
   curl -X POST \
    ${ELASTICCLUSTER_URI}/h.hue-${elastic_index_date}/lights \
    -H 'Authorization: Basic '${ELASTIC_AUTH} \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{
    "lightName": "'$(_jq '.name' | tr -d '[:space:]')'",
    "lightState": '$(_jq '.state.on')',
    "place": "tovarni",
    "timestamp": "'${dt}'"
  }'
done

# +-------------------------------+
# |       NETATMO ACCESS          |
# +-------------------------------+

netatmo_access=$(curl -X POST \
  https://api.netatmo.com/oauth2/token \
  -H 'Accept-Charset: UTF-8' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'cache-control: no-cache' \
  -d 'grant_type=password&client_id='$NETATMO_CLIENT_ID'&client_secret='$NETATMO_SECRET'&username='$NETATMO_USER'&password='$NETATMO_PASS'&scope=&undefined=')


for tok in $(echo "${netatmo_access}"); do
    _jq() {
     echo ${tok} | jq -r ${1}
    }
    access_token=$(_jq '.access_token')

done

# +-------------------------------+
# |     NETATMO BASE SENZOR       |
# +-------------------------------+

netatmo_senzors=$(curl -X POST \
  https://api.netatmo.com/api/getstationsdata \
  -H 'Accept-Charset: UTF-8' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'cache-control: no-cache' \
  -d 'access_token='${access_token}'&device_id='$NETATMO_DEVICE_ID'&undefined=')

curl -X POST \
  ${ELASTICCLUSTER_URI}/h.netatmo-${elastic_index_date}/senzors \
  -H 'Authorization: Basic '${ELASTIC_AUTH} \
  -H 'Content-Type: application/json' \
  -H 'cache-control: no-cache' \
  -d '{
  "moduleType": "base",
  "moduleName": '$(echo $netatmo_senzors | jq '.body.devices[0].module_name')',
  "temperature": '$(echo $netatmo_senzors | jq '.body.devices[0].dashboard_data.Temperature')',
  "temperatureLimit": '${TEMPERATURE_LIMIT}',
  "co2": '$(echo $netatmo_senzors | jq '.body.devices[0].dashboard_data.CO2')',
  "co2Limit": '${CO2_LIMIT}',
  "humidity": '$(echo $netatmo_senzors | jq '.body.devices[0].dashboard_data.Humidity')',
  "humidityLimit": '${HUMIDITY_LIMIT}',
  "noise": '$(echo $netatmo_senzors | jq '.body.devices[0].dashboard_data.Noise')',
  "pressure": '$(echo $netatmo_senzors | jq '.body.devices[0].dashboard_data.Pressure')',
  "batteryPercent": 0,
  "timestamp": "'${dt}'"
}'

additional_modules=$(echo $netatmo_senzors | jq '.body.devices[0].modules')


# +-------------------------------+
# |  NETATMO ADDITIONAL MODUL     |
# +-------------------------------+
echo $additional_modules
for module in $(echo "${additional_modules}" | jq -r '.[] | @base64'); do
  
  moduleName=$(echo $module | base64 --decode | jq '.module_name')
  temperature=$(echo $module | base64 --decode | jq '.dashboard_data.Temperature')
  humidity=$(echo $module | base64 --decode | jq '.dashboard_data.Humidity')
  co2=$(echo $module | base64 --decode | jq '.dashboard_data.CO2')
  # CO2 se u venkovniho modulu nemeri
  if [ "$co2" != 'null' ]; then
      co2=$co2
  fi
  batteryPercent=$(echo $module | base64 --decode | jq '.battery_percent')
  curl -X POST \
  ${ELASTICCLUSTER_URI}/h.netatmo-${elastic_index_date}/senzors \
  -H 'Authorization: Basic '${ELASTIC_AUTH} \
  -H 'Content-Type: application/json' \
  -H 'cache-control: no-cache' \
  -d '{
    "moduleType": "additional",
    "moduleName": '$(echo $moduleName)',
    "temperature": '$(echo $temperature)',
    "temperatureLimit": '${TEMPERATURE_LIMIT}',
    "co2": '$(echo $co2)',
    "co2Limit": '${CO2_LIMIT}',
    "humidity": '$(echo $humidity)',
    "humidityLimit": '${HUMIDITY_LIMIT}',
    "noise": 0,
    "pressure": 0,
    "batteryPercent": '$(echo $batteryPercent)',
    "timestamp": "'${dt}'"
  }'
done

# +-------------------------------+
# |       SMARWI DEVICES          |
# +-------------------------------+

for smarwi in $(echo "${SMARWIS}" | jq -r '.[] | @base64'); do
  _jq() {
    echo ${smarwi} | base64 --decode | jq -r ${1}
  }

  echo $(_jq '.place') $(_jq '.ip')
  device_result_string=$(curl -X GET $(_jq '.ip')/statusn)
  if [[ "$device_result_string" == *"pos:o"* ]]; then
    is_device_opened=true
  else
    is_device_opened=false
  fi

  curl -X POST \
  ${ELASTICCLUSTER_URI}/h.smarwi-${elastic_index_date}/windows \
  -H 'Authorization: Basic '${ELASTIC_AUTH} \
  -H 'Content-Type: application/json' \
  -H 'cache-control: no-cache' \
  -d '{
  "place": "'$(_jq '.place')'",
  "is_open": '$is_device_opened',
  "timestamp": "'${dt}'"
  }'
done