# ==================================
# Identify the chr encoding of bam files
# ----------------------------------
# ================================== 
rule identify_bam_chr_encoding:
    input:
        bam=get_bam_files_input
    output: 
        # TODO: think about where these bam file flags are required as input
        chr_encoding=temp(output/"identify_bam_chr_encoding/{capture_id}/cellranger_bam_file_chr_encoding.txt")
    log:
        logs/"identify_bam_chr_encoding/{capture_id}/identify_bam_chr_encoding.output.log"
    conda:
        "../envs/identify_bam_chr_encoding.yaml"
    script:
        "../scripts/identify_bam_chr_encoding.py"


# ==================================
# Run VCF file processing
# ----------------------------------
# ==================================

# change chr24 to X
rule vcf_change_chr24_to_X:
    input:
        vcf=genotyping/"apt_format_result/combined.b37.vcf"
    output: 
        vcf_chr24_X=genotyping/"preimputation/chr24_to_X_b37.vcf"
    log:
        logs/"genotyping/preimputation/vcf_change_chr24_to_X.log"
    container:
        config["containers"]["SNP_imputation"]
    shell:
        """
        cmd="sed -e 's/^24/X/g' {input.vcf} > {output.vcf_chr24_X}"
        echo $cmd >> {log}
        eval $cmd >> {log} 2>&1
        """

rule vcf_remove_position:
    input:
        vcf_chr24_X=genotyping/"preimputation/chr24_to_X_b37.vcf"
    output: 
        vcf_chr24_X_clean=genotyping/"preimputation/chr24_to_X_b37.clean.vcf"
    log:
        logs/"genotyping/preimputation/vcf_remove_position.log"
    container:
        config["containers"]["SNP_imputation"]
    shell:
        """
        # remove this position (?) not sure why though 
        cmd="grep -v 2147483648 {input.vcf_chr24_X} > {output.vcf_chr24_X_clean}"
        echo $cmd >> {log}
        eval $cmd >> {log} 2>&1
        """

# remove current header
# and reheader the vcf file (according to order in the reference file)
rule vcf_reheader:
    input:
        vcf_chr24_X_clean=genotyping/"preimputation/chr24_to_X_b37.clean.vcf"
    output: 
        vcf_chr24_X_noheader=genotyping/"preimputation/chr24_to_X_b37.clean.noheader.vcf",
        vcf_reheader=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.vcf"
    params:
        # TODO: pull these references from config 
        FAI="resources/genomes/refdata-cellranger-GRCh38-3.0.0/fasta/genome.fa.fai"
    log:
        logs/"genotyping/preimputation/vcf_reheader.log"
    container:
        config["containers"]["SNP_imputation"]
    shell:
        """
        # remove current header
        cmd="sed -e '/##contig=<ID=/d' {input.vcf_chr24_X_clean} > {output.vcf_chr24_X_noheader}"
        echo $cmd >> {log}
        eval $cmd >> {log} 2>&1

        # reheader the vcf file (according to order in the reference file)
        cmd="bcftools reheader -f {params.FAI} {output.vcf_chr24_X_noheader} > {output.vcf_reheader}"
        echo $cmd >> {log}
        eval $cmd >> {log} 2>&1
        """

# update sequence dict of the vcf 
rule vcf_updated_dict:
    input:
        vcf_reheader=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.vcf"
    output: 
        vcf_dict_updated=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.dict_updated.vcf"
    params:
        # TODO: pull these references from config 
        dictionary="resources/genomes/hg38/hg38.dict"
    log:
        logs/"genotyping/preimputation/vcf_updated_dict.log"
    container:
        config["containers"]["SNP_imputation"]
    shell:
        """
        # update sequence dict of the vcf 
        cmd="java -jar /opt/picard/build/libs/picard.jar UpdateVcfSequenceDictionary I={input.vcf_reheader} O={output.vcf_dict_updated} SEQUENCE_DICTIONARY={params.dictionary}"        
        echo $cmd >> {log}
        eval $cmd >> {log} 2>&1
        """

rule vcf_chr_encoded:
    input:
        vcf_dict_updated=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.dict_updated.vcf"
    output: 
        vcf_MT_replaced=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.dict_updated.chrM.vcf",
        vcf_chr_encoded=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.dict_updated.chr_encoded.vcf"
    log:
        logs/"genotyping/preimputation/vcf_chr_encoded.log"
    container:
        config["containers"]["SNP_imputation"]
    shell:
        """
        # replace MT with chrM
        cmd="sed -e 's/MT/chrM/g' {input.vcf_dict_updated} > {output.vcf_MT_replaced}"
        echo $cmd >> {log}
        eval $cmd >> {log} 2>&1

        # add chr encoding
        cmd="sed -e '/^#/! s/^/chr/' {output.vcf_MT_replaced} > {output.vcf_chr_encoded}"
        echo $cmd >> {log}
        eval $cmd >> {log} 2>&1
        
        # DEBUG: log output
        cmd="grep '#CHROM' {output.vcf_chr_encoded}"
        echo $cmd >> {log}
        eval $cmd >> {log} 2>&1
        """

