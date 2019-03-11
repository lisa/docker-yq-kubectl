FROM ubuntu:18.04

ARG kubectlversion=1.12.4
ARG yqversion=2.2.1

RUN \
  apt-get -y update && apt-get -y upgrade && apt-get -y install curl && \
  rm -rf /var/lib/apt/lists/*   && \
  cd /usr/local/bin             && \
  echo "Grabbing binaries..." && \
  curl -qLO https://storage.googleapis.com/kubernetes-release/release/v${kubectlversion}/bin/linux/amd64/kubectl && \
  curl -qLO https://github.com/mikefarah/yq/releases/download/${yqversion}/yq_linux_amd64 && \
  mv /usr/local/bin/yq_linux_amd64 /usr/local/bin/yq && \
  chmod +x /usr/local/bin/kubectl /usr/local/bin/yq

ADD fetch.sh /usr/local/bin

CMD [ "/bin/sh" ]