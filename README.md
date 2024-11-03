# Genotyping

This workflow creates a VCF file based on the SNP microarray data in a set of `.CEL` files.
This VCF file can be used for demultiplexing 10X scRNA-seq data where multiple samples have been "pooled" and captured together.

## Authors

This workflow was originally developed by @nbartonicek as a collection of bash and SGE scripts.
These scripts were then refactored as part of the Swarbrick Lab [souporcell workflow](https://git.gimr.garvan.org.au/CTP/soup-or-cell) (VPN required) by @dlroden, as an extension of the [original souporcell workflow](https://github.com/wheaton5/souporcell) by @wheaton5 et al.
Parts of the Swarbrick Lab souporcell workflow were then transferred to the Swarbrick Lab [demuxafy workflow](https://github.com/swarbricklab/demuxafy) by @dlroden and @BeataKiedik, as an extension of the [original demuxafy workflow](https://github.com/drneavin/Demultiplexing_Doublet_Detecting_Docs) by @drneavin.
Finally, the genotyping steps in the Swarbrick Lab demuxafy workflow were extracted and refactored as a standalone workflow (this repo) by @johnyaku.

## Overview

SNP microarray data is stored in `.CEL` files, with one `.CEL` file per sample, as defined in a sample sheet.
This workflow uses the [Analysis Power Tools](https://www.thermofisher.com/au/en/home/life-science/microarray-analysis/microarray-analysis-partners-programs/affymetrix-developers-network/affymetrix-power-tools.html) (APT) by ThermoFisher Scientific to convert these `.CEL` files into a single VCF file containing high-confidence variant calls for all samples.
Annotation of the VCF file is based on [this annotation reference](https://www.thermofisher.com/order/catalog/product/901153?SID=srch-srp-901153), also by ThermoFisher Scientific.

The workflow, defined by the [Snakefile](workflow/Snakefile) runs as shown by the following rule graph:

![Rulegraph](docs/rulegraph.svg)

