# Reproducible runtime for this research package.
# Fija una base estable; ajusta versiones si tu análisis requiere otras.
# Runtime capturado en producción: R 4.4.2 · OS Linux-4.19.0-gvisor-x86_64-with-glibc2.39
FROM mambaorg/micromamba:1.5.8-jammy@sha256:0d2870c1159dfb0c285e1c942c68385cd1110255cc9551838a29e48793e21af1

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    make build-essential ca-certificates curl git \
    libgeos-dev libproj-dev libgdal-dev libudunits2-dev \
    libxml2-dev libssl-dev libfontconfig1-dev libfreetype6-dev \
    libharfbuzz-dev libfribidi-dev libpng-dev libtiff5-dev libjpeg-dev \
    r-base r-base-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY environment/ /work/environment/

RUN Rscript -e "install.packages('renv', repos='https://cloud.r-project.org')" && \
    Rscript -e "renv::restore(lockfile='environment/renv.lock', prompt=FALSE)" || true

# Sólo para scripts/verify.py — el análisis de este paquete no usa Python.
RUN micromamba install -y -n base -c conda-forge python=3.11

COPY . /work/

# Sandbox profiles usados en producción: sdm-r
# Si necesitas paridad exacta con E2B, replicar el Dockerfile del profile.

CMD ["make", "reproduce"]
