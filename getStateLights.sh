#!/bin/bash

HUE_URI=
ELASTICCLUSTER_URI=
ELASTIC_AUTH=

# prepare date for index and for timestamp
elastic_index_date=$(date '+%Y.%m.%d')
dt=$(date +"%Y-%m-%dT%H:%M:%S")
echo $dt

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
    -H 'Postman-Token: 1c7eddba-5d72-4fa9-9f41-9fd1ec98982c' \
    -H 'cache-control: no-cache' \
    -d '{
    "lightName": "'$(_jq '.name' | tr -d '[:space:]')'",
    "lightState": '$(_jq '.state.on')',
    "place": "tovarni",
    "timestamp": "'${dt}'"
  }'
done
