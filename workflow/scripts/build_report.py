"""Build the static HTML QC report for the genotyping workflow.

Rendered by Snakemake as a `script:` (so `snakemake` is in scope). Engine:
Jinja2 -> a self-contained, offline multi-page bundle, matching
swarbricklab/snp_cna_profiler. Tables-first: no plotting library needed;
distributions are CSS bars and the relatedness matrix is a colour-shaded table.
"""

import gzip
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
from jinja2 import Environment, FileSystemLoader, select_autoescape

# --------------------------------------------------------------------------- #
# Snakemake I/O
# --------------------------------------------------------------------------- #
smk = snakemake  # noqa: F821  (injected by Snakemake)
inp, out, cfg = smk.input, smk.output, smk.config
report_dir = Path(out.report_dir)
# scriptdir is workflow/scripts; templates/static live under workflow/report.
_scriptdir = Path(smk.scriptdir) if hasattr(smk, "scriptdir") else Path(__file__).parent
workflow_dir = _scriptdir.parent
tpl_dir = workflow_dir / "report" / "templates"
static_dir = workflow_dir / "report" / "static"


def log(msg):
    with open(str(smk.log), "a") as fh:
        fh.write(msg + "\n")


# --------------------------------------------------------------------------- #
# Tolerant readers (a missing/renamed input degrades gracefully, never fatal)
# --------------------------------------------------------------------------- #
def safe_read_csv(path, **kw):
    try:
        return pd.read_csv(path, **kw)
    except Exception as e:  # noqa: BLE001
        log(f"WARN could not read {path}: {e}")
        return pd.DataFrame()


def basename(p):
    return Path(str(p)).name


def parse_bcftools_stats(path):
    """Return (summary dict from SN lines, per-sample DataFrame from PSC lines)."""
    sn, psc = {}, []
    try:
        text = Path(path).read_text().splitlines()
    except Exception as e:  # noqa: BLE001
        log(f"WARN stats unreadable: {e}")
        return sn, pd.DataFrame()
    for line in text:
        if line.startswith("SN\t"):
            _, _, key, val = line.split("\t")[:4]
            sn[key.rstrip(":").strip()] = val.strip()
        elif line.startswith("PSC\t"):
            f = line.split("\t")
            # PSC id sample nRefHom nNonRefHom nHets nTs nTv nIndels avgDepth nSingletons nHapRef nHapAlt nMissing
            def _i(v):
                try:
                    return int(float(v))
                except (ValueError, TypeError):
                    return 0
            psc.append({
                "sample": f[2],
                "nRefHom": _i(f[3]), "nNonRefHom": _i(f[4]), "nHets": _i(f[5]),
                "nTs": _i(f[6]), "nTv": _i(f[7]),
                "nSingletons": _i(f[10]) if len(f) > 10 else 0,
                "nMissing": _i(f[13]) if len(f) > 13 else 0,
            })
    return sn, pd.DataFrame(psc)


def parse_gtcheck(path):
    """bcftools gtcheck -> long DataFrame [query, sample, discordance, sites]."""
    rows = []
    try:
        for line in Path(path).read_text().splitlines():
            # modern bcftools: 'DCv2\t<query>\t<genotyped>\t<discordance>\t<avg_depth>\t<nsites>'
            if line.startswith("DC") and "\t" in line:
                f = line.split("\t")
                if len(f) >= 6:
                    try:
                        rows.append({"a": f[1], "b": f[2],
                                     "discordance": float(f[3]),
                                     "sites": int(float(f[-1]))})
                    except ValueError:
                        continue
    except Exception as e:  # noqa: BLE001
        log(f"WARN gtcheck unreadable: {e}")
    return pd.DataFrame(rows)


def count_chroms(vcf_gz):
    """Per-chromosome record counts, read straight from the bgzipped VCF."""
    counts = {}
    try:
        with gzip.open(vcf_gz, "rt") as fh:
            for line in fh:
                if line and line[0] != "#":
                    c = line[: line.index("\t")]
                    counts[c] = counts.get(c, 0) + 1
    except Exception as e:  # noqa: BLE001
        log(f"WARN could not scan {vcf_gz}: {e}")
    return counts


