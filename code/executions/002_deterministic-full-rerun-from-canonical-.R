# ═══════════════════════════════════════════════════════════
# Ressearch AI — Execution Record
# ═══════════════════════════════════════════════════════════
# Run ID:      fast-chat-run-1786039421723-etqegx
# Sequence:    #2
# Title:       Verified reproducibility rehabilitation — full SDM rerun
# Purpose:     Deterministic full rerun from canonical inputs after fixing raster serialization and causal capture
# Objective:   nod_reproducibility-rehabilitation
# Language:    r
# Runtime:     modal · sdm-r
# Status:      succeeded
# Duration:    146963ms
# Started:     2026-08-06T18:10:09.81+00:00
# Installed:   readxl, dplyr, sf, terra, spThin, ENMeval, maxnet, pROC, ggplot2, ggrepel, tidyterra, tidyr, ggnewscale, jsonlite
#
# Path rewrites applied (sandbox → relative):
#   - /data/worldclim (×2)
#   - amazonas.zip (×2)
#   - barriers_sobralia_turkeliae.zip (×2)
#   - Coordenadas_Sobralia turkeliae_nov.xlsx (×2)
#   - external_inputs_manifest.json (×4)
#   - gadm_4.1_per_ecu_col_level0.gpkg (×2)
#   - mantener.geojson (×2)
#   - nod_environmental_tolerance.png (×2)
#   - nod_final_map_countries_fixed.png (×2)
#   - nod_response_curves.png (×2)
#   - nod_variable_importance.csv (×2)
#   - nod_variable_importance.png (×2)
#   - o1_correlation_matrix.csv (×1)
#   - o1_occs_clean.csv (×1)
#   - o1_occs_m_area.geojson (×1)
#   - o1_variable_dendrogram.png (×1)
#   - o2_calibration_results.csv (×1)
#   - o3_barriers_processed.rds (×3)
#   - o3_external_inputs_manifest.json (×3)
#   - o3_final_categorized_map.png (×1)
#   - o4_calibration_results_recalibrated.csv (×1)
#   - o4_suitability_extrapolated.tif (×1)
#   - o5_clipped_suitability.tif (×3)
#   - o8_aoo_grid.geojson (×1)
#   - o8_binary_suitability.tif (×1)
#   - o8_eoo_mcp.geojson (×1)
#   - o8_iucn_metrics.csv (×1)
#   - o8_suitability_double_masked.tif (×3)
# ═══════════════════════════════════════════════════════════
Sys.setenv(RESSEARCH_SCALARS_OUT = '_local_outputs/scalars_run_002.jsonl')
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

# Setup Environment
dir.create("databases", showWarnings = FALSE)
dir.create("analysis-results", showWarnings = FALSE)
dir.create("code", showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)

# Install and load requirements
if (!requireNamespace("tidyterra", quietly = TRUE)) {
  install.packages("tidyterra", repos = "https://cloud.r-project.org")
}

library(readxl)
library(dplyr)
library(sf)
library(terra)
library(spThin)
library(ENMeval)
library(maxnet)
library(pROC)
library(ggplot2)
library(ggrepel)
library(tidyterra)
library(tidyr)
library(ggnewscale)

# The platform's versioned deterministic preamble owns the project seed.

required_inputs <- c(
  "./databases/Coordenadas_Sobralia turkeliae_nov.xlsx",
  "./spatial-objects/barriers_sobralia_turkeliae.zip",
  "./spatial-objects/amazonas.zip",
  "./spatial-objects/gadm_4.1_per_ecu_col_level0.gpkg",
  "./spatial-objects/mantener.geojson",
  "./databases/external_inputs_manifest.json"
)
missing_inputs <- required_inputs[!file.exists(required_inputs)]
if (length(missing_inputs) > 0) stop(paste("Missing canonical inputs:", paste(missing_inputs, collapse = ", ")))
worldclim_files <- list.files("./data/worldclim", pattern = "_bio_?[0-9]+\\.tif$", recursive = TRUE, full.names = TRUE)
if (length(worldclim_files) < 19) stop("WorldClim runtime snapshot is incomplete")

