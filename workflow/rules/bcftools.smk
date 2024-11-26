# Replace CEL file names by sample names
rule format_vcf:
    """
    Formats the generated VCF by removing unknown positions, reheadering, renaming chromosomes, and sorting it.
    """
    input:
        vcf=out_dir/"make_vcf/combined.b37.vcf",
        samples=out_dir/"sample_map.txt",
        int_fai_hg19=out_dir/"genomes/hg19_int.fa.fai"
    output:
        vcf=vcf_hg19
    log:
        logs/"format_vcf.log"
    container:
        "docker://quay.io/biocontainers/bcftools:1.21--h8b25389_0"
    shell:
        """
        grep -v UNKNOWNPOSITION {input.vcf} \
            | bcftools reheader --fai {input.int_fai_hg19} \
            | bcftools reheader -s {input.samples} \
            | bcftools sort \
            | bcftools view - -Oz -o {output.vcf} \
            2> {log}
        bcftools index {output.vcf} 2>> {log}
        """
    
rule liftover:
    """
    Lifts over the VCF file from the hg19 reference genome to the hg38 reference genome using a chain file.
    """
    input:
        vcf_hg19=vcf_hg19,
        chr_map=out_dir/"genomes/map_int2chr.tsv",
        chain=out_dir/"genomes/hg19ToHg38.over.chain",
        src_fa=out_dir/"genomes/hg19.fa",
        target_fa=config['refs']['genomes']['hg38']
    output:
        vcf_hg38=vcf_hg38
    container:
        "docker://yangyxt/bcftools_liftover:1.18"
    log:
        logs/"liftover.log"
    shell:
        """
        bcftools annotate --rename-chrs {input.chr_map} {input.vcf_hg19} \
            | bcftools +liftover - \
                --output {output.vcf_hg38} -Oz -- \
                --chain {input.chain} \
                --src-fasta-ref {input.src_fa} \
                --fasta-ref {input.target_fa} 2> {log}
        bcftools sort {output.vcf_hg38} 2>> {log}
        """