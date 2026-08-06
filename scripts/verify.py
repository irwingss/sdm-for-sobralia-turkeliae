#!/usr/bin/env python3
"""Verificador offline del Research Package.

No requiere red ni confiar en Ressearch AI: recomputa los SHA-256 del arbol y
los compara contra MANIFEST.json y, si el pipeline ya corrio, compara las
cifras reproducidas contra las declaradas.

Uso:
    python scripts/verify.py        # desde cualquier cwd

Codigo de salida 1 si algo no cuadra.
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DECLARED_SCALARS = ROOT / "provenance" / "scalars.jsonl"
REPRODUCED_SCALARS = ROOT / "_local_outputs" / "scalars_reproduced.jsonl"
# Cifras que el manuscrito CITA (document/cite_map.json). Una cifra citada que
# no se re-emite es un hueco de reproducibilidad que el revisor debe ver como
# fallo; una métrica interna no re-emitida sigue siendo sólo un aviso.
CITE_MAP = ROOT / "document" / "cite_map.json"

# Tolerancia relativa al comparar cifras: absorbe ruido de punto flotante
# entre plataformas, no diferencias reales de resultado.
REL_TOL = 1e-6


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def check_integrity(manifest):
    """Recomputa el digest de CADA archivo listado. Ausente = fallo."""
    missing, drift, ok = [], [], 0
    for rel, expected in (manifest.get("checksums") or {}).items():
        target = ROOT / rel
        if not target.exists():
            missing.append(rel)
        elif sha256_file(target) != expected:
            drift.append(rel)
        else:
            ok += 1
    return missing, drift, ok


def check_manifest_self():
    """Compara MANIFEST.json contra su sidecar MANIFEST.sha256.

    OJO: es un CHECKSUM, no una firma. Detecta corrupcion y edicion
    descuidada; no prueba autoria, porque quien edite el manifiesto puede
    recomputar el sidecar. Para eso hace falta firma criptografica.
    """
    sidecar = ROOT / "MANIFEST.sha256"
    if not sidecar.exists():
        return None
    expected = sidecar.read_text(encoding="utf-8").split()[0].strip()
    return sha256_file(ROOT / "MANIFEST.json") == expected


def _as_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def load_declared():
    """name -> valor declarado, solo de las cifras que el pipeline puede re-emitir.

    Dos filtros, ambos necesarios para no reprobar un paquete intacto:
      * source='emit-metric' — las extraidas del kernel no se re-emiten.
      * in_pipeline — el pipeline exportado es el linaje SUPERVIVIENTE: los
        intentos fallidos se descartan y los reintentos se colapsan. Las
        cifras de una corrida descartada viajan en el paquete (un
        <cite-num> del manuscrito puede apuntar a ellas) pero no pueden
        reproducirse. Sin este filtro, renombrar una metrica reprobaba el
        paquete para siempre.
    Un name con valores distintos entre corridas es ambiguo -> se descarta.
    """
    declared, ambiguous = {}, set()
    with open(DECLARED_SCALARS, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("source") != "emit-metric":
                continue
            # Ausente en paquetes previos a la feature -> se asume incluida.
            if rec.get("in_pipeline") is False:
                continue
            name = rec.get("scalar_path")
            if not name:
                continue
            value = rec.get("value_numeric")
            if value is None:
                value = rec.get("value_raw")
            if name in declared and declared[name] != value:
                ambiguous.add(name)
            declared[name] = value
    for name in ambiguous:
        declared.pop(name, None)
    return declared, ambiguous


def load_cited_paths():
    """scalar_paths que el manuscrito cita via <cite-num>. Vacio si el paquete
    no trae cite_map.json (paquete anterior a la feature, o sin cifras
    ancladas) -> ninguna cifra se trata como citada y el comportamiento es el
    de antes."""
    if not CITE_MAP.exists():
        return set()
    try:
        entries = json.loads(CITE_MAP.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return set()
    out = set()
    for e in entries if isinstance(entries, list) else []:
        p = e.get("path") if isinstance(e, dict) else None
        if p:
            out.add(p)
    return out


def load_reproduced():
    out = {}
    with open(REPRODUCED_SCALARS, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            name = rec.get("name")
            if name:
                out[name] = rec.get("value")
    return out


def values_match(declared, reproduced):
    d, r = _as_float(declared), _as_float(reproduced)
    if d is None or r is None:
        return str(declared).strip() == str(reproduced).strip()
    if d == r:
        return True
    scale = max(abs(d), abs(r))
    return abs(d - r) <= REL_TOL * scale if scale else True


def check_scalars():
    """Devuelve (estado, detalle). estado: skip | ok | fail."""
    if not DECLARED_SCALARS.exists():
        return "skip", "el paquete no declara cifras (provenance/scalars.jsonl ausente)"
    if not REPRODUCED_SCALARS.exists():
        return "skip", "el pipeline aun no corrio (ejecuta 'make reproduce')"
    declared, ambiguous = load_declared()
    reproduced = load_reproduced()
    cited = load_cited_paths()
    if not declared:
        if ambiguous:
            return "skip", (
                "las {} cifra(s) comparables tienen valores distintos entre "
                "corridas y no son decidibles: {}".format(
                    len(ambiguous), ", ".join(sorted(ambiguous))
                )
            )
        return "skip", "ninguna cifra del pipeline proviene de emit_metric"
    mismatches, absent, absent_cited = [], [], []
    for name, want in declared.items():
        if name not in reproduced:
            # Ausente Y citada en el manuscrito = hueco real: el paper afirma un
            # numero que el pipeline no reprodujo. Ausente y NO citada = metrica
            # interna, sigue siendo aviso (ver razonamiento abajo).
            (absent_cited if name in cited else absent).append(name)
        elif not values_match(want, reproduced[name]):
            mismatches.append((name, want, reproduced[name]))
    detail = {
        "compared": len(declared),
        "mismatches": mismatches,
        "absent": absent,
        "absent_cited": absent_cited,
        "ambiguous": sorted(ambiguous),
    }
    # Un valor DISTINTO reprueba SIEMPRE. Una cifra que no reaparece Y NO esta
    # citada es sólo un aviso: puede no haberse re-emitido por razones legitimas
    # (condicional en el codigo, metrica heredada de un intento previo), y
    # tratar "no puedo confirmarlo" como "esta mal" volveria ruidoso al
    # verificador. Pero si esa cifra la CITA el manuscrito, "no puedo
    # confirmarlo" ES el fallo: el revisor no puede recomputar lo que el paper
    # afirma. Por eso absent_cited tambien reprueba.
    return ("fail" if mismatches or absent_cited else "ok"), detail


def main():
    manifest_path = ROOT / "MANIFEST.json"
    if not manifest_path.exists():
        print("ERROR: no se encontro MANIFEST.json en", ROOT)
        return 1
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    failed = False

    missing, drift, ok = check_integrity(manifest)
    print("== Integridad de archivos ==")
    print("  {} archivo(s) verificado(s) contra MANIFEST.json".format(ok))
    for rel in missing:
        print("  FALTA:  {}".format(rel))
    for rel in drift:
        print("  DRIFT:  {}  (contenido distinto al declarado)".format(rel))
    if missing or drift:
        failed = True

    self_ok = check_manifest_self()
    print("== Manifiesto ==")
    if self_ok is None:
        print("  sin sidecar MANIFEST.sha256 (paquete anterior a la feature)")
    elif self_ok:
        print("  MANIFEST.json coincide con MANIFEST.sha256")
    else:
        print("  ERROR: MANIFEST.json NO coincide con MANIFEST.sha256")
        failed = True

    state, detail = check_scalars()
    print("== Cifras ==")
    if state == "skip":
        print("  omitido: {}".format(detail))
    else:
        print("  {} cifra(s) del pipeline comparada(s)".format(detail["compared"]))
        for name, want, got in detail["mismatches"]:
            print("  DISCREPANCIA: {} declarado={} reproducido={}".format(name, want, got))
        for name in detail.get("absent_cited", []):
            print("  NO REPRODUCIDA: {} — el manuscrito la CITA pero el pipeline no la re-emitio".format(name))
        for name in detail["absent"]:
            print("  aviso: {} no se re-emitio (no comparable, no citada)".format(name))
        for name in detail["ambiguous"]:
            print("  aviso: {} tiene valores distintos entre corridas (no comparable)".format(name))
        if state == "fail":
            failed = True

    print("")
    if failed:
        print("RESULTADO: FALLO — el paquete no verifica.")
        return 1
    print("RESULTADO: OK — el paquete verifica contra su manifiesto.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
