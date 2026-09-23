#! /bin/bash

set -e
eval  "$(conda shell.bash hook)"
conda activate snakemake_7.32.4

module=genotyping

if [[ "$(hostname)" == *"nci"* ]]; then
    echo "Running on NCI"
    global_profile="--profile modules/$module/profiles/global/nci"
    workflow_profile="--workflow-profile modules/$module/profiles/workflow "
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
# dependencies are in place before building the rule graph or submitting any
# jobs. Set SKIP_PREFLIGHT=1 to bypass (e.g. if you know they are present, or
# singularity is unavailable on this node). This runs before the rule graph
# because that step also needs the inputs resolvable, so a missing dependency
# gives a clear report here rather than a confusing snakemake/dot failure.
if [[ -z "${SKIP_PREFLIGHT:-}" ]]; then
    modules/$module/prep.sh --what check --configfile config/$module/config.yaml
else
    echo "SKIP_PREFLIGHT set -- skipping the dependency preflight."
fi

# Make rule graph
mkdir -p docs/graphs
snakemake $global_profile $workflow_profile \
    --snakefile modules/$module/workflow/Snakefile \
    --configfile config/$module/config.yaml \
    --rulegraph \
    | dot -Tsvg \
    > docs/graphs/${module}.svg

snakemake $global_profile $workflow_profile \
    --snakefile modules/$module/workflow/Snakefile \
    --configfile config/$module/config.yaml \
    $@