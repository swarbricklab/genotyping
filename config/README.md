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
      - resources/genomes/refdata-gex-GRCh38-2020-A/fasta/genome.fa
      - resources/liftover/hg19ToHg38.over.chain.gz
      - resources/genotyping/annotation/Axiom_UKB_WCSG.r5.apt-genotype-axiom.AxiomCN_GT1.apt2.xml
      - resources/genotyping/annotation/Axiom_UKB_WCSG.r5.ps2snp_map.ps
      - resources/genotyping/annotation/Axiom_UKB_WCSG.na35.annot.db
    outs:
      - data/snp/genotyping
      - logs/snp/genotyping
```

The `deps` and `outs` must be kept in step with the `deps` and `outs` blocks of the config file.
Note that `modules/genotyping/workflow` is listed as a dependency, so that DVC will re-run the stage if the workflow code changes.

See [running the workflow](../docs/run.md#running-as-part-of-a-dvc-super-pipeline) for how to then run and freeze the stage.
