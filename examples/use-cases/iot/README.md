# IoT Multisensor Use Cases

In this tutorial we are going to expand the functionality of Intel® RSP and combine more IoT sensors such as temperature, and video data to solve more sophisticated use cases at the edge.

## Contents

- [IoT Multisensor Use Cases](#iot-multisensor-use-cases)
  - [Contents](#contents)
  - [Goals](#goals)
  - [Warnings](#warnings)
  - [Pre-requisites](#pre-requisites)
  - [Ingredients](#ingredients)
  - [Configuration](#configuration)
    - [Inventory Suite](#inventory-suite)
    - [Food Safety](#food-safety)
    - [Loss prevention](#loss-prevention)
      - [Sensor Configuration](#sensor-configuration)
      - [Service Configuration](#service-configuration)
    - [Demo UI](#demo-ui)
  - [Installation](#installation)
  - [Architecture diagram](#architecture-diagram)
  - [Demo Web UI](#demo-web-ui)
  - [Food Safety use case](#food-safety-use-case)
    - [Read BLE temperature data](#read-ble-temperature-data)
    - [Location and ambient temperature](#location-and-ambient-temperature)
    - [Notifications](#notifications)
  - [Loss Prevention use case](#loss-prevention-use-case)
  - [Privacy Compliance](#privacy-compliance)
  - [Hardening your installation](#hardening-your-installation)
    - [Encrypting Docker Data](#encrypting-docker-data)
    - [The easy stuff](#the-easy-stuff)
    - [Encrypting data at rest](#encrypting-data-at-rest)
      - [Full drive encryption](#full-drive-encryption)
      - [Volume encryption](#volume-encryption)
    - [TLS](#tls)

## Goals

- Use [Intel® RSP Inventory Suite](https://github.com/intel/rsp-sw-toolkit-im-suite-inventory-suite) for business context on RFID data.
- Understand data fusion using [EdgeX Foundry](https://www.edgexfoundry.org)
- Combine temperature data from a third-party sensor with Intel® RSP RFID data for food safety use cases.
- Combine video stream with Intel® RSP RFID data for loss prevention use cases.

By the end of this tutorial, you will be able to monitor the ambient temperature of a room where RFID tag(s) are located for food safety purposes and able to trigger a video camera when RFID tag(s) are not supposed to exit a facility for loss prevention purposes.

## Warnings

> ![Warning](docs/images/alert-48.png) **Warning**
>
> **This software has the potential to collect sensitive data including
> CCTV recordings, Inventory Data, Temperature, etc.
> Please read carefully our [Privacy Compliance](#privacy-compliance) section.**

<!-- -->

> ![Warning](docs/images/alert-48.png) **Warning**
>
> This software is a **Dev-Kit** and is **NOT** intended to be deployed into
> production without extra steps to **secure and harden your installation**.
> This is imperative to complete before deploying this software outside of a development environment.
> **Please consult our [Hardening Guide](#hardening-your-installation) for more information.**

## Pre-requisites

1. You have an [H3000 IoT DevKit](https://www.atlasrfidstore.com/intel-rsp-h3000-integrated-rfid-reader-development-kit/),
or an equivalent setup with temperature sensor and USB/IP camera.

2. You have already completed [Tutorial 1 QSR](https://github.com/intel/rsp-sw-toolkit-gw/tree/master/examples/use-cases/qsr) and Intel® RSP Controller and sensors up and running.

3. Bluetooth configured on your system.

4. USB/IP Camera connected.

## Ingredients

This tutorial involves multiples components:

- Intel® RSP Controller
- Intel® RSP Inventory Suite
- EdgeX Foundry Edinburgh release
- Food Safety sample app ([Tempo Disc temperature sensor](https://bluemaestro.com/products/product-details/bluetooth-temperature-sensor-beacon))
- Loss prevention sample app (USB/IP camera)

## Configuration

Edit the following files inside secrets folder:

### Inventory Suite

Edit the file **~/projects/rsp-sw-toolkit-gw/examples/use-cases/iot/secrets/inventory-suite.json** and assign values to the following variables:

- `dbPass`: Password for PostgreSQL database.

### Food Safety

Edit the file **~/projects/rsp-sw-toolkit-gw/examples/use-cases/iot/secrets/food-safety.json** and assign values to the following variables:

- `freezerReaderName`: Alias of RSP reader at the freezer location. (Alias was previously set to 'Freezer' in QSR tutorial 1) (Case sensitive)
- `emailSubscribers`: Email(s) to receive arrival notifications with details (time, ambient temperature, location). Comma separated.
- `trackingEPCs`: EPC tag(s) to be tracked. Comma separated. (Case sensitive)
- `temperatureSensor`: BLE temperature sensor name. Use the BlueMaestro Tempo Plus App ([Tempo Disc temperature sensor](https://bluemaestro.com/products/product-details/bluetooth-temperature-sensor-beacon), **under Apps section**) to find the name of your sensor. (Case sensitive)

### Loss prevention

#### Sensor Configuration

In previous tutorials you should have set the `Personality` of a single RSP sensor to `EXIT`. This is the sensor that will trigger recording events when a matching RFID tag moves near it.

#### Service Configuration

Edit the file **~/projects/rsp-sw-toolkit-gw/examples/use-cases/iot/secrets/loss-prevention.json** with your camera and tag information

- `ipCameraStreamUrl` Stream URL for the IP Camera you wish to connect to. (Example: `"rtsp://user:pass@ipaddress:port"`)
  - **_Notice_**: When using a **USB Camera**, leave the `ipCameraStreamUrl` empty like so: `"ipCameraStreamUrl": ""`
- `epcFilter` Wildcard based filter of EPC tags to trigger on. (Example: `"3014*BEEF*"`)
- `skuFilter` Wildcard based filter of SKU/GTIN values to trigger on. (Example: `"123*78*"`)
- `emailSubscribers` String comma separated of emails to receive notifications. (Example: `"your@email.com,your@email2.com"`)

> **Notes on configuration:**
>
> `skuFilter` and `epcFilter` must **BOTH** match for the tag to match.
> Typically you would set one or the other and then set the other field
> to match everything (`*`)

<!-- -->

> In regards to `skuFilter` and `epcFilter`, a value of `*` effectively matches
> every possible item. Also, the filter must match the whole EPC/SKU
> and not just a subset. For example, if the SKU value is `123456789`, a filter
> of `*345*`, `123*`, `*789`, `1*5*9` **WILL** match, however filters such as
> `1234`, `789`, `*8`, `12*56` will **NOT** match because they only match a
> *subset* of the SKU and not the whole value.

### Demo UI

Edit file **~/projects/rsp-sw-toolkit-gw/examples/use-cases/iot/secrets/demo-ui.json** and assign values to the following variables:

- `freezerReaderName`: Alias of RSP reader at the freezer location. (Alias was previously set to 'Freezer' in tutorial 1)
- `temperatureDevice`: BLE temperature sensor name. Use the BlueMaestro Tempo Plus App ([Tempo Disc temperature sensor](https://bluemaestro.com/products/product-details/bluetooth-temperature-sensor-beacon), **under Apps section**) to find the name of your sensor. (Case sensitive - this should be the same value that was used as temperatureSensor in the Food Safety Section above)

## Installation

Install Docker:

```sh
sudo apt update && sudo apt install -y docker.io docker-compose
```

Install bluetooth libraries and tooling:

```sh
sudo apt-get install -y bluetooth bluez bluez-hcidump rfkill
```

If it's not running, you can start bluetooth with:

```sh
sudo systemctl start bluetooth.service
```

Install Chrome:

```sh
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i google-chrome-stable_current_amd64.deb
```

Make sure that the RSP controller software is running. If it  is not running, please start it with the following command:

```sh
~/deploy/rsp-sw-toolkit-gw/run.sh
```

Run **setup.sh** script (found in this folder) to install Intel® RSP Inventory Suite, EdgeX Edinburgh, Food Safety and Loss Prevention apps.

**_Notice_**: When using a **USB Camera**, add the argument `--usb` like so: `./setup.sh --usb`

```sh
cd ~/projects/rsp-sw-toolkit-gw/examples/use-cases/iot/
./setup.sh
```

![Note](docs/images/coffee-cup-sm2.png)  This step may take some time depending on internet connectivity speed and edge computer.

<!-- -->

> ![Warning](docs/images/alert-48.png) **Warning**
>
> If the setup.sh fails, you should run stop.sh then run setup.sh again.
> Running stop.sh will force the containers to be stopped and put the
> system into a known state.

## Architecture diagram

![Architecture](docs/images/diagram.png)

## Demo Web UI

Verify that everything is up and running by opening the Demo web UI using chrome with web-security disabled. Make sure all chrome windows are closed and execute the following command in a new terminal:

```sh
google-chrome --disable-web-security --user-data-dir='/tmp' http://127.0.0.1:4200
```

![Demo UI](docs/images/demo-ui-home.png)

## Food Safety use case

Food safety service is a sample application that demonstrates how to combine Intel® RSP sensor data with a third-party temperature sensor from EdgeX platform to determine arrival of assets to a specific location (freezer) and ambient temperature of the area. This application also leverages EdgeX Alerts & Notification service to notify users via email.

![Food Safety](docs/images/food-safety.png)

### Read BLE temperature data

If using an external bluetooth dongle, set the appropriate device ID argument.

In a terminal, run the following commands to start reading temperature data from the BLE sensor:

List Bluetooth adapters:

```sh
rfkill list bluetooth --output ID,SOFT,HARD
```

The command should return something similar to:

```sh
ID      SOFT      HARD
 0 unblocked unblocked
```

Use whatever device number is returned by the previous command. In the sample above the ID is 0. By default, if using the integrated bluetooth, it should be device 0.

```sh
cd ~/projects/tempo-device-service/bin
sudo ./sendhci.sh --device <INSERT_YOUR_DEVICE_ID_HERE>
```

For bluetooth troubleshooting please visit [Tempo Device Service](https://github.com/intel/rsp-sw-toolkit-im-suite-tempo-device-service)

Verify the **Temperature** tab in the Demo UI and a chart should populate data from the temperature sensor.

![Sample Temperature Graph](docs/images/temperature.png)

You can verify temperature data on EdgeX Core data using this endpoint:

<http://127.0.0.1:48080/api/v1/reading/name/Temperature/5>

```json
[
  {"id":"01281b8a-5dc1-4bf8-bc47-947424c1f682","created":1576522071372,"origin":1576522071369,"modified":1576522071372,"device":"F4611493","name":"Temperature","value":"Qb8zMw=="},
  {"id":"be486202-d4d2-4b38-a1c7-730dbd2dbf35","created":1576522066073,"origin":1576522066070,"modified":1576522066073,"device":"F4611493","name":"Temperature","value":"Qb8zMw=="},
  {"id":"b109ecde-0974-43a4-bc92-af88859e19dd","created":1576522065632,"origin":1576522065629,"modified":1576522065632,"device":"C7AF971B","name":"Temperature","value":"QcGZmg=="},
  {"id":"8f51040b-7883-4e17-adc4-7d3e07c3f343","created":1576522058317,"origin":1576522058314,"modified":1576522058317,"device":"C1EE0379","name":"Temperature","value":"QcMzMw=="},
  {"id":"33a93522-f376-4d42-858b-4e45fbee21bc","created":1576522051762,"origin":1576522051759,"modified":1576522051762,"device":"F4611493","name":"Temperature","value":"Qb8zMw=="}
]
```

### Location and ambient temperature

In order to see when a RFID tag moves from one location to another, go to the **RFID Inventory** tab in the Demo UI and search for an EPC tag.
When a tag moves to a RSP Reader with an ambient temperature sensor associated with it, you can see the temperature attribute assigned to the tag.
(The association between RSP reader and temperature sensor was previously configured in demo-ui.json file).

![Sample Inventory Temperature](docs/images/inventory-temperature.png)

You can verify data in the Inventory Suite using this endpoint:

<http://127.0.0.1:8090/inventory/tags>

```json
{
  "results": [
    {
      "uri": "encoding:invalid",
      "epc": "000000000000001000000403",
      "product_id": "encoding:invalid",
      "filter_value": 0,
      "tid": "",
      "encode_format": "tbd",
      "facility_id": "QSR_Store_8402",
      "event": "departed",
      "arrived": 1576532484966,
      "last_read": 1576533916632,
      "source": "fixed",
      "location_history": [
        {
          "location": "Receiving-Exiting",
          "timestamp": 1576533916632,
          "source": "fixed"
        },
        {
          "location": "Freezer",
          "timestamp": 1576532484966,
          "source": "fixed"
        }
      ],
      "epc_state": "departed",
      "qualified_state": "unknown",
      "epc_context": ""
    }
  ]
}
```

### Notifications

The Food safety app leverages EdgeX's notification service to send emails. In order to receive email notifications of EPC tags arriving to destination and ambient temperature associated with it, you must configure EdgeX alerts and notification service. The official documentation is available at [Edge-X Documentation](https://docs.edgexfoundry.org/2.0/microservices/support/notifications/Ch-AlertsNotifications/#configure-mail-server).

However, for the simple use case, you can set it up as follows. On the local machine, go to
[EdgeX Notification setup](http://127.0.0.1:8500/ui/dc1/kv/edgex/core/1.0/edgex-support-notifications/Smtp/)

Once on that page, specify a value for each of the following:

- Host (smtp server, EdgeX currently only supports Gmail and Yahoo)
- Password (the password used for your account)
- Port (used by email server)
- Sender (the account to use)
- Subject (can be any text that you want to appear)

-----

Using the Demo Web UI, you can search for all notifications that were sent out by navigating into the **Food Safety** tab. In sender, type **Food Safety App** and set a valid date.

![Sample Notifications](docs/images/notification.png)

## Loss Prevention use case

Loss prevention service is a sample application that demonstrates how to consume data from Intel® RSP sensors and video cameras (USB/IP) to trigger a video clip when not desired events occur. For example, specifics skus should not leave a facility once they arrive.

![Loss Prevention](docs/images/loss-prevention.png)

1. Take the tag that you previously configured in the loss-prevention.json file and move it from the freezer to the exit sensor.
2. A pop up window will be triggered with the live stream of the camera and will record a 15 seconds clip. It will also perform facial detection using computer vision to identify a potential bacon thief.
3. Go to the **Loss Prevention** tab in the Demo UI to see all the video clips that have been recorded.

## Privacy Compliance

This software includes functionality which allows you to record video clips
to a persisted storage device and display them on a basic website. Due to the sensitive nature of
this data, it is imperative that you harden your installation in order
to protect yourselves from potential security and privacy concerns.

We have [some basic guidelines for you to follow](#hardening-your-installation), but ultimately it is up to **YOU**
to protect your installation and data.

## Hardening your installation

### Encrypting Docker Data

Encrypting data in Docker volumes and between Docker nodes is wise practice,
particularly if you're handling data of any sensitivity.
When doing so, there are many different options available,
and which to choose depends largely upon factors specific to your application
and goals.

Below is a list of suggestions with some rough ideas of pros and cons.
Remember that technology changes rapidly,
so it's worth regularly evaluating whether
any particular solution continues to meet your needs
and security requirements; moreover, while this advice attempts to be relevant,
it's also important to examine whether information in this guide
still meets security best-practices.

In short, there is no "one-size-fits-all" solution,
and you should consider the information here as a starting point for further research.

### The easy stuff

First of all, you should ensure your host(s) are at least following basic
[Docker security best practices](https://docs.docker.com/engine/security/security/).

### Encrypting data at rest

#### Full drive encryption

Ubuntu allows you to encrypt the entire OS during the installation step:

![Ubuntu Disk Encryption](docs/images/ubuntu-encrypt-disk.png)

Selecting this will prompt you to create a security key that will be needed on startup to decrypt the drive:

![Ubuntu Security Key](docs/images/ubuntu-encrypt-choose-security-key.jpg)

#### Volume encryption

You can configure Docker to use various different drivers when creating and using Docker volumes. At least one of them allow you to encrypt the data at rest.

[Docker Data Volume Snapshots and Encryption with LVM and LUKS (Blog)](https://medium.com/@kalahari/docker-data-volume-snapshots-and-encryption-with-lvm-and-luks-ce80e0555225)

[Docker Volume Driver for lvm volumes (GitHub)](https://github.com/containers/docker-lvm-plugin)

### TLS

By default Docker swarm nodes will encrypt and authenticate information they exchange between nodes.

In order to encypt the communication between ALL containers/services within Docker, create an Overlay network with encryption enabled.

[Docker swarm mode overlay network security model](https://docs.docker.com/v17.09/engine/userguide/networking/overlay-security-model/)
