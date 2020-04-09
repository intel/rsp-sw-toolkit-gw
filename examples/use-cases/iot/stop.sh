#!/bin/bash

# Apache v2 license
# Copyright (C) <2019> Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

PROJECTS_DIR=$HOME/projects

cd $PROJECTS_DIR/inventory-suite/
sudo -E make stop

cd $PROJECTS_DIR/food-safety-service/
sudo -E make stop

cd $PROJECTS_DIR/loss-prevention-service/
# loss prevention uses both docker-compose and docker swarm based on camera type. try and stop both
sudo -E POE_CAMERA=true make stop || true
sudo -E POE_CAMERA=false make stop || true