# -----------------------------------------------------------------------------
# STEP 1: Prepare M Area and Generate Variable Dendrogram
# -----------------------------------------------------------------------------
message("[1/10] Loading and cleaning occurrences...")
df <- readxl::read_excel("./databases/Coordenadas_Sobralia turkeliae_nov.xlsx")
df_clean <- df %>%
  filter(!is.na(lon) & !is.na(lat) & lon != 0 & lat != 0) %>%
  distinct(lon, lat, .keep_all = TRUE)
write.csv(df_clean, "./databases/o1_occs_clean.csv", row.names = FALSE)
write.csv(df_clean, "databases/o3_occs_clean.csv", row.names = FALSE)
message(sprintf("Clean records retained: %d", nrow(df_clean)))

# Define M area (convex hull + 1 degree buffer)
occs_sf <- st_as_sf(df_clean, coords = c("lon", "lat"), crs = 4326)
mch <- st_convex_hull(st_union(occs_sf))
m_area <- st_buffer(mch, dist = 1)
st_write(m_area, "./spatial-objects/o1_occs_m_area.geojson", delete_dsn = TRUE, quiet = TRUE)

# Load WorldClim bioclimatic variables
message("Loading WorldClim bioclimatic variables...")
f <- list.files("./data/worldclim", pattern="_bio_?[0-9]+\\.tif$", recursive=TRUE, full.names=TRUE)
f <- f[order(as.integer(sub(".*_bio_?([0-9]+).*", "\\1", basename(f))))]
bio <- terra::rast(f)
names(bio) <- paste0("bio", seq_len(terra::nlyr(bio)))
bio_crop <- terra::crop(bio, vect(m_area), mask = TRUE)

# Environmental correlation dendrogram
message("Generating correlation dendrogram...")
bg_samp <- terra::spatSample(bio_crop, size = 10000, method = "random", na.rm = TRUE, xy = FALSE)
occ_env <- terra::extract(bio_crop, vect(occs_sf))
occ_env <- occ_env[, -1] # drop ID
all_env <- rbind(occ_env, bg_samp)
all_env <- all_env[complete.cases(all_env), ]

cor_mat <- cor(all_env, use = "pairwise.complete.obs", method = "pearson")
write.csv(cor_mat, "./databases/o1_correlation_matrix.csv", row.names = TRUE)

dist_mat <- as.dist(1 - abs(cor_mat))
hc <- hclust(dist_mat, method = "average")

png("./figures/o1_variable_dendrogram.png", width = 800, height = 600, res = 100)
plot(hc, main = "Bioclimatic Variables Clustering (Pearson 1-|r|)",
     xlab = "Variables", sub = "", ylab = "1 - |r|")
abline(h = 0.25, col = "red", lty = 2) # Threshold |r| = 0.75
dev.off()

# -----------------------------------------------------------------------------
# STEP 2: Spatial Thinning
# -----------------------------------------------------------------------------
message("[2/10] Performing spatial thinning (1km)...")
thinned <- spThin::thin(
  loc.data = data.frame(species = df_clean$sp, lon = df_clean$lon, lat = df_clean$lat),
  lat.col = "lat", long.col = "lon", spec.col = "species",
  thin.par = 1, # 1 km
  reps = 1,
  locs.thinned.list.return = TRUE,
  write.files = FALSE, write.log.file = FALSE, verbose = FALSE
)
occs_thinned <- thinned[[1]]
names(occs_thinned) <- c("longitude", "latitude") # Standardize thinned coords
write.csv(occs_thinned, "occs_thinned.csv", row.names = FALSE)
write.csv(occs_thinned, "databases/o3_occs_thinned.csv", row.names = FALSE)
message(sprintf("Thinned records retained: %d", nrow(occs_thinned)))

# -----------------------------------------------------------------------------
# STEP 3: Model Calibration and Hyperparameter Tuning
# -----------------------------------------------------------------------------
message("[3/10] Calibrating MaxEnt model...")
selected_vars <- c("bio1", "bio3", "bio4", "bio12", "bio15", "bio19")
bio_selected <- bio[[selected_vars]]
bio_crop <- terra::crop(bio_selected, vect(m_area), mask = TRUE)

# Background points matching presence names
bg_pts <- terra::spatSample(bio_crop, size = 10000, method = "random", na.rm = TRUE, xy = TRUE)
bg_coords <- bg_pts[, c("x", "y")]
names(bg_coords) <- c("longitude", "latitude") # Standardize background coords

