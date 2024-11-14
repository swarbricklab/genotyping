# Script: generate_sample_psam.py
import pandas as pd
import sys
import logging
from pathlib import Path

logging.basicConfig(filename=snakemake.log[0], level=logging.DEBUG)
logger = logging.getLogger()

# Input files
sample_map_file = snakemake.input.sample_map
apt_report_file = snakemake.input.apt_report
output_psam = snakemake.output.psam
output_map = snakemake.output.id_map

# Load the sample map and AxiomGT1 report files
logger.info("Loading sample_map.txt")
sample_map_df = pd.read_csv(sample_map_file, sep='\t', header=None, names=['cel_files','sample_id'], dtype=str)
logger.debug(sample_map_df)

logger.info("Loading AxiomGT1.report.txt")
apt_report_df = pd.read_csv(apt_report_file, sep='\t', comment="#")
apt_report_df=apt_report_df[['cel_files','computed_gender']]
logger.debug(apt_report_df)

# Join sample map with sex report on CEL file name
logger.info("Merging sample mapping and APT report")
mapped_df = apt_report_df.merge(sample_map_df, on='cel_files', how='left')
mapped_df['computed_gender'] = mapped_df['computed_gender'].map({'male': 1, 'female': 2}).fillna(0).astype(int)
logger.debug(mapped_df)

logger.info("Adjusting sample names for plink")
id_map_df=mapped_df[['sample_id']].copy()
id_map_df['plink_sample_id'] = id_map_df['sample_id'].str.replace('-', '_')
logger.debug(id_map_df)
id_map_df.to_csv(output_map, sep='\t', header=False, index=False)

# Create the metadata.psam DataFrame with default values for FID, PAT, MAT, and Provided_Ancestry
logger.info('Creating the metadata.psam DataFrame with default values')
psam_df = pd.DataFrame({
    '#FID': [0] * len(mapped_df),
    'IID': id_map_df['plink_sample_id'],
    'PAT': [0] * len(mapped_df),
    'MAT': [0] * len(mapped_df),
    'SEX': mapped_df['computed_gender'],
    'Provided_Ancestry': ['NONE'] * len(mapped_df)
})
logger.debug(psam_df)

# Write the PSAM file
logger.info('Writing psam to ' + output_psam)
psam_df.to_csv(output_psam, sep='\t', index=False)
