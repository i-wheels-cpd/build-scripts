#!/bin/bash -e

PYTHON_VERSION=$1
BUILD_SCRIPT_PATH=${2:-""}
EXTRA_ARGS=("${@:3}")  # Capture all additional arguments passed to the script
CURRENT_DIR="${PWD}"
EXIT_CODE=0

#install gcc
yum install -y zip unzip 

UBI_MAJOR=$(grep -oP '(?<=^VERSION_ID=")[0-9]+' /etc/os-release || grep -oP 'release \K[0-9]+' /etc/redhat-release 2>/dev/null || echo "8")
if [[ "$UBI_MAJOR" -ge 10 ]]; then
    GCC_TOOLSET="gcc-toolset-15"
    yum install -y "$GCC_TOOLSET"
    # On UBI 10, SCL (Software Collections) was dropped  -  there is no enable script.
    # Activate the toolset by prepending its bin directory to PATH directly.
    export PATH="/opt/rh/${GCC_TOOLSET}/root/usr/bin:$PATH"
else
    GCC_TOOLSET="gcc-toolset-13"
    yum install -y "$GCC_TOOLSET"
    source /opt/rh/${GCC_TOOLSET}/enable
fi
gcc --version

# Temporary build script path
if [ -n "$BUILD_SCRIPT_PATH" ]; then
    TEMP_BUILD_SCRIPT_PATH="temp_build_script.sh"
else
    TEMP_BUILD_SCRIPT_PATH=""
fi

# Function to install a specific Python version
install_python_version() {
    local version=$1
    echo "Installing Python version: $version"
    case $version in
    "3.9" | "3.11" | "3.12")
        echo "Starting python installing..."
        yum install -y python${version} python${version}-devel python${version}-pip
        ;;
    "3.10")
        if ! python3.10 --version &>/dev/null; then
            echo "Installing dependencies required for python installation..."
            yum install -y sudo zlib-devel wget ncurses git
            echo "Installing..."
            yum install -y make cmake openssl-devel
            echo "Installing..."
            yum install -y libffi libffi-devel sqlite sqlite-devel sqlite-libs bzip2-devel
            echo "Starting python installing..."
            wget https://www.python.org/ftp/python/3.10.15/Python-3.10.15.tgz
            tar xf Python-3.10.15.tgz
            cd Python-3.10.15
            ./configure --prefix=/usr/local --enable-optimizations
            echo "Still building..."
            make -j2
            echo "Still building..."
            make altinstall
            echo "Completed..."
            cd .. && rm -rf Python-3.10.15.tgz
        fi
        ;;
    "3.13")
        if ! python3.13 --version &>/dev/null; then
            echo "Installing dependencies required for python installation..."
            yum install -y sudo zlib-devel wget ncurses git
            echo "Installing..."
            yum install -y make cmake openssl-devel
            echo "Installing..."
            yum install -y libffi libffi-devel sqlite sqlite-devel sqlite-libs bzip2-devel
            echo "Starting python installing..."
            wget https://www.python.org/ftp/python/3.13.0/Python-3.13.0.tgz
            tar xzf Python-3.13.0.tgz
            cd Python-3.13.0
            ./configure --prefix=/usr/local --enable-optimizations
            echo "Still building..."
            make -j2
            echo "Still building..."
            make altinstall
            echo "Completed..."
            cd .. && rm -rf Python-3.13.0.tgz
        fi
        ;;
    "3.14")
        if ! python3.14 --version &>/dev/null; then
            if [[ "$UBI_MAJOR" -ge 10 ]]; then
                yum install -y python3.14 python3.14-devel python3.14-pip
            else
                yum install -y sudo zlib-devel wget ncurses git make cmake openssl-devel xz xz-devel
                yum install -y libffi libffi-devel sqlite sqlite-devel sqlite-libs bzip2-devel
                wget https://www.python.org/ftp/python/3.14.3/Python-3.14.3.tgz
                tar xzf Python-3.14.3.tgz
                cd Python-3.14.3
                ./configure --prefix=/usr/local --enable-optimizations --enable-shared
                make -j2
                make altinstall
                echo "/usr/local/lib" > /etc/ld.so.conf.d/python-local.conf && ldconfig
                cd .. && rm -rf Python-3.14.3.tgz
            fi
        fi
        ;;        
    *)
        echo "Unsupported Python version: $version"
        exit 1
        ;;
    esac
}

# Install the specified Python version
install_python_version "$PYTHON_VERSION"

