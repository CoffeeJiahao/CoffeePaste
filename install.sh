cd $(dirname $0)
pkill -f CoffeePaste.app
/bin/rm -rf '/Applications/CoffeePaste.app'
ditto 'build/Build/Products/Release/CoffeePaste.app' '/Applications/CoffeePaste.app'
open '/Applications/CoffeePaste.app'
