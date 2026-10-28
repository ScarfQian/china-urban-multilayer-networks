# Input data

Raw and prepared numerical inputs are read from this directory. They are excluded from Git tracking. Only city and sector concordances and the fixed model parameters are distributed with the code.

## Original sources

| Input | Source and access route |
|---|---|
| Directed intercity investment network | Shu et al. (2025), [Figshare dataset](https://doi.org/10.6084/m9.figshare.28248503); [data description](https://doi.org/10.1038/s41597-025-04658-w) |
| City MRIO tables for 2012, 2015 and 2017 | [CEADs input–output tables](https://www.ceads.net/data/input_output_tables/); [city MRIO framework](https://doi.org/10.1080/09535314.2021.1932764) |
| Provincial MRIO tables for 2017 and 2020 | [CEADs input–output tables](https://www.ceads.net/data/input_output_tables/); [2018/2020 database description](https://doi.org/10.1038/s41597-025-06543-y) |
| City direct emissions for 2015 and 2020 | China City Greenhouse Gas Working Group, Chinese Academy of Environmental Planning: [2015 source page](https://www.cityghg.com/toCauses?id=4), [2020 source page](https://www.cityghg.com/toArticleDetail?id=203). Related inventory methods: [Cai et al. 2018](https://doi.org/10.1016/j.resconrec.2017.10.036), [Cai et al. 2019](https://doi.org/10.1016/j.apenergy.2019.113579), [Meng et al. 2025](https://doi.org/10.1038/s41597-025-05949-y) |

Follow the providers' access procedures and terms. Obtain the city-level emissions workbooks for the two study years; the 2023 dataset description is a methodological reference, not a replacement for the 2015/2020 input.

## Raw-input route

Keep the original values and workbook structure. Copy or rename the downloaded files to these local locations:

| Local path under `data/` | Required content |
|---|---|
| `raw/city_mrio_2012.mat` | 2012 city MRIO, used by the accepted reconstruction-validation calculations |
| `raw/city_mrio_2015.mat` | 2015 city MRIO |
| `raw/city_mrio_2017.mat` | 2017 city MRIO structure |
| `raw/province_mrio_2017.xlsx` | 2017 provincial MRIO |
| `raw/province_mrio_2020.xlsx` | 2020 provincial MRIO |
| `raw/emissions_2015.xlsx` | Original 2015 city emissions workbook |
| `raw/emissions_2020.xlsx` | Original 2020 city emissions workbook |
| `raw/Directed intercity investment network dataset.xlsx` | Directed network workbook; sheets `DirectedNetwork_2015` and `DirectedNetwork_2020` |

The investment workbook is also needed when prepared MRIO and emissions inputs are supplied.

The fixed calibration parameters in `metadata/2017_y_hybrid_0422/` are used without refitting. MRIO deployment compares the reconstructed 2017 tables with two separately held reference reports. Place local copies at:

```text
reference/mrio_2017/
  validation_backcast_2017_y_hybrid.csv
  aggregation_check_2017_y_hybrid.csv
```

These reference reports are excluded from Git tracking. Run `run_models('all')` after preparing the raw inputs and local reference reports. MRIO reconstruction, sector consolidation and emissions matching can also be run separately. The additional `factorized_validation.csv` and `baseline_validation.csv` comparison reports can be placed in the same reference directory; their absence produces missing entries in auxiliary comparison columns, rather than changing the fixed parameters.

## Prepared-input route

For network and selection analyses without repeating raw-data preparation, place the study's prepared outputs at:

```text
prepared/
  mrio/
    city_mrio_2015_4.mat
    city_mrio_2020_hybrid_4.mat
  emissions/
    direct_emission_city4_2015.csv
    direct_emission_city4_2020.csv
    post_mgras_release_manifest.json
    proxy_fallback_report.csv
    city_inventory_coverage_report.csv
```

Each MRIO package must use the same city order and four-sector classification as the metadata. The emissions tables contain `year`, city and province identifiers, `mrio4_sector_code`, `mrio4_sector_name`, `co2_total` and `source_basis`. The network analysis aligns these source packages to the common 309-city study sample and excludes the four provincial proxy units.

Prepared files take precedence over outputs produced by the preparation stages. If no prepared file is present, the model reads the corresponding file from `results/generated/sectors/` or `results/generated/emissions/`.

## Units and metadata

Intermediate production flows and gross output are in 10,000 CNY at current prices. Direct emissions are in 10,000 tonnes CO₂. Investment weights count investment records. Cross-layer comparisons use normalized weights, shares or ranks.

`metadata/mrio42_to_mrio4_mapping.csv` defines the four sectors. `metadata/city2pro_full_313.csv` and `city2pro.xlsx` provide the city and province concordances used before the common sample is selected. The source labels and zero-fill rules are retained by the preparation code.

Full raw inventories, prepared MRIO matrices, investment workbooks and network matrices are not included in the GitHub release.
