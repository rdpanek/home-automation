#!/bin/bash

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin

NETATMO_USER=
NETATMO_PASS=
NETATMO_CLIENT_ID=
NETATMO_SECRET=
# device_id is mac address of station
NETATMO_DEVICE_ID=

pokojicekWindow=192.168.1.203
kuchynWindow=192.168.1.106
obyvakWindow=192.168.1.181
lozniceWindow=192.168.1.166

TEMPERATURE_LIMIT=24
CO2_LIMIT=1100
HUMIDITY_LIMIT=53

# Pripadne vyuziti casoveho rozpeti
#FLATTIME=$(date "+%H%M")
#if [[ $FLATTIME > "0903" && "0905" > $FLATTIME ]] ; then
#  echo "cas"
#  echo $FLATTIME
#fi

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

evaluate () {
  temperature=$1
  humidity=$2
  co2=$3
  ipWindow=$4
  tempInt=$( echo "($temperature/1)" | bc)
  # zjistit stav okna
  device_window_status=$(curl -s -X GET $ipWindow/statusn)
  if [[ "$device_window_status" == *"pos:o"* ]]; then
    isWindowOpened=true
  else
    isWindowOpened=false
  fi

  # otevrit okno pokud je teplota v mistnostni vyssi jak 22
  echo "TEMP MAX: " $TEMPERATURE_LIMIT
  echo "TEMP Actual: " $tempInt
  echo "CO2 MAX: " $CO2_LIMIT
  echo "CO2 Actual: " $co2
  echo "HUMIDITY MAX: " $HUMIDITY_LIMIT
  echo "HUMIDITY Actual: " $humidity
  if (( $tempInt >= $TEMPERATURE_LIMIT || $co2 >= $CO2_LIMIT || $humidity >= $HUMIDITY_LIMIT)); then
    echo "otevrit okno, pokud je zavrene"
    if [ "$isWindowOpened" = false ]; then
      echo "je zavrene - oteviram"
      curl -s -X GET $ipWindow/cmd/open
    fi
  fi

  if (( $TEMPERATURE_LIMIT > $tempInt && $CO2_LIMIT > $co2 && $HUMIDITY_LIMIT > $humidity )) ; then
    echo "zavrit okno, pokud je otevrene"
    if [ "$isWindowOpened" = true ]; then
      echo "je otevrene - zaviram"
      curl -s -X GET $ipWindow/cmd/close
    fi
  fi
}
# +-------------------------------+
# |     NETATMO BASE SENZOR       |
# +-------------------------------+

netatmo_senzors=$(curl -s -X POST \
  https://api.netatmo.com/api/getstationsdata \
  -H 'Accept-Charset: UTF-8' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'cache-control: no-cache' \
  -d 'access_token='${access_token}'&device_id='$NETATMO_DEVICE_ID'&undefined=')

additional_modules=$(echo $netatmo_senzors | jq '.body.devices[0].modules')
kuchynTemperature=$(echo $netatmo_senzors | jq '.body.devices[0].dashboard_data.Temperature')
kuchynHumidity=$(echo $netatmo_senzors | jq '.body.devices[0].dashboard_data.Humidity')
kuchynCO2=$(echo $netatmo_senzors | jq '.body.devices[0].dashboard_data.CO2')

# jeden senzor jak pro kuchyn tak i loznici
#echo "Kuchyn"
#evaluate $kuchynTemperature $kuchynHumidity $kuchynCO2 $kuchynWindow
#echo "---------------"

echo "Obyvak"
evaluate $kuchynTemperature $kuchynHumidity $kuchynCO2 $obyvakWindow
echo "---------------"

# +-------------------------------+
# |  NETATMO ADDITIONAL MODUL     |
# +-------------------------------+

for module in $(echo "${additional_modules}" | jq -r '.[] | @base64'); do
  
  moduleName=$(echo $module | base64 --decode | jq '.module_name')
  temperature=$(echo $module | base64 --decode | jq '.dashboard_data.Temperature')
  humidity=$(echo $module | base64 --decode | jq '.dashboard_data.Humidity')
  co2=$(echo $module | base64 --decode | jq '.dashboard_data.CO2')
  # CO2 se u venkovniho modulu nemeri
  if [ "$co2" != 'null' ]; then
      co2=$co2
  fi

  if [ "$moduleName" == "Loznice" ]; then
    echo $moduleName
    evaluate $temperature $humidity $co2 $lozniceWindow
    echo "---------------"
  fi
  
done