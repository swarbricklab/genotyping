# Run affy power-tools on (axiom) SNP arrays
rule apt:
    """
    Runs Affymetrix Power Tools (APT) to perform genotyping on SNP arrays using the provided CEL files and annotation.
    """
    input:
        # QC-passing samples from the Best-Practices front-end (qc.smk), not the
        # raw list -- Dish QC + call-rate + plate QC have already removed
        # failing samples so they cannot contaminate the batch clustering.
        cel_list=rules.plate_qc.output.cel_list,
        arg_file=config['refs']['apt']['step2_arg_file']
    output:
        axiom_calls=temp(out_dir/"apt/AxiomGT1.calls.txt"),
        axiom_summary=temp(out_dir/"apt/AxiomGT1.summary.txt"),
        axiom_snp_posteriors=temp(out_dir/"apt/AxiomGT1.snp-posteriors.txt"),
        apt_report=out_dir/"apt/AxiomGT1.report.txt",
        axiom_dir=temp(directory(out_dir/"apt")),
        data_dir=temp(directory(out_dir/"apt/AxiomAnalysisSuiteData"))
    log:
        console=logs/"apt/console.log",
        axiom=logs/"apt/apt-genotype-axiom.log"
    container:
        apt_container
    shell:
        # NOTE: for now I'm assuming the SNP file format is UKB
        #       - TODO: make more generic to process the PMDA array type
        # Uses the Step2 SNP-specific-priors arg file (Best Practices step 7).
        """
        annotation_dir=$(dirname {input.arg_file})
        apt-genotype-axiom \
            --cel-files {input.cel_list} \
            --out-dir {output.axiom_dir} \
            --batch-folder {output.axiom_dir} \
            --arg-file {input.arg_file} \
            --analysis-files-path $annotation_dir \
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
        axiom_calls=out_dir/"apt/AxiomGT1.calls.txt",
        axiom_summary=out_dir/"apt/AxiomGT1.summary.txt",
        apt_report=out_dir/"apt/AxiomGT1.report.txt",
        special_snps=config['refs']['apt']['special_snps']
    output:
        metrics=temp(out_dir/"ps_metrics/metrics.txt")
    log:
        ps=logs/"ps_metrics/ps_metrics.log",
        console=logs/"ps_metrics/console.log"
    container:
        apt_container
    shell:
        # --special-snps / --use-ssp handle chrX/Y/MT/PAR probesets, and
        # --do-pHW adds the Hardy-Weinberg metric, matching the Best-Practices
        # (and cna_profiler) SNP QC.
        """
        ps-metrics --posterior-file {input.axiom_snp_posteriors} \
            --call-file {input.axiom_calls} \
            --summary-file {input.axiom_summary} \
            --report-file {input.apt_report} \
            --special-snps {input.special_snps} \
            --do-pHW true \
            --use-ssp true \
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
        ps2snp_file=config['refs']['apt']['ps2snp']
    output:
        recommended=temp(out_dir/"ps_classification/Recommended.ps"),
        class_dir=temp(directory(out_dir/"ps_classification/"))
    log:
        ps=logs/"ps_classification/ps_classification.log",
        console=logs/"ps_classification/console.log"
    container: 
        apt_container
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
        apt_container
    shell:
        """
        otv-caller --pid-file {input.recommended} \
            --batch-folder {input.axiom_dir} \
            --output-dir {output.otv_dir} \
            --log-file {log.otv} \
            --console-add-neg-select WARNING,summary,debug \
            > {log.console} 2>&1
        """

rule finalize_snp_list:
    """
    Builds the probeset list to export. otv-caller cannot off-target-analyse
    hemizygous (chrY / chrMT) probesets, so it drops them from OTV.keep.ps even
    though ps-classification recommends them -- which is why no Y/MT calls reach
    the VCF. Add the recommended hemizygous probesets back to the OTV keep list.
    """
    input:
        otv_keep=out_dir/"otv_caller/OTV.keep.ps",
        recommended=out_dir/"ps_classification/Recommended.ps",
        special_snps=config['refs']['apt']['special_snps']
    output:
        snp_list=temp(out_dir/"otv_caller/export.snp-list.ps")
    run:
        sp = pd.read_csv(input.special_snps, sep='\t', comment='#',
                         header=None, names=['probeset', 'chr'], usecols=[0, 1])
        hemi = set(sp.loc[sp['chr'].isin(['Y', 'MT']), 'probeset'])
        recommended = {l.strip() for l in open(input.recommended)
                       if l.strip() and not l.startswith('#')}
        keep_lines = [l.rstrip('\n') for l in open(input.otv_keep)]
        keep_set = {l.strip() for l in keep_lines}
        add = sorted((hemi & recommended) - keep_set)
        with open(output.snp_list, 'w') as fh:
            fh.write('\n'.join(keep_lines).rstrip('\n') + '\n')
            for pid in add:
                fh.write(pid + '\n')

rule make_vcf:
    """
    Runs apt-format-result to generate a VCF file from the APT outputs using the SNP annotation file.
    """
    input:
        snp_list=out_dir/"otv_caller/export.snp-list.ps",
        otv_dir=out_dir/"otv_caller/",
        data_dir=out_dir/"apt/AxiomAnalysisSuiteData/",
        apt_dir=out_dir/"apt",
        annotation=config['refs']['apt']['annotation']
    output:
        vcf_file=temp(out_dir/"make_vcf/combined.b37.vcf")
    log:
        apt=logs/"make_vcf/apt_format_result.log",
        console=logs/"make_vcf/console.log"
    container:
        apt_container
    shell:
        """
        data_dir=$(realpath --relative-to {input.otv_dir} {input.data_dir})
        apt-format-result --batch-folder {input.otv_dir} \
            --batch-folder-data-dir $data_dir \
            --snp-list-file {input.snp_list} \
            --annotation-file {input.annotation} \
            --export-vcf-file {output.vcf_file} \
            --log-file {log.apt} \
            --console-add-neg-select WARNING,summary,debug \
            > {log.console} 2>&1
        """
