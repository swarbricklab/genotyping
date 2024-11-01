# ==================================
# Dan Roden
# Beata Kiedik
# ----------------------------------
# CREATED: 07/03/2022
# ----------------------------------
# Rules for processing genotyping arrays for all samples in a project
# ------------------------------------------------------------------------------
# ==================================

# ==================================
# Generate CEL file input list full
# ----------------------------------
# ==================================
rule generate_cel_file_list_all:
    input:
        cel_files=get_cel_files_input_all
    output:
        cel_list=out_dir/"cel_list.txt"
    log:
        logs/"genotyping/output.generate_cel_file_list.log"
    run:
        import pandas as pd
        df = pd.DataFrame(input.cel_files, columns=["cel_files"])
        df.to_csv(output.cel_list, sep="\t", index=False)

# ==================================
# Run affy power-tools on (axiom) SNP arrays
# ----------------------------------
# TODO/QUESTIONS:
#   - Does the SNP geneotyping processing results depend on which samples are run together? i.e., if I run samples1-3 as a batch, is the output of sample1 different to running just sample1 alone?
#     I'd like to run each sample separately, but currently the script uses a "batch-folder" to run the sample (just the pool?) together
# ==================================
# TODO: rewrite for project based list, not per capture files. 
# actually in previous step we generated one capture id == project id
rule apt:
    input:
        cel_list=out_dir/"cel_list.txt",
        # apt files
        arg_file="resources/genotyping/annotation/Axiom_UKB_WCSG.r5.apt-genotype-axiom.AxiomCN_GT1.apt2.xml",
        # common-common_variants for genotyping
        common_variants="resources/genotyping/variants/common_variants_grch38.vcf"
    output:
        axiom_log=out_dir/"apt/apt-genotype-axiom.log",
        axiom_calls=out_dir/"apt/AxiomGT1.calls.txt",
        axiom_confidences=out_dir/"apt/AxiomGT1.confidences.txt",
        axiom_report=out_dir/"apt/AxiomGT1.report.txt",
        axiom_snp_posteriors=out_dir/"apt/AxiomGT1.snp-posteriors.txt",
        axiom_summary=out_dir/"apt/AxiomGT1.summary.a5",
        axion_chp_bin=out_dir/"apt/AxiomAnalysisSuiteData/All_genotypes_by_snps.CHP.bin",
        axion_chp_index=out_dir/"apt/AxiomAnalysisSuiteData/All_genotypes_by_snps.CHP.index.txt"
    params:
        dir_annotation="resources/genotyping/annotation/",
        dir_output=out_dir/"apt/"
    log:
        logs/"genotyping/apt/output.apt.log"
    container: 
        "docker://swarbricklab/ctp-tools:apt-2.10.2"
    shell:
        # NOTE: for now I'm assuming the SNP file format is UKB
        #       - TODO: make more generic to process the PMDA array type
        "apt-genotype-axiom --log-file {output.axiom_log} --arg-file {input.arg_file} --analysis-files-path {params.dir_annotation} --out-dir {params.dir_output} --dual-channel-normalization true --cel-files {input.cel_list} --summaries --write-models --batch-folder {params.dir_output} --console-add-neg-select WARNING,summary,debug > {log} 2>&1"


# ==================================
# Run SNPolisher ps-metrics
# ----------------------------------
# ==================================
rule ps_metrics:
    input:
        axiom_snp_posteriors=out_dir/"apt/AxiomGT1.snp-posteriors.txt",
        axiom_calls=out_dir/"apt/AxiomGT1.calls.txt"
    output:
        metrics=out_dir/"ps_metrics/metrics.txt"
    log:
        logs/"genotyping/ps_metrics/output.ps_metrics.log"
    container: 
        "docker://swarbricklab/ctp-tools:apt-2.10.2"
    shell:
        "ps-metrics --posterior-file {input.axiom_snp_posteriors} --call-file {input.axiom_calls} --metrics-file {output.metrics} --log-file {log} --console-add-neg-select WARNING,summary,debug > {log}.console_output.log 2>&1"

# ==================================
# Run SNPolisher ps-classification
# ----------------------------------
# ==================================
rule ps_classification:
    input:
        metrics=out_dir/"ps_metrics/metrics.txt",
        ps2snp_file="resources/genotyping/annotation/Axiom_UKB_WCSG.r5.ps2snp_map.ps"
    output:
        # TODO: full list of the output from this step.
        #       - I assume "Recommended.ps" is one of the outputs as it's needed for the otv-caller
        recommended=out_dir/"ps_classification/Recommended.ps"
    params:
        dir_output=out_dir/"ps_classification/"
    log:
        logs/"genotyping/ps_classification/output.ps_classification.log"
    container: 
        "docker://swarbricklab/ctp-tools:apt-2.10.2"
    shell:
        "ps-classification --species-type human --metrics-file {input.metrics} --output-dir {params.dir_output} --ps2snp-file {input.ps2snp_file} --log-file {log} --console-add-neg-select WARNING,summary,debug > {log}.console_output.log 2>&1"


# ==================================
# Run SNPolisher otv-caller
# ----------------------------------
# ==================================
rule otv_caller:
    input:
        rules.apt.output,
        recommended=out_dir/"ps_classification/Recommended.ps"
    output:
        otv_output=expand(genotyping/"otv_caller/{otv_files}", otv_files=["OTV.BIC.txt", "OTV.calls.txt", "OTV.confidences.txt", "OTV.keep.ps", "OTV.remove.ps", "OTV.snp-posteriors.txt", "OTV.summary.txt"])
    params:
        dir_batch=out_dir/"apt/",
        dir_output=out_dir/"otv_caller/"
    log:
        logs/"genotyping/otv_caller/output.otv_caller.log"
    container: 
        "docker://swarbricklab/ctp-tools:apt-2.10.2"
    shell:
        "otv-caller --pid-file {input.recommended} --batch-folder {params.dir_batch} --output-dir {params.dir_output} --log-file {log} --console-add-neg-select WARNING,summary,debug > {log}.console_output.log 2>&1"

# =================================================================
############### create vcf and convert from hg19 to b38
# fetch sqlite annotation from https://www.thermofisher.com/order/catalog/product/901153?SID=srch-srp-901153
# WARNING: it will throw an error if the file already exits
# =================================================================

# ==================================
# Run ("runPolisher") apt-format-result
# ----------------------------------
# ==================================
rule apt_format_result:
    input:
        annotation="resources/genotyping/annotation/Axiom_UKB_WCSG.na35.annot.db",
        otv_keep=out_dir/"otv_caller/OTV.keep.ps"
    output:
        vcf_file=out_dir/"apt_format_result/combined.b37.vcf"
    params:
        dir_batch=out_dir/"otv_caller/",
        batch_folder_data_dir="../apt/AxiomAnalysisSuiteData/"
    log:
        logs/"genotyping/apt_format_result/output.apt_format_result.log"
    container: 
        "docker://swarbricklab/ctp-tools:apt-2.10.2"
    shell:
        "apt-format-result --batch-folder {params.dir_batch} --batch-folder-data-dir {params.batch_folder_data_dir} --snp-list-file {input.otv_keep} --annotation-file {input.annotation} --export-vcf-file {output.vcf_file} --log-file {log} --console-add-neg-select WARNING,summary,debug > {log}.console_output.log 2>&1"

