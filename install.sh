cd $(dirname $0)
pkill -f CoffeePaste.app
rm -rf '/Applications/CoffeePaste.app'
cp -r 'build/Build/Products/Release/CoffeePaste.app' '/Applications/'
open '/Applications/CoffeePaste.app'
