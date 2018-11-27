#!/bin/bash

ELASTICCLUSTER_URI=
ELASTIC_AUTH=

HUE_URI=

NETATMO_USER=
NETATMO_PASS=
NETATMO_CLIENT_ID=
NETATMO_SECRET=
NETATMO_DEVICE_ID=

SMARWIS=$(cat <<EOF
[
  {"place":"Pracovna","ip":"192.168.1.203"},
  {"place":"Kuchyn","ip":"192.168.1.106"},
  {"place":"Obyvak","ip":"192.168.1.181"},
  {"place":"Loznice","ip":"192.168.1.167"}
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
list_of_lights=$(curl -X GET ${HUE_URI}/lights)

# parse json and send to elasitc
for row in $(echo "${list_of_lights}" | jq -r '.[] | @base64'); do
    _jq() {
     echo ${row} | base64 --decode | jq -r ${1}
    }

   echo $(_jq '.name') $(_jq '.state.on') ${lightState}
   curl -X POST \
    ${ELASTICCLUSTER_URI}/homeautomation-${elastic_index_date}/lights \
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

for senzor in $(echo "${netatmo_senzors}"); do
    _jq() {
     echo ${senzor} | jq -r ${1}
    }
    curl -X POST \
     ${ELASTICCLUSTER_URI}/netatmo-${elastic_index_date}/senzors \
     -H 'Authorization: Basic '${ELASTIC_AUTH} \
     -H 'Content-Type: application/json' \
     -H 'cache-control: no-cache' \
     -d '{
     "moduleType": "base",
     "moduleName": "'$(_jq '.body.devices[0].module_name' | tr -d '[:space:]')'",
     "temperature": '$(_jq '.body.devices[0].dashboard_data.Temperature')',
     "co2": '$(_jq '.body.devices[0].dashboard_data.CO2')',
     "humidity": '$(_jq '.body.devices[0].dashboard_data.Humidity')',
     "noise": '$(_jq '.body.devices[0].dashboard_data.Noise')',
     "pressure": '$(_jq '.body.devices[0].dashboard_data.Pressure')',
     "batteryPercent": 0,
     "place": "tovarni",
     "timestamp": "'${dt}'"
    }'

    additional_modules=$(_jq '.body.devices[0].modules')

done


# +-------------------------------+
# |  NETATMO ADDITIONAL MODUL     |
# +-------------------------------+

echo $additional_modules
for module in $(echo "${additional_modules}" | jq -r '.[] | @base64'); do
    _jq() {
     echo ${module} | base64 --decode | jq -r ${1}
    }
    moduleName=$(_jq '.module_name' | tr -d '[:space:]')
    temperature=$(_jq '.dashboard_data.Temperature')
    humidity=$(_jq '.dashboard_data.Humidity')
    co2=$(_jq '.dashboard_data.CO2')
    # CO2 se u venkovniho modulu nemeri
    if [ "$co2" != 'null' ]; then
       co2=$co2
    fi
    batteryPercent=$(_jq '.battery_percent')
   curl -X POST \
    ${ELASTICCLUSTER_URI}/netatmo-${elastic_index_date}/senzors \
    -H 'Authorization: Basic '${ELASTIC_AUTH} \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{
    "moduleType": "additional",
    "moduleName": "'$moduleName'",
    "temperature": '$temperature',
    "co2": '$co2',
    "humidity": '$humidity',
    "noise": 0,
    "pressure": 0,
    "batteryPercent": '$batteryPercent',
    "place": "tovarni",
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
  ${ELASTICCLUSTER_URI}/smarwi-${elastic_index_date}/windows \
  -H 'Authorization: Basic '${ELASTIC_AUTH} \
  -H 'Content-Type: application/json' \
  -H 'cache-control: no-cache' \
  -d '{
  "place": "'$(_jq '.place')'",
  "is_open": '$is_device_opened',
  "timestamp": "'${dt}'"
  }'
done
