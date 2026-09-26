#!/bin/bash
# based on build_al_kernel in https://github.com/firecracker-microvm/firecracker/blob/main/resources/rebuild.sh

set -euo pipefail

KERNEL_VERSION=6.1.102

# Check if we're running inside a container
IN_CONTAINER=${IN_CONTAINER:-false}


# Function to run the build in a Docker container
function run_in_docker {
    echo "Starting build in Docker container..."

    # Build the Docker image
    docker build -t thiri-kernel-builder .
    
    # Run the container with the current directory mounted
    docker run --rm -v "$(pwd):/build" thiri-kernel-builder
    
    exit 0
}

# Make sure we have all the needed tools
function install_dependencies {
    apt update
    apt install -y bc flex bison gcc make libelf-dev libssl-dev squashfs-tools busybox-static tree cpio curl patch kmod
}

# prints the git tag corresponding to the newest and best matching the provided kernel version $1
# this means that if a microvm kernel exists, the tag returned will be of the form
#
#    microvm-kernel-$1.<patch number>.amzn2[023]
#
# otherwise choose the newest tag matching
#
#    kernel-$1.<patch number>.amzn2[023]
function get_tag {
    local KERNEL_VERSION=$1

    # list all tags from newest to oldest
    (git --no-pager tag -l --sort=-creatordate | grep microvm-kernel-$KERNEL_VERSION\..*\.amzn2 \
        || git --no-pager tag -l --sort=-creatordate | grep kernel-$KERNEL_VERSION\..*\.amzn2) | head -n1
}

function build_version {
  install_dependencies
  make distclean || true
  local version=$1
  echo "Starting build for kernel version: $version"

  cp ../"${version}.config" .config

  echo "Checking out repo for kernel at version: $version"
  git checkout "$(get_tag "$version")"

  echo "Building kernel version: $version"
  make olddefconfig
  make vmlinux -j "$(nproc)"
  make modules -j "$(nproc)"

  echo "Copying finished build to builds directory"
  mkdir -p "../builds/vmlinux-${version}"
  cp vmlinux "../builds/vmlinux-${version}/vmlinux.bin"

  # Module tree for the guest image. Every driver is built in today, so this is
  # mostly metadata (modules.builtin, modules.dep, modules.alias ...) -- but it
  # makes modprobe behave instead of erroring on a missing /lib/modules, and it
  # lets an option move to =m later without reworking this build.
  local builds_dir
  builds_dir="$(cd .. && pwd)/builds"
  local modroot="${builds_dir}/modroot-${version}"
  rm -rf "$modroot"
  make modules_install INSTALL_MOD_PATH="$modroot"

  local kernelrelease
  kernelrelease="$(make -s kernelrelease)"
  # These point at the builder's kernel tree and would dangle in the guest.
  rm -f "$modroot/lib/modules/${kernelrelease}/source" \
        "$modroot/lib/modules/${kernelrelease}/build"
  # modules_install skips depmod when there is nothing loadable to install, but
  # modprobe refuses to start without modules.dep.
  depmod -b "$modroot" "$kernelrelease"

  tar czf "${builds_dir}/modules-${version}.tar.gz" -C "$modroot" lib
  rm -rf "$modroot"
  echo "Module tree written to ${builds_dir}/modules-${version}.tar.gz"
}

echo "Cloning the linux kernel repository"


# The following code will only execute inside the container
[ -d linux ] || git clone --no-checkout --filter=tree:0 https://github.com/amazonlinux/linux

# If not in container, run in Docker
if [ "$IN_CONTAINER" != "true" ]; then
    run_in_docker
fi
pushd linux
git checkout "$(get_tag "$KERNEL_VERSION")"

build_version $KERNEL_VERSION

popd
