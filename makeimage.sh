#!/bin/bash

docker run --privileged --platform linux/amd64 --rm -v $(pwd):/build -t archlinux:latest /build/build.sh
docker run --privileged --platform linux/amd64 --rm -v $(pwd):/build -t archlinux:latest /build/build_orangepi.sh
echo "Done!"
