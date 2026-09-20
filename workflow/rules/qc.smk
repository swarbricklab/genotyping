# Axiom Best Practices sample-QC front-end (see issue #26).
#
# Dish QC -> QC call-rate genotyping -> plate QC, producing the QC-passing CEL
# list that the genotyping rule (apt) runs on. All samples are clustered as one
# batch, which the manual allows (up to 50 plates per batch); plate QC groups
# the per-sample results by the optional `plate` column of the sample sheet,
# treating everything as one plate when that column is absent.
#
# Thresholds come from the config `qc:` block (defaults are the manual's).

_qc = config.get('qc', {})
_dqc_threshold = _qc.get('dqc_threshold', 0.82)
_cr_threshold = _qc.get('call_rate_threshold', 97.0)
_plate_cr_threshold = _qc.get('plate_call_rate_threshold', 98.5)
_plate_pass_threshold = _qc.get('plate_pass_rate_threshold', 95.0)
_exclude_failing_plates = _qc.get('exclude_failing_plates', False)


def _read_apt_report(path, metric_col):
    """An APT report is a TSV with leading '#'-comment lines, keyed on cel_files."""
    df = pd.read_csv(path, sep='\t', comment='#')
    return df[['cel_files', metric_col]].copy()


def _basename_to_path(cel_list_file):
    """Map CEL basename -> the path as written in the sample sheet, so a report
    that echoes basenames can be turned back into a usable --cel-files list."""
    orig = pd.read_csv(cel_list_file)
    return {Path(str(p)).name: p for p in orig['cel_files']}


def _write_cel_list(paths, out_file):
    pd.DataFrame({'cel_files': list(paths)}).to_csv(out_file, index=False)


def _plate_of(donors_file):
    """donor CEL basename -> plate label (from an optional `plate` column)."""
    df = pd.read_csv(donors_file, dtype=str)
    plate_col = 'plate' if 'plate' in df.columns else None
    out = {}
    for _, row in df.iterrows():
        bn = Path(str(row['cel_files'])).name
        out[bn] = row['plate'] if plate_col else 'plate1'
    return out


rule dqc:
    """
    Dish QC (Best Practices step 2): apt-geno-qc-axiom scores each sample from
    the contrast of its non-polymorphic probes. Samples below qc.dqc_threshold
    are dropped by filter_dqc.
    """
    input:
        cel_list=out_dir/"cel_list.txt",
        dqc_arg=config['refs']['apt']['dqc_arg_file']
    output:
        report=out_dir/"qc/dqc/apt2-genotype.report.txt",
        dqc_dir=temp(directory(out_dir/"qc/dqc"))
    log:
        qc=logs/"qc/apt-geno-qc.log",
        console=logs/"qc/dqc_console.log"
    container:
        apt_container
    shell:
        r"""
        annotation_dir=$(dirname {input.dqc_arg})
        mkdir -p {output.dqc_dir}/logs
        apt-geno-qc-axiom \
            --analysis-files-path $annotation_dir/ \
            --arg-file {input.dqc_arg} \
            --cel-files {input.cel_list} \
            --out-dir {output.dqc_dir} \
            --log-file {log.qc} \
            > {log.console} 2>&1
        """


rule filter_dqc:
    """Keep samples with Dish QC >= qc.dqc_threshold (Best Practices step 3)."""
    input:
        report=rules.dqc.output.report,
        cel_list=out_dir/"cel_list.txt"
    output:
        cel_list=out_dir/"qc/cel_list.dqc_pass.txt",
        summary=out_dir/"qc/dqc_summary.csv"
    run:
        bn2path = _basename_to_path(input.cel_list)
        rep = _read_apt_report(input.report, 'axiom_dishqc_DQC')
        rep['passed'] = rep['axiom_dishqc_DQC'].astype(float) >= _dqc_threshold
        rep.to_csv(output.summary, index=False)
        passing = [bn2path.get(Path(str(c)).name, c)
                   for c in rep.loc[rep['passed'], 'cel_files']]
        _write_cel_list(passing, output.cel_list)


