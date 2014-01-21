#!/usr/bin/env bash

apt-get update
apt-get install -y curl perl mongodb git build-essential
curl -L http://cpanmin.us | perl - App::cpanminus 