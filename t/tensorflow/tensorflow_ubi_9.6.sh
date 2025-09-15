#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package          : tensorflow
# Version          : v2.18.1
# Source repo      : https://github.com/tensorflow/tensorflow
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

PACKAGE_NAME=tensorflow
PACKAGE_VERSION=${1:-v2.18.1}
PACKAGE_URL=https://github.com/tensorflow/tensorflow
PACKAGE_DIR=tensorflow

WORK_DIR=${PWD}

yum install -y git make cmake zip tar wget python3.12 python3.12-devel python3.12-pip gcc-toolset-13 gcc-toolset-13-gcc-c++ gcc-toolset-13-gcc zlib-devel libjpeg-devel openssl openssl-devel freetype-devel pkgconfig ninja-build java-11-openjdk java-11-openjdk-devel java-11-openjdk-headless sqlite-devel rsync

python3.12 -m pip install wheel

export GCC_TOOLSET_PATH=/opt/rh/gcc-toolset-13/root/usr
export PATH=$GCC_TOOLSET_PATH/bin:$PATH

export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH=$PATH:$JAVA_HOME/bin

#install bazel
wget https://github.com/bazelbuild/bazel/releases/download/6.5.0/bazel-6.5.0-dist.zip
mkdir -p  bazel-6.5.0
unzip bazel-6.5.0-dist.zip -d bazel-6.5.0/
cd bazel-6.5.0/
env EXTRA_BAZEL_ARGS="--tool_java_runtime_version=local_jdk" bash ./compile.sh
#export the path of bazel bin
export PATH=$PATH:`pwd`/output
bazel --version
cd $WORK_DIR
echo "-----------------------------------------------------Installed bazel-----------------------------------------------------"

#installing patchelf from source
yum install -y git autoconf automake libtool make
git clone https://github.com/NixOS/patchelf.git
cd patchelf
./bootstrap.sh
./configure
make 
make install
ln -s /usr/local/bin/patchelf /usr/bin/patchelf
cd $WORK_DIR
echo "-----------------------------------------------------Installed patchelf-----------------------------------------------------"

export TF_NEED_CUDA=0

SHLIB_EXT=".so"
export TF_PYTHON_VERSION=3.12
#Set the GCC_HOME variable here since it isn't obtaining the value from the environment.
export GCC_HOME=/opt/rh/gcc-toolset-13/root/usr 
# set the variable, when grpcio fails to compile on the system. 
export GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=true;  
export LDFLAGS="${LDFLAGS} -lrt"
export CC=$GCC_HOME/bin/gcc
export CXX=$GCC_HOME/bin/g++


cd $WORK_DIR
git clone $PACKAGE_URL
cd $PACKAGE_NAME
git checkout $PACKAGE_VERSION

#Apply patch
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/t/tensorflow/tf_2.18.1_fix.patch
git apply tf_2.18.1_fix.patch

