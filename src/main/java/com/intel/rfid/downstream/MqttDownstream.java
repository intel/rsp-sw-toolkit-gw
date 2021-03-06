/*
 * Copyright (C) 2018 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
package com.intel.rfid.downstream;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.intel.rfid.api.data.MqttStatus;
import com.intel.rfid.api.gpio.GPIOConnectResponse;
import com.intel.rfid.api.upstream.RspControllerStatusUpdateNotification;
import com.intel.rfid.controller.ConfigManager;
import com.intel.rfid.controller.RspControllerStatus;
import com.intel.rfid.exception.RspControllerException;
import com.intel.rfid.helpers.Jackson;
import com.intel.rfid.mqtt.Mqtt;
import org.eclipse.paho.client.mqttv3.MqttMessage;

import java.io.IOException;

public class MqttDownstream extends Mqtt {

    public static final String TOPIC_PREFIX = "rfid/rsp";
    public static final String GPIO_PREFIX = "rfid/gpio";

    public static final String COMMAND_TOPIC = TOPIC_PREFIX + "/command";
    public static final String CONNECT_TOPIC = TOPIC_PREFIX + "/connect";
    public static final String DATA_TOPIC = TOPIC_PREFIX + "/data";
    public static final String RESPONSE_TOPIC = TOPIC_PREFIX + "/response";
    public static final String RSP_STATUS_TOPIC = TOPIC_PREFIX + "/rsp_status";
    public static final String CONTROLLER_STATUS_TOPIC = TOPIC_PREFIX + "/controller_status";
    @Deprecated
    public static final String GATEWAY_STATUS_TOPIC = TOPIC_PREFIX + "/gw_status";

    public static final String GPIO_COMMAND_TOPIC = GPIO_PREFIX + "/command";
    public static final String GPIO_CONNECT_TOPIC = GPIO_PREFIX + "/connect";
    public static final String GPIO_RESPONSE_TOPIC = GPIO_PREFIX + "/response";
    public static final String GPIO_STATUS_TOPIC = GPIO_PREFIX + "/status";

    protected Dispatch dispatch;
    protected ObjectMapper mapper = Jackson.getMapper();

    public MqttDownstream(Dispatch _dispatch) {
        ConfigManager cm = ConfigManager.instance;
        credentials = cm.getMQTTDownstreamCredentials();
        brokerURI = cm.getMQTTDownstreamURI();
        dispatch = _dispatch;
    }

    @Override
    public void start() {
        subscribe(CONNECT_TOPIC);
        subscribe(RESPONSE_TOPIC + "/#");
        subscribe(RSP_STATUS_TOPIC + "/#");
        subscribe(DATA_TOPIC + "/#");
        subscribe(GPIO_CONNECT_TOPIC);
        subscribe(GPIO_RESPONSE_TOPIC + "/#");
        subscribe(GPIO_STATUS_TOPIC + "/#");

        super.start();
    }

    protected void onConnect() {
        super.onConnect();
        try {
            String deviceId = ConfigManager.instance.getRspControllerDeviceId();
            RspControllerStatusUpdateNotification update = new RspControllerStatusUpdateNotification(deviceId,
                                                                                                  RspControllerStatus.RSP_CONTROLLER_STARTED);
            publishControllerStatus(mapper.writeValueAsBytes(update));
            log.info("Published {}", update.params.status);
        } catch (Exception e) {
            log.warn("Error publishing {}", RspControllerStatus.RSP_CONTROLLER_STARTED.label, e);
        }
    }

    public interface Dispatch {
        void onMessage(final String _topic, final MqttMessage _msg);
    }

    @Override
    public void messageArrived(final String _topic, final MqttMessage _msg) {

        if (_msg.isRetained()) {
            log.info("Discarding retained message");
            return;
        }
        if (_msg.isDuplicate()) {
            log.info("Discarding duplicate message");
            return;
        }

        dispatch.onMessage(_topic, _msg);
    }

    public void publishConnectResponse(String _deviceId, byte[] _msg) throws RspControllerException {
        String topic = CONNECT_TOPIC + "/" + _deviceId;
        publish(topic, _msg, DEFAULT_QOS);
    }

    public void publishCommand(String _deviceId, byte[] _msg) throws RspControllerException {
        String topic = COMMAND_TOPIC + "/" + _deviceId;
        publish(topic, _msg, DEFAULT_QOS);
    }

    public void publishControllerStatus(byte[] _msg) throws RspControllerException {
        publish(CONTROLLER_STATUS_TOPIC, _msg, DEFAULT_QOS);
    }

    public void publishGatewayStatus(byte[] _msg) throws RspControllerException {
        publish(GATEWAY_STATUS_TOPIC, _msg, DEFAULT_QOS);
    }

    public void publishGPIOConnectResponse(String _deviceId, byte[] _msg) throws RspControllerException {
        String topic = GPIO_CONNECT_TOPIC + "/" + _deviceId;
        publish(topic, _msg, DEFAULT_QOS);
    }

    public void publishGPIOCommand(String _deviceId, byte[] _msg) throws RspControllerException {
        String topic = GPIO_COMMAND_TOPIC + "/" + _deviceId;
        publish(topic, _msg, DEFAULT_QOS);
    }

    public MqttStatus getSummary() {
        MqttStatus summary = super.getSummary();
        summary.publishes.add(COMMAND_TOPIC);
        return summary;
    }


}
