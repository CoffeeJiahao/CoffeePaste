cd $(dirname $0)
pkill -f CoffeePaste.app
sleep 0.5
while pgrep -f CoffeePaste.app >/dev/null 2>&1; do
    sleep 0.2
done
/bin/rm -rf '/Applications/CoffeePaste.app'
ditto 'build/Build/Products/Release/CoffeePaste.app' '/Applications/CoffeePaste.app'
open '/Applications/CoffeePaste.app'
