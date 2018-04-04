FROM alpine:3.7

RUN apk --no-cache upgrade

RUN apk add --no-cache \
    wget \
    bash \
    pcre \
    ca-certificates \
    openssl-dev \
    ncurses-dev \
    unixodbc-dev \
    zlib-dev \
    # dpkg-dev \
    # dpkg \
    autoconf \
    build-base \
    perl-dev

RUN mkdir -p /home/build/out
WORKDIR /home/build

COPY build_otp_alpine.sh /home/build/build.sh
RUN chmod +x /home/build/build.sh
CMD ./build.sh
