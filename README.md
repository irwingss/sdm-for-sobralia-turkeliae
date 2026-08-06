# Species distribution model for *Sobralia turkeliae*

> Research Package generado por **[Ressearch AI](https://ressearchai.app)** · 2026-08-06T23:55:37.740488+00:00

## ⚠️ Aviso de asistencia por IA

Este documento fue elaborado con asistencia de Ressearch AI. Su contenido puede incluir material generado o asistido por inteligencia artificial y debe validarse por una persona responsable antes de su publicación, uso clínico, regulatorio o académico. Marco normativo: Ley N.° 31814 del Perú y Reglamento DS 115-2025-PCM.

Marco normativo aplicable: **Ley N.° 31814** (Perú) y su Reglamento **Decreto Supremo N.° 115-2025-PCM**, así como la **NTP-ISO/IEC 42001:2025** (sistema de gestión de IA). Autoridad competente: Secretaría de Gobierno y Transformación Digital (SGTD) de la PCM. Más detalle en la [Tarjeta de Sistema de IA de Ressearch AI](https://ressearchai.app/legal/sistema-de-ia).

## Pregunta de investigación

Species distribution model for *Sobralia turkeliae*

## Objetivos

- Delimitar el área de estudio del raster de idoneidad a la región de la Cuenca Amazónica.
- Integrar las barreras geográficas en el mapa de idoneidad de hábitat.
- Elaborar un mapa de idoneidad de hábitat y barreras utilizando ggplot, categorizando las barreras según sus atributos.

## Contenido del paquete

| Path | Contenido |
|------|-----------|
| `MANIFEST.json` | Inventario + SHA-256 de cada archivo |
| `ro-crate-metadata.json` | RO-Crate 1.1 (FAIR) |
| `codemeta.json` | CodeMeta 2.0 (software metadata) |
| `CITATION.cff` | Cómo citar este paquete |
| `LICENSE` / `LICENSE-DATA` | Licencias de código y datos |
| `Makefile` | `make reproduce` corre todo el pipeline |
| `Dockerfile` | Contenedor reproducible (`make docker-run`) |
| `code/pipeline.R` | Pipeline R (2 ejecución(es)) |
| `code/executions/` | Scripts individuales por ejecución |
| `code/execution_log.jsonl` | Log estructurado (uno-por-línea) |
| `figures/` | 6 figura(s) |
| `databases/` (canvas) | 10 dataset artifact(s) |
| `RESSEARCH_AGENTS.md` | Constitución + journal del agente |
| `provenance/` | Grafo PROV-O + changelog de artifacts |
| `provenance/scalars.jsonl` | Cifras citables: `(run, scalar_path) → valor` |
| `scripts/verify.py` | Verificador offline (checksums + cifras) |
| `environment/` | requirements.txt · environment.yml · r_packages.txt · renv.lock |
| `metadata/` | project.json · research_brief.json · data_availability.md |
| `.env.example` | Variables de entorno que el código necesita — **declaración sin valores** |

## Claves y variables de entorno

Este paquete **no contiene ninguna credencial**. Ni el ZIP, ni el repositorio de
GitHub, ni los scripts de `code/` llevan claves de API, tokens ni contraseñas —
por diseño, no por revisión manual.

Lo que sí incluye es la **declaración** de lo que el código necesita:

```bash
cp .env.example .env    # completá los valores que te falten
```

`.env` está en `.gitignore`, así que no se sube al repositorio. `.env.example`
sí se versiona, porque no tiene valores: sólo nombres, para qué sirve cada uno y
dónde se obtiene.

El código de este paquete no lee ninguna variable de entorno: corre sin credenciales.

## Cómo reproducir

Opción 1 — **Local** (recomendado si tienes Python/R instalado):

```bash
make reproduce
```

Opción 2 — **Contenedor reproducible** (si no quieres tocar tu sistema):

```bash
make docker-run
```

Opción 3 — **Manual**:

```bash
Rscript -e "renv::restore(lockfile='environment/renv.lock')"
cd code && Rscript pipeline.R && cd ..
make verify   # confirma checksums contra MANIFEST.json
```

## Verificación independiente

```bash
make verify        # o: python scripts/verify.py
```

Sin red y sin confiar en Ressearch AI, `scripts/verify.py` comprueba:

1. **Archivos** — recomputa el SHA-256 de cada entrada de `MANIFEST.json`.
   Un archivo ausente es un FALLO, no un aviso.
2. **Manifiesto** — `MANIFEST.sha256` cubre al propio `MANIFEST.json`.
   Es un checksum, **no una firma**: detecta corrupción y edición
   descuidada, no prueba autoría.
3. **Cifras** — si ya corriste `make reproduce`, compara las cifras que
   re-emitió el pipeline contra las declaradas en
   `provenance/scalars.jsonl`.

Sale con código 1 si un archivo falta, cambió, si **una cifra reproduce con
otro valor**, o si **una cifra que el manuscrito CITA (`document/cite_map.json`)
no se re-emitió** — el revisor no puede recomputar lo que el paper afirma. Una
cifra que no reaparece y que **nadie cita** sale como **aviso**, no como fallo:
puede no haberse re-emitido por razones legítimas (una métrica interna detrás de
un condicional) y tratar "no puedo confirmarlo" como "está mal" volvería ruidoso
al verificador. La distinción la da `cite_map.json`: sin él (paquete anterior a
la feature) toda ausencia es sólo aviso, como antes.

Se comparan sólo las cifras de `emit_metric` marcadas `in_pipeline`. Las
demás viajan igual — una cita del manuscrito puede apuntar a ellas — pero no
son reproducibles: las extraídas del kernel no se re-emiten, y el pipeline
exportado es el linaje superviviente (descarta intentos fallidos y colapsa
reintentos).

### Lo que este paquete NO prueba

- No está **firmado**: quien edite un archivo puede recomputar su checksum.
  (Firmar contra identidad pública —ORCID— es el nivel L4, fuera de esta versión.)
- El entorno se reconstruye desde el `Dockerfile`, que fija la imagen base
  **por digest** (`@sha256:…` multi-arch), no sólo por tag; aun así, la
  reproducibilidad bit-a-bit depende de que los paquetes internos estén todos
  pineados. Ver `reproducibility.note` en `MANIFEST.json` para la fidelidad
  medida de este paquete concreto.

## Niveles de garantía (L0–L4)

Cada cifra de resultado del manuscrito se sostiene a un **nivel de garantía**. No
es un formato nuevo: es un perfil sobre la evidencia que este paquete ya trae. Un
tercero asigna el nivel de cualquier cifra citada (`document/cite_map.json`) así:

| Nivel | Qué exige | Dónde se comprueba |
|-------|-----------|--------------------|
| **L0** declarada | la cifra existe como fila | `provenance/scalars.jsonl` |
| **L1** atada | su `execution_run_id` resuelve a una corrida real de máquina (`source` = emit-metric \| kernel-extract) | `provenance/scalars.jsonl` |
| **L2** content-addressable | la corrida tiene `code_hash`, hashes de contenido y sus archivos están en el manifiesto | `MANIFEST.json` (`executions[].codeHash/inputDataHashes/outputHashes`) + `MANIFEST.checksums` |
| **L3** reproducida | la cifra se re-emite dentro de tolerancia al correr el pipeline | `make verify` tras `make reproduce` |
| **L4** firmada | todo lo anterior, contra identidad pública (ORCID) | — fuera de alcance de esta versión |

La app muestra el nivel de cada cifra en vivo (tope honesto **L1**: el manifiesto
y la reproducción no existen sin exportar). Este paquete es justo lo que permite
ganar **L2** y **L3**.

## Estándares cumplidos

- **RO-Crate 1.1** — empaquetado FAIR (`ro-crate-metadata.json`).
- **W3C PROV-O** — grafo de proveniencia (`provenance/provenance.json`).
- **CodeMeta 2.0** — metadata de software (`codemeta.json`).
- **CITATION.cff** — citación interoperable con Zenodo, GitHub, Zotero.

## Licencias

- **Código**: MIT (ver `LICENSE`)
- **Datos / figuras / tablas**: CC-BY-4.0 (ver `LICENSE-DATA`)

## Reproducibilidad estricta

El pipeline inyecta un **random seed determinístico** derivado del proyecto;
los paths del sandbox (E2B `/home/user/`) se reescriben a relativos al
package root antes de exportar; el ZIP contiene un Dockerfile que fija un
entorno cerrado. Si necesitas paridad bit-exacta con el entorno original,
revisa los profiles del sandbox en `code/execution_log.jsonl` (campo
`profile`) y reproduce las imágenes desde el repo de Ressearch AI.

## Limitaciones conocidas

Los pasos se ejecutaron de forma interactiva y pueden depender de **estado en
memoria del kernel** entre turnos que **no se recrea** al correr el pipeline
linealmente. Si un paso falla con `NameError` (Python) u `object '...' not
found` (R), reordená los pasos o recomputá las dependencias del paso previo.
El pipeline instala un hook de error que imprimirá esta misma guía a `stderr`
cuando detecte ese tipo de fallo, sin ocultar el traceback original.

---

Si depositas este paquete en Zenodo, automaticamente recibe un DOI citable
desde tu paper.
