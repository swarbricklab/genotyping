# Replace CEL file names by sample names
rule format_vcf:
    input:
        vcf=out_dir/"make_vcf/combined.b37.vcf",
        samples=out_dir/"sample_map.txt"
    output:
        bcf=temp(out_dir/"combined.b37.bcf"),
        csi=temp(out_dir/"combined.b37.bcf.csi")
    params:
        int_fai_hg19="resources/genomes/hg19/hg19_int.fa.fai",
        chr_map="resources/chr_map.tsv"
    log:
        logs/"format_vcf.log"
    container:
        "docker://quay.io/biocontainers/bcftools:1.21--h8b25389_0"
    shell:
        """
        grep -v UNKNOWNPOSITION {input.vcf} \
            | bcftools reheader --fai {params.int_fai_hg19} \
            | bcftools annotate --rename-chrs {params.chr_map} \
            | bcftools reheader -s {input.samples} \
            | bcftools sort \
            | bcftools view -O b -o {output.bcf} && \
            bcftools index {output.bcf}
        """
    
rule liftover:
    input:
        bcf_b37=out_dir/"combined.b37.bcf"
    output:
        bcf_hg38=out_dir/"combined.hg38.bcf"
    params:
        chain="resources/genotyping/liftover/hg19ToHg38.over.chain",
        src_fa="resources/genomes/hg19/hg19.fa",
        target_fa="resources/genomes/refdata-gex-GRCh38-2020-A/fasta/genome.fa"
    container:
        "docker://yangyxt/bcftools_liftover:1.18"
    log:
        logs/"liftover.log"
    shell:
        """
        bcftools +liftover {input.bcf_b37} \
            --output {output.bcf_hg38} -- \
            --chain {params.chain} \
            --src-fasta-ref {params.src_fa} \
            --fasta-ref {params.target_fa} 2> {log}
        bcftools sort {output.bcf_hg38} 2>> {log}
        """