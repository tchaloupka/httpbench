FROM debian:testing

RUN apt update \
    && apt install -y wget xz-utils build-essential \
       libxml2 libcurl4 zlib1g-dev git lsof \
    && rm -rf /var/lib/apt/lists/* /tmp/*

WORKDIR /opt

# https://github.com/ldc-developers/ldc/releases
ARG LDC=1.23.0
RUN wget --progress=dot:giga -O - \
    https://github.com/ldc-developers/ldc/releases/download/v$LDC/ldc2-$LDC-linux-x86_64.tar.xz \
    | tar -xJ
ENV PATH="/opt/ldc2-$LDC-linux-x86_64/bin:${PATH}"

# https://golang.org/dl/
RUN wget --progress=dot:giga -O - \
    https://golang.org/dl/go1.15.1.linux-amd64.tar.gz \
    | tar -xz
ENV PATH="/opt/go/bin/:${PATH}"
ENV GOPATH="$HOME"
ENV GOBIN="$HOME/bin"

# https://www.rust-lang.org/tools/install
ENV CARGO_HOME="/opt/.cargo" PATH="/opt/.cargo/bin:${PATH}"
RUN wget -O - https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly

# https://github.com/rakyll/hey
RUN wget --progress=dot:giga \
    https://storage.googleapis.com/hey-release/hey_linux_amd64 \
    && chmod +x hey_linux_amd64 \
    && ln -s /opt/hey_linux_amd64 /usr/bin/hey

RUN go version && echo "---" \
    && ldc2 --version && echo "---" \
    && rustc --version && echo "---" \
    echo " END"

WORKDIR /src
ENTRYPOINT [ "bash" ]

RUN cat /etc/os-release
