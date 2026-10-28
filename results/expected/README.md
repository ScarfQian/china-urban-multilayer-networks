# Reference numerical results

These tables are study outputs used to check that the packaged code preserves the recorded results. They are not raw datasets or model inputs. The city-set tables retain the 95% production-flow-retention comparison; the count-constrained set is the carbon burden–weak investment position rule.

After running the models, use `python scripts/verify_results.py`. Use `--group network`, `--group targeting` or `--group python` to verify one group. Timing and solver workload fields are excluded; scientific values, labels and the selected city identifiers are compared. Absolute tolerances follow the existing model checks: 1e-10 for network and statistical results, and 1e-8 for frontier and attainment tables.
