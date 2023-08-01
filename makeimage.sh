#!/bin/bash

docker run --privileged --platform linux/amd64 --rm -v $(pwd):/build -t archlinux:latest /build/build.sh
docker run --privileged --platform linux/amd64 --rm -v $(pwd):/build -t archlinux:latest /build/build_orangepi5.sh
docker run --privileged --platform linux/amd64 --rm -v $(pwd):/build -t archlinux:latest /build/build_orangepi_r1_plus_lts.sh
echo "Done!"
