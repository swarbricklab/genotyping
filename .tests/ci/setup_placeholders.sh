#!/bin/bash
# Touch empty placeholder inputs so `snakemake -n` can build the full DAG in CI
# without any real data. Paths mirror config/test.yaml (the CI config).
set -eu
mkdir -p resources/genomes/hg19 resources/liftover resources/axiom resources/genomes/GRCh38
touch resources/genomes/hg19/hg19.fa.gz \
      resources/liftover/hg19ToHg38.over.chain.gz \
      resources/axiom/Axiom_UKB_WCSG.r5.apt-genotype-axiom.AxiomCN_GT1.apt2.xml \
      resources/axiom/Axiom_UKB_WCSG.r5.ps2snp_map.ps \
      resources/axiom/Axiom_UKB_WCSG.na35.annot.db
# GRCh38 is consumed via expand() over a fixed 25-chromosome list; all must exist.
for c in 1 10 11 12 13 14 15 16 17 18 19 2 20 21 22 3 4 5 6 7 8 9 MT X Y; do
  touch "resources/genomes/GRCh38/Homo_sapiens.GRCh38.dna.chromosome.${c}.fa.gz"
done
echo "placeholders touched"