# ENMeval tuning
eval_results <- ENMevaluate(
  occs = occs_thinned, 
  envs = bio_crop, 
  bg = bg_coords,
  algorithm = "maxnet", 
  partitions = "block",
  parallel = FALSE, # Sequential to prevent OOM
  tune.args = list(fc = c("L", "LQ", "LQH"), rm = seq(0.5, 3.0, by = 0.5))
)

res_table <- eval.results(eval_results)
write.csv(res_table, "./databases/o2_calibration_results.csv", row.names = FALSE)
write.csv(res_table, "./databases/o4_calibration_results_recalibrated.csv", row.names = FALSE)
write.csv(res_table, "databases/nod_calibration_results_recalibrated.csv", row.names = FALSE)

best_idx <- which.min(res_table$AICc)
best_tune_args <- as.character(res_table$tune.args[best_idx])
best_model <- eval.models(eval_results)[[best_tune_args]]
message(sprintf("Optimal model: %s (AICc: %f, AUC: %f)", best_tune_args, res_table$AICc[best_idx], res_table$auc.val.avg[best_idx]))

# Emit metrics
emit_metric("best_model_auc", res_table$auc.val.avg[best_idx], kind="ratio")
emit_metric("best_model_aicc", res_table$AICc[best_idx], kind="scalar")

# -----------------------------------------------------------------------------
# STEP 4: Process Barriers shapefile and copy manifest
# -----------------------------------------------------------------------------
message("[4/10] Processing barriers...")
unzip_dir <- "barriers_temp"
if (dir.exists(unzip_dir)) unlink(unzip_dir, recursive = TRUE)
unzip("./spatial-objects/barriers_sobralia_turkeliae.zip", exdir = unzip_dir)
shp_file <- list.files(unzip_dir, pattern="\\.shp$", full.names=TRUE)
barriers <- st_read(shp_file[1], quiet = TRUE)
barriers <- st_transform(barriers, 4326)
saveRDS(barriers, "./databases/o3_barriers_processed.rds")
message("Barriers processed and saved successfully.")

# Copy the manifest
if (file.exists("./databases/external_inputs_manifest.json")) {
  copied_manifest <- file.copy("./databases/external_inputs_manifest.json", "./analysis-results/o3_external_inputs_manifest.json", overwrite = TRUE)
  if (!isTRUE(copied_manifest)) stop("External input manifest copy failed")
}

# -----------------------------------------------------------------------------
# STEP 5: Calculate Variable Importance & Generate Ecological Figures
# -----------------------------------------------------------------------------
message("[5/10] Calculating Variable Importance and generating ecological curves...")
pres_env <- terra::extract(bio_crop, occs_thinned, ID = FALSE)
pres_env <- na.omit(pres_env)
bg_env <- as.data.frame(bg_pts[, selected_vars])

p_vec <- c(rep(1, nrow(pres_env)), rep(0, nrow(bg_env)))
data_env <- rbind(pres_env, bg_env)

# Fit best model
mod <- maxnet(p_vec, data_env, f = maxnet.formula(p_vec, data_env, classes = "lq"), regmult = 0.5)

pred_baseline <- predict(mod, data_env, type = "cloglog")
roc_baseline <- roc(p_vec, as.numeric(pred_baseline), quiet = TRUE)
auc_baseline <- as.numeric(auc(roc_baseline))

var_imp <- data.frame(Variable = selected_vars, Importance = NA)
for(i in 1:length(selected_vars)) {
  var <- selected_vars[i]
  data_perm <- data_env
  data_perm[[var]] <- sample(data_perm[[var]]) # Shuffle values
  pred_perm <- predict(mod, data_perm, type = "cloglog")
  roc_perm <- roc(p_vec, as.numeric(pred_perm), quiet = TRUE)
  auc_perm <- as.numeric(auc(roc_perm))
  var_imp$Importance[i] <- max(0, auc_baseline - auc_perm)
}
var_imp$Importance <- (var_imp$Importance / sum(var_imp$Importance)) * 100
var_imp <- var_imp[order(-var_imp$Importance), ]
write.csv(var_imp, "./databases/nod_variable_importance.csv", row.names = FALSE)
write.csv(var_imp, "./databases/nod_variable_importance.csv", row.names = FALSE)