# Function to copy and format the build script
format_build_script() {
    if [ -n "$BUILD_SCRIPT_PATH" ]; then
        cp "$BUILD_SCRIPT_PATH" "$TEMP_BUILD_SCRIPT_PATH"

        # Modify the build script for compatibility
        sed -i 's/\bpython[0-9]\+\.[0-9]\+ -m pip /pip /g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/python[0-9]\+\.[0-9]\+/python/g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/python3 /python /g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/pip3 /pip /g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/-m venv/d' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/bin\/activate/d' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/^\s*deactivate\s*$/d' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/yum install/{s/\(python\|python-devel\|python-pip\)\([[:space:]]\|$\)//g; s/[[:space:]]\+/ /g}' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/dnf install/{s/\(python\|python-devel\|python-pip\)\([[:space:]]\|$\)//g; s/[[:space:]]\+/ /g}' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/\bpython3 -m pytest/pytest/g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i "s/tox -e py[0-9]\{2,3\}\([[:space:]]*.*\)\?/tox -e py${PYTHON_VERSION//./}\1/g" "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/^[[:space:]]*exit[[:space:]]\+0[[:space:]]*$//' "$TEMP_BUILD_SCRIPT_PATH"
    else
        echo "No build script specified, skipping copying."
    fi
}

# Function to create a virtual environment
create_venv() {
    local VENV_DIR=$1
    local python_version=$2

    "python$python_version" -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
}

# Function to clean up the virtual environment
cleanup() {
    local VENV_DIR=$1

    deactivate
    rm -rf "$VENV_DIR"
}

# Function to apply suffix and/or classifier to a wheel file.
# Mirrors the logic from opence-pip-packaging/common/change-suffix.sh.
#
# Usage: change_suffix_classifier <wheel_path> <suffix> <classifier>
#   suffix     - version suffix string e.g. "+ibmpyeco". Pass "None" to skip.
#   classifier - classifier string e.g. "Environment :: MetaData :: IBM Python Ecosystem". Pass "None" to skip.
if [[ " ${EXTRA_ARGS[*]} " == *" cuda "* ]]; then
    SUFFIX="+ibmpyeco.cuda13.3"
else
    SUFFIX="+ibmpyeco"
fi
CLASSIFIER="Environment :: MetaData:: IBM Python Ecosystem"
change_suffix_classifier() {
    local wheel_file="$1"
    local suffix="$2"
    local classifier="$3"

    # Preserve original platform tag (last dash-separated token before .whl)
    local arch
    arch=$(basename "$wheel_file" | rev | cut -d '-' -f1 | rev | sed 's/\.whl//')

    # Extract wheel contents
    local contents_dir="$CURRENT_DIR/contents"
    [ -d "$contents_dir" ] && rm -rf "$contents_dir"
    unzip -q "$wheel_file" -d "$contents_dir"
    cd "$contents_dir"

    # Locate .dist-info directory
    local dist_info_dir
    dist_info_dir=$(find . -type d -name "*.dist-info")
    if [ -z "$dist_info_dir" ]; then
        echo ".dist-info directory not found in $wheel_file!"
        rm -rf "$contents_dir"
        return 1
    fi

    local metadata_file="$dist_info_dir/METADATA"

    # --- Apply version suffix ---
    local new_dist_info_dir="$dist_info_dir"
    local base_name new_version
    if [[ "$suffix" != "None" ]]; then
        local original_version
        original_version=$(grep -m1 "^Version:" "$metadata_file" | awk '{print $2}')
        if [ -z "$original_version" ]; then
            echo "Version not found in METADATA of $wheel_file!"
            rm -rf "$contents_dir"
            return 1
        fi

        # Strip any existing suffix, then append the new one
        new_version=$(echo "$original_version" | cut -d '+' -f1)
        new_version="${new_version}${suffix}"

        # Update METADATA version field
        sed -i "s/^Version: .*/Version: $new_version/" "$metadata_file"

        # Rename .dist-info directory to include new version
        base_name=$(basename "$dist_info_dir" | sed -E 's/(.*)-([0-9a-zA-Z]+([+.][0-9a-zA-Z]+)*).dist-info/\1/')
        new_dist_info_dir="${base_name}-${new_version}.dist-info"
        mv "$dist_info_dir" "$new_dist_info_dir"

        metadata_file="$new_dist_info_dir/METADATA"
    fi

    # --- Apply classifier ---
    if [[ "$classifier" != "None" ]]; then
        echo "Classifier: ${classifier}" >> "$metadata_file"
    fi

    # --- Repack wheel using `wheel pack` ---
    cd "$CURRENT_DIR"
    pip show wheel &>/dev/null || pip install --quiet wheel
    wheel pack "$contents_dir" --dest-dir "$CURRENT_DIR"

    # Restore original platform tag
    local matches
    matches=$(find "$CURRENT_DIR" -maxdepth 1 -type f -name "${base_name:-*}-${new_version:-*}*.whl" | head -2)
    local match_count
    match_count=$(echo "$matches" | grep -c '\.whl' || true)
    if [ "$match_count" -eq 1 ]; then
        local new_file_name
        new_file_name=$(echo "$matches" | sed -E "s/[^-]+\.whl$/${arch}.whl/")
        [[ "$matches" != "$new_file_name" ]] && mv "$matches" "$new_file_name"
    elif [ "$match_count" -gt 1 ]; then
        echo "Warning: more than one wheel matched after repacking — skipping platform tag restore."
    else
        echo "Warning: repacked wheel not found — skipping platform tag restore."
    fi

    # Remove the original (pre-suffix) wheel if a new one was produced
    if [[ "$suffix" != "None" ]] && [ -f "$wheel_file" ]; then
        rm -f "$wheel_file"
    fi

    # Clean up extraction directory
    rm -rf "$contents_dir"
    echo "Suffix/classifier applied to $(basename "$wheel_file")"
}

# Format the build script if it's non-empty
if [ -n "$BUILD_SCRIPT_PATH" ]; then
    format_build_script
fi

echo "Processing Package with Python $PYTHON_VERSION"

# Create and activate virtual environment
VENV_DIR="$CURRENT_DIR/pyvenv_$PYTHON_VERSION"
create_venv "$VENV_DIR" "$PYTHON_VERSION"

echo "=============== Running package build-script starts =================="

if [ -n "$TEMP_BUILD_SCRIPT_PATH" ]; then
    echo "Installing required dependencies..."
    python$PYTHON_VERSION -m pip install --upgrade pip wheel build pytest nox tox requests setuptools
    echo "Installing required dependencies completed..."

    package_dir=$(grep -oP '(?<=^PACKAGE_DIR=).*' "$TEMP_BUILD_SCRIPT_PATH" | tr -d '"')
    package_url=$(grep -oP '(?<=^PACKAGE_URL=).*' "$TEMP_BUILD_SCRIPT_PATH" | tr -d '"')
    package_name=$(basename "$package_url" .git)

    echo "Running the build script..."
    source "$TEMP_BUILD_SCRIPT_PATH" "${EXTRA_ARGS[@]}"
    
else
    echo "No build script to run, skipping execution."
fi

#checking if wheel is generated through script itself
cd $CURRENT_DIR
if ls *.whl 1>/dev/null 2>&1; then
    echo "Wheel file already exist in the current directory:"
    ls *.whl
else
    #Navigating to the package directory to build wheel
    if [ -d "$package_dir" ]; then
        echo "Navigating to the package directory: $package_dir"
        cd "$package_dir"
    else
        echo "package_dir not found, Navigating to package_name: $package_name"
        cd "$package_name"
    fi

    echo "=============== Building wheel =================="

    # Attempt to build the wheel without isolation
    if ! python -m build --wheel --no-isolation --outdir="$CURRENT_DIR/"; then
        echo "============ Wheel Creation Failed for Python $PYTHON_VERSION (without isolation) ================="
        echo "Attempting to build with isolation..."

        # Attempt to build the wheel without isolation
        if ! python -m build --wheel --outdir="$CURRENT_DIR/"; then
            echo "============ Wheel Creation Failed for Python $PYTHON_VERSION ================="
            EXIT_CODE=1
        fi
    fi
fi

cd "$CURRENT_DIR"
if ls *.whl 1>/dev/null 2>&1; then
    if [[ "$SUFFIX" != "None" ]] || [[ "$CLASSIFIER" != "None" ]]; then
        echo "=============== Applying suffix/classifier to wheel(s) =================="
        for whl in *.whl; do
            change_suffix_classifier "$CURRENT_DIR/$whl" "$SUFFIX" "$CLASSIFIER"
        done
    fi
fi

# Clean up virtual environment
cleanup "$VENV_DIR"

# Remove temporary build script
[ -n "$TEMP_BUILD_SCRIPT_PATH" ] && rm "$CURRENT_DIR/$TEMP_BUILD_SCRIPT_PATH"

exit $EXIT_CODE
