FROM ubuntu:18.04

RUN \
  apt-get -y update && apt-get -y install curl && \
  echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list && \
  echo "deb http://ppa.launchpad.net/rmescandon/yq/ubuntu bionic main" > /etc/apt/sources.list.d/yq.list && \
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -                          && \
  apt-get -y update && apt-get -y upgrade                                                                && \
  apt-get -y install yq kubectl && \
  rm -rf /var/lib/apt/lists/*

CMD [ "/bin/sh" ]