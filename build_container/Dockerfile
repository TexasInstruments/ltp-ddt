ARG BASE_DISTRO=SPECIFY_ME

FROM $BASE_DISTRO

# Arguments are dropped by docker after the `FROM` statement
ARG BASE_DISTRO=SPECIFY_ME
ARG KERNEL_BRANCH=SPECIFY_ME

LABEL TI_IMAGE_SOURCE=$BASE_DISTRO
LABEL maintainer="Minas Hambardzumyan <minas@ti.com>"

#Install all packages needed
RUN export DEBIAN_FRONTEND=noninteractive; \
    apt-get update \
    && apt-get install -y --no-install-recommends \
    curl wget       \
    git             \
    ssh-tools       \
    automake        \
    pkg-config      \
    libtool         \
    rsync           \
    xz-utils bzip2  \
    make            \
    dumb-init       \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install missing library
WORKDIR /opt

ENV SDK_PATH="/opt/arm-gnu-toolchain-13.3.rel1-x86_64-aarch64-none-linux-gnu"
# Install ARM toolchain
RUN mkdir ${SDK_PATH} \
    && curl -k -L "https://developer.arm.com/-/media/Files/downloads/gnu/13.3.rel1/binrel/arm-gnu-toolchain-13.3.rel1-x86_64-aarch64-none-linux-gnu.tar.xz" | tar xvJ --strip-components=1 -C ${SDK_PATH} 

ENV TARGET_SYS=aarch64-none-linux-gnu
ENV CROSS_COMPILER=${TARGET_SYS}-
ENV CC=${CROSS_COMPILER}gcc
ENV LD=${CROSS_COMPILER}ld
ENV AR=${CROSS_COMPILER}ar
ENV STRIP=${CROSS_COMPILER}strip
ENV RANLIB=${CROSS_COMPILER}ranlib
ENV PATH=${SDK_PATH}/bin:$PATH


WORKDIR /dependencies

# Install alsa
RUN mkdir /dependencies/alsa-lib-1.2.9 \
    && curl -k -L https://www.alsa-project.org/files/pub/lib/alsa-lib-1.2.9.tar.bz2 | tar xvj --strip-components=1 -C /dependencies/alsa-lib-1.2.9 \
    && cd /dependencies/alsa-lib-1.2.9 \
    && ./configure --enable-shared=yes --enable-static=no --with-pic --host=${TARGET_SYS} --prefix=${SDK_PATH}/${TARGET_SYS} \
    && make -j 4 \
    && make install 

WORKDIR /dependencies

ENV GIT_SSL_NO_VERIFY=1
#install tirpc
RUN git clone https://github.com/alisw/libtirpc.git \
    && cd /dependencies/libtirpc \
    && git checkout libtirpc-1-2-6 \
    && autoupdate \
    && autoreconf --install \
    && ./configure --enable-shared=yes --enable-static=no --with-pic --host=${TARGET_SYS} --prefix=${SDK_PATH}/${TARGET_SYS} --disable-gssapi \
    && make -j 4 \
    && make install

WORKDIR /dependencies
# kernel headings
RUN git clone https://git.ti.com/git/ti-linux-kernel/ti-linux-kernel.git \
    && cd /dependencies/ti-linux-kernel \
    && git checkout ${KERNEL_BRANCH} \
    && make CROSS_COMPILE=aarch64-none-linux-gnu- distclean \
    && make CROSS_COMPILE=aarch64-none-linux-gnu- headers_install

# volume directories and user set-up
RUN mkdir -p /workspace /target /home/user \
    && touch /workspace/.docker-local /target/.docker-local /dependencies/ti-linux-kernel/.docker-local \
    && groupadd -r user -g 1000 \
    && useradd -u 1000 -r -g user -d /home/user -s /bin/bash -c "Docker user" user \
    && sed -i 's/PATH="/PATH="\/opt\/arm-gnu-toolchain-13.2.rel1-x86_64-aarch64-none-linux-gnu\/bin:/g' /etc/environment \
    && chown -R user:user /workspace /target /home/user

VOLUME /workspace
VOLUME /target

WORKDIR /workspace

COPY ./docker-init /docker-init
# RUN chmod +x /docker-init

ENTRYPOINT ["/docker-init"]
CMD ./build.sh -p /target -k /dependencies/ti-linux-kernel/usr/include -c aarch64-none-linux-gnu-gcc -t cross -i
