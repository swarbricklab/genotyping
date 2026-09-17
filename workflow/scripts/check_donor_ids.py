import pandas as pd

# Define the path to the donors CSV file
donors_path = '../../../../config/genotyping'
donors = pd.read_csv(f'{donors_path}/donors_backup.csv')

# Print duplicated donor IDs (based on donor column)
duplicates = donors[donors.duplicated(['donor'], keep=False)]
if not duplicates.empty:
    print("Duplicated donor IDs:")
    print(duplicates[['donor', 'cel_files']])

def choose_row(group):
    """
    Given a DataFrame group (with same donor_id), choose the correct row:
    
    1. If the rows are exact duplicates, return the first one.
    2. Otherwise, if the 'cel_files' column shows one row with 'Tumour'
       and another with 'Blood', return the row with 'Tumour'.
    3. If both rows contain 'Tumour' (or there is no clear preference), return
       the first row that appears.
    """
    # 1. Exact duplicates: if dropping duplicates leaves just one row, return it.
    if group.drop_duplicates().shape[0] == 1:
        return group.iloc[0]
    
    # 2 & 3. Not exact duplicates: inspect the 'cel_files' column
    tumour_mask = group['cel_files'].str.contains("Tumour", case=False, na=False)
    blood_mask = group['cel_files'].str.contains("Blood", case=False, na=False)
    
    # If some rows contain 'Tumour' and some contain 'Blood', choose a 'Tumour' row.
    if tumour_mask.any() and blood_mask.any():
        tumour_rows = group[tumour_mask]
        return tumour_rows.iloc[0]  # keep the first row among those with 'Tumour'
    
    # If not the above case (either all 'Tumour', all 'Blood', or neither), keep the first row.
    return group.iloc[0]

# Process each donor id, choosing rows
chosen_rows = []
for donor_id, group in donors.groupby('donor', sort=False):
    chosen_rows.append(choose_row(group))

filtered_donors = pd.DataFrame(chosen_rows)
# Save, overwriting the original donors file
filtered_donors.to_csv(f'{donors_path}/donors.csv', index=False)
