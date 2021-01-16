#!/bin/bash

ELASTICCLUSTER_URI=
ELASTIC_AUTH=

HUE_URI=
HUE_USER=

NETATMO_USER=
NETATMO_PASS=
NETATMO_CLIENT_ID=
NETATMO_SECRET=
# device_id is mac address of station
NETATMO_DEVICE_ID=

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
  "co2": '$(echo $netatmo_senzors | jq '.body.devices[0].dashboard_data.CO2')',
  "humidity": '$(echo $netatmo_senzors | jq '.body.devices[0].dashboard_data.Humidity')',
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
    "co2": '$(echo $co2)',
    "humidity": '$(echo $humidity)',
    "noise": 0,
    "pressure": 0,
    "batteryPercent": '$(echo $batteryPercent)',
    "timestamp": "'${dt}'"
  }'
done