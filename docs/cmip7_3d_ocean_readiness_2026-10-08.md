# CMIP7 readiness for depth-resolved ocean projections

Assessment date: 8 October 2026.  
Status: preliminary assessment for manuscript preparation; not a completed dataset availability audit.

## Purpose and scope

This note documents the requirements of the existing CMIP6 ocean workflow and evaluates the basis for a future CMIP7 extension. It distinguishes scenario comparability, requested scientific outputs, published datasets, and suitability for this particular analysis. The assessment used repository inspection and the public sources cited below. No processing code was modified and no CMIP7 model files were downloaded or validated.

## Suggested manuscript wording

### Methods: dataset scope and potential CMIP7 extension

The ocean projection workflow is configured for monthly CMIP6 output under SSP1-2.6, SSP2-4.5, and SSP5-8.5. Required depth-resolved fields comprise ocean potential temperature (`thetao`), salinity (`so`), eastward and northward seawater velocity (`uo`, `vo`), pH (`ph`), dissolved oxygen (`o2`), chlorophyll (`chl`), and zooplankton carbon concentration (`zooc`). The configured model reference period is 2006–2014, with future climatological windows of 2030–2040, 2050–2060, and 2090–2100. A preliminary assessment of CMIP7 suitability was conducted on 8 October 2026. Incorporation of CMIP7 would require verification of monthly, depth-resolved coverage for the selected variables and periods, together with compatible historical and scenario ensemble members. This assessment did not establish a complete set of CMIP7 inputs suitable for the workflow.

### Discussion: interpretation of future CMIP7 comparisons

CMIP7 ScenarioMIP provides low-, medium-, and high-emissions pathways that permit broad comparisons with the scenario range represented in CMIP6. These categories do not establish equivalence in radiative forcing, warming, or regional ocean responses (Van Vuuren et al., 2026). Comparisons between CMIP generations would therefore combine changes in scenario design with changes in model formulation and ensemble composition. CMIP7 should be evaluated as a separately identified ensemble, with inclusion based on verified variable, temporal, and vertical coverage. The presence of an experiment in a publication catalogue alone does not establish its suitability for depth-resolved ocean analysis.

These paragraphs describe configuration and a preliminary assessment. Before submission, align the tense and variable list with the datasets actually analysed, and cite their dataset identifiers and versions. Do not describe this note as evidence that CMIP7 data were globally unavailable or that an exhaustive ESGF search was performed.

## Requirements established from the repository

| Requirement | Current configuration |
| --- | --- |
| Three-dimensional physics | `thetao`, `so`, `uo`, `vo` |
| Three-dimensional biogeochemistry | `ph`, `o2`, `chl`, `zooc` |
| Additional two-dimensional products | `zos`, `mlotst`, `siconc` |
| Temporal sampling | Monthly fields |
| Model reference period | 2006–2014 |
| Future periods | 2030–2040; 2050–2060; 2090–2100 |
| Ocean discovery defaults | CMIP6, `Omon`, native grid label `gn` |
| Ensemble selection | First available realization per model/experiment/variable in discovery; continuity must be checked explicitly |
| Vertical processing | Interpolation to GLORYS reference levels |

Here, “3D” means a field resolved horizontally and vertically at each time step; the time-dependent array typically has four dimensions. A surface field or depth-integrated quantity cannot automatically replace the required depth-resolved field.

The repository currently documents `zooc` processing through the model-delta stage only, because a trusted present-day baseline for anomaly addition has not been selected. Its inclusion in the requested stack does not imply an existing final downscaled zooplankton product.

Repository evidence:

- [Workflow description and baseline matrix](../README.md).
- [Discovery configuration and time windows](../scripts/R/discover_ipcc_esgf_nci_cmip6.R).
- [Manifest downloader and temporal selection](../scripts/R/fetch_ipcc_esgf_cmip6_manifest.R).
- [Downstream scenario recognition](../scripts/lib/ipcc_esgf_discovery.sh).

## Scenario interpretation

| CMIP6 scenario | Candidate CMIP7 emissions-driven comparison | Permitted interpretation |
| --- | --- | --- |
| SSP1-2.6 (`ssp126`) | Low (`esm-scen7-l`) | Broad low-emissions comparison |
| SSP2-4.5 (`ssp245`) | Medium (`esm-scen7-m`) | Broad intermediate/current-policy comparison |
| SSP5-8.5 (`ssp585`) | High (`esm-scen7-h`) | Broad high-emissions comparison |

