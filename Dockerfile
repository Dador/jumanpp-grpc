ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE} AS builder
# ARG should be placed after FROM
ARG JPP_VERSION=2.0.0-rc4
WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update -q && apt-get install -yq --no-install-recommends \
    build-essential \
    cmake \
    ca-certificates \
    g++ \
    libprotobuf-dev \
    make \
    tar \
    wget \
    xz-utils \
    libgrpc++-dev \
    protobuf-compiler-grpc

# Build and install Juman++ gRPC
COPY . ./jumanpp-grpc
RUN cd jumanpp-grpc \
    && mkdir build || true \
    && cd build \
    && cmake .. -DCMAKE_BUILD_TYPE=Release \
    && make -j "$([ "$(nproc)" -le 8 ] && nproc || echo "8")"

# Build and install Juman++ with model
RUN set -ex \
    && wget "https://github.com/ku-nlp/jumanpp/releases/download/v${JPP_VERSION}/jumanpp-${JPP_VERSION}.tar.xz" \
    && mkdir -p jumanpp-grpc/jumanpp/model || true \
    && tar xf "jumanpp-${JPP_VERSION}.tar.xz" --strip-components=2 -C jumanpp-grpc/jumanpp/model jumanpp-${JPP_VERSION}/model \
    && rm jumanpp-${JPP_VERSION}.tar.xz \
    && mkdir jumanpp-grpc/jumanpp/build || true \
    && cd jumanpp-grpc/jumanpp/build \
    && cmake .. -DCMAKE_BUILD_TYPE=Release \
    && make -j "$([ "$(nproc)" -le 8 ] && nproc || echo "8")" \
    && make install

FROM ${BASE_IMAGE} AS runner

# Configure Japanese locale
RUN apt-get update -q && apt-get install -yq --no-install-recommends \
    locales \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen ja_JP.UTF-8
ENV LANG="ja_JP.UTF-8" \
    LANGUAGE="en_US" \
    LC_ALL="ja_JP.UTF-8"
RUN localedef -f UTF-8 -i ja_JP ja_JP.utf8

COPY --from=builder /usr/local /usr/local
COPY --from=builder /app/jumanpp-grpc/build/src/jumandic/jumanpp-jumandic-grpc /usr/local/bin/jumanpp-jumandic-grpc

CMD ["jumanpp-jumandic-grpc", "--config=/usr/local/libexec/jumanpp/jumandic.config", "--port=51231", "--threads=1"]