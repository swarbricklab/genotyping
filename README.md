# Genotyping

This workflow creates a VCF file based on the SNP microarray data in a set of `.CEL` files.
This VCF file can be used for demultiplexing 10X scRNA-seq data where multiple samples have been "pooled" and captured together.

## Authors

This workflow was originally developed by [@nbartonicek](https://github.com/nbartonicek) as a collection of bash and SGE scripts.
These scripts were then refactored as part of the Swarbrick Lab [souporcell workflow](https://git.gimr.garvan.org.au/CTP/soup-or-cell) (VPN required) by [@dlroden](https://github.com/dlroden), as an extension of the [original souporcell workflow](https://github.com/wheaton5/souporcell) by [@wheaton5](https://github.com/wheaton5) et al.
Parts of the Swarbrick Lab souporcell workflow were then transferred to the Swarbrick Lab [demuxafy workflow](https://github.com/swarbricklab/demuxafy) by [@dlroden](https://github.com/dlroden) and [@BeataKiedik](https://github.com/BeataKiedik), as an extension of the [original demuxafy workflow](https://github.com/drneavin/Demultiplexing_Doublet_Detecting_Docs) by [@drneavin](https://github.com/drneavin).
Finally, the genotyping steps in the Swarbrick Lab demuxafy workflow were extracted and refactored as a standalone workflow (this repo) by [@johnyaku](https://github.com/johnyaku).

## Overview

SNP microarray data is stored in `.CEL` files, with one `.CEL` file per donor sample, as defined in a sample sheet (`donors.csv`).
This workflow converts the genotyping information in these `.CEL` files into a VCF file containing high-confidence variant calls for all donor samples.
Actually, two versions of this VCF file are produced: one for the `hg19` assembly (build 37) and another for the `hg38` assembly (build 38). 

The workflow also creates a `.psam` file, ready for use with `plink`.
The donor IDs in this `.psam` file are reformatted (if necessary) by replacing hyphens with underscores, so `id_map.tsv` is provided for switching back and forth between the original and reformatted donor IDs.

This workflow uses the [Analysis Power Tools](https://www.thermofisher.com/au/en/home/life-science/microarray-analysis/microarray-analysis-partners-programs/affymetrix-developers-network/affymetrix-power-tools.html) (APT) by ThermoFisher Scientific.
Annotation of the VCF file is based on the NetAffx annotation for the [Axiom UK Biobank array](https://www.thermofisher.com/order/catalog/product/902502) (also by ThermoFisher Scientific), which in turn is based on the `hg19` assembly of the human genome. 
This worklow formats the VCF file by adding header contigs for `hg19` and reformatting the chomosome names from 1, 2, 3, ... to chr1, chr2, chr3, ...
Finally, the formatted `hg19` VCF file is lifted over to the `hg38` assembly.

The workflow, defined by the [Snakefile](workflow/Snakefile) runs as shown by the following rule graph:

![Rulegraph](docs/rulegraph.svg)

See the individual rule definitions to understand the function of each rule.

Further reading: [Axiom Genotyping Solution Data Analysis User Guide](https://assets.thermofisher.com/TFS-Assets/LSG/manuals/axiom_genotyping_solution_analysis_guide.pdf)

## Installation and use

- [Installation](docs/installation.md) -- installing this workflow as a git submodule
- [Configuration](config/README.md) -- the config file and the sample sheet
- [Running the workflow](docs/run.md) -- environment, profiles and the run scripts
- [Prior art and citations](docs/prior-art.md) -- how to cite the tools this workflow drives, and how it relates to existing Axiom genotyping pipelines
- [Known limitations](docs/limitations.md) -- chrY/chrMT calls, supported array types, and other caveats

## Third-party software

The genotyping rules call the [Analysis Power Tools](https://www.thermofisher.com/au/en/home/life-science/microarray-analysis/microarray-analysis-partners-programs/affymetrix-developers-network/affymetrix-power-tools.html) (APT) and SNPolisher, which are **proprietary software** distributed by Life Technologies Corporation (ThermoFisher Scientific) under an End User License Agreement.
The EULA grants a non-transferable licence, with no right to sublicense, to use the software on computers you own or control, for research use only, and prohibits distributing or electronically transmitting it -- alone or combined with other products.
APT is not open source: the 2.x downloads ship no source code, and the GPL terms that search results often surface apply to the retired 1.x series.

APT is therefore **not covered by the licence for this repository, and cannot be redistributed with it**.
To run the `apt`, `ps_metrics`, `ps_classification`, `otv_caller` and `make_vcf` rules you must obtain APT from ThermoFisher yourself, under your own acceptance of their terms, and build a container image using the [`Dockerfile`](containers/apt/Dockerfile) in `containers/apt/`.
Point the workflow at the result with `containers.apt` in your config file, as either a registry reference or the path to a local Singularity image:

```yaml
containers:
  apt: "docker://your-registry/apt:2.12.0"
```

The [`prep.sh`](prep.sh) script does this for you — it builds the image, converts it for Singularity if needed, puts it where `containers.apt` points, and checks that APT runs inside it:

```
./modules/genotyping/prep.sh --configfile config/genotyping/config.yaml
```

Because APT cannot be redistributed, any registry you use has to be one you control.
See [preparing the APT container](docs/run.md#preparing-the-apt-container) for the options, including clusters such as NCI Gadi that provide Singularity but not Docker, and [`containers/apt/README.md`](containers/apt/README.md) for the licensing background.

> Earlier revisions of this workflow pinned `docker://swarbricklab/ctp-tools:apt-2.10.2`, a public image that bundled the APT binaries.
> That image is no longer public, because publishing it was not compatible with the EULA above.
> Anything pinning a `paper/`-tagged revision of this workflow will still reference it and will need to be repointed at a locally built image.

Note that the version recorded in that image tag was not accurate: `apt-genotype-axiom` in it reports **2.10.0**, while the SNPolisher tools report 2.10.2.
Genotypes are called by `apt-genotype-axiom`, so **2.10.0** is the version to quote for the calling step.
ThermoFisher still publishes 2.10.0, at a different URL from the current release; `prep.sh --apt-version 2.10.0` builds an image that reproduces the calling step, while the default builds the current 2.12.0. See [`containers/apt/README.md`](containers/apt/README.md#versions).

The array library and annotation files referenced under `refs.apt` in the config file (`Axiom_UKB_WCSG.*`) are vendor-supplied and likewise cannot be redistributed here.
ThermoFisher reserves all rights in them, and they are not covered by the APT EULA, which applies only to the software.
`prep.sh` downloads them for you and checks them against recorded checksums:

```
./modules/genotyping/prep.sh --configfile config/genotyping/config.yaml --what resources
```

Note that the config file names three of these files, but APT reads ten: the arg file is an XML document that references seven further library files by bare filename, which APT resolves against the directory the arg file lives in.
They therefore all have to be downloaded into that one directory.
See [fetching the Axiom array files](docs/run.md#fetching-the-axiom-array-files).

The remaining rules use openly licensed containers: [bcftools](https://github.com/samtools/bcftools) (MIT/Expat) and [samtools](https://github.com/samtools/samtools) (MIT/Expat) via [BioContainers](https://biocontainers.pro/), and the [bcftools +liftover](https://github.com/freeseek/score) plugin (MIT).

## Tools, references and citations

This section records the provenance a citing manuscript needs. Full citations, with DOIs/PMIDs, and how to cite tools that have no dedicated paper (APT, SNPolisher) are in [docs/prior-art.md](docs/prior-art.md#how-to-cite-the-dependencies).

### Platform

| Item | Value | Source |
|---|---|---|
| Array | Applied Biosystems™ UK Biobank Axiom™ Array (`Axiom_UKB_WCSG`) | CEL headers (`affymetrix-array-type`) |
| Array design citation | Bycroft C, et al. *Nature* 2018;562:203–209. doi:10.1038/s41586-018-0579-z | |
| Library package | `Axiom_UKB_WCSG` **r5** | `refs.apt` filenames |
| Annotation build | **na35** (GRCh37/hg19) | `Axiom_UKB_WCSG.na35.annot.db` |
| Genotyping facility | Ramaciotti Centre for Genomics, UNSW Sydney | service records |

### Tools

| Tool | Version | Container | Role |
|---|---|---|---|
| Analysis Power Tools (APT) | `apt-genotype-axiom` **2.10.0** (calling); `ps-metrics`/`ps-classification` 2.10.2; `apt-format-result` 2.10.2.2 | `swarbricklab/ctp-tools:apt-2.10.2` (private; a version mix — see [containers/apt/README.md](containers/apt/README.md#versions)) | genotype calling, metrics, classification, OTV, VCF export |
| SNPolisher | bundled in the APT image | as above | probeset classification |
| bcftools | 1.21 | `quay.io/biocontainers/bcftools:1.21--h8b25389_0` | VCF formatting |
| bcftools `+liftover` | bcftools 1.18 + [liftover plugin](https://github.com/freeseek/score) | `yangyxt/bcftools_liftover:1.18` | hg19 → hg38 liftover |
| samtools | 1.21 | `quay.io/biocontainers/samtools:1.21--h50ea8bc_0` | FASTA indexing |
| Snakemake | 7.32.4 | conda ([`env/snakemake_7.32.4.yaml`](env/snakemake_7.32.4.yaml)) | workflow engine |

Genotypes are called by `apt-genotype-axiom`, so **2.10.0** is the version to quote for the calling step. See [containers/apt/README.md](containers/apt/README.md#versions) for how to build a container pinned to that version.

### Reference data

| Reference | Build | How it is obtained |
|---|---|---|
| hg19 FASTA | UCSC hg19 | `dvc import-url` (UCSC goldenPath) |
| hg38 FASTA | GRCh38, Ensembl release-98 (main chromosomes) | 25 `dvc import-url` stages + the `prepare_hg38` rule |
| liftover chain | UCSC hg19ToHg38 | `dvc import-url` (UCSC gbdb) |
| Axiom library | `Axiom_UKB_WCSG` r5 | Thermo Fisher (`prep.sh --what resources`) |
| Axiom annotation | na35 | Thermo Fisher |

### Citing this workflow

A [`CITATION.cff`](CITATION.cff) at the repository root provides citation metadata, which GitHub surfaces via *Cite this repository*.

To mint a DOI for the archived workflow (once the repository is public):

1. Enable the repository at [zenodo.org](https://zenodo.org) → *GitHub* (Zenodo only sees public repositories).
2. Create a GitHub release (e.g. `v1.0.0`); Zenodo archives it and mints a version DOI plus a version-independent *concept* DOI.
3. Add the concept DOI to `CITATION.cff` (uncomment the `identifiers` block).

Known caveats of the workflow's output are documented in [docs/limitations.md](docs/limitations.md).

## Test data

The test dataset is four human induced pluripotent stem cell lines from [GEO series GSE224950](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE224950), run on the same Axiom UK Biobank array as our own data and deposited by the Powell lab at the Garvan Institute for [Neavin et al. 2023](https://pubmed.ncbi.nlm.nih.gov/37296104/).
Two are female and two male, so the sex calls in the `.psam` are exercised.

These `.CEL` files are not redistributed here.
They are fetched from GEO and checked against recorded checksums by [`prep.sh`](prep.sh):
```
./prep.sh --what testdata
```
See [fetching the test data](docs/run.md#fetching-the-test-data).

Earlier releases tested against SNP microarray measurements from our own donors, which are potentially identifiable and not publicly redistributable.
Those files are no longer referenced here; researchers wanting them should refer to the data availability statement of the associated publication.

The reference data under `resources/` is still tracked with [DVC](https://dvc.org/) against a remote hosted on the NCI Gadi system, accessible only to members of project `a56`, so the test run is not yet reproducible end to end outside the lab.

The workflow itself does not depend on this data -- it can be run on any set of Axiom `.CEL` files by pointing the config file at them.

## Releases

Projects using this workflow pin a specific revision of it as a git submodule, so that published results can always be traced back to the exact code that produced them.
Revisions used for published analyses are tagged with a `paper/` prefix -- see the [tags](../../tags).

## License

This repository is released under the [MIT License](LICENSE), with the exception of the third-party software noted above.

