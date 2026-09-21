# sc-rnaseq-wf

Repo for testing and developing a common postmortem-derived brain sequencing (PMDBS) workflow harmonized across ASAP with human and non-human (mouse) sc/sn RNA sequencing data.

Common workflows, tasks, utility scripts, and docker images reused across harmonized ASAP workflows are defined in [the wf-common repository](https://github.com/ASAP-CRN/wf-common).


# Table of contents

- [Workflows](#workflows)
- [Inputs](#inputs)
- [Outputs](#outputs)
    - [Output structure](#output-structure)
- [Docker images](#docker-images)


# Workflows

Worfklows are defined in [the `workflows` directory](workflows). The python scripts which process the data at each stage can be found [the docker/sc_tools/scripts directory](docker/sc_tools/scripts).

Workflow names:
- `pmdbs_sc_rnaseq`
- `mouse_sc_rnaseq`

![Workflow diagram](workflows/workflow_diagram.svg "Workflow diagram")

**Entrypoint**: [workflows/main.wdl](workflows/main.wdl)

**Input template**: [workflows/inputs.json](workflows/inputs.json)

The workflow is broken up into two main chunks:

1. [Preprocessing](#preprocessing)
2. [Cohort analysis](#cohort-analysis)

> Note: The details of the cohort analysis are described in the [sc_tools docker README](docker/sc_tools/scripts/README.md).

## Preprocessing

Run once per sample; only rerun when the preprocessing workflow version is updated. Preprocessing outputs are stored in the originating team's raw and staging data buckets.

## Cohort analysis

Run once per team (all samples from a single team) if `project.run_project_cohort_analysis` is set to `true`, and once for the whole cohort (all samples from all teams). This can be rerun using different sample subsets; including additional samples requires this entire analysis to be rerun. Intermediate files from previous runs are not reused and are stored in timestamped directories.

# Inputs

An input template file can be found at [workflows/inputs.json](workflows/inputs.json).

| Type | Name | Description |
| :- | :- | :- |
| String | organism | Organism; used to select `workflow_name`. Options: 'human' or 'mouse'. If human, `pmdbs_sc_rnaseq` will be the workflow name (i.e., bucket folder name) and if mouse, `mouse_sc_rnaseq` will be selected. |
| String | cohort_id | Name of the cohort; used to name output files during cross-team cohort analysis. |
| Array[[Project](#project)] | projects | The project ID, set of samples and their associated reads and metadata, output bucket locations, and whether or not to run project-level cohort analysis. |
| File | cellranger_reference_data | Cellranger transcriptome reference data; see https://www.10xgenomics.com/support/software/cell-ranger/downloads/previous-versions. |
| Float? | cellbender_fpr | Cellbender false positive rate for signal removal. [0.0] |
| Float? | pct_counts_mt_max | Maximum percentage of mitochondrial gene counts allowed per cell. [10] |
| Int? | doublet_score_max | Maximum doublet detection score threshold. [0.2] |
| Array[Int]? | total_counts_limits | Absolute minimum and maximum total UMI (unique molecular identifier) counts per cell; applied on top of the MAD-based thresholds. [500, 100000] |
| Array[Int]? | n_genes_by_counts_limits | Absolute minimum and maximum number of genes detected per cell (genes with at least one count); applied on top of the MAD-based thresholds. [300, 10000] |
| Float? | n_mads_lower | Number of median absolute deviations below the per-sample median allowed for total UMI counts and number of genes detected per cell. [3] |
| Float? | n_mads_upper | Number of median absolute deviations above the per-sample median allowed for total UMI counts and number of genes detected per cell. [5] |
| File? | allen_brain_mmc_precomputed_stats_h5 | A precomputed statistics file from the Allen Brain Cell Atlas containing reference statistics (the average gene expression profile per cell type cluster and cell type taxonomy).  |
| File? | allen_brain_mmc_marker_genes_json | A text file that contains the JSON serialization of a dict file from the Allen Brain Cell Atlas specifying which marker genes to use at which node in the cell type taxonomy. Currently, only used when processing mouse data. |
| Int? | norm_target_sum | The total count value that each cell will be normalized to. [10000] |
| Int? | n_top_genes | Number of HVG genes to keep. [3000] |
| Int? | n_comps | Number of principal components to compute. [30] |
| String? | scvi_latent_key | Latent key to save the scVI latent to. ['X_scVI'] |
| String? | scanvi_latent_key | Latent key to save the scANVI latent to. ['X_scANVI'] |
| String? | scanvi_predictions_key | scANVI cell type predictions column name. ['C_scANVI'] |
| String? | batch_key | Key in AnnData object for batch information. ['batch_id'] |
| Int? | n_neighbors | The size of local neighborhood (in terms of number of neighboring data points) used for manifold approximation. [15] |
| Array[Float]? | leiden_res | Leiden resolutions which are the parameter values controlling the coarseness of the clustering. [0.2, 0.5, 1.0] |
| Array[String]? | groups | Groups to produce umap plots for. ['sample', 'batch', 'cell_type', 'leiden_res_0.20', 'leiden_res_0.50', 'leiden_res_1.0'] |
| Array[String]? | features | Features to produce umap plots for. ['n_genes_by_counts', 'total_counts', 'pct_counts_mt', 'pct_counts_rb', 'doublet_score', 'S_score', 'G2M_score'] |
| Boolean? | run_cross_team_cohort_analysis | Whether to run downstream harmonization steps on all samples across projects. If set to false, only preprocessing steps (cellranger and generating the initial adata object(s)) will run for samples. [false] |
| String | cohort_raw_data_bucket | Bucket to upload cross-team cohort intermediate files to. |
| Array[String] | cohort_staging_data_buckets | Buckets to upload cross-team cohort analysis outputs to. |
| String | container_registry | Container registry where workflow Docker images are hosted. |
| String? | zones | GCP zones where compute will take place. ['us-central1-c us-central1-f'] |

## Structs

### Project

| Type | Name | Description |
| :- | :- | :- |
| String | asap_team_id | ASAP-generated unique identifier for team; used for naming output files. |
| String | asap_dataset_id | ASAP-generated unique identifier for dataset; used for metadata. |
| String | asap_dataset_doi_url | ASAP-generated Zenodo DOI URL referencing the dataset. |
| Array[[Sample](#sample)] | samples | The set of samples associated with this project. |
| Boolean | multimodal_sc_data | Whether or not the sc/sn RNAseq is from multimodal data. |
| Boolean | run_project_cohort_analysis | Whether or not to run cohort analysis within the project. |
| String | raw_data_bucket | Raw data bucket; intermediate output files that are not final workflow outputs are stored here. |
| String | staging_data_bucket | Staging data bucket; final project-level outputs are stored here. |

### Sample

| Type | Name | Description |
| :- | :- | :- |
| String | sample_id | ASAP-generated unique identifier combined with the replicate for the sample within the project. |
| String? | batch | The sample's batch. If unset, the analysis will stop after running `cellranger_count`. |
| String? | sex | The sample's sex. |
| String? | brain_region_level_1 | Abbreviation of most granular anatomical region (Level 1). |
| String? | brain_region_level_2 | Abbreviation of intermediate level anatomical region (Level 2). |
| String? | brain_region_level_3 | Abbreviation of coarse level anatomical region (Level 3). |
| File | fastq_R1 | Path to the sample's read 1 FASTQ file. |
| File | fastq_R2 | Path to the sample's read 2 FASTQ file. |
| File? | fastq_I1 | Optional fastq index 1. |
| File? | fastq_I2 | Optional fastq index 2. |

## Generating the inputs JSON

The inputs JSON may be generated manually, however when running a large number of samples, this can become unwieldly. The [`generate_inputs` utility script](https://github.com/ASAP-CRN/wf-common/blob/main/util/generate_inputs) may be used to automatically generate the inputs JSON (`inputs.{staging_env}.{cohort_dataset_id}.{date}.json`) and a sample list TSV (`{team_id}.{cohort_dataset_id}.sample_list.{date}.tsv`); same as the one generated in [the write_cohort_sample_list task](https://github.com/ASAP-CRN/wf-common/wdl/tasks/write_cohort_sample_list.wdl)). The script requires the libraries outlined in [the requirements.txt file](https://github.com/ASAP-CRN/wf-common/util/requirements.txt) and the following inputs:

- `project-tsv`: One or more project TSVs with one row per sample and columns team_id, ASAP_dataset_id, ASAP_sample_id, batch, sex, fastq_R1s, fastq_R2s, fastq_R3s, fastq_I1s, fastq_I2s, embargoed, source, modality_flavour, dataset_DOI_url, and SPATIAL columns if applicable: geomx_config, geomx_dsp_config, geomx_annotation_file, visium_cytassist, visium_probe_set, visium_slide_ref, and visium_capture_area. All samples from all projects may be included in the same project TSV, or multiple project TSVs may be provided.
    - `team_id`: A unique identifier for the team from which the sample(s) arose.
    - `ASAP_dataset_id`: A generated unique identifier for the dataset from which the sample(s) arose.
    - `ASAP_sample_id`: A generated unique identifier for the sample within the project.
    - `batch`: The sample's batch.
    - `sex`: The sample's sex.
    - `brain_region_level_1`: Abbreviation of most granular anatomical region (Level 1).
    - `brain_region_level_2`: Abbreviation of intermediate level anatomical region (Level 2).
    - `brain_region_level_3`: Abbreviation of coarse level anatomical region (Level 3).
    - `fastq_R1s`: The gs uri to read 1 of sample FASTQ.
        - This is appended to the `project-tsv` from the `fastq-locs-txt`: FASTQ locations for all samples provided in the `project-tsv`. Each sample is expected to have one set of paired fastqs located at `${fastq_path}/${sample_id}*`. The read 1 file should include 'R1' somewhere in the filename. Generate this file e.g. by running `gcloud storage ls gs://fastq_bucket/some/path/**.fastq.gz >> fastq_locs.txt`.
    - `fastq_R2s`: The gs uri to read 2 of sample FASTQ.
        - This is appended to the `project-tsv` from the `fastq-locs-txt`: FASTQ locations for all samples provided in the `project-tsv`. Each sample is expected to have one set of paired fastqs located at `${fastq_path}/${sample_id}*`. The read 2 file should include 'R2' somewhere in the filename. Generate this file e.g. by running `gcloud storage ls gs://fastq_bucket/some/path/**.fastq.gz >> fastq_locs.txt`.
    - `fastq_I1s`: The gs uri to sample FASTQ index 1.
    - `fastq_I2s`: The gs uri to sample FASTQ index 2.
    - `embargoed`: The internal QC/embargo status of dataset.
    - `source`: The source of dataset (e.g. 'pmdbs').
    - `modality_flavour`: The data modality flavour of dataset (e.g. 'sn-rnaseq')
    - `dataset_DOI_url`: Generated Zenodo DOI URL referencing the dataset.
- `inputs-template`: The inputs template JSON file into which the `projects` information derived from the `project-tsv` will be inserted. Must have a key ending in `*.projects`. Other default values filled out in the inputs template will be written to the output inputs.json file.
- `run-project-cohort-analysis`: Optionally run project-level cohort analysis for provided projects. This value will apply to all projects. [false]
- `workflow_name`: WDL workflow name.
- `cohort-dataset-id`: Dataset name in cohort bucket id (e.g. 'cohort-pmdbs-sc-rnaseq').

Example usage:

```bash
./wf-common/util/generate_inputs \
    --project-tsv metadata.tsv \
    --inputs-template workflows/inputs.json \
    --run-project-cohort-analysis \
    --workflow-name sc_rnaseq_analysis \
    --release-version v5.0.0 \
    --cohort-dataset-id cohort-pmdbs-sc-rnaseq
```

# Outputs

## Output structure

- `cohort_id`: either the `team_id` for project-level cohort analysis, or the `cohort_id` for the full cohort
- `workflow_run_timestamp`: format: `%Y-%m-%dT%H-%M-%SZ`
- The list of samples used to generate the cohort analysis will be output alongside other cohort analysis outputs in the staging data bucket (`${cohort_id}.sample_list.tsv`)
- The `MANIFEST.tsv` file in the staging data bucket describes the file name, md5 hash, timestamp, workflow version, workflow name, and workflow release for the run used to generate each file in that directory

### Raw data (intermediate files and final outputs for all runs of the workflow)

The raw data bucket will contain *some* artifacts generated as part of workflow execution. Following successful workflow execution, the artifacts will also be copied into the staging bucket as final outputs.

In the workflow, task outputs are either specified as `String` (final outputs, which will be copied in order to live in raw data buckets and staging buckets) or `File` (intermediate outputs that are periodically cleaned up, which will live in the cromwell-output bucket). This was implemented to reduce storage costs.

```bash
asap-raw-{cohort,team-xxyy}-{source}-{modality_flavour}-{context}
└── workflow_execution
    └── ${workflow_name}
        ├── cohort_analysis
        │   └──${cohort_analysis_workflow_version}
        │       └── ${workflow_run_timestamp}
        │            └── <cohort outputs>
        └── preprocess  // only produced in project raw data buckets, not in the full cohort bucket
            ├── cellranger
            │   └── ${cellranger_task_version}
            │       └── <cellranger output>
            ├── remove_technical_artifacts
            │   └── ${cellbender_task_version}
            │       └── <remove_technical_artifacts output>
            └── counts_to_adata
                └── ${adata_task_version}
                    └── <counts_to_adata output>
```

### Staging data (intermediate workflow objects and final workflow outputs for the latest run of the workflow)

Following QC by researchers, the objects in the dev or uat bucket are synced into the curated data buckets, maintaining the same file structure. Curated data buckets are named `asap-curated-{cohort,team-xxyy}-{source}-{modality_flavour}-{context}` and `dataset_id` = `{cohort,team-xxyy}-{source}-{modality_flavour}-{context}`.

Data may be synced using [the `promote_staging_data` script](#promoting-staging-data).

```bash
asap-dev-{cohort,team-xxyy}-{source}-{modality_flavour}-{context}
└── ${workflow_name}
    └── release
        └── ${crn_release_version}
            ├── cohort_analysis
            │   ├── ${cohort_id}.sample_list.tsv
            │   ├── ${cohort_id}.merged_cleaned_unfiltered.h5ad
            │   ├── ${cohort_id}.initial_metadata.csv
            │   ├── ${cohort_id}.doublet_score.violin.png
            │   ├── ${cohort_id}.n_genes_by_counts.violin.png
            │   ├── ${cohort_id}.pct_counts_mt.violin.png
            │   ├── ${cohort_id}.pct_counts_rb.violin.png
            │   ├── ${cohort_id}.total_counts.violin.png
            │   ├── ${cohort_id}.{mmc_otf_mapping.SEAAD,mmc_markers_mapping}.extended_results.json
            │   ├── ${cohort_id}.{mmc_otf_mapping.SEAAD,mmc_markers_mapping}.results.csv
            │   ├── ${cohort_id}.{mmc_otf_mapping.SEAAD,mmc_markers_mapping}.log.txt
            │   ├── ${cohort_id}.all_genes.csv
            │   ├── ${cohort_id}.hvg_genes.csv
            │   ├── ${cohort_id}.mmc_results.parquet
            │   ├── ${cohort_id}.scvi_model.tar.gz
            │   ├── ${cohort_id}.scanvi_model.tar.gz
            │   ├── ${cohort_id}.scanvi_cell_types.parquet
            │   ├── ${cohort_id}.final.h5ad
            │   ├── ${cohort_id}.final_metadata.csv
            │   ├── ${cohort_id}.scib_report.csv
            │   ├── ${cohort_id}.scib_results.svg
            │   ├── ${cohort_id}.features.umap.png
            │   ├── ${cohort_id}.groups.umap.png
            │   └── MANIFEST.tsv
            ├── preprocess
            │   ├── ${dataset_id}.${sampleA_id}.cellranger_sc_rnaseq_outputs.tar.gz
            │   ├── ${dataset_id}.${sampleA_id}.filtered_feature_bc_matrix.h5
            │   ├── ${dataset_id}.${sampleA_id}.metrics_summary.csv
            │   ├── ${dataset_id}.${sampleA_id}.molecule_info.h5
            │   ├── ${dataset_id}.${sampleA_id}.raw_feature_bc_matrix.h5
            │   ├── ${dataset_id}.${sampleA_id}.possorted_genome_bam.bam
            │   ├── ${dataset_id}.${sampleA_id}.possorted_genome_bam.bam.bai
            │   ├── ${dataset_id}.${sampleA_id}.cellbender_report.html
            │   ├── ${dataset_id}.${sampleA_id}.cellbender_metrics.csv
            │   ├── ${dataset_id}.${sampleA_id}.cellbender_filtered.h5
            │   ├── ${dataset_id}.${sampleA_id}.cellbender_ckpt.tar.gz
            │   ├── ${dataset_id}.${sampleA_id}.cellbender_cell_barcodes.csv
            │   ├── ${dataset_id}.${sampleA_id}.cellbender.pdf
            │   ├── ${dataset_id}.${sampleA_id}.cellbender.log
            │   ├── ${dataset_id}.${sampleA_id}.cellbender.h5
            │   ├── ${dataset_id}.${sampleA_id}.cellbender_posterior.h5
            │   ├── ${dataset_id}.${sampleA_id}.cleaned_unfiltered.h5ad
            │   ├── ${dataset_id}.${sampleB_id}.cellranger_sc_rnaseq_outputs.tar.gz
            │   ├── ${dataset_id}.${sampleB_id}.filtered_feature_bc_matrix.h5
            │   ├── ${dataset_id}.${sampleB_id}.metrics_summary.csv
            │   ├── ${dataset_id}.${sampleB_id}.molecule_info.h5
            │   ├── ${dataset_id}.${sampleB_id}.raw_feature_bc_matrix.h5
            │   ├── ${dataset_id}.${sampleB_id}.possorted_genome_bam.bam
            │   ├── ${dataset_id}.${sampleB_id}.possorted_genome_bam.bam.bai
            │   ├── ${dataset_id}.${sampleB_id}.cellbender_report.html
            │   ├── ${dataset_id}.${sampleB_id}.cellbender_metrics.csv
            │   ├── ${dataset_id}.${sampleB_id}.cellbender_filtered.h5
            │   ├── ${dataset_id}.${sampleB_id}.cellbender_ckpt.tar.gz
            │   ├── ${dataset_id}.${sampleB_id}.cellbender_cell_barcodes.csv
            │   ├── ${dataset_id}.${sampleB_id}.cellbender.pdf
            │   ├── ${dataset_id}.${sampleB_id}.cellbender.log
            │   ├── ${dataset_id}.${sampleB_id}.cellbender.h5
            │   ├── ${dataset_id}.${sampleB_id}.cellbender_posterior.h5
            │   ├── ${dataset_id}.${sampleB_id}.cleaned_unfiltered.h5ad
            │   ├── ...
            │   ├── ${dataset_id}.${sampleN_id}.cellranger_sc_rnaseq_outputs.tar.gz
            │   ├── ${dataset_id}.${sampleN_id}.filtered_feature_bc_matrix.h5
            │   ├── ${dataset_id}.${sampleN_id}.metrics_summary.csv
            │   ├── ${dataset_id}.${sampleN_id}.molecule_info.h5
            │   ├── ${dataset_id}.${sampleN_id}.raw_feature_bc_matrix.h5
            │   ├── ${dataset_id}.${sampleN_id}.possorted_genome_bam.bam
            │   ├── ${dataset_id}.${sampleN_id}.possorted_genome_bam.bam.bai
            │   ├── ${dataset_id}.${sampleN_id}.cellbender_report.html
            │   ├── ${dataset_id}.${sampleN_id}.cellbender_metrics.csv
            │   ├── ${dataset_id}.${sampleN_id}.cellbender_filtered.h5
            │   ├── ${dataset_id}.${sampleN_id}.cellbender_ckpt.tar.gz
            │   ├── ${dataset_id}.${sampleN_id}.cellbender_cell_barcodes.csv
            │   ├── ${dataset_id}.${sampleN_id}.cellbender.pdf
            │   ├── ${dataset_id}.${sampleN_id}.cellbender.log
            │   ├── ${dataset_id}.${sampleN_id}.cellbender.h5
            │   ├── ${dataset_id}.${sampleN_id}.cellbender_posterior.h5
            │   ├── ${dataset_id}.${sampleN_id}.cleaned_unfiltered.h5ad
            │   └── MANIFEST.tsv
            ├── workflow_version # plain text file
            └── workflow_metadata
                └── ${timestamp}
                    ├── MANIFEST.tsv # combined
                    └── data_promotion_report.md
```

## Promoting staging data

The [`promote_staging_data` script](https://github.com/ASAP-CRN/wf-common/blob/main/util/promote_staging_data) can be used to promote staging data that has been approved to the curated data bucket for a team or set of teams.

This script compiles bucket and file information for both the initial (staging) and target (prod) environment. It also runs data integrity tests to ensure staging data can be promoted and generates a Markdown report. It (1) checks that files are not empty and are not less than or equal to 10 bytes (factoring in white space) and (2) checks that files have associated metadata and is present in MANIFEST.tsv.

If data integrity tests pass, this script will upload a combined MANIFEST.tsv and the data promotion Markdown report under a metadata/{timestamp} directory in the staging bucket. Previous manifest files and reports will be kept. Next, it will rsync all files in the staging bucket to the curated bucket's workflow and metadata directories. **Exercise caution when using this script**; files that are not present in the source (staging) bucket will be deleted at the destination (curated) bucket.

If data integrity tests fail, staging data cannot be promoted. The combined `MANIFEST.tsv`, Markdown report, and `promote_staging_data_script.log` will be locally available.

The script defaults to a dry run, printing out the files that would be copied or deleted for each selected team.

### Options

```
-h  Display this message and exit
-l  List available teams
-w  Workflow name used as a directory in bucket (e.g. 'pmdbs_sc_rnaseq')
-v  Release version (e.g. v4.0.0)
-p  Promote data. If this option is not selected, data that would be copied or deleted is printed out, but files are not actually changed (dry run)
```

### Usage

```bash
# List available teams
./wf-common/util/promote_staging_data -l -w pmdbs_sc_rnaseq -v v4.0.0

# Print out the files that would be copied or deleted from the staging bucket to the curated bucket for teams' datasets processed through the sc RNA-seq pipeline for a specific release version
./wf-common/util/promote_staging_data -w pmdbs_sc_rnaseq -v v4.0.0

# Promote data for teams' datasets processed through the sc RNA-seq pipeline for a specific release version
./wf-common/util/promote_staging_data -w pmdbs_sc_rnaseq -v v4.0.0 -p

# Promote data for teams' datasets processed through the sc RNA-seq pipeline for a specific release version
./wf-common/util/promote_staging_data -w mouse_sc_rnaseq -v v4.0.0 -p
```

# Docker images

Docker images are defined in [the `docker` directory](docker). Each image must minimally define a `build.env` file and a `Dockerfile`.

Example directory structure:
```bash
docker
├── sc_tools
│   ├── build.env
│   ├── Dockerfile
│   ├── requirements.txt
│   └── scripts
│       └── ...
└── cellbender
    ├── build.env
    └── Dockerfile
```

## The `build.env` file

Each target image is defined using the `build.env` file, which is used to specify the name and version tag for the corresponding Docker image. It must contain at minimum the following variables:

- `IMAGE_NAME`
- `IMAGE_TAG`

All variables defined in the `build.env` file will be made available as build arguments during Docker image build.

The `DOCKERFILE` variable may be used to specify the path to a Dockerfile if that file is not found alongside the `build.env` file, for example when multiple images use the same base Dockerfile definition.

## Building Docker images

Docker images can be build using the [`build_docker_images`](https://github.com/DNAstack/bioinformatics-scripts/blob/main/scripts/build_docker_images) script.

```bash
# Build a single image
./build_docker_images -d docker/sc_tools

# Build all images in the `docker` directory
./build_docker_images -d docker

# Build and push all images in the docker directory, using the `dnastack` container registry
./build_docker_images -d docker -c dnastack -p
```

## Tool and library versions

| Image | Major tool versions | Links |
| :- | :- | :- |
| cellbender | <ul><li>[cellbender v0.3.0](https://github.com/broadinstitute/CellBender/releases/tag/v0.3.0)</li><li>[google-cloud-cli 397.0.0](https://cloud.google.com/sdk/docs/release-notes#39700_2022-08-09)</li><li>[python 3.7.16](https://www.python.org/downloads/release/python-3716/)</li><li>[miniconda 23.1.0](https://docs.anaconda.com/miniconda/miniconda-release-notes/)</li><li>[cuda 11.4.0](https://developer.nvidia.com/cuda-11-4-0-download-archive)</li></ul> | [Dockerfile](https://github.com/ASAP-CRN/sc-rnaseq-wf/tree/main/docker/cellbender) |
| cellranger | <ul><li>[cellranger v10.1.0](https://www.10xgenomics.com/support/software/cell-ranger/latest/release-notes/cr-release-notes#v10-1-0)</li><li>[google-cloud-cli 524.0.0](https://cloud.google.com/sdk/docs/release-notes#52400_2025-05-28)</li></ul> | [Dockerfile](https://github.com/ASAP-CRN/sc-rnaseq-wf/tree/main/docker/cellranger) |
| sc_tools | <ul><li>[google-cloud-cli 524.0.0](https://cloud.google.com/sdk/docs/release-notes#52400_2025-05-28)</li><li>[python 3.10.12](https://www.python.org/downloads/release/python-31012/)</li><li>[torch 2.6.0](https://github.com/pytorch/pytorch/releases/tag/v2.6.0)</li></ul> Python libraries: <ul><li>[scvi-tools 1.3.2](https://github.com/scverse/scvi-tools/releases/tag/1.3.2)</li><li>argparse 1.4.0</li><li>[scanpy 1.11.3](https://scanpy.readthedocs.io/en/stable/release-notes/index.html#v1-11-3)</li><li>muon 0.1.7</li><li>tables 3.10.1</li><li>scrublet 0.2.3</li><li>[scikit-learn 1.7.0](https://github.com/scikit-learn/scikit-learn/releases/tag/1.7.0)</li><li>[harmonypy 0.0.10](https://github.com/slowkow/harmonypy/releases/tag/v0.0.10)</li><li>[scib-metrics 0.5.6](https://github.com/YosefLab/scib-metrics/releases/tag/v0.5.6)</li><li>[cell_type_mapper 1.5.3](https://github.com/AllenInstitute/cell_type_mapper/releases/tag/v1.5.3)</li></ul>| [Dockerfile](https://github.com/ASAP-CRN/sc-rnaseq-wf/tree/main/docker/sc_tools) |
| util | <ul><li>[google-cloud-cli 524.0.0](https://cloud.google.com/sdk/docs/release-notes#52400_2025-05-28)</li></ul> | [Dockerfile](https://github.com/ASAP-CRN/wf-common/tree/main/docker/util) |
| DEPRECATED - multiome | <ul><li>[google-cloud-cli 444.0.0](https://cloud.google.com/sdk/docs/release-notes#44400_2023-08-22)</li><li>[multiome seuratv4 environment](https://github.com/shahrozeabbas/Multiome-SeuratV4/tree/main)</li><li>[R scripts](https://github.com/shahrozeabbas/Harmony-RNA-Workflow/tree/main/scripts)</li></ul> | [Dockerfile](https://github.com/ASAP-CRN/sc-rnaseq-wf/tree/main/docker/multiome) |

# wdl-ci

[`wdl-ci`](https://github.com/DNAstack/wdl-ci) provides tools to validate and test workflows and tasks written in [Workflow Description Language (WDL)](https://github.com/openwdl/wdl). In addition to the tests packaged in `wdl-ci`, the [sc-rnaseq-wdl-ci-custom-test-dir](./sc-rnaseq-wdl-ci-custom-test-dir) is a directory containing custom WDL-based tests that are used to test workflow tasks. `wdl-ci` in this repository is set up to run on pull request.

In general, `wdl-ci` will use inputs provided in the [wdl-ci.config.json](./wdl-ci.config.json) and compare current outputs and validated outputs based on changed tasks/workflows to ensure outputs are still valid by meeting the critera in the specified tests. For example, if the Cell Ranger task in our workflow was changed, then this task would be submitted and that output would be considered the "current output". When inspecting the raw counts generated by Cell Ranger, there is a test specified in the [wdl-ci.config.json](./wdl-ci.config.json) called, "check_hdf5". The test will compare the "current output" and "validated output" (provided in the [wdl-ci.config.json](./wdl-ci.config.json)) to make sure that the raw_feature_bc_matrix.h5 file is still a valid HDF5 file.


# Notes

## References

### Cell Ranger references

| Genome | Cell Ranger reference | Link |
| :- | :- | :- |
| Human GRCh38 (GENCODE v44/Ensembl110 annotations) | 2024-A | https://www.10xgenomics.com/support/software/cell-ranger/latest/release-notes/cr-reference-release-notes#2024-a |
| Mouse GRCm39 (GENCODE vM33/Ensembl110 annotations) | 2024-A | https://www.10xgenomics.com/support/software/cell-ranger/latest/release-notes/cr-reference-release-notes#2024-a |

### Allen Brain Institute's MapMyCells references

[Overview of MapMyCells](https://brain-map.org/bkp/analyze/mapmycells) with available taxonomies.

| Taxonomy | Description | Link |
| :- | :- | :- |
| 10x Whole human brain taxonomy (CCN20240330) | Transcriptomic diversity of cell types in adult human brain. Source file used is `precomputed_stats.siletti.training.h5`. | https://allen-brain-cell-atlas.s3.us-west-2.amazonaws.com/index.html#mapmycells/WHB-10Xv3/20240831/. |
| 10x Whole mouse brain taxonomy (CCN20230722) | A high-resolution transcriptomic and spatial atlas of cell types in the whole mouse brain. Source files used are `precomputed_stats_ABC_revision_230821.h5` and `mouse_markers_230821.json`. | https://allen-brain-cell-atlas.s3.us-west-2.amazonaws.com/index.html#mapmycells/WMB-10X/20240831/. |


## DEPRECATED

### Cell type marker table [July 2025]

The reference taxonomy for inference of cell types via [CellAssign](https://docs.scvi-tools.org/en/1.1.0/user_guide/models/cellassign.html) are sourced from https://github.com/NIH-CARD/brain-taxonomy/blob/main/markers/cellassign_card_markers.csv.

## GitHub Repo renaming

### `pmdbs-sc-rna-seq-wf`→`sc-rna-seq-wf` [Dec 2025]

This repo was changed to a more general name to accommodate samples from different sources, such as, PMDBS multimodal sc/sn RNAseq and mouse sc/sn RNAseq.

### `harmonized-wf-dev`→`pmdbs-sc-rna-seq-wf` [Dec 2024]

This repo and work was originally developed under the name `harmonized-wf-dev`.

This workflow was initally set up to implement the [Harmony RNA snakemake workflow](https://github.com/shahrozeabbas/Harmony-RNA-Workflow) in WDL. The WDL version of the workflow aims to maintain backwards compatibility with the snakemake scripts. Scripts used by the WDL workflow were modified from the Harmony RNA snakemake repo; originals may be found [here](https://github.com/shahrozeabbas/Harmony-RNA-Workflow/tree/5384b546f02b6e68f154f77d25667fed03759870/scripts), and their modified R versions in [the docker/multiome/scripts directory](https://github.com/ASAP-CRN/sc-rnaseq-wf/tree/cohort-analysis-v1.0.0/docker/multiome/scripts). Eventually snakemake support was deprecated and the workflows were migrated to Python. Initial version [here](https://github.com/ASAP-CRN/sc-rnaseq-wf/tree/harmonized_pmdbs_analysis-v1.1.0_1.0.0_2.1.0).