# Plot Variable Importance
p_imp <- ggplot(var_imp, aes(x = reorder(Variable, Importance), y = Importance)) +
  geom_bar(stat = "identity", fill = "#0072B2", width = 0.6) +
  coord_flip() +
  labs(title = "Permutation Importance for S. turkeliae SDM",
       x = "Environmental Variable", y = "Relative Importance (%)") +
  theme_minimal()
ggsave("./figures/nod_variable_importance.png", plot = p_imp, width = 6, height = 4, dpi = 300, bg = "white")

# Plot Response Curves
png("./figures/nod_response_curves.png", width = 800, height = 600, res = 100)
par(mfrow = c(2, 3), mar = c(4, 4, 2, 1))
for(var in selected_vars) {
  plot(mod, var, type = "cloglog", ylab = "Suitability (cloglog)", xlab = var, 
       main = paste("Response Curve:", var), col = "darkgreen", lwd = 2)
}
dev.off()

# Plot Environmental Tolerance (Presences vs Background)
pres_env$Type <- "Presence"
bg_env$Type <- "Background"
combined_env <- rbind(pres_env, bg_env)

df_long <- pivot_longer(combined_env, cols = all_of(selected_vars), names_to = "variable", values_to = "value")

p_tol <- ggplot(df_long, aes(x = value, fill = Type, color = Type)) +
  geom_density(alpha = 0.4, linewidth = 0.6) +
  facet_wrap(~ variable, scales = "free", ncol = 3) +
  scale_fill_manual(values = c("Presence" = "#D55E00", "Background" = "#999999")) +
  scale_color_manual(values = c("Presence" = "#B24700", "Background" = "#666666")) +
  labs(title = "Environmental Tolerance (Presences vs Background)",
       x = "Value", y = "Density") +
  theme_minimal() +
  theme(
    legend.position = "bottom",
    strip.text = element_text(face = "bold", size = 11),
    plot.title = element_text(face = "bold", size = 14, hjust = 0),
    plot.background = element_rect(fill = "white", color = NA),
    panel.background = element_rect(fill = "white", color = NA)
  )
ggsave("./figures/nod_environmental_tolerance.png", plot = p_tol, width = 9, height = 6, dpi = 300, bg = "white")

# -----------------------------------------------------------------------------
# STEP 6: Suitability Projections (Peru, Ecuador, Colombia)
# -----------------------------------------------------------------------------
message("[6/10] Extrapolating suitability model over regional extent...")
countries_sf <- st_read("./spatial-objects/gadm_4.1_per_ecu_col_level0.gpkg", quiet = TRUE)
bio_extrap_crop <- terra::crop(bio_selected, vect(countries_sf), mask = TRUE)

valid_cells <- which(!is.na(values(bio_extrap_crop[[1]])))
env_df <- as.data.frame(terra::extract(bio_extrap_crop, valid_cells))
if("ID" %in% names(env_df)) { env_df <- env_df[, -1] }

preds_extrap <- predict(best_model, env_df, type = "cloglog")

pred_raster_extrap <- terra::rast(bio_extrap_crop[[1]])
values(pred_raster_extrap) <- NA
values(pred_raster_extrap)[valid_cells] <- as.numeric(preds_extrap)

# Save extrapolated rasters
terra::writeRaster(pred_raster_extrap, "./spatial-objects/o4_suitability_extrapolated.tif", overwrite = TRUE)
# GeoTIFF is the canonical raster; the corrupt duplicate AAIGrid is intentionally omitted.

# -----------------------------------------------------------------------------
# STEP 7: Crop to Amazon Basin & Double-Mask with 'mantener'
# -----------------------------------------------------------------------------
message("[7/10] Masking and clipping suitability raster...")
# Clip with Amazon Basin
amazon_dir <- "amazonas_reproducible_input"
if (dir.exists(amazon_dir)) unlink(amazon_dir, recursive = TRUE)
unzip("./spatial-objects/amazonas.zip", exdir = amazon_dir)
amazon_shp <- list.files(amazon_dir, pattern = "\\.shp$", full.names = TRUE)
if (length(amazon_shp) != 1) stop("Amazon basin archive must contain exactly one shapefile")
amazon <- st_read(amazon_shp[[1]], quiet = TRUE)
amazon <- st_transform(amazon, 4326)
suit_amazon <- terra::crop(pred_raster_extrap, vect(amazon), mask = TRUE)
terra::writeRaster(suit_amazon, "./spatial-objects/o5_clipped_suitability.tif", overwrite = TRUE)
# GeoTIFF is the canonical raster; no duplicate AAIGrid is emitted.

