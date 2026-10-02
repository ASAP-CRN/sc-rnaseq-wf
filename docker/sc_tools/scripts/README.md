# PMDBS sc/sn RNAseq pipeline Python scripts with scVI

![Workflow diagram](../../../workflows/workflow_diagram.svg "Workflow diagram")


## _PREPROCESSING_
- _pre-preprocessing_: executed by WDL [`cellbender :: remove_technical_artifacts`](../../../workflows/preprocess/preprocess.wdl#L327-L350)

- _doublet detection_ + _qc metrics_: [`prep_metadata`](./main/prep_metadata)
    - Calculates `scrublet` metrics and adds additional metrics to metadata

- _merge and plot QC_: [`merge_and_plot_qc`](./main/merge_and_plot_qc)
    - Merges adatas
    - Plot general QC metrics for all cells
    - Save initial metadata

- _filtering_: [`filter`](./main/filter)
    - QC filtering


## _PROCESSING_

- _map my cells_: [`mmc`](./main/mmc)
    - Leverage Allen Brain Map's [MapMyCells](https://portal.brain-map.org/atlases-and-data/bkp/mapmycells) on SEA-AD taxonomy for Human and 10x whole brain Mouse taxonomy for Mouse
    - This needs to be done BEFORE feature selection so we can leverage as many genes as possible
        - FUTURE: In the future we can map to just a subset of the taxonomy for efficiency (e.g. `nodes_to_drop`, or constructing a simplified reference)

- _processing_: [`process`](./main/process)
    - Normalize + feature selection (i.e. identification of highly variable genes)
        - Human only: the 17 Kamath et al. 2022 dopaminergic neuron marker genes ([`da_marker_genes_kamath_hm.txt`](../resources/da_marker_genes_kamath_hm.txt)) are kept in addition to the top `n_top_genes` HVGs
    - Add PCA (for `harmony` integration)


## _INTEGRATE DATA_

- _cell transcriptional phenotype_: [`transcriptional_phenotype`](./main/transcriptional_phenotype)
    - Assign "cell_type" to high-fidelity mappings (i.e. correlation >0.5 and bootstrap_probability>0.5), all else "unknown" to the high level labels
    - The taxonomy levels are read from the MMC results header: SEA-AD (class/subclass/supertype) or Siletti (supercluster/cluster/subcluster). For Siletti, "cell_type" is the supercluster, except cluster `Splat_395` (DA VGLUT2 neurons, within the heterogeneous `Splatter` supercluster), which is labeled "Dopaminergic" using cluster-level scores
    - Annotate adata & export full cell types

- _dopaminergic neuron spike-in_: [`prep_da_spike_in`](./main/prep_da_spike_in) (optional; human only; WDL input `kamath_post_qc_adata_object`)
    - Spikes [Kamath et al. 2022](https://pubmed.ncbi.nlm.nih.gov/35513515/) dopaminergic (DA) neurons into the cohort's MMC-labeled AnnData object so scANVI can learn DA subtype labels (e.g. `SOX6_AGTR1` PD-vulnerable, `CALB1_*` PD-resistant); the SEA-AD taxonomy used by MMC has no DA class
    - Formats the DA neurons (cells with a `da_subtype` label) to match the cohort: Ensembl IDs mapped to the cohort's gene symbols (`all_genes.csv`), QC metrics, `sample`/`batch` per donor, `batch_id` = `kamath_{donor_id}`, raw counts in `layers['counts']`, log1p normalized `X` and cell cycle scores (as in `process`), `cell_type` = DA subtype, and `is_spike_in = True` (`False` for cohort cells)
    - Sets cohort cells labeled "Dopaminergic" by MMC (Siletti `Splat_395`) to "Unknown" so scANVI assigns them a Kamath DA subtype; MMC's call is kept in `phenotype` and `cluster_name`
    - Restricts the spike-in cells to the cohort's HVGs (missing genes set to 0), merges them into the cohort, and recomputes PCA on all cells (used by Harmony and `scib` metrics)
    - Input: `kamath_merged_da_all_non_da_13000_postQC.h5ad`, generated in [spatial-sc-rnaseq-integration-wf `reference_building/da_neurons_identification_analysis`](https://github.com/ASAP-CRN/spatial-sc-rnaseq-integration-wf/tree/c74ea2b5ea543b6a9ecf564183b31ef31360abf0/reference_building/da_neurons_identification_analysis):
        1. [`download_kamath_menon_siletti.py`](https://github.com/ASAP-CRN/spatial-sc-rnaseq-integration-wf/blob/c74ea2b5ea543b6a9ecf564183b31ef31360abf0/reference_building/da_neurons_identification_analysis/scripts/download_kamath_menon_siletti.py) downloads the Kamath H5ADs from CELLxGENE
        2. [`downsample_kamath_menon_siletti_asap.py`](https://github.com/ASAP-CRN/spatial-sc-rnaseq-integration-wf/blob/c74ea2b5ea543b6a9ecf564183b31ef31360abf0/reference_building/da_neurons_identification_analysis/scripts/downsample_kamath_menon_siletti_asap.py) `--kamath-non-da-per-type 13000` keeps all DA neurons, downsamples each non-DA cell type file to 13,000 cells, and applies the same QC filters as this workflow (mt%, per-donor scrublet doublet score, total counts, genes detected); 96,744 cells postQC
        - Location: `gs://asap-workflow-dev/pmdbs_sc_rnaseq_karen/spatial-sc-rnaseq-integration-wf/reference_building/da_neurons_identification_analysis/reference_data/kamath/intermediate/kamath_merged_da_all_non_da_13000_postQC.h5ad`

- _integration_: [`integrate_scvi`](./main/integrate_scvi)
    - `scVI` integration to remove batch effects (minimize non-biological variability)

- _assign remaining cells_: [`label_scanvi`](./main/label_scvi)
    - `scANVI` leverage cell-type from MMC to assign the rest of the cells

- _UMAP clustering_: [`clustering_umap`](./main/clustering_umap)
    - Updated to do leiden at 3 resolutions - [0.2, 0.5, 1.0]
        - FUTURE: We may choose `mde` (`clustering_mde`) over `umap`, as it is super fast and efficient on a GPU, and the embeddings are only useful for visualization so the choice is semi-arbitrary

- __DEPRECATED__  --- _annotation_: [`DEPRECATED_annotate_cells.py`](./main/DEPRECATED_annotate_cells.py)
    - Use cellassign and a list of marker genes. Currently using CARD cortical list of genes. NOTE: this is not annotating the "clusters" but the cells based on marker gene expression.

- _alternate integration_: [`add_harmony`](./main/add_harmony)
    - Add and Harmony integration obsm
    - Save final metadata

- _`SCIB` METRICS_: [`artifact_metrics`](./main/artifact_metrics)
    - Integration metrics
    - Compute `scib` metrics on final artifacts and generate a report to assess quality of batch correction vs. preservation of biological variability
    - TODO: make sure this works correctly. Current jax implementation fails.


## _PLOTTING_
- _plot groups and features_: [`plot_groups_and_feats`](./main/plot_groups_and_feats) 
    - Groups: "sample", "batch", "cell_type"
    - Features: "n_genes_by_counts", "total_counts", "pct_counts_mt", "pct_counts_rb", "doublet_score", "S_score", "G2M_score"
