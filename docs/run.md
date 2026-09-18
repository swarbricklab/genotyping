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

## Preparing the APT container

Five of the rules call Analysis Power Tools (APT), which is proprietary and cannot be redistributed with this workflow.
You have to supply that container image yourself, so there is one preparation step before the first run:
```
./modules/genotyping/prep.sh --configfile config/genotyping/config.yaml
```
This reads `containers.apt` from the config file and makes sure a usable image exists at that location, so the script and the workflow cannot disagree about where to look.
It is safe to re-run: if the image is already there it does nothing.

What it does depends on what `containers.apt` holds:

| `containers.apt` | What `prep.sh` does |
|------------------|---------------------|
| a registry reference (`docker://...`) | Nothing to place on disk — checks that the reference can actually be pulled |
| a local path (`containers/apt.sif`) | Builds the image and writes it there, then verifies APT runs inside it |

By default it builds from the [`Dockerfile`](../containers/apt/Dockerfile), which needs `docker` (or `podman`).
**NCI Gadi has Singularity but no Docker**, and Singularity cannot build from a Dockerfile, so on Gadi you cannot use that default.
Build the image on a machine that does have Docker, then give `prep.sh` the result.
[`build.sh`](../containers/apt/build.sh) prompts for EULA acceptance, builds (setting `--platform linux/amd64`, which matters on Apple Silicon) and saves the tarball:
```
# on a machine with docker
./modules/genotyping/containers/apt/build.sh          # writes apt-2.12.0.tar

# on Gadi, after copying the archive across
./modules/genotyping/prep.sh --configfile config/genotyping/config.yaml --from apt-2.12.0.tar
```
Or by hand — the build fails without the EULA acknowledgement:
```
docker build --build-arg ACCEPT_THERMOFISHER_EULA=yes -t apt:2.12.0 modules/genotyping/containers/apt
docker save apt:2.12.0 -o apt-2.12.0.tar
```
Or, if you have pushed the image to a registry you control, pull it directly — this needs no Docker at all:
```
./modules/genotyping/prep.sh --configfile config/genotyping/config.yaml --from docker://your-registry/apt:2.12.0
```
Since APT cannot be redistributed, any registry you use has to be your own.
See [`containers/apt/README.md`](../containers/apt/README.md) for the licensing background and `prep.sh --help` for all options.

## Fetching the Axiom array files

The `refs.apt` entries in the config file point at ThermoFisher's library and annotation files for the array.
These are vendor-supplied and not redistributable, so they are fetched from ThermoFisher rather than shipped here:
```
./modules/genotyping/prep.sh --configfile config/genotyping/config.yaml --what resources
```
This downloads release `r5` of the Axiom UK Biobank (`Axiom_UKB_WCSG`) library files and the `na35` annotation database into the directory holding `refs.apt.arg_file`, then verifies them against [`resources/axiom_ukb_wcsg_r5.sha256`](../resources/axiom_ukb_wcsg_r5.sha256).
About 480 MB of downloads expanding to roughly 2.5 GB, most of it the annotation database.
Re-running is a no-op once the files are present and match.

Use `--what all` to do this and the container in one go.

**It is ten files, not the three the config names.** The arg file is an XML document that references seven further library files (`.cdf`, `specialSNPs`, `chrXprobes`, `chrYprobes`, `AxiomGT1.sketch`, `AxiomGT1.models`, `snp_specific_parameters.txt`) by bare filename.
APT resolves those against `--analysis-files-path`, which the `apt` rule sets to the directory containing the arg file — so all ten have to sit in that one directory.
Downloading only the three named in the config gives a runtime failure, not a config error.

The checksums are ones we recorded, because ThermoFisher publishes none.
They are verified byte-identical to the files used for the published runs, so a mismatch means the vendor has re-released something and is worth understanding before you rely on the results.

Members of project `a56` do not normally need this step — these files come from the DVC remote instead (`dvc pull`).

### Other arrays

Only `array_type: UKB` is supported.
The Axiom Precision Medicine Diversity Array (`PMDA`) needs more than a different set of downloads: it has no `ps2snp_map.ps` (the equivalent is `ps2multisnp_map.ps`) and uses a different annotation build, and the workflow does not handle either yet — see the `TODO` in [`workflow/rules/apt.smk`](../workflow/rules/apt.smk).

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