# Mask with 'mantener'
mantener <- st_read("./spatial-objects/mantener.geojson", quiet = TRUE)
suit_double_masked <- terra::mask(suit_amazon, vect(mantener))
terra::writeRaster(suit_double_masked, "./spatial-objects/o8_suitability_double_masked.tif", overwrite = TRUE)

# -----------------------------------------------------------------------------
# STEP 8: Calculate EOO and AOO (IUCN Metrics)
# -----------------------------------------------------------------------------
message("[8/10] Calculating Extent of Occurrence (EOO) and Area of Occupancy (AOO)...")
occs_sf <- st_as_sf(occs_thinned, coords = c("longitude", "latitude"), crs = 4326)

extracted_vals <- terra::extract(suit_double_masked, occs_sf, ID = FALSE)
valid_idx <- which(!is.na(extracted_vals[, 1]))
occs_filtered <- occs_sf[valid_idx, ]
suit_vals <- extracted_vals[valid_idx, 1]

threshold_10p <- quantile(suit_vals, 0.1, na.rm = TRUE)
binary_suit <- suit_double_masked >= threshold_10p
terra::writeRaster(binary_suit, "./spatial-objects/o8_binary_suitability.tif", overwrite = TRUE)

sa_albers <- "+proj=aea +lat_1=-5 +lat_2=-42 +lat_0=-32 +lon_0=-60 +x_0=0 +y_0=0 +ellps=aust_SA +units=m +no_defs"
occs_albers <- st_transform(occs_filtered, crs = sa_albers)

eoo_poly_albers <- st_convex_hull(st_union(occs_albers))
eoo_area_km2 <- as.numeric(st_area(eoo_poly_albers)) / 1e6

eoo_wgs84 <- st_transform(eoo_poly_albers, crs = 4326)
eoo_sf_df <- st_sf(geometry = eoo_wgs84)
st_write(eoo_sf_df, "./spatial-objects/o8_eoo_mcp.geojson", delete_dsn = TRUE, quiet = TRUE)

# Calculate AOO
grid_aoo <- st_make_grid(st_buffer(occs_albers, dist = 2000), cellsize = 2000, square = TRUE)
grid_sf <- st_sf(geometry = grid_aoo)
intersects <- st_intersects(grid_sf, occs_albers)
occupied_cells <- grid_sf[lengths(intersects) > 0, ]
aoo_area_km2 <- nrow(occupied_cells) * 4

occupied_cells_wgs84 <- st_transform(occupied_cells, crs = 4326)
st_write(occupied_cells_wgs84, "./spatial-objects/o8_aoo_grid.geojson", delete_dsn = TRUE, quiet = TRUE)

metrics_df <- data.frame(
  Species = "Sobralia turkeliae",
  Initial_Occurrences = nrow(occs_sf),
  Filtered_Occurrences = nrow(occs_filtered),
  Threshold_10p = round(threshold_10p, 4),
  EOO_km2 = round(eoo_area_km2, 2),
  AOO_km2 = aoo_area_km2,
  Grid_Size = "2x2 km"
)
write.csv(metrics_df, "./databases/o8_iucn_metrics.csv", row.names = FALSE)
write.csv(metrics_df, "databases/nod_iucn_metrics.csv", row.names = FALSE)
emit_metric("clean_occurrence_count", nrow(df_clean), kind = "count")
emit_metric("thinned_occurrence_count", nrow(occs_thinned), kind = "count")
emit_metric("threshold_10p", as.numeric(threshold_10p), kind = "ratio")
emit_metric("eoo_km2", eoo_area_km2, unit = "km2", kind = "scalar")
emit_metric("aoo_km2", aoo_area_km2, unit = "km2", kind = "scalar")
dir.create("analysis-results", showWarnings = FALSE, recursive = TRUE)
metric_evidence <- list(
  best_model_auc = as.numeric(res_table$auc.val.avg[best_idx]),
  best_model_aicc = as.numeric(res_table$AICc[best_idx]),
  clean_occurrence_count = nrow(df_clean),
  thinned_occurrence_count = nrow(occs_thinned),
  threshold_10p = as.numeric(threshold_10p),
  eoo_km2 = eoo_area_km2,
  aoo_km2 = aoo_area_km2
)
jsonlite::write_json(metric_evidence, "analysis-results/nod_reproducibility_metrics.json", auto_unbox = TRUE, pretty = TRUE, digits = NA)

