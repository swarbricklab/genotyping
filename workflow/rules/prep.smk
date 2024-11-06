rule map_samples:
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
