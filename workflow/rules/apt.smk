# Run affy power-tools on (axiom) SNP arrays
rule apt:
    input:
        cel_list=out_dir/"cel_list.txt"
    output:
        axiom_calls=temp(out_dir/"apt/AxiomGT1.calls.txt"),
        axiom_snp_posteriors=temp(out_dir/"apt/AxiomGT1.snp-posteriors.txt"),
        axiom_dir=temp(directory(out_dir/"apt")),
        data_dir=temp(directory(out_dir/"apt/AxiomAnalysisSuiteData"))
    params:
        arg_file="resources/genotyping/annotation/Axiom_UKB_WCSG.r5.apt-genotype-axiom.AxiomCN_GT1.apt2.xml",
        dir_annotation="resources/genotyping/annotation/"
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
            --arg-file {params.arg_file} \
            --analysis-files-path {params.dir_annotation} \
            --dual-channel-normalization true \
            --summaries --write-models \
            --console-add-neg-select WARNING,summary,debug \
            --log-file {log.axiom} \
            > {log.console} 2>&1
        """

# Run SNPolisher ps-metrics
rule ps_metrics:
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
    input:
        metrics=out_dir/"ps_metrics/metrics.txt"
    output:
        recommended=temp(out_dir/"ps_classification/Recommended.ps"),
        class_dir=temp(directory(out_dir/"ps_classification/"))
    params:
        ps2snp_file="resources/genotyping/annotation/Axiom_UKB_WCSG.r5.ps2snp_map.ps"
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
            --ps2snp-file {params.ps2snp_file} \
            --log-file {log.ps} \
            --console-add-neg-select WARNING,summary,debug \
            > {log.console} 2>&1
        """

# Run SNPolisher otv-caller
rule otv_caller:
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

# Run ("runPolisher") apt-format-result
rule make_vcf:
    input:
        otv_keep=out_dir/"otv_caller/OTV.keep.ps",
        otv_dir=out_dir/"otv_caller/",
        data_dir=out_dir/"apt/AxiomAnalysisSuiteData/",
        apt_dir=out_dir/"apt"
    output:
        vcf_file=temp(out_dir/"make_vcf/combined.b37.vcf")
    params:
        annotation="resources/genotyping/annotation/Axiom_UKB_WCSG.na35.annot.db"
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
            --annotation-file {params.annotation} \
            --export-vcf-file {output.vcf_file} \
            --log-file {log.apt} \
            --console-add-neg-select WARNING,summary,debug \
            > {log.console} 2>&1
        """
