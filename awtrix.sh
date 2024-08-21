if [ -z "$openweatherApiKey" ]; then
    if [ -f "awtrix.env" ]; then
        . ./awtrix.env
    else
        echo "You have awtrix.env or set opensearchApiKey manually as an env var"
        exit 1
    fi
fi

mqtt='192.168.86.214'
tc001='http://192.168.86.229/api/notify'
tempLat='37.939329576'
tempLon='-93.401831726'
waterRefreshIntervalHour=2   # hour % this and that's when we update the water stats from ReST
tempRefreshIntervalMin=15     # minute % this and that's when we update the temp stats from ReST
numberOfTransitions=3        # number of things we're displaying
transitionDuration=6         # seconds for each display on the screen
sleepTime="$(($numberOfTransitions * $transitionDuration))"   # how long to actually sleep


function getLakeLevel {
    hour=$(date +%-H)

    if [[ $(($hour % $waterRefreshIntervalHour)) -eq 0 || -z $lakeLevel ]]; then
        #echo "$($dir/getLakeLevel.sh)"
        curl -kLs "https://labs.waterdata.usgs.gov/sta/v1.1/Datastreams('2fb29bf2793b472f978d02bdc5ed4ea0')/Observations?\$skip=500&\$orderby=%40iot.id+asc" | jq -r '.value[-1].result'
    else
        echo "$lakeLevel"
    fi
}

function getLakeDischarge {
    hour=$(date +%-H)

    if [[ $(($hour % $waterRefreshIntervalHour)) -eq 0 || -z $lakeDischarge ]]; then
        #echo "$($dir/getLakeDischarge.sh)"
        curl -XGET -kLs "http://waterservices.usgs.gov/nwis/iv/?site=06921350&format=json&period=P1d" | jq -r '.value.timeSeries[0].values[].value[-1].value'
    else
        echo "$lakeDischarge"
    fi
}

function getOutsideTemp {
    minute=$(date +%-M)

    if [[ $(($minute % $tempRefreshIntervalMin)) -eq 0 || -z $temp ]]; then
         curl -kLs "https://api.openweathermap.org/data/2.5/weather?lat=${tempLat}&lon=${tempLon}&appid=${openweatherApiKey}&units=imperial" | jq -r '.main.temp'
    else
        echo "$temp"
    fi
}

function getTextJson {
    text="$1"
    icon="$2"
    duration="$3"

    cat <<EOF
{
  "text": "$text",
  "icon": "$icon",
  "duration": "$duration"
}
EOF
}


###########   MAIN LOOP   ##############
while (true); do
    ######### mqtt lake level
    lakeLevel="$(getLakeLevel)"
    echo "$(date):  lakeLevel=$lakeLevel"
    json="$(getTextJson "$lakeLevel" "waterglass" "8")"
    mosquitto_pub -h "$mqtt" -m "$json" -t 'awtrix/notify'

    ######### mqtt lake release
    lakeDischarge="$(getLakeDischarge)"
    echo "$(date):  lakeDischarge=$lakeDischarge"
    json="$(getTextJson "$lakeDischarge" "water_leaked" "8")"
    mosquitto_pub -h "$mqtt" -m "$json" -t 'awtrix/notify'

    ######### mqtt current temp
    temp="$(getOutsideTemp)"
    echo "$(date):  temp=$temp"
    json="$(getTextJson "$temp" "temperaturecenter" "8")"
    mosquitto_pub -h "$mqtt" -m "$json" -t 'awtrix/notify'

    echo "Sleeping for ${sleepTime}s to let things render"
    sleep $sleepTime
done

######### curl
#curl -kLs -XPOST -H 'Content-Type: application/json' -d "$lakeLevelJSON" "$tc001"

