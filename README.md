# EIFTPI image for Raspberry Pi 3 / 4

Currently this image supports the following functionality:
- ProxyPI



## ProxyPI
Proxy wired iOS internet connection and only allow cert server communication for safe agent signing.

The proxy pi allows connections to the following domains:

    elcomsoft.com
    humb.apple.com
    ppq.apple.com

The connection is only permitted after a DNS request was issued. If you want to test this, make sure to use the domain (first), not the ip directly!

i.e. this works:
```
ping elcomsoft.com
PING elcomsoft.com (35.161.100.221): 56 data bytes
```
but this does not (without performing a DNS request first)
```
ping 35.161.100.221
```
 
The simplest way to use it is:
1) Flash image in microSD card (at least 4GB)
2) Power on RPI
3) Connect iPhone with lightning to ethernet adapter to the builtin Ethernet port of the Raspberry PI
4) Use a USB-to-Ethernet adapter to connect the Raspberry PI to internet

If you want to use WiFi for uplink you need to:
1) Use an ethernet cable to connect a computer to the Raspberry Pi builtin ethernet port
2) SSH into the pi with `ssh eift@192.168.41.1` the password is `Elcomsoft`
3) Run `sudo nmtui` and setup WiFi
4) Finally, disconnect the computer and connect the iPhone to the builtin ethernet port of the Raspberry PI



## Building
### Pre-requirements
1) Make sure docker is installed on your system and can be run in `--privileged` mode
2) Make sure `qemu-user-static` is installed on your host system (if running on linux)
3) Make sure `binfmt-support` is installed, configured and running on our host (if running on linux)

Finally Run `./makeimage.sh`