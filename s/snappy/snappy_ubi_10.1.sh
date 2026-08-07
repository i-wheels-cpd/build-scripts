#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package       : snappy
# Version       : 1.2.2
# Source repo   : https://github.com/google/snappy
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
#!/bin/bash

set -ex

PACKAGE_NAME=snappy
PACKAGE_VERSION=1.2.2
PYTHON_VERSION=3.12
PACKAGE_URL=https://github.com/google/snappy

echo "PACKAGE_NAME: $PACKAGE_NAME"
echo "PACKAGE_VERSION: $PACKAGE_VERSION"
echo "PACKAGE_URL: $PACKAGE_URL"

OUTPUT_DIR=$(pwd)

# Install system-level build dependencies required for snappy
yum install -y git make cmake wget python3.12 python3.12-devel python3.12-pip pkgconfig g++ gcc-c++

echo "Building snappy..."

cd ${OUTPUT_DIR}

# Clone snappy source repository
echo "Cloning the repository..."
if [ ! -d "$PACKAGE_NAME" ]; then
    git clone -b $PACKAGE_VERSION $PACKAGE_URL
fi
cd snappy
git submodule update --init

mkdir -p local/snappy
export PREFIX=$(pwd)/local/snappy
mkdir -p build
cd build

cmake -DCMAKE_INSTALL_PREFIX=$PREFIX \
      -DBUILD_SHARED_LIBS=ON \
      -DCMAKE_INSTALL_LIBDIR=lib \
      ..
make -j$(nproc)
make install
cd ..

cd ${OUTPUT_DIR}
#install pyproject.toml
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/s/snappy/pyproject.toml
sed -i s/{PACKAGE_VERSION}/$PACKAGE_VERSION/g pyproject.toml

pip install setuptools

python -m pip wheel \
       -w "$OUTPUT_DIR" \
       -vv \
       --no-build-isolation \
       --no-deps \
       .

# Install locally built wheel for validation

WHEEL=$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${PACKAGE_NAME}-*.whl" | head -1)

echo "Built wheel: ${WHEEL}"

if ! pip install "${WHEEL}" --no-deps; then
    echo "------------------${PACKAGE_NAME}:Install_fails-------------------------------------"
    echo "${PACKAGE_NAME} | ${PACKAGE_URL} | ${PACKAGE_VERSION} | GitHub | Fail | Install_Fails"
    exit 1
fi
