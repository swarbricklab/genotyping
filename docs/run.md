# Running the workflow

This repo is organised as [Snakemake](https://snakemake.readthedocs.io/en/v7.32.3/index.html) workflow, and has been tested with Snakemake v7.32.4.

## Environment

A conda environment definition for Snakemake v7.32.4 and other dependencies can be found [here](../env/snakemake_7.32.4.yaml).
This environment is available as a global conda environment for project `a56` on NCI.
For other platforms, create this environment as follows:
```
conda env create -f env/snakemake_7.32.4.yaml
```
([Install conda](https://docs.conda.io/projects/conda/en/latest/user-guide/install/index.html) first if necessary.)

## Profiles

This workflow provides two [profiles](https://github.com/swarbricklab/snakemake_config?tab=readme-ov-file#profiles):
1. a [global profile](https://github.com/swarbricklab/snakemake_config) for running the workflow under project `a56` on NCI. This profile is shared by all other workflows running on NCI.
2. a [workflow profile](../profiles/workflow/config.yaml) containing workflow-specific options, such as resource requirements per rule

The global profile can be modified for other platforms, or for other projects on NCI.

## Run script

The workflow can be run as a module with [the following script](../run_mod.sh):
```
./run_mod.sh
```
This script is a lightweight wrapper around the `snakemake` command.
The script activates the conda environment above, and sets profiles based on the detected hostname.
The script assumes that the workflow has been installed as a submodule at `modules/genotyping` (so that the Snakefile is located at `modules/genotyping/workflow/Snakefile`) and that the config file is located at `config/genotyping/config.yaml`.

These default assumptions can be over-ridden by providing `--snakefile` or `--configfile` options.
In fact, the `run_mod.sh` script accepts and passes on any and all snakemake options.
If specified, such options will over-ride the default options in both `run_mod.sh` and in the profiles above.

This can be useful if you need to provide extra resources (such as memory) to a particular rule but don't want to update the profile, for example.

## Running as part of a DVC super pipeline

If this workflow has been [configured as a stage](../config/README.md#dvc-pipeline) in a DVC pipeline, then it can be run as part of the overall pipeline with just
```
dvc repro
```
It is often prudent to first to a dry run to see what will be run first:
```
dvc repro --dry
```

## Freezing the genotyping stage

If the stage for this workflow has run successfully and you want to avoid futile re-runs then you can freeze the stage by adding `frozen: true` to the `dvc.yaml` file.