rm -rf tensorflow/*.bazelrc

SRC_DIR=$(pwd)

PYTHON_BIN_PATH=$(which python3.12)
PYTHON_LIB_PATH=$($PYTHON_BIN_PATH -c "import site; print(site.getsitepackages()[0])")

cd tensorflow

#Pick up additional variables defined from the conda build environment and set python path variables
cat > "python_configure.bazelrc" << EOF
build --action_env PYTHON_BIN_PATH="$PYTHON_BIN_PATH"
build --action_env PYTHON_LIB_PATH="$PYTHON_LIB_PATH"
build --python_path="$PYTHON_BIN_PATH"
EOF

#Build the bazelrc
XNNPACK_STATUS=true
#Use centralized optimization settings
NL=$'\n'
BUILD_COPT="build:opt --copt="
BUILD_HOST_COPT="build:opt --host_copt="
CPU_ARCH_OPTION='';
CPU_ARCH_HOST_OPTION='';
CPU_TUNE_OPTION='';
CPU_TUNE_HOST_OPTION='';
VEC_OPTIONS='';
USE_MMA=0

SYSTEM_LIBS_PREFIX=$PREFIX
cat >> tensorflow.bazelrc << EOF
import %workspace%/tensorflow/python_configure.bazelrc
build:xla --define with_xla_support=true
build --config=xla
${CPU_ARCH_OPTION}
${CPU_ARCH_HOST_OPTION}
${CPU_TUNE_OPTION}
${CPU_TUNE_HOST_OPTION}
${VEC_OPTIONS}
build:opt --define with_default_optimizations=true

build --action_env TF_CONFIGURE_IOS="0"
build --action_env TF_SYSTEM_LIBS="org_sqlite"
build --action_env GCC_HOME="/opt/rh/gcc-toolset-13/root/usr"
build --action_env RULES_PYTHON_PIP_ISOLATED="0"
build --define=PREFIX="$SYSTEM_LIBS_PREFIX"
build --define=LIBDIR="$SYSTEM_LIBS_PREFIX/lib"
build --define=INCLUDEDIR="$SYSTEM_LIBS_PREFIX/include"
build --define=tflite_with_xnnpack="$XNNPACK_STATUS"
build --copt="-DEIGEN_ALTIVEC_ENABLE_MMA_DYNAMIC_DISPATCH=$USE_MMA"
build --strip=always
build --color=yes
build --verbose_failures
build --spawn_strategy=standalone
EOF

cat >> $BAZEL_RC_DIR/tensorflow.bazelrc << EOF
build --config=mkl
EOF

BAZEL_JOBS="32"
HOST_CPUS=$(nproc --all)

# build using bazel
export BUILD_TARGET="//tensorflow/tools/pip_package:wheel //tensorflow/tools/lib_package:libtensorflow //tensorflow:libtensorflow_cc${SHLIB_EXT}"

cd ..

#Build package
if ! (bazel --bazelrc=$SRC_DIR/tensorflow/tensorflow.bazelrc build --local_cpu_resources=HOST_CPUS*0.50 --local_ram_resources=HOST_RAM*0.50 --jobs=$BAZEL_JOBS ${BUILD_TARGET}) ; then
    echo "------------------$PACKAGE_NAME:install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_Fails"
    exit 1
fi

echo "-------------------------------tensroflow installation successful-------------------------------------"


#copying .so and .a files into local/tensorflow/lib
mkdir -p $SRC_DIR/tensorflow_pkg
mkdir -p $SRC_DIR/local
find ./bazel-bin/tensorflow/tools/pip_package/wheel_house -iname "*.whl" -exec cp {} $SRC_DIR/tensorflow_pkg  \;
unzip -n $SRC_DIR/tensorflow_pkg/*.whl -d ${SRC_DIR}/local
mkdir -p ${SRC_DIR}/local/tensorflow/lib
find  ${SRC_DIR}/local/tensorflow  -type f \( -name "*.so*" -o -name "*.a" \) -exec cp {} ${SRC_DIR}/local/tensorflow/lib \;

#Build libtensorflow and libtensorflow_cc artifacts
mkdir -p $SRC_DIR/libtensorflow_extracted
tar -xzf $SRC_DIR/bazel-bin/tensorflow/tools/lib_package/libtensorflow.tar.gz -C $SRC_DIR/libtensorflow_extracted
mkdir -p ${SRC_DIR}/local/tensorflow/include
rsync -a  $SRC_DIR/libtensorflow_extracted/lib/*.so*  ${SRC_DIR}/local/tensorflow/lib 
cp -d -r $SRC_DIR/libtensorflow_extracted/include/* ${SRC_DIR}/local/tensorflow/include

mkdir -p $SRC_DIR/libtensorflow_cc_output/lib
mkdir -p $SRC_DIR/libtensorflow_cc_output/include
cp -d  bazel-bin/tensorflow/libtensorflow_cc.so* $SRC_DIR/libtensorflow_cc_output/lib/
cp -d  bazel-bin/tensorflow/libtensorflow_framework.so* $SRC_DIR/libtensorflow_cc_output/lib/
cp -d  $SRC_DIR/libtensorflow_cc_output/lib/libtensorflow_framework.so.2 ./libtensorflow_cc_output/lib/libtensorflow_framework.so

chmod u+w $SRC_DIR/libtensorflow_cc_output/lib/libtensorflow*


mkdir -p $SRC_DIR/libtensorflow_cc_output/include/tensorflow
rsync -r --chmod=D777,F666 --exclude '_solib*' --exclude '_virtual_includes/' --exclude 'pip_package/' --exclude 'lib_package/' --include '*/' --include '*.h' --include '*.inc' --exclude '*' bazel-bin/ $SRC_DIR/libtensorflow_cc_output/include
rsync -r --chmod=D777,F666 --include '*/' --include '*.h' --include '*.inc' --exclude '*' tensorflow/cc $SRC_DIR/libtensorflow_cc_output/include/tensorflow/
rsync -r --chmod=D777,F666 --include '*/' --include '*.h' --include '*.inc' --exclude '*' tensorflow/core $SRC_DIR/libtensorflow_cc_output/include/tensorflow/
rsync -r --chmod=D777,F666 --include '*/' --include '*.h' --include '*.inc' --exclude '*' third_party/xla/third_party/tsl/ $SRC_DIR/libtensorflow_cc_output/include/
rsync -r --chmod=D777,F666 --include '*/' --include '*' --exclude '*.cc' third_party/ $SRC_DIR/libtensorflow_cc_output/include/tensorflow/third_party/
rsync -a $SRC_DIR/libtensorflow_cc_output/include/*  ${SRC_DIR}/local/tensorflow/include
rsync -a $SRC_DIR/libtensorflow_cc_output/lib/*.so ${SRC_DIR}/local/tensorflow/lib

mkdir -p repackged_wheel

# Pack the locally built TensorFlow files into a wheel
wheel pack local/ -d repackged_wheel
cp -a $SRC_DIR/repackged_wheel/*.whl $WORK_DIR

# Run tests for the pip_package directory
if ! (bazel test  -k  //tensorflow/tools/pip_package/...); then
    # Check if the failure is specifically due to "No test targets were found"
    if bazel test  -k  //tensorflow/tools/pip_package/... 2>&1 | grep -q "No test targets were found"; then
        echo "------------------$PACKAGE_NAME:no_test_targets_found---------------------"
        echo "$PACKAGE_URL $PACKAGE_NAME"
        echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub | Pass | No_Test_Targets_Found"
        exit 0  # Graceful exit for no test targets
    fi
    # Handle actual test errors
    echo "------------------$PACKAGE_NAME:install_success_but_test_fails---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub | Fail | Install_Success_But_Test_Fails"
    exit 2
else
    # Tests ran successfully
    echo "------------------$PACKAGE_NAME:install_&_test_both_success------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub | Pass | Both_Install_and_Test_Success"
    exit 0
fi


