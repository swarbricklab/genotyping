# Replace CEL file names by sample names
rule format_vcf:
    """
    Formats the generated VCF by removing unknown positions, reheadering, renaming chromosomes, and sorting it.
    """
    input:
        vcf=out_dir/"make_vcf/combined.b37.vcf",
        samples=out_dir/"sample_map.txt",
        chr_map="resources/genomes/hg19/map_int2chr.tsv",
        int_fai_hg19="resources/genomes/hg19/hg19_int.fa.fai"
    output:
        vcf=out_dir/"combined.b37.vcf"
    log:
        logs/"format_vcf.log"
    container:
        "docker://quay.io/biocontainers/bcftools:1.21--h8b25389_0"
    shell:
        """
        grep -v UNKNOWNPOSITION {input.vcf} \
            | bcftools reheader --fai {input.int_fai_hg19} \
            | bcftools annotate --rename-chrs {input.chr_map} \
            | bcftools reheader -s {input.samples} \
            | bcftools sort -o {output.vcf} \
            2> {log}
        """
    
rule liftover:
    """
    Lifts over the VCF file from the hg19 reference genome to the hg38 reference genome using a chain file.
    """
    input:
        vcf_b37=out_dir/"combined.b37.vcf",
        chain="resources/liftover/hg19ToHg38.over.chain",
        src_fa="resources/genomes/hg19/hg19.fa",
        target_fa="resources/genomes/refdata-gex-GRCh38-2020-A/fasta/genome.fa"
    output:
        vcf_hg38=out_dir/"combined.hg38.vcf"
    container:
        "docker://yangyxt/bcftools_liftover:1.18"
    log:
        logs/"liftover.log"
    shell:
        """
        bcftools +liftover {input.vcf_b37} \
            --output {output.vcf_hg38} -- \
            --chain {input.chain} \
            --src-fasta-ref {input.src_fa} \
            --fasta-ref {input.target_fa} 2> {log}
        bcftools sort {output.vcf_hg38} 2>> {log}
        """