# Generate a PSAM file with metadata.
rule make_psam:
    """
    Generates a metadata.psam file for samples using sample mapping information and available SEX calls.
    """
    input:
        sample_map=out_dir/"sample_map.txt",
        apt_report=out_dir/"apt/AxiomGT1.report.txt"
    output:
        psam=psam,
        id_map=id_map
    log:
        logs/"make_psam.log"
    script:
        "../scripts/make_psam.py"