rule sort_vcf:
    input:
        vcf_chr_encoded=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.dict_updated.chr_encoded.vcf"        
    output: 
        vcf_sorted=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.dict_updated.chr_encoded.sorted.vcf"
    log:
        logs/"genotyping/preimputation/sort_vcf.log"
    container:
        config["containers"]["SNP_imputation"]
    shell:
        """
        # Sort vcf file with picard::SortVcf
        cmd="java -jar /opt/picard/build/libs/picard.jar SortVcf \
        I={input.vcf_chr_encoded} \
        O={output.vcf_sorted}"
        echo $cmd >> {log}
        eval $cmd >> {log} 2>&1

        # DEBUG: log output
        cmd="grep '#CHROM' {output.vcf_sorted}"
        echo $cmd >> {log}
        eval $cmd >> {log} 2>&1
        """

rule vcf_remove_unknowns:
    input:
        vcf_sorted=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.dict_updated.chr_encoded.sorted.vcf"
    output: 
        vcf_removed_unknowns=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.dict_updated.chr_encoded.sorted.removed_unknowns.vcf"
    log:
        logs/"genotyping/preimputation/vcf_remove_unknowns.log"
    container:
        config["containers"]["SNP_imputation"]
    shell:
        """
        # remove possible unknown positions
        cmd="sed -e '/UNKNOWNPOSITION/d' {input.vcf_sorted} > {output.vcf_removed_unknowns}"        
        echo $cmd >> {log}
        eval $cmd >> {log} 2>&1
        """

# Used as input to vcf re-header step
rule generate_cel_genotype_sample_mappings_file:
    input:
        samples=config["samples"],
        vcf=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.dict_updated.chr_encoded.sorted.removed_unknowns.vcf"
    output: 
        genotype_sample_mappings=genotyping/"preimputation/cel_genotype_sample_mappings.txt"
    log:
        logs/"genotyping/preimputation/generate_cel_genotype_sample_mappings_file.log"
    conda:
        "../envs/generate_cel_genotype_sample_mappings_file.yaml"    
    script:
        #  1) map CEL files to GENOTYPE_SAMPLE_IDs (in config - sample-sheet)
        #  2) Use this to re-header the VCF file -> vcf_rename_cel_sample_ids
        "../scripts/generate_cel_genotype_sample_mappings_file.py"

rule vcf_rename_cel_sample_ids:
    input:
        vcf=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.dict_updated.chr_encoded.sorted.removed_unknowns.vcf",
        cel_sample_mappings=genotyping/"preimputation/cel_genotype_sample_mappings.txt"
    output: 
        vcf_sample_ids_mapped=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.dict_updated.chr_encoded.sorted.removed_unknowns.sample_ids_mapped.vcf"
    log:
        logs/"genotyping/preimputation/vcf_rename_cel_sample_ids.log"
    container:
        config["containers"]["SNP_imputation"]
    shell:
        """
        bcftools reheader --samples {input.cel_sample_mappings} {input.vcf} --output {output.vcf_sample_ids_mapped}
        """


# NOTE: this is quite a strange output format. Can we optimise in some way?
rule generate_sample_CEL_file_mappings_file:
    input:
        vcf_sample_ids_mapped=genotyping/"preimputation/chr24_to_X_b37.clean.reheader.dict_updated.chr_encoded.sorted.removed_unknowns.sample_ids_mapped.vcf"
    output: 
        # TODO: rename this file as it's no longer CEL files that are generated here, so the filename is confusing (maybe something like: vcf_sample_header.txt)
        sample_cel_file_mappings=genotyping/"preimputation/CEL_files.txt"
    log:
        logs/"genotyping/preimputation/generate_sample_CEL_file_mappings_file.log"
    container:
        config["containers"]["SNP_imputation"]
    shell:
        """
        # save sample-CEL files names to a file to use in next rule for running plink
        cmd="grep '#CHROM' {input.vcf_sample_ids_mapped} > {output.sample_cel_file_mappings}"
        echo $cmd >> {log}
        eval $cmd >> {log} 2>&1
        """

# ==================================
# make metadata.psam
# ----------------------------------
# ================================== 
rule metadata_psam:
    input:
        CEL_file=genotyping/"preimputation/CEL_files.txt"
    output: 
        psam=genotyping/"metadata/metadata.psam"
    log:
        logs/"genotyping/metadata/metadata_psam.log"
    container:
        config["containers"]["SNP_imputation"]
    shell:
        """
        # write header
        echo -e "#FID\tIID\tPAT\tMAT\tSEX\tProvided_Ancestry" >> {output.psam}

        T=$(printf '\t')
        FID=0
        PAT=0
        MAT=0
        SEX=0
        Ancestry=NONE
        for ID_SAMPLE in $(cat {input.CEL_file}); do 
            echo "$FID$T$ID_SAMPLE$T$PAT$T$MAT$T$SEX$T$Ancestry" >> {output.psam}
        done

        # delete the #CHROM etc from the psam file etc 
        sed -i '/CHROM/d' {output.psam}
        sed -i '/POS/d' {output.psam}
        # remove second line, couldn't grab it by ID, because of ID matching in the header
        sed -i '2d' {output.psam}
        sed -i '/REF/d' {output.psam}
        sed -i '/ALT/d' {output.psam}
        sed -i '/QUAL/d' {output.psam}
        sed -i '/FILTER/d' {output.psam}
        sed -i '/INFO/d' {output.psam}
        sed -i '/FORMAT/d' {output.psam}
        """

# all files are ready to be used in plink, imputation and filtering 

