sudo service klipper stop
cd ~/klipper
git pull


make clean KCONFIG_CONFIG=~/klipper-cfg/menuconfigs/manta_m8p_v2_klipper.config
make menuconfig KCONFIG_CONFIG=~/klipper-cfg/menuconfigs/manta_m8p_v2_klipper.config
make KCONFIG_CONFIG=~/klipper-cfg/menuconfigs/manta_m8p_v2_klipper.config
read -p "Manta firmware built, please check above for any errors. Press [Enter] to continue flashing, or [Ctrl+C] to abort"

./scripts/flash-sdcard.sh /dev/ttyAMA0 fysetc-spider-v1
read -p "Spider firmware flashed, please check above for any errors. Press [Enter] to continue, or [Ctrl+C] to abort"

make clean KCONFIG_CONFIG=~/klipper-cfg/menuconfigs/rpi_klipper.config
make menuconfig KCONFIG_CONFIG=~/klipper-cfg/menuconfigs/rpi_klipper.config

make KCONFIG_CONFIG=~/klipper-cfg/menuconfigs/rpi_klipper.config
read -p "RPi firmware built, please check above for any errors. Press [Enter] to continue flashing, or [Ctrl+C] to abort"
make flash KCONFIG_CONFIG=~/klipper-cfg/menuconfigs/rpi_klipper.config

sudo service klipper start

