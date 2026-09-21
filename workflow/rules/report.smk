# HTML QC report -- a static, offline, Jinja2-rendered multi-page bundle,
# matching the engine used by swarbricklab/snp_cna_profiler. Cohort-level QC
# with a sortable per-sample table.
#
# Data it needs is either already produced (the QC front-end summaries, the
# psam) or computed here from the final VCF with bcftools.

rule vcf_stats:
    """Per-sample and overall variant statistics for the report."""
    input:
        vcf=vcf_hg38
    output:
        stats=report_dir.parent/"report_data/bcftools_stats.txt"
    log:
        logs/"report/vcf_stats.log"
    container:
        "docker://quay.io/biocontainers/bcftools:1.21--h8b25389_0"
    shell:
        "bcftools stats -s - {input.vcf} > {output.stats} 2> {log}"


rule gtcheck:
    """
    All-vs-all pairwise genotype discordance (bcftools gtcheck): a duplicate /
    sample-swap check, and -- read the other way -- a demux-distinguishability
    matrix (unrelated donors should be highly discordant).
    """
    input:
        vcf=vcf_hg38
    output:
        gtcheck=report_dir.parent/"report_data/gtcheck.txt"
    log:
        logs/"report/gtcheck.log"
    container:
        "docker://quay.io/biocontainers/bcftools:1.21--h8b25389_0"
    shell:
        "bcftools gtcheck {input.vcf} > {output.gtcheck} 2> {log}"


rule report:
    """Render the HTML QC report bundle from the QC summaries, psam and VCF stats."""
    input:
        stats=rules.vcf_stats.output.stats,
        gtcheck=rules.gtcheck.output.gtcheck,
        dqc_summary=out_dir/"qc/dqc_summary.csv",
        call_rate_summary=out_dir/"qc/call_rate_summary.csv",
        plate_qc=out_dir/"qc/plate_qc.csv",
        psam=psam,
        donors=config['deps']['donors'],
        vcf_hg19=vcf_hg19,
        vcf_hg38=vcf_hg38
    output:
        report_dir=directory(report_dir),
        index=report_dir/"index.html"
    log:
        logs/"report/build_report.log"
    script:
        "../scripts/build_report.py"
