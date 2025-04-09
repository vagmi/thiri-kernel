FROM ubuntu:22.04
RUN apt-get update && apt-get install -y git bc flex bison gcc make libelf-dev \
    libssl-dev squashfs-tools busybox-static tree cpio curl patch
WORKDIR /build
RUN git config --global --add safe.directory /build/linux
ENV IN_CONTAINER=true
CMD ["/bin/bash", "./build.sh"]