# -----------------------------------------------------------------------------
# STEP 9: Generate Final Suitability Map
# -----------------------------------------------------------------------------
message("[9/10] Plotting final suitability map...")
countries_sf <- st_transform(countries_sf, terra::crs(suit_double_masked))
suit_trimmed <- terra::trim(suit_double_masked)
suit_ext <- ext(suit_trimmed)

barriers$x_right <- sapply(st_geometry(barriers), function(geom) { max(st_coordinates(geom)[, "X"]) })
barriers$y_mid <- sapply(st_geometry(barriers), function(geom) { mean(st_coordinates(geom)[, "Y"]) })

x_max_expanded <- suit_ext[2] + 1.5

p_final <- ggplot() +
  geom_spatraster(data = suit_trimmed) +
  scale_fill_whitebox_c(palette = "muted", na.value = "transparent", name = "Idoneidad") +
  geom_sf(data = countries_sf, fill = NA, color = "gray50", linewidth = 0.5) +
  new_scale_fill() +
  geom_sf(data = eoo_sf_df, aes(color = "EOO"), fill = NA, linetype = "dashed", linewidth = 0.8) +
  geom_sf(data = occupied_cells_wgs84, aes(color = "AOO", fill = "AOO"), alpha = 0.4, linewidth = 0.4) +
  geom_sf(data = occs_filtered, aes(color = "Presencias", fill = "Presencias"), size = 2.2, shape = 21) +
  geom_sf(data = barriers, color = "darkblue", linewidth = 1.6, linetype = "solid") +
  geom_text_repel(
    data = barriers, aes(x = x_right, y = y_mid, label = barrier),
    nudge_x = 0.5, hjust = 0, direction = "y", segment.color = NA,
    color = "darkblue", bg.color = "white", bg.r = 0.15,
    fontface = "bold", size = 3.5
  ) +
  coord_sf(xlim = c(suit_ext[1], x_max_expanded), ylim = c(suit_ext[3] - 0.2, suit_ext[4] + 0.2), expand = FALSE) +
  scale_color_manual(
    name = "Elementos",
    values = c("Presencias" = "black", "EOO" = "black", "AOO" = "blue"),
    breaks = c("Presencias", "EOO", "AOO"),
    guide = guide_legend(
      override.aes = list(
        shape = c(21, NA, NA),
        fill = c("red", NA, "blue"),
        color = c("black", "black", "blue"),
        linetype = c("blank", "dashed", "solid"),
        alpha = c(1, 1, 0.4),
        size = c(2.5, 1, 1)
      )
    )
  ) +
  # Fill has only Presence/AOO levels; use the three-level colour guide
  # as the single combined legend to avoid a malformed override matrix.
  scale_fill_manual(
    values = c("Presencias" = "red", "AOO" = "blue"),
    guide = "none"
  ) +
  labs(
    subtitle = "Idoneidad de Hábitat y Barreras Geográficas de Sobralia turkeliae",
    x = "Longitud", y = "Latitud"
  ) +
  theme_minimal() +
  theme(
    legend.position = "right",
    panel.background = element_rect(fill = "white", color = NA),
    plot.background = element_rect(fill = "white", color = NA)
  )
ggsave("./figures/o3_final_categorized_map.png", plot = p_final, width = 7.5, height = 9.5, dpi = 300, bg = "white")

# -----------------------------------------------------------------------------
# STEP 10: Generate Map with Countries and Fixed Aspect Ratio
# -----------------------------------------------------------------------------
message("[10/10] Plotting map with country borders and fixed aspect ratio...")
r_df <- as.data.frame(suit_amazon, xy = TRUE, na.rm = TRUE)
colnames(r_df)[3] <- "Suitability"

