#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package       : libvpx
# Version       : 1.3.1
# Source repo   : https://github.com/webmproject/libvpx
# Tested on     : UBI:9.3
# Language      : Python
# Travis-Check  : True
# Script License: Apache License, Version 2 or later
# Maintainer    : Aastha Sharma <aastha.sharma4@ibm.com>
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------
set -ex

PACKAGE_NAME=libvpx
PACKAGE_DIR=libvpx
PACKAGE_VERSION=${1:-v1.13.1}
PACKAGE_URL=https://github.com/webmproject/libvpx
CURRENT_DIR=$(pwd)

# install core dependencies
yum install -y python python-pip python-devel git cmake gcc-toolset-13 wget
export PATH=/opt/rh/gcc-toolset-13/root/usr/bin:$PATH

echo "-----------------------------------------------------build & install yasm------------------------------------------------"
#install yasm
cd $CURRENT_DIR
curl -LO https://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz
tar xzvf yasm-1.3.0.tar.gz
cd yasm-1.3.0
./configure
make
make install
cd $CURRENT_DIR
echo "-----------------------------------------------------Installed yasm------------------------------------------------"

# clone source repository
git clone $PACKAGE_URL
cd $PACKAGE_DIR
git checkout $PACKAGE_VERSION

mkdir prefix
export PREFIX=$(pwd)/prefix

export target_platform=$(uname)-$(uname -m)
export CC=$(which gcc)
export CXX=$(which g++)

if [[ ${target_platform} == Linux-* ]]; then
    LDFLAGS="$LDFLAGS -pthread"
fi

CPU_DETECT="${CPU_DETECT} --enable-runtime-cpu-detect"

./configure --prefix=$PREFIX $HOST_BUILD \
--as=yasm                    \
--enable-shared              \
--disable-static             \
--disable-install-docs       \
--disable-install-srcs       \
--enable-vp8                 \
--enable-postproc            \
--enable-vp9                 \
--enable-vp9-highbitdepth    \
--enable-pic                 \
${CPU_DETECT}                \
--enable-experimental || { cat config.log; exit 1; }
make -j${CPU_COUNT}
make install


mkdir -p local/libvpx
cp -r prefix/* local/libvpx/

pip install setuptools

#Downloading pyproject.toml file
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/l/libvpx/pyproject.toml
sed -i s/{PACKAGE_VERSION}/$PACKAGE_VERSION/g pyproject.toml

if ! pip install . ; then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_Fails"
    exit 1
fi

# Run test cases
if !(./configure --enable-unit-tests); then
    echo "------------------$PACKAGE_NAME:install_success_but_test_fails---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_success_but_test_Fails"
    exit 2
else
    echo "------------------$PACKAGE_NAME:install_&_test_both_success-------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub  | Pass |  Both_Install_and_Test_Success"
    exit 0
fi
