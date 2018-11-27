#!/bin/bash


NETATMO_USER=
NETATMO_PASS=
NETATMO_CLIENT_ID=
NETATMO_SECRET=
NETATMO_DEVICE_ID=

pracovnaWindow=192.168.1.203

TEMPERATURE_LIMIT_PRACOVNA=22

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

    if [ "$moduleName" == "Pracovna" ]; then
        echo $moduleName
        tempInt=$( echo "($temperature/1)" | bc)
        # zjistit stav okna
        device_window_status=$(curl -X GET $pracovnaWindow/statusn)
        if [[ "$device_window_status" == *"pos:o"* ]]; then
          isWindowOpened=true
        else
          isWindowOpened=false
        fi

        # otevrit okno pokud je teplota v mistnostni vyssi jak 22
        echo "Required: " $TEMPERATURE_LIMIT_PRACOVNA
        echo "Actual: " $tempInt
        if (( $tempInt >= $TEMPERATURE_LIMIT_PRACOVNA )); then
          echo "otevrit okno, pokud je zavrene"
          if [ "$isWindowOpened" = false ]; then
            echo "je zavrene - oteviram"
            curl -X GET $pracovnaWindow/cmd/open
          fi
        fi

        if (( $TEMPERATURE_LIMIT_PRACOVNA < $tempInt )) ; then
          echo "zavrit okno, pokud je otevrene"
          if [ "$isWindowOpened" = true ]; then
            echo "je otevrene - zaviram"
            curl -X GET $pracovnaWindow/cmd/close
          fi
        fi
    fi

done
