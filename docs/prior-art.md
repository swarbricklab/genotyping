# Prior art and citations

Background for the manuscript: what to cite for the tools this workflow drives,
and how the workflow relates to existing Axiom genotyping pipelines.

The workflow takes Affymetrix / Thermo Fisher **Axiom SNP-array `.CEL` files** and
produces an annotated **VCF**, by driving Analysis Power Tools (APT) and SNPolisher
through the Axiom Best Practices steps — `apt-genotype-axiom` → `ps-metrics` →
`ps-classification` → `otv-caller` → `apt-format-result`, followed by `bcftools`
formatting and an `hg19`→`hg38` liftover.

## How to cite the dependencies

### APT and SNPolisher (no peer-reviewed paper)

There is **no dedicated peer-reviewed publication** for Analysis Power Tools or
SNPolisher. They are vendor software, documented only through user guides and white
papers, and Thermo Fisher recommends no citation on the APT or Axiom product pages.
Cite them as software (name, vendor, version, URL), and cite the peer-reviewed papers
for the algorithms they implement.

- **APT / SNPolisher** — Thermo Fisher Scientific (formerly Affymetrix), Santa Clara,
  CA. Give the exact version; note that genotypes are called by `apt-genotype-axiom`,
  so its version is the one to quote for the calling step (see
  [`../containers/apt/README.md`](../containers/apt/README.md#versions)).
- **Axiom Genotyping Solution Data Analysis Guide** — Thermo Fisher manual
  MAN0018363 (`axiom_genotyping_solution_analysis_guide.pdf`). The workflow follows
  this Best Practices document; it is a manual, not a peer-reviewed source.

### Peer-reviewed references for the algorithms

- **Axiom platform / genotyping algorithm (BRLMM-P / AxiomGT1)** — Hoffmann TJ, Kvale
  MN, Hesselson SE, et al. Next generation genome-wide association tool: design and
  coverage of a high-throughput European-optimized SNP array. *Genomics.*
  2011;98(2):79–89. PMID 21565264. doi:10.1016/j.ygeno.2011.04.005
- **Multi-ethnic Axiom array design (companion)** — Hoffmann TJ, Zhan Y, Kvale MN, et
  al. Design and coverage of high throughput genotyping arrays optimized for
  individuals of East Asian, African American, and Latino race/ethnicity using
  imputation and a novel hybrid SNP selection algorithm. *Genomics.*
  2011;98(6):422–430. PMID 21903159. doi:10.1016/j.ygeno.2011.08.007
- **APT-based genotyping/QC best-practices workflow** — Kvale MN, Hesselson S,
  Hoffmann TJ, et al. Genotyping Informatics and Quality Control for 100,000 Subjects
  in the Genetic Epidemiology Research on Adult Health and Aging (GERA) Cohort.
  *Genetics.* 2015;200(4):1051–1060. PMID 26092718. doi:10.1534/genetics.115.178905
- **Off-target-variant (OTV / VINO) basis for `otv-caller`** — Didion JP, Yang H,
  Sheppard K, et al. Discovery of novel variants in genotyping arrays improves
  genotype retention and reduces ascertainment bias. *BMC Genomics.* 2012;13:34.
  PMID 22260749. doi:10.1186/1471-2164-13-34
  (There is no dedicated SNPolisher paper; this describes the phenomenon `otv-caller`
  addresses. Cite it as the methodological basis, not as "the SNPolisher paper".)
- **Rare-variant Axiom calling (Thermo Fisher, UK Biobank)** — Mizrahi-Man O,
  Woehrmann MH, Webster TA, et al. Novel genotyping algorithms for rare variants
  significantly improve the accuracy of Applied Biosystems Axiom array genotyping
  calls: Retrospective evaluation of UK Biobank array data. *PLoS One.*
  2022;17(11):e0277680. PMID 36395175. doi:10.1371/journal.pone.0277680
- **UK Biobank Axiom array context** (if relevant to the dataset) — Bycroft C,
  Freeman C, Petkova D, et al. The UK Biobank resource with deep phenotyping and
  genomic data. *Nature.* 2018;562(7726):203–209. PMID 30305743.
  doi:10.1038/s41586-018-0579-z

### Downstream tools this workflow uses

- **bcftools / samtools** — Danecek P, Bonfield JK, Liddle J, et al. Twelve years of
  SAMtools and BCFtools. *GigaScience.* 2021;10(2):giab008. PMID 33590861.
  doi:10.1093/gigascience/giab008
- **`bcftools +liftover` plugin** — Genovese G, score/liftover
  (https://github.com/freeseek/score). Cite the software and its version.

## Prior art

No existing peer-reviewed tool performs open, reproducible **Axiom-CEL → VCF**
genotyping the way this workflow does. The survey below covers both plain-script tools
and workflow-manager implementations (Nextflow, WDL, Snakemake, CWL, Galaxy). The
recurring pattern: the peer-reviewed tools stop at PLINK and use superseded APT tools;
the tools that reach a modern genotype VCF are unpublished, unlicensed, low-visibility
repositories; and the one published pipeline that reaches VCF from CEL is not
Axiom-native.

### Plain-script tools

| Tool | Endpoint | Licence | Publication |
|---|---|---|---|
| [AffyPipe](https://github.com/nicolazzie/AffyPipe) | PLINK | GPL | **Peer-reviewed** (below) |
| [AGAAT](https://github.com/anilprakash94/agaat) | VCF | MIT | Preprint only (below) |
| [skbioinfo/axiom-ukb-genotyping-qc-pipeline](https://github.com/skbioinfo/axiom-ukb-genotyping-qc-pipeline) | PLINK | MIT (loosely stated) | None |
| [MAF-GRLS/axiom_genotyping](https://github.com/MAF-GRLS/axiom_genotyping) | VCF (canine) | None | None |
| [OpenCGA](https://github.com/opencb/opencga) | ingests VCF (not a CEL caller) | Apache-2.0 | No dedicated paper |

- **AffyPipe** — Nicolazzi EL, Iamartino D, Williams JL. AffyPipe: an open-source
  pipeline for Affymetrix Axiom genotyping workflow. *Bioinformatics.*
  2014;30(21):3118–3119. PMID 25028724. PMC4609010.
  doi:10.1093/bioinformatics/btu486.
  The only peer-reviewed Axiom-CEL prior art, but a decade old and **PLINK-only**:
  it drives the retired **APT 1.15.2** via `apt-probeset-genotype`, not the modern
  `apt-genotype-axiom`, and does not produce a VCF. Because APT, SNPolisher and the
  vendor Axiom library files are non-redistributable, 29 of its 33 committed files are
  zero-byte placeholders (including directories named
  `download_apt-folder_from_AffymetrixWebsite` and
  `download_SNPolisher_from_AffymetrixWebsite`) — the same constraint this workflow
  handles by fetching and checksum-verifying the vendor files at prep time.
- **AGAAT** — Prakash A, Banerjee M. AGAAT: Automated computational tool integrating
  different genotyping array and correctional methods for data analysis. *bioRxiv*
  2025.02.25.637414 (2025). doi:10.1101/2025.02.25.637414. **Preprint only**, not
  peer-reviewed. Reaches VCF (APT + `bcftools +affy2vcf`), then PLINK association.

### Workflow-manager implementations

| Tool | Language | CEL in? | Calls APT? | Endpoint | Licence | Publication |
|---|---|---|---|---|---|---|
| [jasteen/nextflow-workflows](https://github.com/jasteen/nextflow-workflows) | Nextflow | Yes | Yes | genotype calls + SNP QC; no VCF/PLINK | None | None |
| [jfoster-f/dx-axiom](https://github.com/jfoster-f/dx-axiom) | WDL (DNAnexus) | Yes | Yes | calls + cluster plots; no VCF | None | None |
| [swarbricklab/snp_cna_profiler](https://github.com/swarbricklab/snp_cna_profiler) | Snakemake | Yes | Yes | copy-number (PennCNV→ASCAT→GISTIC2) | None shown | None |
| Galaxy GeneTitan pipeline | Galaxy | Yes | Yes (legacy `apt-probeset-genotype`) | PLINK | Not stated | **Peer-reviewed** (below) |
| [freeseek/mochawdl (MoChA)](https://github.com/freeseek/mochawdl) | WDL | SNP 6.0 only | Yes (SNP6) | VCF → mosaic-CNA | MIT | **Peer-reviewed** (below) |

- **`swarbricklab/snp_cna_profiler`** is from the same lab as this workflow. It shares
  the APT + SNPolisher front end but branches to **copy-number** rather than a
  genotype VCF; relate it as a companion pipeline, not independent prior art.
- **Galaxy GeneTitan pipeline** — Karpenko O, Bahroos N, Chukhman M, et al. [A pipeline
  for processing GeneTitan/Axiom genotyping arrays.] *AMIA Jt Summits Transl Sci Proc.*
  2013;2013:102. PMID 24303311. (No DOI indexed for this AMIA proceedings item.)
  Reaches **PLINK**, uses the superseded `apt-probeset-genotype`.
- **MoChA (WDL)** — reaches CEL→VCF, but its `cel` mode supports only the legacy
  **Affymetrix SNP 6.0** array; for modern Axiom biobank arrays it explicitly requires
  the user to run `apt-genotype-axiom` externally and enters at text mode. The MoChA
  method is peer-reviewed (Loh et al., *Nature*); see the repository for its exact
  citations. It is not an Axiom-CEL-native genotyping pipeline.

### Negative results

Stated explicitly because absence is part of the novelty argument:

- **CWL** — none. No Axiom / Affymetrix / `apt-genotype-axiom` CWL workflow on GitHub
  code search, Dockstore, or WorkflowHub.
- **nf-core** — none. No genotyping-array pipeline exists; the ~157 nf-core pipelines
  are all sequencing/omics-focused.
- **WorkflowHub** — nothing relevant (only an unrelated GATK4 fastq→VCF WDL).
- **Galaxy ToolShed** — no current `apt-genotype-axiom` wrapper; the only Galaxy
  artifact is the static 2013 GeneTitan pipeline above.

## Bottom line

Across plain scripts and every major workflow manager, the end-to-end **Axiom-CEL →
APT + SNPolisher (including OTV calling) → annotated VCF with `hg19`→`hg38` liftover**,
packaged in a workflow manager with reproducible, checksum-verified fetching of the
non-redistributable dependencies, has **no direct peer-reviewed prior art**. The nearest
published comparators are AffyPipe and the 2013 Galaxy GeneTitan pipeline (both
peer-reviewed, both PLINK-only, both on superseded APT tooling) and MoChA (peer-reviewed,
reaches VCF, but SNP-6.0-only for CEL input). Everything that is Axiom-CEL-native and
current is unpublished and unlicensed.
