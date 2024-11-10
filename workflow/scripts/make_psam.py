# Script: generate_sample_psam.py
import pandas as pd
import sys
from pathlib import Path

# Input files
sample_map_file = snakemake.input.sample_map
apt_report_file = snakemake.input.apt_report
output_psam = snakemake.output.psam

# Redirect print statements to the log file
log_file = snakemake.log[0]
sys.stdout = open(log_file, 'w')

# Load the sample map and AxiomGT1 report files
print("Loading sample_map.txt")
sample_map_df = pd.read_csv(sample_map_file, sep='\t', header=None, names=['CelFileName','SampleID'], dtype=str)
print(sample_map_df)

print("Loading AxiomGT1.report.txt")
apt_report_df = pd.read_csv(apt_report_file, sep='\t', comment="#")
apt_report_df.rename(columns={'cel_files': 'CelFileName', 'computed_gender': 'SEX'}, inplace=True)
print(apt_report_df)

# Join sample map with sex report on CEL file name
print("Merging sample mapping and APT report")
mapped_df = sample_map_df.merge(apt_report_df[['CelFileName', 'SEX']], on='CelFileName', how='left')
mapped_df['SEX'] = mapped_df['SEX'].map({'male': 1, 'female': 2}).fillna(0).astype(int)
print(mapped_df)

# Create the metadata.psam DataFrame with default values for FID, PAT, MAT, and Provided_Ancestry
print('Creating the metadata.psam DataFrame with default values')
psam_df = pd.DataFrame({
    '#FID': [0] * len(mapped_df),
    'IID': mapped_df['SampleID'],
    'PAT': [0] * len(mapped_df),
    'MAT': [0] * len(mapped_df),
    'SEX': mapped_df['SEX'],
    'Provided_Ancestry': ['NONE'] * len(mapped_df)
})

# Write the PSAM file
print('Writing metadata.psam')
psam_df.to_csv(output_psam, sep='\t', index=False)