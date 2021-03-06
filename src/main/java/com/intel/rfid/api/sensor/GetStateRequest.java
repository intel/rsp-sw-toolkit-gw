/*
 * Copyright (C) 2018 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

package com.intel.rfid.api.sensor;

import com.intel.rfid.api.JsonRequest;

public class GetStateRequest extends JsonRequest {

    public static final String METHOD_NAME = "get_state";

    public GetStateRequest() { method = METHOD_NAME; }

}
