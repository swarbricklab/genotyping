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

# Ensembl release-98 main chromosomes, listed in the same order as the 10x
# GRCh38-2020-A reference (numerics sorted lexically, then MT, X, Y). Building
# the reference in this order keeps the liftover output's contig order -- and
# so the whole VCF body -- unchanged from the published runs.
GRCH38_CHR_ORDER = ["1", "10", "11", "12", "13", "14", "15", "16", "17", "18",
                    "19", "2", "20", "21", "22", "3", "4", "5", "6", "7", "8",
                    "9", "MT", "X", "Y"]

rule prepare_hg38:
    """
    Builds the hg38 (GRCh38) reference from Ensembl release-98 per-chromosome
    FASTAs: rewrites each header to the chr-prefixed name the liftover chain
    uses (MT -> chrM), concatenates them in the 10x GRCh38-2020-A order, and
    indexes the result. The sequence is byte-identical to the 10x reference's
    main chromosomes; only the empty scaffolds are omitted.
    """
    input:
        src=expand(
            config['refs']['genomes']['hg38_chromosomes']
                + "/Homo_sapiens.GRCh38.dna.chromosome.{c}.fa.gz",
            c=GRCH38_CHR_ORDER,
        )
    output:
        fa=temp(out_dir/"genomes/GRCh38.fa"),
        fai=temp(out_dir/"genomes/GRCh38.fa.fai")
    container:
        "docker://quay.io/biocontainers/samtools:1.21--h50ea8bc_0"
    log:
        logs/"prepare_hg38.log"
    shell:
        r"""
        : > {output.fa}
        for f in {input.src}; do
            n=$(basename "$f" .fa.gz); n=${{n##*.chromosome.}}
            if [ "$n" = MT ]; then c=chrM; else c=chr$n; fi
            zcat "$f" | awk -v h=">$c $n" 'NR==1{{print h; next}} {{print}}' >> {output.fa}
        done
        samtools faidx {output.fa} 2> {log}
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
