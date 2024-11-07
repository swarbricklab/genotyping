# Run affy power-tools on (axiom) SNP arrays
rule apt:
    """
    Runs Affymetrix Power Tools (APT) to perform genotyping on SNP arrays using the provided CEL files and annotation.
    """
    input:
        cel_list=out_dir/"cel_list.txt",
        arg_file="resources/genotyping/annotation/Axiom_UKB_WCSG.r5.apt-genotype-axiom.AxiomCN_GT1.apt2.xml",
        dir_annotation="resources/genotyping/annotation/"
    output:
        axiom_calls=temp(out_dir/"apt/AxiomGT1.calls.txt"),
        axiom_snp_posteriors=temp(out_dir/"apt/AxiomGT1.snp-posteriors.txt"),
        axiom_dir=temp(directory(out_dir/"apt")),
        data_dir=temp(directory(out_dir/"apt/AxiomAnalysisSuiteData"))
    log:
        console=logs/"apt/console.log",
        axiom=logs/"apt/apt-genotype-axiom.log"
    container: 
        "docker://swarbricklab/ctp-tools:apt-2.10.2"
    shell:
        # NOTE: for now I'm assuming the SNP file format is UKB
        #       - TODO: make more generic to process the PMDA array type
        """
        apt-genotype-axiom \
            --cel-files {input.cel_list} \
            --out-dir {output.axiom_dir} \
            --batch-folder {output.axiom_dir} \
            --arg-file {input.arg_file} \
            --analysis-files-path {input.dir_annotation} \
            --dual-channel-normalization true \
            --summaries --write-models \
            --console-add-neg-select WARNING,summary,debug \
            --log-file {log.axiom} \
            > {log.console} 2>&1
        """

# Run SNPolisher ps-metrics
rule ps_metrics:
    """
    Runs SNPolisher to generate performance metrics for SNPs using posterior and call files.
    """
    input:
        axiom_snp_posteriors=out_dir/"apt/AxiomGT1.snp-posteriors.txt",
        axiom_calls=out_dir/"apt/AxiomGT1.calls.txt"
    output:
        metrics=temp(out_dir/"ps_metrics/metrics.txt")
    log:
        ps=logs/"ps_metrics/ps_metrics.log",
        console=logs/"ps_metrics/console.log"
    container: 
        "docker://swarbricklab/ctp-tools:apt-2.10.2"
    shell:
        """
        ps-metrics --posterior-file {input.axiom_snp_posteriors} \
            --call-file {input.axiom_calls} \
            --metrics-file {output.metrics} \
            --log-file {log.ps} \
            --console-add-neg-select WARNING,summary,debug \
            > {log.console} 2>&1
        """

# Run SNPolisher ps-classification
rule ps_classification:
    """
    Runs SNPolisher to classify SNPs using performance metrics and an annotation file.
    """
    input:
        metrics=out_dir/"ps_metrics/metrics.txt",
        ps2snp_file="resources/genotyping/annotation/Axiom_UKB_WCSG.r5.ps2snp_map.ps"
    output:
        recommended=temp(out_dir/"ps_classification/Recommended.ps"),
        class_dir=temp(directory(out_dir/"ps_classification/"))
    log:
        ps=logs/"ps_classification/ps_classification.log",
        console=logs/"ps_classification/console.log"
    container: 
        "docker://swarbricklab/ctp-tools:apt-2.10.2"
    shell:
        """
        ps-classification --species-type human \
            --metrics-file {input.metrics} \
            --output-dir {output.class_dir} \
            --ps2snp-file {input.ps2snp_file} \
            --log-file {log.ps} \
            --console-add-neg-select WARNING,summary,debug \
            > {log.console} 2>&1
        """

# Run SNPolisher otv-caller
rule otv_caller:
    """
    Runs SNPolisher to call Off-Target Variants (OTVs) using the recommended SNPs and output from APT.
    """
    input:
        rules.apt.output,
        recommended=out_dir/"ps_classification/Recommended.ps",
        axiom_dir=out_dir/"apt/",
        class_dir=out_dir/"ps_classification/"
    output:
        keep=temp(out_dir/"otv_caller/OTV.keep.ps"),
        otv_dir=temp(directory(out_dir/"otv_caller/"))
    log:
        otv=logs/"otv_caller/otv_caller.log",
        console=logs/"otv_caller/console.log"
    container: 
        "docker://swarbricklab/ctp-tools:apt-2.10.2"
    shell:
        """
        otv-caller --pid-file {input.recommended} \
            --batch-folder {input.axiom_dir} \
            --output-dir {output.otv_dir} \
            --log-file {log.otv} \
            --console-add-neg-select WARNING,summary,debug \
            > {log.console} 2>&1
        """

rule make_vcf:
    """
    Runs apt-format-result to generate a VCF file from the APT outputs using the SNP annotation file.
    """
    input:
        otv_keep=out_dir/"otv_caller/OTV.keep.ps",
        otv_dir=out_dir/"otv_caller/",
        data_dir=out_dir/"apt/AxiomAnalysisSuiteData/",
        apt_dir=out_dir/"apt",
        annotation="resources/genotyping/annotation/Axiom_UKB_WCSG.na35.annot.db"
    output:
        vcf_file=temp(out_dir/"make_vcf/combined.b37.vcf")
    log:
        apt=logs/"make_vcf/apt_format_result.log",
        console=logs/"make_vcf/console.log"
    container: 
        "docker://swarbricklab/ctp-tools:apt-2.10.2"
    shell:
        """
        data_dir=$(realpath --relative-to {input.otv_dir} {input.data_dir})
        apt-format-result --batch-folder {input.otv_dir} \
            --batch-folder-data-dir $data_dir \
            --snp-list-file {input.otv_keep} \
            --annotation-file {input.annotation} \
            --export-vcf-file {output.vcf_file} \
            --log-file {log.apt} \
            --console-add-neg-select WARNING,summary,debug \
            > {log.console} 2>&1
        """
