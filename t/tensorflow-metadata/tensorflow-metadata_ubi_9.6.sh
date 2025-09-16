#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package          : tensorflow-metadata
# Version          : v1.16.1
# Source repo      : https://github.com/tensorflow/metadata
# Tested on        : UBI:9.6
# Language         : Python
# Travis-Check     : True
# Script License   : Apache License, Version 2 or later
# Maintainer       : Ramnath Nayak <Ramnath.Nayak@ibm.com>
#
# Disclaimer       : This script has been tested in root mode on given
# ==========         platform using the mentioned version of the package.
#                    It may not work as expected with newer versions of the
#                    package and/or distribution. In such case, please
#                    contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

PACKAGE_NAME=metadata
PACKAGE_VERSION=${1:-v1.16.1}
PACKAGE_URL=https://github.com/tensorflow/metadata
PACKAGE_DIR=metadata

CURRENT_DIR=${PWD}

yum install -y git make cmake zip tar wget python3.12 python3.12-devel python3.12-pip gcc-toolset-13 gcc-toolset-13-gcc-c++ gcc-toolset-13-gcc zlib-devel libjpeg-devel openssl openssl-devel freetype-devel pkgconfig ninja-build sqlite-devel rsync java-11-openjdk java-11-openjdk-devel

python3.12 -m pip install setuptools wheel build pytest

export GCC_TOOLSET_PATH=/opt/rh/gcc-toolset-13/root/usr
export PATH=$GCC_TOOLSET_PATH/bin:$PATH

export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH=$PATH:$JAVA_HOME/bin

#Build bazel from source
cd $CURRENT_DIR
mkdir bazel
cd bazel
wget https://github.com/bazelbuild/bazel/releases/download/6.5.0/bazel-6.5.0-dist.zip
unzip bazel-6.5.0-dist.zip
env EXTRA_BAZEL_ARGS="--tool_java_runtime_version=local_jdk" bash ./compile.sh
cp output/bazel /usr/local/bin
export PATH=/usr/local/bin:$PATH
bazel --version
echo "-----------------------------------------------------Installed bazel-----------------------------------------------------"

cd $CURRENT_DIR
git clone $PACKAGE_URL
cd $PACKAGE_NAME
git checkout $PACKAGE_VERSION


#Build package
if ! (python3.12 -m pip install .) ; then
    echo "------------------$PACKAGE_NAME:install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_Fails"
    exit 1
fi

# Wheel building
python3.12 setup.py bdist_wheel --plat-name=linux_x86_64 --dist-dir=$CURRENT_DIR

# Run test
if ! pytest tensorflow_metadata/ ; then
    echo "------------------$PACKAGE_NAME:install_success_but_test_fails---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub | Fail |  Install_success_but_test_Fails"
    exit 2
else
    echo "------------------$PACKAGE_NAME:install_&_test_both_success-------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub  | Pass |  Both_Install_and_Test_Success"
fi


cd $CURRENT_DIR
# Run import test
if ! python3.12 -c "import tensorflow_metadata" ; then
    echo "------------------$PACKAGE_NAME:install_success_but_test_fails---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub | Fail |  Install_success_but_test_Fails"
    exit 2
else
    echo "------------------$PACKAGE_NAME:install_&_test_both_success-------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub  | Pass |  Both_Install_and_Test_Success"
    exit 0
fi


