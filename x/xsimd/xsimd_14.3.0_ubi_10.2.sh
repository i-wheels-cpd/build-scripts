#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package       : xsimd
# Version       : 14.3.0
# Source repo   : https://github.com/xtensor-stack/xsimd
# Tested on     : UBI:10.2
# Language      : C++
# Ci-Check      : True
# Script License: Apache License, Version 2 or later
# Maintainer    : Nayana Thorat <Nayana.Thorat1@ibm.com>
# Disclaimer    : This script has been tested in root mode on given
# ==========      platform using the mentioned version of the package.
#                 It may not work as expected with newer versions of the
#                 package and/or distribution. In such case, please
#                 contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

PACKAGE_NAME=xsimd
PACKAGE_DIR=xsimd
PACKAGE_VERSION=${1:-14.3.0}
PACKAGE_URL=https://github.com/xtensor-stack/xsimd/

yum install -y python3.14 python3.14-pip git make cmake gcc-toolset-15
export PATH=/opt/rh/gcc-toolset-15/root/usr/bin:$PATH
pip3 install ninja setuptools

SCRIPT_DIR=$(pwd)

echo "------- xsimd installing----------------------"
# clone source repository
git clone -b $PACKAGE_VERSION $PACKAGE_URL
cd $PACKAGE_DIR
git submodule update --init

mkdir prefix
export PREFIX=$(pwd)/prefix

INCLUDE_PATH="${PREFIX}/include"
LIBRARY_PATH="${PREFIX}/lib"

export CC=$(which gcc)
export CXX=$(which g++)

CXXFLAGS="${CXXFLAGS} -fPIC"
mkdir build-cmake
cd build-cmake

cmake ${CMAKE_ARGS} \
  -DCMAKE_PREFIX_PATH=$PREFIX \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  ..
make install

cd $SCRIPT_DIR
mkdir -p local/$PACKAGE
cp -r xsimd/prefix/* local/$PACKAGE/

#pyproject.toml
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/x/xsimd/pyproject.toml
sed -i s/{PACKAGE_VERSION}/$PACKAGE_VERSION/g pyproject.toml

python3.14 -m pip wheel -w $SCRIPT_DIR -vv --no-build-isolation --no-deps .

#install
if ! (pip install .) ; then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_Fails"
    exit 1
fi
