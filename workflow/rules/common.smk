from pathlib import Path
import pandas as pd

# Global paths
out_dir=Path(config['out_dir'])
logs=Path(config['log_dir'])

# Sample sheet
samples = pd.read_csv(config["samples"], dtype=str)

# Input functions