This is an analytical grouping, not an official one-to-one conversion. The CMIP7 high scenario has lower 21st-century emissions than the highest scenarios in previous sets [1, 2]. The very-low scenario (`esm-scen7-vl`) is distinct from the low scenario and must not be substituted merely because it is available.

The `esm-` prefix identifies emissions-driven experiments. WCRP also documents concentration-driven counterparts. For example, `esm-scen7-l` branches from CMIP7 `esm-hist` at the end of 2021 and covers 2022–2100 [3]. Keeping the 2006–2014 reference interval is therefore temporally possible for that design, but requires the appropriate historical parent and verified data coverage. A CMIP6 historical field should not be assumed to be a valid parent for a CMIP7 future simulation.

## Publication evidence and its limits

WCRP user guidance confirms that initial CMIP7 data publication has begun [4]. The WCRP-linked Climate Resource experiment tracker, in its 6 October 2026 snapshot, lists six ScenarioMIP experiments with published datasets: `esm-scen7-h`, `esm-scen7-m`, `esm-scen7-vl`, `scen7-h`, `scen7-m`, and `scen7-vl` [5]. `esm-scen7-l` is not listed among those six. This is a dated catalogue observation, not proof of absence across all archives or later publications.

The CMIP7 Earth-system data-request paper supports depth-resolved marine ecosystem applications [6]. A requested output is nevertheless distinct from a published, accessible, complete dataset. This assessment has not verified all eight variables as monthly 3D outputs for each candidate scenario, model, and member. In particular, no NetCDF headers, depth coordinates, units, or actual monthly timestamps were inspected.

## Recommended inclusion checks before implementation

The proposed next step is a documented availability audit. For every candidate model, scenario, and variable, record:

1. Source model, experiment, ensemble member, grid, dataset version, persistent identifier, catalogue endpoint, and search date.
2. Exact CMIP7 variable identity, physical definition, units, frequency, and vertical representation.
3. Available depth range and levels, including whether the field is surface-only, integrated, or depth-resolved.
4. Actual monthly coverage in each required window, including gaps, duplicate months, and calendar.
5. Historical parent, branching metadata, and consistency of members across variables and scenarios.
6. Download accessibility and metadata compatibility with the processing workflow.

Classify each combination as verified suitable, published but unverified, incomplete/incompatible, or not found in the searched catalogue. Keep “not found” separate from “not produced.” Preserve query results and the final dataset manifest with the manuscript provenance.

The current recommendation is to retain CMIP6 for production while evaluating CMIP7 separately. This is a workflow recommendation, not a completed study-design decision. A later implementation would also need to address existing CMIP6 discovery defaults and downstream filters that recognize only `historical` and `ssp###`; changing scenario labels alone would not establish compatibility.

## References and dated web evidence

1. Van Vuuren, D. P., et al. (2026). The Scenario Model Intercomparison Project for CMIP7 (ScenarioMIP-CMIP7). *Geoscientific Model Development*, **19**, 2627–2656. [https://doi.org/10.5194/gmd-19-2627-2026](https://doi.org/10.5194/gmd-19-2627-2026).
2. WCRP CMIP. [CMIP Phase 7 (CMIP7)](https://www.wcrp-cmip.org/cmip-phases/cmip7/). Accessed 8 October 2026.
3. WCRP CMIP. [Experiment Setup and Forcings Guidance: esm-scen7-l](https://wcrp-cmip.github.io/cmip7-guidance/docs/CMIP7/Experiment_set_up_and_Forcings/esm-scen7-l/). Accessed 8 October 2026.
4. WCRP CMIP. [CMIP7 Guidance for Data Users](https://wcrp-cmip.github.io/cmip7-guidance/docs/CMIP7/Guidance_for_users/). Accessed 8 October 2026.
5. Climate Resource. [Experiments: CMIP7 data availability](https://www.climate-resource.com/tools/esm-model/cmip7-availability/experiments). Page snapshot dated 6 October 2026; accessed 8 October 2026. Dynamic catalogue summary linked from WCRP user guidance; not an archived dataset manifest.
6. McPartland et al. (2026). CMIP7 data request: Earth system priorities and opportunities. *Geoscientific Model Development*, **19**, 2849 ff. [https://doi.org/10.5194/gmd-19-2849-2026](https://doi.org/10.5194/gmd-19-2849-2026).

Before manuscript submission, refresh the availability assessment and export complete bibliographic records from the publishers. Retain this dated note as the record of the preliminary assessment.
