#!/bin/bash

docker network create --subnet=192.168.20.0/24 client
docker network ls | grep kind02
if [ $? -eq 0 ]


mkdir configs
