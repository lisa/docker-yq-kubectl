FROM alpine:3.9.2

ARG kubectlversion=1.12.4
ARG yqversion=2.2.1

RUN apk add --no-cache curl bash
RUN \
  cd /usr/local/bin             && \
  echo "Grabbing binaries..." && \
  curl -sLO https://storage.googleapis.com/kubernetes-release/release/v${kubectlversion}/bin/linux/amd64/kubectl && \
  curl -sLO https://github.com/mikefarah/yq/releases/download/${yqversion}/yq_linux_amd64 && \
  mv /usr/local/bin/yq_linux_amd64 /usr/local/bin/yq && \
  chmod +x /usr/local/bin/kubectl /usr/local/bin/yq
ADD fetch.sh /usr/local/bin

CMD [ "/bin/sh" ]