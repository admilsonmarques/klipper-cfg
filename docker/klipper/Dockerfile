## Get Code and Build venv
FROM python:2 as build

ARG REPO=https://github.com/Klipper3d/klipper
ARG VERSION=master

ARG Z_CAL_REPO=https://github.com/protoloft/klipper_z_calibration.git

WORKDIR /opt

RUN git clone ${REPO} klipper \
 && cd klipper \
 && git checkout ${VERSION} \
 && rm -rf .git

RUN virtualenv -p python2 venv \
 && venv/bin/pip install -r klipper/scripts/klippy-requirements.txt \
 && venv/bin/pip install numpy \
 && venv/bin/python -m compileall klipper/klippy \
 && venv/bin/python klipper/klippy/chelper/__init__.py

RUN git clone ${Z_CAL_REPO} zcal \
 && cp zcal/z_calibration.py klipper/klippy/extras/z_calibration.py \
 && rm -rf zcal

## Runtime Image
FROM python:2-slim as run

WORKDIR /opt
RUN groupadd klipper --gid 1000 \
 && useradd klipper --uid 1000 --gid klipper \
 && usermod klipper --append --groups dialout
RUN mkdir -p printer_data/run printer_data/gcodes printer_data/logs printer_data/config \
 && chown -R klipper:klipper /opt/*

COPY --chown=klipper:klipper --from=build /opt/klipper ./klipper
COPY --chown=klipper:klipper --from=build /opt/venv ./venv

USER klipper
VOLUME ["/opt/printer_data/run", "/opt/printer_data/gcodes", "/opt/printer_data/logs", "/opt/printer_data/config"]
ENTRYPOINT ["/opt/venv/bin/python", "klipper/klippy/klippy.py"]
CMD ["-I", "printer_data/run/klipper.tty", "-a", "printer_data/run/klipper.sock", "printer_data/config/klipper.cfg"]


