# China urban multilayer networks

Model code for comparing intercity investment ties, intermediate production flows and production-side carbon burdens across 309 Chinese cities in 2015 and 2020.

The analyses cover network construction and comparison, city roles, province-fixed-effects associations, city selection under production-flow loss and city-count limits, and sequential city removal. Investment links are weighted by recorded investment frequency. Production links are monetary intermediate transactions. Carbon links weight those transactions by supplying city-sectors' direct CO₂ intensity.

## Contents

```text
config/             Shared locations for data and model outputs
src/matlab/mrio/    City MRIO reconstruction
src/matlab/sectors/ Four-sector harmonization
src/matlab/emissions/  Direct emissions matching
src/matlab/network/    Networks, city roles, targeting and node removal
src/python/        Carbon reweighting and city-structure analyses
scripts/           Model execution entry points
data/              Input instructions and study metadata
docs/              Reproduction details and code provenance
```

Figure-generation code and images are outside this release. A separate local `Figure/` directory is excluded from Git tracking.

## Requirements

- MATLAB R2024a was used to check and run the MATLAB code. The Statistics and Machine Learning Toolbox is used by the correlation analyses.
- The exact selection models use the Gurobi MATLAB interface. Gurobi 13.0.0 is the local verification version; a valid Gurobi licence is required for those stages.
- Python 3.9 or later. The package versions used for verification are listed in `requirements.txt`.

Install the Python requirements in your environment:

```bash
python -m pip install -r requirements.txt
```

Make the Gurobi MATLAB interface available on the MATLAB path before running the frontier stages. MATLAB and Gurobi are obtained separately and are not distributed here.

## Input data

Obtain the source datasets and follow [data/README.md](data/README.md). Third-party raw datasets are not redistributed in this repository. The input catalog includes provider links, required filenames and the distinction between raw inputs and prepared four-sector model inputs.

Edit [config/paths.json](config/paths.json) to change the data or output directory. Paths are relative to the repository root unless an absolute location is supplied. The defaults are `data/` and `results/generated/`.

## Run the models

Run commands from the repository root.

If the four-sector city MRIO packages and matched emissions are already prepared, execute the network and selection stages in MATLAB:

```matlab
addpath('scripts');
run_models('analysis');
```

To include the original-data preparation stages:

```matlab
addpath('scripts');
run_models('all');
```

Individual stages are also available:

| Command | Calculation |
|---|---|
| `run_models('mrio')` | Reconstruct the 2020 city MRIO using the accepted 2017 structure and provincial totals |
| `run_models('sectors')` | Consolidate the MRIO sectors into four sectors |
| `run_models('emissions')` | Match the 2015 and 2020 city emissions to the four sectors |
| `run_models('network')` | Construct and compare networks; estimate MRQAP models; classify roles; remove cities sequentially |
| `run_models('targeting')` | Calculate city shares, mismatch and ranked attenuation scenarios |
| `run_models('cross_layer')` | Calculate cross-layer overlap, strong-link co-occurrence and city geometry |
| `run_models('frontier')` | Solve the unrestricted binary selection frontier |
| `run_models('city_counts')` | Solve count-constrained optima and compare selected city sets |

After the MATLAB analysis, run the Python analyses:

```bash
python scripts/run_analysis.py
```

The optional arguments `carbon`, `structure` and `inference` select one Python stage. They calculate carbon reweighting, city-structure models and province-clustered inference, respectively.

Outputs are written under the configured output directory and remain local. Result files, reference tables and generated reports are excluded from this repository. The selection stages require a new, empty output subdirectory; they do not overwrite an existing frontier run. To repeat a complete run, select a new output directory in `paths.json`.

## Reproduction and interpretation

[docs/reproduction.md](docs/reproduction.md) connects model stages to their inputs and outputs and explains how to compare them with separately held local reference tables. [docs/source-map.csv](docs/source-map.csv) records the source of the study code.

The selection experiments retain the study's common attenuation proportion and distinguish unrestricted and city-count-constrained comparisons. Production-flow losses are changes in intermediate monetary flows. City-structure models estimate associations, and city removal measures the concentration of flows across networks.

## Citation and licence

Use `CITATION.cff` to cite this code. Cite the original datasets listed in `data/README.md` when using them.

The study code is distributed under the MIT licence. External datasets and separately installed software retain their providers' terms.
