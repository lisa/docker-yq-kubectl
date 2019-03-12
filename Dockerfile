FROM quay.io/openshift/origin-cli:v4.0.0

ARG ocpythonlibver=0.8.6

RUN \
  cd /tmp && \
  curl -L https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
  python /tmp/get-pip.py && \
  pip install -U setuptools

RUN \
  cd /tmp && \ 
  curl -LO https://github.com/openshift/openshift-restclient-python/archive/v${ocpythonlibver}.tar.gz && \
  tar xvzf v${ocpythonlibver}.tar.gz && \
  cd openshift-restclient-python-${ocpythonlibver} && \
  (python setup.py install || python setup.py install)

# https://medium.com/@gloriapalmagonzalez/urllib3-1-22-or-chardet-2-2-1-doesnt-match-a-supported-version-requestsdependencywarning-97c36e0cb561
RUN \
  pip uninstall -y requests && \
  pip install requests && \
  pip uninstall -y chardet && \
  pip install chardet

COPY src/init.py /usr/local/bin

RUN chmod +x /usr/local/bin/init.py

CMD [ "/bin/sh" ]