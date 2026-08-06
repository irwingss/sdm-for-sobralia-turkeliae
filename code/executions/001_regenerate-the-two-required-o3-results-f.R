# ═══════════════════════════════════════════════════════════
# Ressearch AI — Execution Record
# ═══════════════════════════════════════════════════════════
# Run ID:      fast-chat-run-1786037071254-kmnsax
# Sequence:    #1
# Title:       Verified barriers and external-input manifest lineage
# Purpose:     Regenerate the two required o3 results from original canonical inputs with embedded deterministic provenance
# Objective:   nod_reproducibility-lineage-repair
# Language:    r
# Runtime:     modal · sdm-r
# Status:      succeeded
# Duration:    2728ms
# Started:     2026-08-06T17:26:49.066+00:00
# Installed:   sf, jsonlite, digest
#
# Path rewrites applied (sandbox → relative):
#   - barriers_sobralia_turkeliae.zip (×4)
#   - external_inputs_manifest.json (×3)
#   - o3_barriers_processed.rds (×3)
#   - o3_external_inputs_manifest.json (×3)
# ═══════════════════════════════════════════════════════════
Sys.setenv(RESSEARCH_SCALARS_OUT = '_local_outputs/scalars_run_001.jsonl')
# Ressearch AI: emit_metric offline — re-emite la cifra para que
# scripts/verify.py pueda compararla contra provenance/scalars.jsonl.
emit_metric <- function(name, value, unit = NA, label = NA, kind = "scalar") {
  .p <- Sys.getenv("RESSEARCH_SCALARS_OUT", unset = "_local_outputs/scalars_reproduced.jsonl")
  try({
    .d <- dirname(.p)
    if (nzchar(.d)) dir.create(.d, showWarnings = FALSE, recursive = TRUE)
    .esc <- function(x) gsub('"', '\\"', as.character(x), fixed = TRUE)
    .pieces <- c(sprintf('"name":"%s"', .esc(name)))
    if (is.numeric(value) && length(value) == 1 && is.finite(value)) {
      .pieces <- c(.pieces, sprintf('"value":%s',
                   format(value, scientific = FALSE, trim = TRUE)))
    } else if (is.logical(value) && length(value) == 1 && !is.na(value)) {
      # Paridad con el prelude del sandbox: sin esta rama un TRUE se emitia
      # como la cadena "TRUE" mientras el lado declarado guarda 1, y el
      # verificador reportaba discrepancia sobre una cifra correcta.
      .pieces <- c(.pieces, sprintf('"value":%s', tolower(.esc(value))))
    } else {
      .pieces <- c(.pieces, sprintf('"value":"%s"', .esc(value)))
    }
    .pieces <- c(.pieces, sprintf('"kind":"%s"', .esc(kind)))
    if (!is.na(unit))  .pieces <- c(.pieces, sprintf('"unit":"%s"',  .esc(unit)))
    if (!is.na(label)) .pieces <- c(.pieces, sprintf('"label":"%s"', .esc(label)))
    cat(paste0("{", paste(.pieces, collapse = ","), "}"), "\n",
        file = .p, append = TRUE, sep = "")
  }, silent = TRUE)
  invisible(value)
}

dir.create("databases", showWarnings = FALSE)
dir.create("analysis-results", showWarnings = FALSE)
library(sf)
library(jsonlite)
library(digest)

required_inputs <- c("./spatial-objects/barriers_sobralia_turkeliae.zip", "./databases/external_inputs_manifest.json")
missing_inputs <- required_inputs[!file.exists(required_inputs)]
if (length(missing_inputs) > 0) stop(paste("Missing canonical inputs:", paste(missing_inputs, collapse = ", ")))

barriers_dir <- "barriers_verified_lineage"
if (dir.exists(barriers_dir)) unlink(barriers_dir, recursive = TRUE)
unzip("./spatial-objects/barriers_sobralia_turkeliae.zip", exdir = barriers_dir)
barriers_shp <- list.files(barriers_dir, pattern = "\\.shp$", full.names = TRUE)
if (length(barriers_shp) != 1) stop("Barriers archive must contain exactly one shapefile")
barriers <- st_transform(st_read(barriers_shp[[1]], quiet = TRUE), 4326)
attr(barriers, "ressearch_provenance") <- list(
  source_file = "./spatial-objects/barriers_sobralia_turkeliae.zip",
  source_sha256 = digest(file = "./spatial-objects/barriers_sobralia_turkeliae.zip", algo = "sha256"),
  deterministic_seed_policy = "project_versioned_preamble",
  deterministic_seed_preamble_version = "1"
)
# Write at the workspace root. Output capture assigns .rds to databases/;
# this also remains compatible with Modal executors deployed before
# directory-kind metadata was added to listFiles.
saveRDS(barriers, "./databases/o3_barriers_processed.rds", version = 3)

manifest <- fromJSON("./databases/external_inputs_manifest.json", simplifyVector = FALSE)
manifest$ressearch_reproducibility <- list(
  source_manifest_sha256 = digest(file = "./databases/external_inputs_manifest.json", algo = "sha256"),
  transformation = "identity_plus_provenance_metadata",
  deterministic_seed_policy = "project_versioned_preamble",
  deterministic_seed_preamble_version = "1"
)
writeLines(
  toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA),
  "./analysis-results/o3_external_inputs_manifest.json",
  useBytes = TRUE
)

restored <- readRDS("./databases/o3_barriers_processed.rds")
if (!inherits(restored, "sf") || nrow(restored) == 0) stop("Processed barriers RDS failed validation")
roundtrip_manifest <- fromJSON("./analysis-results/o3_external_inputs_manifest.json", simplifyVector = FALSE)
if (is.null(roundtrip_manifest$ressearch_reproducibility$source_manifest_sha256)) stop("Manifest provenance is missing")
outputs <- c("./databases/o3_barriers_processed.rds", "./analysis-results/o3_external_inputs_manifest.json")
if (any(!file.exists(outputs)) || any(file.info(outputs)$size <= 0)) stop("Required lineage outputs are missing or empty")
message("Verified barriers and external-input manifest generated successfully")