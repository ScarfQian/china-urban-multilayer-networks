# Reproducing the models

This release contains the models and numerical analyses for 309 Chinese cities in 2015 and 2020. Figure-generation code is outside this release.

| Analysis | MATLAB module or Python script | Reference output |
|---|---|---|
| City MRIO reconstruction | `src/matlab/mrio/` | 2020 city MRIO; provincial aggregation and column balance |
| Four-sector harmonization | `src/matlab/sectors/` | City MRIO packages for the two study years |
| Direct emissions matching | `src/matlab/emissions/` | Four-sector city emissions and matching reports |
| Network construction, city roles, MRQAP and node removal | `src/matlab/network/`, pipeline 1 | Layer weights, city roles, conditional associations and retained flows |
| City shares and targeting rules | Network pipelines 2 and 3 | Investment shares, carbon burdens, CRM and cross-layer comparisons |
| Unrestricted selection frontier | Network pipeline 4 | Maximum carbon-flow reductions under production-flow loss budgets |
| Selection with city-count limits | Network pipeline 5 | Count-constrained optima and selected city sets |
| Carbon-intensity reweighting | `src/python/carbon_reweighting.py` | Corridor weights and city-position shifts |
| Province effects and clustered inference | `src/python/urban_structure.py`, `clustered_inference.py` | City-structure associations and province-clustered uncertainty |

`source-map.csv` records the source of each model file. Source paths are relative to the original study code directory. Model definitions, study years, sample selection and scientific parameters are retained. The standalone entry points use the shared locations in `config/paths.json`.

## Run order and outputs

The MATLAB `all` entry runs MRIO reconstruction, sector consolidation, emissions matching, network analysis, targeting, cross-layer comparison, the unrestricted frontier and the city-count-constrained frontier. The `analysis` entry starts at the network stage and reads prepared four-sector MRIO and emissions files.

The configured output root contains:

- `mrio/`, `sectors/` and `emissions/`: preparation results.
- `network/revised_mrio4/`: network layers, roles, MRQAP results and city-removal results.
- `network/revised_transition/`: city shares, mismatch, rankings and attenuation scenarios.
- `network/revised_multilayer_extension/`: cross-layer overlap and city geometry.
- `network/revised_transition_pareto_extension/`: unrestricted selection frontiers.
- `network/revised_transition_pareto_extension_v2/`: city-count-constrained frontiers and set comparisons.
- `analysis/CarbonReweighting/` and `analysis/UrbanStructure/`: Python analysis outputs.

The Python stages run after the MATLAB network results are available. The city-structure analysis reads the network manifest to use the same MRIO packages that supplied the network calculation. If files are moved, regenerate the network results or update the input locations before re-running the analyses.

## Scientific settings

The common study sample contains 309 cities in each of 2015 and 2020. The source MRIO packages include four provincial proxy units, which the alignment code excludes. The four sectors are Agriculture, Industry, Transport and Services.

The final MRQAP analysis uses 4,999 permutations; the separate 200-permutation calculation is a diagnostic. Random city-removal comparisons use 50 orders. The main selection experiment reduces selected cities' outgoing flows by 10%, with the full retention grid from 1.000 to 0.900 at increments of 0.001. City-count-constrained comparisons use the same number-of-cities ceiling as the corresponding ranking rule. Gurobi objectives, tolerances, seeds and tie-breaking remain in the model functions.

For the city-structure analysis, the model specifications, within-year transformations, province effects and 27-cluster inference follow the original analysis functions. These are associations with output and sector composition.

## Numerical checks

Run `python scripts/verify_results.py` after all model groups. A single group can be checked with `--group network`, `--group targeting` or `--group python`. The reference tables contain scientific results and selected city identifiers; raw input matrices and inventories are not distributed.

The comparison checks scientific values and labels and excludes elapsed time and solver workload. The default absolute tolerances are 1e-10 for network/statistical quantities and 1e-8 for frontier and attainment tables, matching the existing numerical checks. City-set comparisons include city identifiers, rather than relying only on objective values.

### Verification of version 1.0.0

The packaged MATLAB analysis was run from the study's prepared four-sector MRIO and emissions inputs and the directed investment workbook. This included the final 4,999-permutation MRQAP calculation, city roles, node removal, the 202-point unrestricted frontier and 590 count-constrained comparisons. All three Python analysis stages were then run from the new network outputs.

All 13 reference-table comparisons passed. Network, selection and selected-city-set comparisons agreed exactly; the largest difference in the statistical coefficient tables was 2.14 × 10⁻¹³. The six network matrices were also compared directly with the study matrices and agreed exactly. City-role and mismatch tables agreed, and the statistical coefficient fields were finite.

The raw 42-sector MRIO reconstruction and raw-inventory preparation code is included, but those upstream stages were not rerun for this packaging check. This verification starts from the prepared four-sector inputs. No figure-generation code was run.
