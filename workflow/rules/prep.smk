rule map_donors:
    """
    Creates a mapping file that maps CEL file names to donor names, extracted from the given sample sheet.
    """
    input:
        samplesheet=config['deps']['donors']
    output:
        mapping=temp(out_dir/"sample_map.txt")
    run:
        # Read the CSV file into a DataFrame
        samples_df = pd.read_csv(input.samplesheet)
        # Extract just the filename (without path) from 'cel_files' column
        samples_df['cel_file_name'] = samples_df['cel_files'].apply(lambda x: Path(x).name)
        # Create a new DataFrame with only 'cel_file_name' and 'sample' columns for the mapping
        samples_df[['cel_file_name', 'donor']].to_csv(output.mapping, sep='\t', header=False, index=False)


# Generate list of all unique CEL files in the sample sheet
rule list_cel_files:
    """
    Creates a list of all unique CEL files by reading the sample sheet and removing duplicates.
    """
    input:
        samplesheet=config['deps']['donors']
    output:
        cel_list=temp(out_dir/"cel_list.txt")
    log:
        logs/"cel_list.log"
    run:
        df = pd.read_csv(input.samplesheet, dtype=str)
        cel_list=df['cel_files'].dropna().drop_duplicates()
        cel_list.to_frame().to_csv(output.cel_list, index=False)

rule prepare_hg19:
    """
    Prepares the hg19 reference genome by decompressing the FASTA file, indexing it, and generating intermediate files for VCF reformatting and liftover.
    """
    input:
        gz=config['refs']['genomes']['hg19']
    output:
        fa=temp(out_dir/"genomes/hg19.fa"),
        fai=temp(out_dir/"genomes/hg19.fa.fai")
    container:
         "docker://quay.io/biocontainers/samtools:1.21--h50ea8bc_0"
    log:
        logs/"prepare_hg19.log"
    shell:
        """
        gunzip -c {input.gz} > {output.fa}
        samtools faidx {output.fa}
        """

rule prepare_int_fai:
    input:
        fai=rules.prepare_hg19.output.fai
    output:
        int_fai=temp(out_dir/"genomes/hg19_int.fa.fai")
    shell:
        """
        cat {input.fai} \
            | sed '/_/d' \
            | sed '/M/d' \
            | sed 's/^chr//g' \
            | sed 's/Y/23/g' \
            | sed 's/X/24/g' \
            | sort -n \
            > {output.int_fai}
        """

rule prepare_chromosome_maps:
    input:
        int_fai=rules.prepare_int_fai.output.int_fai
    output:
        chr_map=temp(out_dir/"genomes/map_intxy2chr.tsv"),
        intxy_map=temp(out_dir/"genomes/map_int2intxy.tsv")
    shell:
        """
        cat {input.int_fai} \
            | awk -F'\t' '{{print $1 "\t" $1}}' \
            | sed 's/\t23/\tY/g' \
            | sed 's/\t24/\tX/g' \
            > {output.intxy_map}
        cat {output.intxy_map} \
            | awk -F'\t' 'BEGIN {{OFS="\t"}} {{print $2, $2}}' \
            | sed 's/\t/\tchr/g' \
            > {output.chr_map}
        """

rule prepare_chain:
    """
    Decompresses the liftover chain file for use in the liftover process.
    """
    input:
        gz=config['refs']['genomes']['chain']
    output:
        chain=temp(out_dir/"genomes/hg19ToHg38.over.chain")
    shell:
        """
        gunzip -c {input.gz} > {output.chain}
        """
