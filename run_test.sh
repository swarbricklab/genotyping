#! /bin/bash

set -e
eval  "$(conda shell.bash hook)"
conda activate snakemake_7.32.4

if [[ "$(hostname)" == *"nci"* ]]; then
    echo "Running on NCI"
    global_profile="--profile profiles/global/nci"
    workflow_profile="--workflow-profile profiles/workflow "
    module load singularity
    mkdir -p logs/joblogs
else
    echo "WARNING: Unknown host: $(hostname)"
    echo "WARNING: No known global profile for this host"
    echo "WARNING: Running without global profile"
    echo "See https://github.com/swarbricklab/snakemake_config/blob/main/README.md"
    global_profile=""
fi

# Preflight: verify the APT container and the reference / array / CEL
# dependencies are in place before submitting any jobs. Set SKIP_PREFLIGHT=1
# to bypass (e.g. if you know they are present, or singularity is unavailable
# on this node).
if [[ -z "${SKIP_PREFLIGHT:-}" ]]; then
    ./prep.sh --what check --configfile config/test.yaml
else
    echo "SKIP_PREFLIGHT set -- skipping the dependency preflight."
fi

snakemake $global_profile $workflow_profile \
    --snakefile workflow/Snakefile \
    --configfile config/test.yaml \
    $@
