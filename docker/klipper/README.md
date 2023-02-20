# Klipper docker
Some configuration needs to e done in order to this klipper instance run correctly, all the code bellow expect a host running linux, but it probably work for macOS too.

## Make the USB Serial name persistent

[REF](http://hintshop.ludvig.co.nz/show/persistent-names-usb-serial-devices/)

In case of the SKR3EZ, after flashing Klipper to it, I've noticed that the `/dev/serial/by-id` would always be the same, however after a ton of research it seems the `udev` configuration seems to be the best approach to make it available on docker.

### Figure out the `tty` port you are using

The tty port can be found using the following command:

```
> ls -la /dev/serial/by-id/*

lrwxrwxrwx 1 root root 13 Dec 31 14:09 /dev/serial/by-id/usb-Klipper_stm32h743xx_3D002C001651303232383230-if00 -> ../../ttyACM0
```

In the case above the interface is `ttyACM0`.

### Get extra information from the board

In this step we will try to get all information necessary to configure the udev rule. we will use at least the following: `idVendor`, `idProduct`, `serial`.

Running `lsusb` will give the first two, leaving us without the `serial` as you can see bellow

```
> lsusb

Bus 003 Device 005: ID 1d50:614e OpenMoko, Inc. stm32h743xx
```
Being `1d50` the `idVendor` and `614e` the `idProduct`

So using the `udevadm` command will give us all information we need and more. The volume of information can be overwhelming, specially if you have many devices connected, so use the `idVendor` and `idProduct` we found earlier to help you search for the right device.

```
> udevadm info -a -n /dev/ttyACM0

looking at parent device '/devices/pci0000:00/0000:00:14.0/usb3/3-3':
    KERNELS=="3-3"
    SUBSYSTEMS=="usb"
    DRIVERS=="usb"
    ATTRS{authorized}=="1"
    ATTRS{avoid_reset_quirk}=="0"
    ATTRS{bConfigurationValue}=="1"
    ATTRS{bDeviceClass}=="02"
    ATTRS{bDeviceProtocol}=="00"
    ATTRS{bDeviceSubClass}=="00"
    ATTRS{bMaxPacketSize0}=="16"
    ATTRS{bMaxPower}=="100mA"
    ATTRS{bNumConfigurations}=="1"
    ATTRS{bNumInterfaces}==" 2"
    ATTRS{bcdDevice}=="0100"
    ATTRS{bmAttributes}=="c0"
    ATTRS{busnum}=="3"
    ATTRS{configuration}==""
    ATTRS{devnum}=="5"
    ATTRS{devpath}=="3"
    ATTRS{idProduct}=="614e"
    ATTRS{idVendor}=="1d50"
    ATTRS{ltm_capable}=="no"
    ATTRS{manufacturer}=="Klipper"
    ATTRS{maxchild}=="0"
    ATTRS{physical_location/dock}=="no"
    ATTRS{physical_location/horizontal_position}=="left"
    ATTRS{physical_location/lid}=="no"
    ATTRS{physical_location/panel}=="back"
    ATTRS{physical_location/vertical_position}=="center"
    ATTRS{power/active_duration}=="1984997"
    ATTRS{power/autosuspend}=="2"
    ATTRS{power/autosuspend_delay_ms}=="2000"
    ATTRS{power/connected_duration}=="1984997"
    ATTRS{power/control}=="on"
    ATTRS{power/level}=="on"
    ATTRS{power/persist}=="1"
    ATTRS{power/runtime_active_time}=="1984734"
    ATTRS{power/runtime_status}=="active"
    ATTRS{power/runtime_suspended_time}=="0"
    ATTRS{product}=="stm32h743xx"
    ATTRS{quirks}=="0x0"
    ATTRS{removable}=="removable"
    ATTRS{remove}=="(not readable)"
    ATTRS{rx_lanes}=="1"
    ATTRS{serial}=="3D002C001651303232383230"
    ATTRS{speed}=="12"
    ATTRS{tx_lanes}=="1"
    ATTRS{urbnum}=="12306"
    ATTRS{version}==" 2.00"
```

With that we have the 3 information we want:

```
ATTRS{idProduct}=="614e"
ATTRS{idVendor}=="1d50"
ATTRS{serial}=="3D002C001651303232383230"
```

### Creating the udev rule
First we need to create the file `/etc/udev/rules.d/99-serial.rules`. After that we need to add a row for each device you want to persist in the ruleset.

To make it readable and executable we are also adding the `MODE` option, that is configured as a `chmod`.

The `SYMLINK` text will be the symlink name on `/dev` pointing to the device.

```
> cat /etc/udev/rules.d/99-serial.rules
SUBSYSTEM=="tty", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="614e", ATTRS{serial}=="3D002C001651303232383230", SYMLINK+="printa_skr3ez", MODE="0666"
```

## Adding the device to docker-compose
Here we are mapping the device/folder/etc from the host into the docker container.

Just add the symlink in the composer and give privileged access to it.

```
klipper:
    container_name: klipper
    image: klipper-dev
    privileged: true
    devices:
      - '/dev/printa_skr3ez:/dev/printa_skr3ez'
    volumes:
      - './klipper:/opt/printer_data/config'
      - './klipper/run:/opt/printer_data/run'
      - '~/gcode:/opt/printer_data/gcodes'
      - './klipper/logs:/opt/printer_data/logs'
      - '/dev/printa_skr3ez:/dev/printa_skr3ez'
    restart: always
```

## Change klipper config
On klipper config you need to change the serial prot to the one you created on docker under the `mcu` session

```
[mcu]
serial: /dev/printa_skr3ez 
```

