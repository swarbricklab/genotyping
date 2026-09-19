# Configuration

Configuring the workflow involves editing two files:
- config file (see [this template](template.yaml) for an example)
- sample sheet (see [this example](donors.csv) used for testing)

### Config file

To use this workflow as a module in a super-project, first copy the template config file from the module to the super project:
```
cd top/of/superproject
mkdir -p config/genotyping
cp modules/genotyping/config/template.yaml config/genotyping/config.yaml
```
(*) This assumes that this workflow module has been installed to `modules/genotyping`.

Next, check the paths in the config file and edit if needed. 
In many cases, the template can be left unchanged.
Refer to the comments in the template for the meaning for each item.

One item usually does need changing: **`containers.apt`**.
This names the container image providing Analysis Power Tools (APT) and SNPolisher, which are proprietary and cannot be redistributed with this workflow.
Build your own image with the [`Dockerfile`](../containers/apt/Dockerfile) in `containers/apt/` and set `containers.apt` to either a registry reference or the path of a local Singularity image.

Once this is set, run [`prep.sh`](../prep.sh) to populate it before the first run — it reads this same key, so the two cannot drift apart:
```
./modules/genotyping/prep.sh --configfile config/genotyping/config.yaml
```
See [preparing the APT container](../docs/run.md#preparing-the-apt-container).

The `refs.apt` entries point at ThermoFisher's library and annotation files for the array, which are also not redistributable.
The same script fetches them, into the directory holding `refs.apt.arg_file`:
```
./modules/genotyping/prep.sh --configfile config/genotyping/config.yaml --what resources
```
Note that APT reads ten files from that directory even though only three are named here — see [fetching the Axiom array files](../docs/run.md#fetching-the-axiom-array-files).
Members of project `a56` get these from the DVC remote instead.

The same script also fetches the `.CEL` files for the test dataset, with `--what testdata`; `--what all` does all three stages.
Those are only needed to run [`config/test.yaml`](test.yaml), not your own dataset.

The value in the template is the image used for our published runs, and its registry repository is private, so it will not pull without credentials.
That fallback is deliberate -- it keeps existing dataset configs resolving to the exact image their results came from -- but it means an authentication error on the first APT rule indicates that `containers.apt` has not been set.
See [`containers/apt/README.md`](../containers/apt/README.md).

### Sample sheet

The sample sheet links donors to the `.CEL` file for each donor sample.
There should be exactly one row per donor -- no duplicates.

The sample sheet is a CSV file with the following columns:
- donor
- cel_files
- array_type

These column names are fixed, but additional columns can be added if desired.
See [this example](donors.csv).

The meanings of each column are as follows:

| Column | Meaning |
|--------|---------|
| donor | The donor id to use in the VCF header |
| cel_files | The path to the .CEL file for each donor, relative to the top of the super project |
| array_type | Either 'UKB' or 'PMDA' |

Here 'UKB' refers to the [UK Biobank Array](https://www.thermofisher.com/order/catalog/product/902502),while 'PMDA' refers to the [Axiom Precision Medicine Diversity Array](https://www.thermofisher.com/order/catalog/product/951962?SID=srch-srp-951962).

Make sure that the path to the sample sheet is specified correctly in the config file.

### DVC pipeline

To include this workflow as a stage in a [DVC](https://dvc.org/) pipeline, copy the stage definition from [the template](../.dvc/template.yaml) into the `stages:` block of the `dvc.yaml` file at the top of the super-project:

```
  genotyping:
    cmd: ./modules/genotyping/run_mod.sh
    deps:
      - modules/genotyping/run_mod.sh
      - modules/genotyping/workflow
      - config/genotyping/config.yaml
      - config/genotyping/donors.csv
      - data/snp/microarray
      - resources/genomes/hg19/hg19.fa.gz
      - resources/genomes/GRCh38
      - resources/liftover/hg19ToHg38.over.chain.gz
      - resources/genotyping/annotation/Axiom_UKB_WCSG.r5.apt-genotype-axiom.AxiomCN_GT1.apt2.xml
      - resources/genotyping/annotation/Axiom_UKB_WCSG.r5.ps2snp_map.ps
      - resources/genotyping/annotation/Axiom_UKB_WCSG.na35.annot.db
    outs:
      - data/snp/genotyping
      - logs/snp/genotyping
```

The `deps` and `outs` must be kept in step with the `deps` and `outs` blocks of the config file.
Note that the annotation entries above list only the three files the config names, not the ten APT actually reads, so DVC will not notice a change to the other seven.
Listing `resources/genotyping/annotation` instead would cover all of them, at the cost of changing the stage hash and so forcing a re-run.
Note that `modules/genotyping/workflow` is listed as a dependency, so that DVC will re-run the stage if the workflow code changes.

See [running the workflow](../docs/run.md#running-as-part-of-a-dvc-super-pipeline) for how to then run and freeze the stage.
