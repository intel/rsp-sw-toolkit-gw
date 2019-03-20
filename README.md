# Gateway

The features and functionality included in this reference design are intended to showcase the capabilities of the Intel® RFID Sensor Platform (Intel® RSP) by demonstrating the use of the API to collect and process RFID tag read information. **_THIS SOFTWARE IS NOT INTENDED TO BE A COMPLETE END-TO-END INVENTORY MANAGEMENT SOLUTION._**

## Getting Started

These instructions will get you a copy of the project up and running on your local machine for development and testing purposes. 

The Gateway is a Java application built with Gradle. As such, it can run on any OS that supports a Java Runtime Environment version 8 or greater. The development of the Gateway software has been done on an Ubuntu Linux platform and there are several bash scripts supporting installation and configuration so to enable out of the box (repository) operation, a Linux OS is recommended. These instructions assume an installation of Ubuntu 18. 

### Install and Build
``` 
sudo apt-get install openjdk-8-jdk git
sudo apt-get install mosquitto avahi-daemon ntp ssh gradle

cd ${PROJECT_DIR}
# clone the project into this project directory

# build an archive suitable for deployment
cd ${PROJECT_DIR}
gradle buildTar
```

### Deploy
```
cd $DEPLOY_DIR
tar -xf ${PROJECT_DIR}/build/distributions/rsp-sw-toolkit-gw-1.0.tgz
cd ${DEPLOY_DIR}/rsp-sw-toolkit-gw

# need to create self signed certificates for sensors to connect
mkdir -p ${DEPLOY_DIR}/rsp-sw-toolkit-gw/cache
cd ${DEPLOY_DIR}/rsp-sw-toolkit-gw/cache
${DEPLOY_DIR}/rsp-sw-toolkit-gw/gen_keys.sh
```

### Run
A shell script is provided to start the application in the foreground. 
```
${DEPLOY_DIR}/rsp-sw-toolkit-gw/run.sh
```

#### Read RFID Tags
Connect an Intel&reg; RFID Sensor Platform on the same network segment as the gateway. 
The sensor will listen for a gateway announcement and initiate a connection. 
From a separate console window, connect to the gateway command line interface (CLI).
```
ssh -p5222 gwconsole@localhost
```
and enter the default password **_gwconsole_** when prompted. 
The CLI features tab completion for commands and parameters.  

Sensor status can be seen as follows.
```
rfid-gw> sensor show
--------------------------------------------------------------------------------------------
| device | connect | reading | behavior | facility | personality
--------------------------------------------------------------------------------------------
| RSP-000001 | CONNECTED | STOPPED | Default | UNKNOWN | 
| RSP-000002 | CONNECTED | STOPPED | Default | UNKNOWN | 
| RSP-000003 | CONNECTED | STOPPED | Default | UNKNOWN | 
--------------------------------------------------------------------------------------------
```

Sensors must be assigned a facility id before reading rfid tags.
Issue the following commands to get the sensor(s) reading.
```
rfid-gw> sensor set.facility YourFacilityId ALL
rfid-gw> scheduler activate.all.on
rfid-gw> sensor show
--------------------------------------------------------------------------------------------
| device | connect | reading | behavior | facility | personality
--------------------------------------------------------------------------------------------
| RSP-000001 | CONNECTED | STARTED | DefaultAllOn | YourFacilityId | 
| RSP-000002 | CONNECTED | STARTED | DefaultAllOn | YourFacilityId | 
| RSP-000003 | CONNECTED | STARTED | DefaultAllOn | YourFacilityId | 
--------------------------------------------------------------------------------------------
```

Tag reads are incorporated into the gateway inventory.
```
rfid-gw> inventory detail
--------------------------------------------------------------------------------------------
3014369F84191AD66100001, P, RSP-000001, 00:00:15:510
3014369F84191AD66100002, P, RSP-000001, 00:00:15:525
3014369F84191AD66100003, P, RSP-000002, 00:00:08:430
3014369F84191AD66100004, P, RSP-000002, 00:00:08:299
3014369F84191AD66100005, P, RSP-000003, 00:00:42:794
--------------------------------------------------------------------------------------------
```
(columns are EPC, Tag State, Location, Elapsed time since last read)
