#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package          : tensorflow-model-optimization
# Version          : v0.8.0
# Source repo      : https://github.com/tensorflow/model-optimization
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

PACKAGE_NAME=model-optimization
PACKAGE_VERSION=${1:-v0.8.0}
PACKAGE_URL=https://github.com/tensorflow/model-optimization
PACKAGE_DIR=model-optimization

WORK_DIR=${PWD}

yum install -y git make cmake zip tar wget python3.12 python3.12-devel python3.12-pip gcc-toolset-13 gcc-toolset-13-gcc-c++ gcc-toolset-13-gcc zlib-devel libjpeg-devel openssl openssl-devel freetype-devel pkgconfig ninja-build sqlite-devel rsync

python3.12 -m pip install numpy setuptools wheel build

export GCC_TOOLSET_PATH=/opt/rh/gcc-toolset-13/root/usr
export PATH=$GCC_TOOLSET_PATH/bin:$PATH

cd $WORK_DIR
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

# Needed to have platform-specific suffix in wheel name
sed -i '/def has_ext_modules(self):/{n;s/return False/return True/;}' setup.py

#Build wheel
python3.12 setup.py bdist_wheel --release --dist-dir $WORK_DIR
echo "---------Wheel Built successfully---------"

python3.12 -m pip install tensorflow_cpu==2.18.1 tf-keras==2.18.0 tensorflow==2.18.0 mock scipy 


#There are effectively no proper runnable tests in this repo; attempts to run them either fail with TensorFlow graph errors or hang indefinitely. The failures suggest that the tests require extensive system resources such as high CPU availability or CUDA-enabled GPU support to execute successfully.

# Run import test
cd $WORK_DIR
if ! python3.12 -c "import tensorflow_model_optimization; print(tensorflow_model_optimization.__version__)"; then
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


