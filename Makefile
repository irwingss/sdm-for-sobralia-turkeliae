.PHONY: reproduce reproduce-python reproduce-r verify install docker-build docker-run clean

PYTHON ?= $(shell command -v python3 2>/dev/null || command -v python 2>/dev/null || echo python3)

# Reproduce todo el análisis end-to-end.
reproduce:
	$(MAKE) reproduce-r
	$(MAKE) verify

reproduce-r:
	Rscript -e "if(!requireNamespace('renv',quietly=TRUE)) install.packages('renv'); renv::restore(lockfile='environment/renv.lock')"
	cd code && Rscript pipeline.R

# Verifica integridad del paquete y, si el pipeline ya corrió, que las
# cifras reproducidas coincidan con las declaradas.
verify:
	$(PYTHON) scripts/verify.py

# Construye el contenedor reproducible y ejecuta el pipeline dentro.
docker-build:
	docker build -t ressearch-package:latest .

docker-run: docker-build
	docker run --rm -v $(PWD):/work -w /work ressearch-package:latest make reproduce

clean:
	rm -rf _local_outputs/ .venv/ __pycache__/ .Rhistory
