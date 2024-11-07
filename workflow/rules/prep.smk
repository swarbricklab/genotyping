rule map_samples:
    """
    Creates a mapping file that maps CEL file names to sample names, extracted from the given sample sheet.
    """
    input:
        samplesheet=config['samples']
    output:
        mapping=temp(out_dir/"sample_map.txt")
    run:
        # Read the CSV file into a DataFrame
        samples_df = pd.read_csv(input.samplesheet)
        # Extract just the filename (without path) from 'cel_files' column
        samples_df['cel_file_name'] = samples_df['cel_files'].apply(lambda x: Path(x).name)
        # Create a new DataFrame with only 'cel_file_name' and 'sample' columns for the mapping
        samples_df[['cel_file_name', 'sample']].to_csv(output.mapping, sep='\t', header=False, index=False)


# Generate list of all unique CEL files in the sample sheet
rule list_cel_files:
    """
    Creates a list of all unique CEL files by reading the sample sheet and removing duplicates.
    """
    input:
        samplesheet=config['samples']
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
        gz="resources/genomes/hg19/hg19.fa.gz"
    output:
        fa=temp("resources/genomes/hg19/hg19.fa"),
        fai=temp("resources/genomes/hg19/hg19.fa.fai"),
        int_fai=temp("resources/genomes/hg19/hg19_int.fa.fai"),
        chr_map=temp("resources/genomes/hg19/map_int2chr.tsv")
    container:
         "docker://quay.io/biocontainers/samtools:1.21--h50ea8bc_0"
    log:
        logs/"prepare_hg19.log"
    shell:
        """
        gunzip -c {input.gz} > {output.fa}
        samtools faidx {output.fa}
        cat {output.fai} \
            | sed '/_/d' \
            | sed '/M/d' \
            | sed 's/^chr//g' \
            | sed 's/Y/23/g' \
            | sed 's/X/24/g' \
            | sort -n \
            > {output.int_fai}
        cat {output.int_fai} \
            | awk -F'\t' '{{print $1 "\tchr" $1}}' \
            | sed 's/chr23/chrY/g' \
            | sed 's/chr24/chrX/g' \
            > {output.chr_map}
        """

rule prepare_chain:
    """
    Decompresses the liftover chain file for use in the liftover process.
    """
    input:
        gz="resources/liftover/hg19ToHg38.over.chain.gz"
    output:
        chain=temp("resources/liftover/hg19ToHg38.over.chain")
    shell:
        """
        gunzip -c {input.gz} > {output.chain}
        """