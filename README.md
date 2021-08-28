# sysinfo_MQTTtoHA
## Introduction
The shell script `sysmonitor_MQTTtoHA.sh` collects some system information on the Linux machine it is executed on and publishes MQTT message using JSON format with the information such as:
* Hostname
* IP address (with connection type Ethernet or Wireless and SSID)
* Uptime
* CPU load
* Temperature
* Disk size and usage (%)
* Memory ans Swap usages
* Type of proecessors
* Number of processors
* Model (for Raspberry Pi, Odroid...)
* Operating system

Below is an example of JSON message:
```JSON
{
  "hostname": "Corei5-lab",
  "os": "Ubuntu 20.04.3 LTS",
  "proc": "Intel(R) Core(TM) i5-10500 CPU @ 3.10GHz",
  "nproc": "12",
  "cpu_load": "1.1",
  "disk_size": "457G",
  "disk_usage": "11",
  "memory": "13.2",
  "swap": "0.0",
  "uptime": "28410.91",
  "temperature": "27.8",
  "connection": {
    "type": "wireless",
    "ssid": "ggxlan5"
  },
  "ip": "192.168.0.3"
}
```
The message can be used to display wihtin Home Assistant the status of the machine. The screenshot below depicts the sensors displayed in Home Assistant for four different machines and OS:
* A PC with Ubuntu
* A Raspberry Pi with Raspbian (Jessie)
* A Raspberry Pi with piCorePlayer
* An Odroid-XU4 with dietPi (Buster)

To ease the integration with Home Assistant, MQTT discovery messages can be sent by the script `sysinfo_MQTTtoHA.sh`. All sensors for a machine can be attached to a device whose name is the hostname of the machine. It further ease the integration in Home Assistant: by selecting the device in Home Assistant configuration menu, a Lovelace card with all entities is ready to be inserted in one of the tabs.

## Installation
It is assumed that an MQTT broker (e.g. mosquitto) is already installed on one of your computers ans is accessible through the local network.
1. Clone the repository or download the script on the machine.
2. Edit the script with a text editor and adjust the parameters to your configuration
  * MQTT: the IP address of the broker, port, user and password (if needed)
  * The topic prefix: the MQTT messages with system information are published in topic: mqtt_topicprefix/hostname
  * The Home Assistant discovery prefix (homeassistant by default as mentionned here)
  * The default parameters of the scripts: whether discovery messages shall be published or not, whether the MQTT messages with system information shall be sent once or repeatidly, the delay between each publishing. These three parameters can be overridden by arguments on the command line
3. Run the script (it is recommended to set the update rate to a low value e.g. 5s for intial test) and check if it is working properly:
  * By checking the discovery messages are published by the command `mosquitto_sub -h MQTTBrokerIP -t homeassistant/#/config` 
  * By checking the MQTT messages with system information are periodically published by the command `mosquitto_sub -h MQTTBrokerIP -t computers/+`
  * By checking a new device is available in Home Assistant (assuming the variable `use_device` is set to 1)
  * By checking new entities are available in Home Assistant
4. If it works as expected, the script can be automatically launched as a service for machines supporting systemd. Run the script `install_service.sh` with the root priviledges: `sudo sh install_service.sh`. By default, a message is sent every minutes. To change the value, edit the script `install_service.sh` with a text editor and replace the value 60.

The status of the service (active/stopped) is reflected in Home Assistant: the entities are declared "unavailable" when the service is stopped (or the script no longer executed in loop mode)