def chrom_sort_key(c):
    m = re.match(r"(?:chr)?(\d+|X|Y|M|MT)$", str(c))
    if not m:
        return (99, str(c))
    v = m.group(1)
    order = {"X": 23, "Y": 24, "M": 25, "MT": 25}
    return (int(v) if v.isdigit() else order.get(v, 98), str(c))


# --------------------------------------------------------------------------- #
# Assemble the data model
# --------------------------------------------------------------------------- #
log(f"building report at {report_dir}")

donors = safe_read_csv(inp.donors, dtype=str)
sample_col = "sample_id" if "sample_id" in donors.columns else ("donor" if "donor" in donors.columns else donors.columns[0])
# CEL basename -> sample label, and -> plate (optional)
bn2sample, bn2plate = {}, {}
for _, r in donors.iterrows():
    bn = basename(r.get("cel_files", ""))
    bn2sample[bn] = r.get(sample_col, bn)
    bn2plate[bn] = r.get("plate", "plate1") if "plate" in donors.columns else "plate1"

dqc = safe_read_csv(inp.dqc_summary)
crs = safe_read_csv(inp.call_rate_summary)
plate = safe_read_csv(inp.plate_qc)
psam = safe_read_csv(inp.psam, sep="\t")

sn, psc = parse_bcftools_stats(inp.stats)
gt = parse_gtcheck(inp.gtcheck)
chroms19 = count_chroms(inp.vcf_hg19)
chroms38 = count_chroms(inp.vcf_hg38)

# Per-sample QC table, keyed on the readable sample label.
def _bn_metric(df, metric):
    d = {}
    if not df.empty and "cel_files" in df.columns and metric in df.columns:
        for _, r in df.iterrows():
            d[basename(r["cel_files"])] = r[metric]
    return d

dqc_by_bn = _bn_metric(dqc, "axiom_dishqc_DQC")
dqcpass_by_bn = _bn_metric(dqc, "passed")
cr_by_bn = _bn_metric(crs, "call_rate")
crpass_by_bn = _bn_metric(crs, "passed")

SEX = {"1": "male", "2": "female", "0": "unknown"}
sex_by_sample = {}
if not psam.empty:
    iid = "IID" if "IID" in psam.columns else psam.columns[1 if len(psam.columns) > 1 else 0]
    sexcol = "SEX" if "SEX" in psam.columns else None
    for _, r in psam.iterrows():
        sex_by_sample[str(r[iid])] = SEX.get(str(r[sexcol]), str(r.get(sexcol, "?"))) if sexcol else "?"

psc_by_sample = {r["sample"]: r for _, r in psc.iterrows()} if not psc.empty else {}

samples = []
for bn, sample in bn2sample.items():
    p = psc_by_sample.get(sample, {})
    n_hom = p.get("nRefHom", 0) + p.get("nNonRefHom", 0)
    het_hom = round(p.get("nHets", 0) / n_hom, 3) if n_hom else None
    samples.append({
        "sample": sample,
        "plate": bn2plate.get(bn, "plate1"),
        "dqc": dqc_by_bn.get(bn),
        "dqc_pass": bool(dqcpass_by_bn.get(bn, True)),
        "call_rate": cr_by_bn.get(bn),
        "cr_pass": bool(crpass_by_bn.get(bn, True)),
        "sex": sex_by_sample.get(sample, "?"),
        "n_het": p.get("nHets"),
        "n_missing": p.get("nMissing"),
        "het_hom": het_hom,
    })
samples.sort(key=lambda s: s["sample"])

# QC funnel
n_total = len(bn2sample)
n_dqc = int(dqc["passed"].sum()) if ("passed" in dqc.columns and not dqc.empty) else n_total
n_cr = int(crs["passed"].sum()) if ("passed" in crs.columns and not crs.empty) else n_total
n_final = len(psc_by_sample) or n_total
funnel = [("Samples in", n_total), ("Pass Dish QC", n_dqc),
          ("Pass call rate", n_cr), ("Genotyped", n_final)]

