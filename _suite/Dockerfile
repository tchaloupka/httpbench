FROM debian:testing

RUN apt update \
    && apt install -y curl wget xz-utils build-essential \
       libxml2 libcurl4 zlib1g-dev git lsof cmake \
    && rm -rf /var/lib/apt/lists/* /tmp/*

WORKDIR /opt

# https://github.com/ldc-developers/ldc/releases
ARG LDC=1.29.0
RUN wget --progress=dot:giga -O - \
    https://github.com/ldc-developers/ldc/releases/download/v$LDC/ldc2-$LDC-linux-x86_64.tar.xz \
    | tar -xJ
ENV PATH="/opt/ldc2-$LDC-linux-x86_64/bin:${PATH}"

# https://golang.org/dl/
RUN wget --progress=dot:giga -O - \
    https://golang.org/dl/go1.18.2.linux-amd64.tar.gz \
    | tar -xz
ENV PATH="/opt/go/bin/:${PATH}"
ENV GOPATH="$HOME"
ENV GOBIN="$HOME/bin"

# https://www.rust-lang.org/tools/install
ENV CARGO_HOME="/opt/.cargo" PATH="/opt/.cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# .Net Core SDK
ENV \
    # Unset ASPNETCORE_URLS from aspnet base image
    ASPNETCORE_URLS= \
    DOTNET_SDK_VERSION=5.0.408 \
    # Enable correct mode for dotnet watch (only mode supported in a container)
    DOTNET_USE_POLLING_FILE_WATCHER=true \
    # Skip extraction of XML docs - generally not useful within an image/container - helps performance
    NUGET_XMLDOC_MODE=skip \
    # PowerShell telemetry for docker image usage
    POWERSHELL_DISTRIBUTION_CHANNEL=PSDocker-DotnetSDK-Ubuntu-20.04

RUN curl -SL --output dotnet.tar.gz https://dotnetcli.azureedge.net/dotnet/Sdk/$DOTNET_SDK_VERSION/dotnet-sdk-$DOTNET_SDK_VERSION-linux-x64.tar.gz \
    && dotnet_sha512='abbf22c420df2d8398d1616efa3d31e1b8f96130697746c45ad68668676d12e65ec3b4dd75f28a5dc7607da58b6e369693c0e658def15ce2431303c28e99db55' \
    && echo "$dotnet_sha512 dotnet.tar.gz" | sha512sum -c - \
    && mkdir -p /usr/share/dotnet \
    && tar -zxf dotnet.tar.gz -C /usr/share/dotnet \
    && rm dotnet.tar.gz \
    # Trigger first run experience by running arbitrary cmd
    && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet \
    && dotnet help

# Nginx
RUN apt update \
    && apt install -y nginx-light \
    && rm -rf /var/lib/apt/lists/* /tmp/*

# https://github.com/rakyll/hey
# RUN wget --progress=dot:giga \
#     https://storage.googleapis.com/hey-release/hey_linux_amd64 \
#     && chmod +x hey_linux_amd64 \
#     && ln -s /opt/hey_linux_amd64 /usr/bin/hey

ARG HEY=0.1.4
RUN wget --progress=dot:giga -O - \
    https://github.com/rakyll/hey/archive/v$HEY.tar.gz \
    | tar -xz \
    && cd hey-$HEY \
    && go build -o ./bin/hey_linux_amd64 \
    && cd .. \
    && mv /opt/hey-$HEY/bin/hey_linux_amd64 /usr/bin/hey \
    && rm -rf hey-$HEY \
    && rm -rf /root/go

# https://github.com/wg/wrk
RUN apt update \
    && apt install -y unzip \
    && git clone https://github.com/wg/wrk.git \
    && cd wrk && make && mv wrk /usr/local/bin/wrk \
    && cd .. && rm -rf wrk \
    && apt purge -y unzip \
    && rm -rf /var/lib/apt/lists/* /tmp/*

RUN go version && echo "---" \
    && ldc2 --version && echo "---" \
    && rustc --version && echo "---" \
    && dotnet --version && echo "---" \
    && nginx -v && echo "---" \
    echo " END"

WORKDIR /src
ENTRYPOINT [ "bash" ]

RUN cat /etc/os-release
