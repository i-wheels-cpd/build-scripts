#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package       : utf8proc
# Version       : 2.6.1
# Source repo   : https://github.com/JuliaStrings/utf8proc
# Tested on     : UBI 10.1
# Language      : Python, Cython, C++
# Ci-Check  : True
# Script License: Apache License 2.0
# Maintainer    : Arcahna Shinde <Archana.Shinde2@ibm.com>
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# -----------------------------------------------------------------------------
set -ex

# Package configuration
PACKAGE=utf8proc
PACKAGE_VERSION=2.6.1
PACKAGE_URL=https://github.com/JuliaStrings/utf8proc

echo "------------------------Installing dependencies-------------------"
yum install -y git make cmake wget python3.12 python3.12-devel python3.12-pip pkgconfig gcc gcc-c++ gcc-gfortran

WORK_DIR=$(pwd)
cd $WORK_DIR

# Clone utf8proc source repository
echo "Cloning the repository..."
if [ ! -d "$PACKAGE" ]; then
    git clone -b v$PACKAGE_VERSION $PACKAGE_URL
fi
cd utf8proc
git submodule update --init

echo "Building utf8proc..."
mkdir -p prefix
export PREFIX=$(pwd)/prefix
mkdir -p build
cd build

cmake -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE="Release" \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=1 \
  -DBUILD_SHARED_LIBS=1 \
  ..

cmake --build .
cmake --build . --target install

cd $WORK_DIR
mkdir -p local/$PACKAGE

cp -r utf8proc/prefix/* local/$PACKAGE/

# Download pyproject.toml template
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/u/utf8proc/pyproject.toml
sed -i s/{PACKAGE_VERSION}/$PACKAGE_VERSION/g pyproject.toml

pip install setuptools

python3.12 -m pip wheel -w $WORK_DIR -vv --no-build-isolation --no-deps .

# Install locally built wheel for validation

WHEEL=$(find "${WORK_DIR}" -maxdepth 1 -name "${PACKAGE}-*.whl" | head -1)
echo "Built wheel: ${WHEEL}"

if ! pip install "${WHEEL}" --no-deps; then
    echo "------------------${PACKAGE}:Install_fails-------------------------------------"
    echo "${PACKAGE} | ${PACKAGE_URL} | ${PACKAGE_VERSION} | GitHub | Fail | Install_Fails"
    exit 1
fi
SITE_PACKAGES=$(python3.12 -m pip show utf8proc | awk -F': ' '/^Location:/ {print $2}')
test -f "${SITE_PACKAGES}/utf8proc/include/utf8proc.h" || {
    echo "ERROR: utf8proc.h not found"
    exit 1
}

test -f "${SITE_PACKAGES}/utf8proc/lib/libutf8proc.so" || {
    echo "ERROR: libutf8proc.so not found"
    exit 1
}