rule call_rate_qc:
    """
    QC call-rate genotyping (Best Practices step 4): a first pass with the
    Step1 SNP-specific-priors arg file over the DQC-passing samples, to get a
    per-sample QC call rate. --table-output false: only the report is needed.
    """
    input:
        cel_list=rules.filter_dqc.output.cel_list,
        step1_arg=config['refs']['apt']['step1_arg_file']
    output:
        report=out_dir/"qc/call_rate/AxiomGT1.report.txt",
        cr_dir=temp(directory(out_dir/"qc/call_rate"))
    log:
        axiom=logs/"qc/call_rate.log",
        console=logs/"qc/call_rate_console.log"
    container:
        apt_container
    shell:
        r"""
        annotation_dir=$(dirname {input.step1_arg})
        mkdir -p {output.cr_dir}/logs
        apt-genotype-axiom \
            --analysis-files-path $annotation_dir/ \
            --arg-file {input.step1_arg} \
            --cel-files {input.cel_list} \
            --dual-channel-normalization true \
            --table-output false \
            --out-dir {output.cr_dir} \
            --log-file {log.axiom} \
            > {log.console} 2>&1
        """


rule filter_call_rate:
    """Keep samples with QC call rate >= qc.call_rate_threshold (step 5)."""
    input:
        report=rules.call_rate_qc.output.report,
        cel_list=rules.filter_dqc.output.cel_list
    output:
        cel_list=out_dir/"qc/cel_list.call_rate_pass.txt",
        summary=out_dir/"qc/call_rate_summary.csv"
    run:
        bn2path = _basename_to_path(input.cel_list)
        rep = _read_apt_report(input.report, 'call_rate')
        rep['passed'] = rep['call_rate'].astype(float) >= _cr_threshold
        rep.to_csv(output.summary, index=False)
        passing = [bn2path.get(Path(str(c)).name, c)
                   for c in rep.loc[rep['passed'], 'cel_files']]
        _write_cel_list(passing, output.cel_list)


rule plate_qc:
    """
    Plate QC (Best Practices step 6): per plate, the mean QC call rate of
    passing samples and the plate pass rate. Advisory by default -- plates that
    fail are flagged in plate_qc.csv but their samples are kept, unless
    qc.exclude_failing_plates is set. The final CEL list this writes is what the
    genotyping rule (apt) runs on.
    """
    input:
        call_rate_summary=rules.filter_call_rate.output.summary,
        call_rate_pass=rules.filter_call_rate.output.cel_list,
        donors=config['deps']['donors']
    output:
        cel_list=out_dir/"qc/cel_list.final.txt",
        plate_report=out_dir/"qc/plate_qc.csv"
    run:
        plate_of = _plate_of(input.donors)
        cr = pd.read_csv(input.call_rate_summary)
        cr['cel_basename'] = cr['cel_files'].map(lambda c: Path(str(c)).name)
        cr['plate'] = cr['cel_basename'].map(lambda b: plate_of.get(b, 'plate1'))

        rows, failing = [], set()
        for plate, grp in cr.groupby('plate'):
            n_total = len(grp)
            passers = grp[grp['passed']]
            n_pass = len(passers)
            mean_cr = float(passers['call_rate'].astype(float).mean()) if n_pass else 0.0
            pass_rate = 100.0 * n_pass / n_total if n_total else 0.0
            ok = (mean_cr >= _plate_cr_threshold) and (pass_rate >= _plate_pass_threshold)
            if not ok:
                failing.add(plate)
            rows.append({'plate': plate, 'n_total': n_total, 'n_pass': n_pass,
                         'mean_call_rate': round(mean_cr, 4),
                         'plate_pass_rate': round(pass_rate, 2), 'passed': ok})
        pd.DataFrame(rows).to_csv(output.plate_report, index=False)

        final = pd.read_csv(input.call_rate_pass)
        if _exclude_failing_plates and failing:
            keep = final['cel_files'].map(
                lambda c: plate_of.get(Path(str(c)).name, 'plate1') not in failing)
            final = final[keep]
        final.to_csv(output.cel_list, index=False)