# Relatedness matrix (pairwise discordance). Low discordance between unrelated
# samples flags a possible duplicate / swap.
rel_labels, rel_matrix, rel_flags = [], [], []
if not gt.empty:
    labels = sorted(set(gt["a"]) | set(gt["b"]))
    rel_labels = labels
    idx = {s: i for i, s in enumerate(labels)}
    mx = [[None] * len(labels) for _ in labels]
    vals = []
    for _, r in gt.iterrows():
        i, j = idx[r["a"]], idx[r["b"]]
        mx[i][j] = mx[j][i] = r["discordance"]
        vals.append(r["discordance"])
    lo, hi = (min(vals), max(vals)) if vals else (0, 1)
    span = (hi - lo) or 1.0
    for i, s in enumerate(labels):
        row = []
        for j in range(len(labels)):
            v = mx[i][j]
            frac = None if v is None else (v - lo) / span
            row.append({"v": v, "frac": frac})
        rel_matrix.append({"sample": s, "cells": row})
    # flag the lowest-discordance off-diagonal pairs
    med = pd.Series(vals).median() if vals else 0
    for _, r in gt.sort_values("discordance").iterrows():
        if r["discordance"] < 0.5 * med:
            rel_flags.append({"a": r["a"], "b": r["b"],
                              "discordance": round(r["discordance"], 4),
                              "sites": int(r["sites"])})

# Per-chromosome table (both builds), naturally sorted
all_chroms = sorted(set(chroms19) | set(chroms38), key=chrom_sort_key)
per_chrom = [{"chrom": c, "hg19": chroms19.get(c, 0), "hg38": chroms38.get(c, 0)}
             for c in all_chroms]

apt = cfg.get("refs", {}).get("apt", {})
qc = cfg.get("qc", {})
provenance = {
    "generated": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
    "container_apt": cfg.get("containers", {}).get("apt", "?"),
    "library": "Axiom_UKB_WCSG r5",
    "annotation": "na35 (GRCh37/hg19)",
    "dqc_threshold": qc.get("dqc_threshold", 0.82),
    "call_rate_threshold": qc.get("call_rate_threshold", 97.0),
    "plate_call_rate_threshold": qc.get("plate_call_rate_threshold", 98.5),
    "plate_pass_rate_threshold": qc.get("plate_pass_rate_threshold", 95.0),
}

overview = {
    "n_samples": n_total,
    "n_records_hg19": sum(chroms19.values()),
    "n_records_hg38": sum(chroms38.values()),
    "n_dropped_liftover": sum(chroms19.values()) - sum(chroms38.values()),
    "sex_counts": pd.Series([s["sex"] for s in samples]).value_counts().to_dict(),
    "ts_tv": sn.get("ts/tv", "?"),
    "n_snps": sn.get("number of SNPs", "?"),
}

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #
env = Environment(loader=FileSystemLoader(str(tpl_dir)),
                  autoescape=select_autoescape(["html"]))
ctx = dict(generated=provenance["generated"], overview=overview, funnel=funnel,
           samples=samples, plate=plate.to_dict("records") if not plate.empty else [],
           per_chrom=per_chrom, sn=sn, psc=psc.to_dict("records") if not psc.empty else [],
           rel_labels=rel_labels, rel_matrix=rel_matrix, rel_flags=rel_flags,
           provenance=provenance)

report_dir.mkdir(parents=True, exist_ok=True)
(report_dir / "assets").mkdir(exist_ok=True)
if static_dir.exists():
    shutil.copytree(static_dir, report_dir / "assets", dirs_exist_ok=True)

pages = {"index": "index.html.j2", "qc": "qc.html.j2", "variants": "variants.html.j2",
         "relatedness": "relatedness.html.j2", "methods": "methods.html.j2"}
for name, tpl in pages.items():
    html = env.get_template(tpl).render(active=name, **ctx)
    (report_dir / f"{name}.html").write_text(html)
    log(f"wrote {name}.html")

log("report complete")
