# Configuration

Configuring the workflow involves editing two files:
- config file (see [this template](config/template.yaml) for an example)
- sample sheet (see [this example](config/donors.csv) used for testing)

### Config file

To use this workflow as a module in a super-project, first copy the template config file from the module to the super project:
```
cd top/of/superproject
mkdir -p config/genotyping
cp modules/genotyping/config/template.yaml config/genotyping/config.yaml
```
(*) This assumes that this workflow module has been installed to `modules/genotyping`.

Next, check the paths in the config file and edit if needed. 
In many cases, the template can be left unchanged.
Refer to the comments in the template for the meaning for each item.

### Sample sheet

The sample sheet is a CSV file with the following columns:
- donor
- cel_files
- array_type

These column names are fixed, but additional columns can be added if desired.
See [this example](config/donor.csv).

The meanings of each column are as follows:

| Column | Meaning |
|--------|---------|
| donor | The donor id to use in the VCF header |
| cel_files | The path to the .CEL file for each donor, relative to the top of the super project |
| array_type | Either 'UKB' or 'PMDA' |

Here 'UKB' refers to the [UK Biobank Array](https://www.thermofisher.com/order/catalog/product/902502),while 'PMDA' refers to the [Axiom Precision Medicine Diversity Array](https://www.thermofisher.com/order/catalog/product/951962?SID=srch-srp-951962).

Make sure that the path to the sample sheet is specfied correctly in the config file.