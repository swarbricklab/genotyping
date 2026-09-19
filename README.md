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
Annotation of the VCF file is based on [this annotation reference](https://www.thermofisher.com/order/catalog/product/901153?SID=srch-srp-901153) (also by ThermoFisher Scientific), which in turn is based on the `hg19` assembly of the human genome. 
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

## Third-party software

The genotyping rules call the [Analysis Power Tools](https://www.thermofisher.com/au/en/home/life-science/microarray-analysis/microarray-analysis-partners-programs/affymetrix-developers-network/affymetrix-power-tools.html) (APT) and SNPolisher, which are **proprietary software distributed by ThermoFisher Scientific under their own licence terms**.
They are not covered by the licence for this repository, and this repository does not redistribute them.
To run the workflow you must obtain APT from ThermoFisher and make it available to the `apt`, `ps_metrics`, `ps_classification`, `otv_caller` and `make_vcf` rules.

The same applies to the array annotation files referenced under `refs.apt` in the config file (`Axiom_UKB_WCSG.*`), which must be downloaded from the relevant ThermoFisher [product page](https://www.thermofisher.com/order/catalog/product/901153?SID=srch-srp-901153).

The remaining rules use openly licensed containers: [bcftools](https://github.com/samtools/bcftools) (MIT/Expat) and [samtools](https://github.com/samtools/samtools) (MIT/Expat) via [BioContainers](https://biocontainers.pro/), and the [bcftools +liftover](https://github.com/freeseek/score) plugin (MIT).

## Test data

The `.CEL` files under `test/` and the reference data under `resources/` are tracked with [DVC](https://dvc.org/) against a remote hosted on the NCI Gadi system, which is accessible only to members of project `a56`.
The test `.CEL` files are SNP microarray measurements from human donors and are therefore potentially identifiable; they are **not** publicly redistributable.
Researchers wishing to reproduce the test run should refer to the data availability statement of the associated publication.

The workflow itself does not depend on this data -- it can be run on any set of Axiom `.CEL` files by pointing the config file at them.

## Releases

Projects using this workflow pin a specific revision of it as a git submodule, so that published results can always be traced back to the exact code that produced them.
Revisions used for published analyses are tagged with a `paper/` prefix -- see the [tags](../../tags).

## License

This repository is released under the [MIT License](LICENSE), with the exception of the third-party software noted above.

