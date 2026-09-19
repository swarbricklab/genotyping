# Replace CEL file names by sample names
rule format_vcf:
    """
    Formats the generated VCF by removing unknown positions, reheadering, renaming chromosomes, and sorting it.
    """
    input:
        vcf=rules.make_vcf.output.vcf_file,
        donors=rules.map_donors.output.mapping,
        intxy_map=rules.prepare_chromosome_maps.output.intxy_map,
        int_fai_hg19=rules.prepare_int_fai.output.int_fai
    output:
        vcf_hg19=temp(out_dir/"format/combined.hg19.vcf")
    log:
        logs/"format_vcf.log"
    container:
        "docker://quay.io/biocontainers/bcftools:1.21--h8b25389_0"
    shell:
        """
        grep -v UNKNOWNPOSITION {input.vcf} \
            | bcftools reheader --fai {input.int_fai_hg19} \
            | bcftools reheader -s {input.donors} \
            | bcftools annotate --rename-chrs {input.intxy_map} \
            | bcftools sort \
            | bcftools view - -o {output.vcf_hg19} \
            2> {log}
        """
    
rule liftover:
    """
    Lifts over the VCF file from the hg19 reference genome to the hg38 reference genome using a chain file.
    """
    input:
        vcf_hg19=rules.format_vcf.output.vcf_hg19,
        chr_map=rules.prepare_chromosome_maps.output.chr_map,
        chain=rules.prepare_chain.output.chain,
        src_fa=rules.prepare_hg19.output.fa,
        target_fa=rules.prepare_hg38.output.fa,
        target_fai=rules.prepare_hg38.output.fai
    output:
        vcf_hg38=temp(out_dir/"liftover/combined.hg38.vcf")
    container:
        "docker://yangyxt/bcftools_liftover:1.18"
    log:
        logs/"liftover.log"
    shell:
        """
        bcftools annotate --rename-chrs {input.chr_map} {input.vcf_hg19} \
            | bcftools +liftover -- \
                --chain {input.chain} \
                --src-fasta-ref {input.src_fa} \
                --fasta-ref {input.target_fa} \
            | bcftools sort -o {output.vcf_hg38} \
            2> {log}
        """

rule remove_timestamps:
    input:
        hg19=rules.format_vcf.output.vcf_hg19,
        hg38=rules.liftover.output.vcf_hg38
    output:
        vcf_hg19=vcf_hg19,
        vcf_hg38=vcf_hg38
    log:
        logs/"remove_timestamps.log"
    container:
        "docker://quay.io/biocontainers/bcftools:1.21--h8b25389_0"
    shell:
        """
            function remove_dates () {{
                cat $1 | sed 's/; Date=.*//' | sed '/^##fileDate=/d'
            }}
            remove_dates {input.hg19} | bgzip -c > {output.vcf_hg19}
            remove_dates {input.hg38} | bgzip -c > {output.vcf_hg38}
        """