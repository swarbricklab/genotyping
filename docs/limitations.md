# Known limitations

These are characteristics of the workflow as it was run for the published
results. They are **documented rather than changed**, so the released workflow
reproduces those results exactly. Fixes that would alter the output belong in
follow-up work, tracked as issues, not in the publication release.

## No chrY or chrMT genotype calls

The output VCFs (both `hg19` and `hg38`) contain **no chromosome Y and no
mitochondrial (MT) genotype calls**, even though the Axiom UK Biobank array
targets them — the r5 `specialSNPs` file lists 813 Y and 354 MT probesets. (For
comparison, the GSE224950 depositors' own VCFs, made with Axiom Analysis Suite,
do carry Y and MT calls.)

Two distinct things contribute:

- **MT is explicitly excluded.** [`prepare_int_fai`](../workflow/rules/prep.smk)
  drops the mitochondrial contig (`sed '/M/d'`) when it builds the internal
  FASTA index used to re-header the VCF, so MT is removed at the `hg19`
  formatting stage regardless of what the caller produced.
- **Y is retained through the plumbing but ends up empty.** The Y contig
  survives the internal chromosome mapping (which is why it still appears in the
  header, below), yet no Y records reach the output. They are lost earlier, in
  the APT / SNPolisher calling chain; the exact stage has not been fully
  diagnosed.

For this workflow's purpose — demultiplexing pooled scRNA-seq from autosomal
and X-chromosome SNPs — Y and MT calls are not needed, so this does not affect
that use. It does mean the VCFs are not a complete genotype across Y and MT.

## Phantom Y and M contigs in the VCF header

Both VCFs declare a Y contig in the header (`Y` in `hg19`, `chrY` in `hg38`)
that carries zero records, and the `hg38` VCF likewise declares an empty `chrM`.
These are harmless header artifacts — a contig line with no data — but strict
downstream tools may warn about them. (The `hg19` VCF does not declare an M
contig at all, because `prepare_int_fai` removes it as described above.)

## Only the UK Biobank array is supported

`array_type` must be `UKB`. The Axiom Precision Medicine Diversity Array
(`PMDA`) is not supported: it has no `ps2snp_map.ps` (the equivalent is
`ps2multisnp_map.ps`) and uses a different annotation build, and
[`apt.smk`](../workflow/rules/apt.smk) does not yet handle either — see the
`TODO` there.

## Contig naming differs between the two VCFs

The `hg19` VCF uses bare contig names (`1`–`22`, `X`, `Y`); the `hg38` VCF uses
chr-prefixed names (`chr1`–`chr22`, `chrX`, `chrY`, `chrM`). This follows from
the integer chromosome mapping applied before liftover. Consumers that assume a
single naming convention across both files should account for the difference.