bbox_raster <- st_bbox(c(xmin = xmin(suit_amazon), xmax = xmax(suit_amazon), 
                         ymin = ymin(suit_amazon), ymax = ymax(suit_amazon)), 
                       crs = st_crs(4326))
bbox_polygon <- st_as_sfc(bbox_raster)

countries_clipped <- st_intersection(countries_sf, bbox_polygon)

barrier_col <- "barrier"
barriers_centers <- suppressWarnings(st_centroid(barriers))
coords <- st_coordinates(barriers_centers)
barriers_centers$X <- coords[, "X"]
barriers_centers$Y <- coords[, "Y"]

occs_coords <- as.data.frame(st_coordinates(occs_sf))

p_countries <- ggplot() +
  geom_raster(data = r_df, aes(x = x, y = y, fill = Suitability)) +
  scale_fill_distiller(palette = "Spectral", direction = -1,
                       name = "Habitat\nSuitability",
                       guide = guide_colorbar(barwidth = 1.5, barheight = 12,
                                              frame.colour = "black", ticks.colour = "black")) +
  geom_sf(data = countries_clipped, fill = NA, color = "#474747", linewidth = 0.4) +
  geom_sf(data = barriers, aes(linetype = .data[[barrier_col]]), color = "black", linewidth = 0.8) +
  scale_linetype_discrete(name = "Barriers") +
  geom_text_repel(data = barriers_centers, 
                  aes(x = X, y = Y, label = .data[[barrier_col]]),
                  fontface = "bold", size = 4.5, 
                  bg.color = "white", bg.r = 0.15, 
                  segment.color = "black", min.segment.length = 0,
                  nudge_x = 2, direction = "y", hjust = 0) +
  geom_point(data = occs_coords, aes(x = X, y = Y),
             shape = 4, color = "black", size = 2, stroke = 0.8) +
  coord_sf(xlim = c(bbox_raster["xmin"], bbox_raster["xmax"]), 
           ylim = c(bbox_raster["ymin"], bbox_raster["ymax"]), 
           expand = FALSE) +
  theme_void() +
  theme(
    legend.position = "right",
    legend.title = element_text(face = "bold", size = 12, margin = margin(b = 10)),
    legend.text = element_text(size = 10),
    legend.margin = margin(t = 0, r = 10, b = 0, l = 10),
    legend.key.width = unit(1.5, "cm"),
    plot.background = element_rect(fill = "white", color = NA),
    panel.background = element_rect(fill = "white", color = NA),
    plot.margin = margin(10, 10, 10, 10)
  )
ggsave("./figures/nod_final_map_countries_fixed.png", plot = p_countries, width = 8, height = 8, dpi = 300, bg = "white")

required_outputs <- c(
  "./analysis-results/o3_external_inputs_manifest.json",
  "./databases/o3_barriers_processed.rds",
  "./figures/nod_environmental_tolerance.png",
  "./figures/nod_final_map_countries_fixed.png",
  "./figures/nod_response_curves.png",
  "./figures/nod_variable_importance.png",
  "./spatial-objects/o5_clipped_suitability.tif",
  "./spatial-objects/o8_suitability_double_masked.tif"
)
missing_outputs <- required_outputs[!file.exists(required_outputs)]
if (length(missing_outputs) > 0) stop(paste("Missing required outputs:", paste(missing_outputs, collapse = ", ")))
empty_outputs <- required_outputs[file.info(required_outputs)$size <= 0]
if (length(empty_outputs) > 0) stop(paste("Empty required outputs:", paste(empty_outputs, collapse = ", ")))
if (!inherits(readRDS("./databases/o3_barriers_processed.rds"), "sf")) stop("Processed barriers RDS is invalid")
if (!identical(unname(tools::md5sum("./databases/external_inputs_manifest.json")), unname(tools::md5sum("./analysis-results/o3_external_inputs_manifest.json")))) stop("Manifest bytes changed during copy")
if (terra::ncell(terra::rast("./spatial-objects/o5_clipped_suitability.tif")) <= 0) stop("Clipped suitability GeoTIFF is invalid")
if (terra::ncell(terra::rast("./spatial-objects/o8_suitability_double_masked.tif")) <= 0) stop("Double-masked suitability GeoTIFF is invalid")
message("=== PIPELINE EXECUTION AND OUTPUT VALIDATION SUCCESSFUL ===")
