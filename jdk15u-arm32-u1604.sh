#!/bin/bash
#
# Copyright 2020, akashche at redhat.com
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e
set -x

# variables
export OJDK_TAG="$1"
# uncomment for standalone runs
#export OJDK_UPDATE=`echo ${OJDK_TAG} | sed 's/\./ /g' | sed 's/+/ /' | awk '{print $3}'`
#export OJDK_BUILD=`echo ${OJDK_TAG} | sed 's/+/ /' | awk '{print $2}'
#export OJDK_MILESTONE=ojdkbuild
#export OJDK_IMAGE=jdk-15.0.${OJDK_UPDATE}-${OJDK_MILESTONE}-linux-armhf
export OJDK_WITH_NATIVE_DEBUG_SYMBOLS=none
export OJDK_WITH_DEBUG_LEVEL=release
export D="sudo docker exec builder"

# docker
sudo docker pull ubuntu:xenial
sudo docker run \
    -id \
    --name builder \
    -w /opt \
    -v `pwd`:/host \
    ubuntu:xenial \
    bash

# dependencies
$D apt update
$D apt install -y \
    autoconf \
    gcc \
    g++ \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    make \
    zip \
    unzip \
    bzip2 \
    file \
    debootstrap \
    qemu-user-static

# sysroot
$D qemu-debootstrap \
    --arch=armhf \
    --verbose \
    --include=fakeroot,build-essential,libx11-dev,libxext-dev,libxrandr-dev,libxrender-dev,libxtst-dev,libxt-dev,libcups2-dev,libfontconfig1-dev,libasound2-dev,libfreetype6-dev \
    --resolve-deps trusty \
    /opt/chroot \
    || true
for fi in `$D bash -c "ls /opt/chroot/var/cache/apt/archives/*.deb"` ; do
    $D dpkg-deb -R $fi /opt/sysroot
done
$D ln -s /opt/sysroot/lib/arm-linux-gnueabihf /lib/arm-linux-gnueabihf

# boot jdk
$D wget -nv https://github.com/ojdkbuild/contrib_jdk15u-ci/releases/download/jdk-15.0.${OJDK_UPDATE}%2B${OJDK_BUILD}/jdk-15.0.${OJDK_UPDATE}-ojdkbuild-linux-x64.zip
$D unzip -q jdk-15.0.${OJDK_UPDATE}-ojdkbuild-linux-x64.zip
$D mv jdk-15.0.${OJDK_UPDATE}-ojdkbuild-linux-x64 bootjdk

# sources
$D wget -nv http://hg.openjdk.java.net/jdk-updates/jdk15u/archive/${OJDK_TAG}.tar.bz2
$D tar -xjf ${OJDK_TAG}.tar.bz2
$D rm ${OJDK_TAG}.tar.bz2
$D mv jdk15u-${OJDK_TAG} jdk15u

# build
$D mkdir jdkbuild
$D bash -c "cd jdkbuild && \
    bash /opt/jdk15u/configure \
    --openjdk-target=arm-linux-gnueabihf \
    --with-jvm-variants=server \
    --with-sysroot=/opt/sysroot/ \
    --with-toolchain-path=/opt/sysroot/ \
    --disable-warnings-as-errors \
    --disable-hotspot-gtest \
    --with-native-debug-symbols=${OJDK_WITH_NATIVE_DEBUG_SYMBOLS} \
    --with-debug-level=${OJDK_WITH_DEBUG_LEVEL} \
    --with-stdc++lib=static \
    --with-zlib=bundled \
    --with-boot-jdk=/opt/bootjdk/ \
    --with-build-jdk=/opt/bootjdk/ \
    --with-freetype-include=/opt/sysroot/usr/include/freetype2/ \
    --with-freetype-lib=/opt/sysroot/usr/lib/arm-linux-gnueabihf/ \
    --with-version-pre='' \
    --with-version-build=${OJDK_BUILD} \
    --with-version-opt='' \
    --with-vendor-version-string=20.9 \
    --with-vendor-name=ojdkbuild \
    --with-vendor-url=https://github.com/ojdkbuild \
    --with-vendor-bug-url=https://github.com/ojdkbuild/ojdkbuild/issues \
    --with-vendor-vm-bug-url=https://github.com/ojdkbuild/ojdkbuild/issues \
    --with-log=info"
$D bash -c "cd jdkbuild && \
    make images"

# bundle
$D mv ./jdkbuild/images/jdk ${OJDK_IMAGE}
$D rm -rf ./${OJDK_IMAGE}/demo
$D zip -qyr9 ${OJDK_IMAGE}.zip ${OJDK_IMAGE}
$D mv ${OJDK_IMAGE}.zip /host/
sha256sum ${OJDK_IMAGE}.zip > ${OJDK_IMAGE}.zip.sha256
