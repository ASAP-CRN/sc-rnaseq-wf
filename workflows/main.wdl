version 1.0

# Harmonized human PMDBS and non-human (mouse) brain sc/sn RNAseq workflow entrypoint

import "structs.wdl"
import "../wf-common/wdl/tasks/get_workflow_metadata.wdl" as GetWorkflowMetadata
import "preprocess/preprocess.wdl" as Preprocess
import "cohort_analysis/cohort_analysis.wdl" as CohortAnalysis

workflow sc_rnaseq_analysis {
	input {
		String organism
		String cohort_id
		Array[Project] projects

		# Preprocess
		File cellranger_reference_data
		Float cellbender_fpr = 0.0

		# Filtering parameters
		Int pct_counts_mt_max = 10
		Float doublet_score_max = 0.2
		Array[Int] total_counts_limits = [100, 100000]
		Array[Int] n_genes_by_counts_limits = [100, 10000]

		# Allen Institute's Map My Cells
		String mmc_taxonomy
		File allen_brain_mmc_precomputed_stats_h5
		File? allen_brain_mmc_marker_genes_json

		# Normalization parameters
		Int norm_target_sum = 10000
		Int n_top_genes = 3000
		Int n_comps = 30

		# Sample integration
		String scvi_latent_key = "X_scVI"
		String scanvi_latent_key = "X_scANVI"
		String scanvi_predictions_key = "C_scANVI"
		String batch_key = "batch_id"

		# Clustering parameters
		Int n_neighbors = 15
		Array[Float] leiden_res = [0.05, 0.1, 0.2, 0.4]

		Array[String] groups = ["sample", "batch", "cell_type", "leiden_res_0.05", "leiden_res_0.10", "leiden_res_0.20", "leiden_res_0.40"]
		Array[String] features = ["n_genes_by_counts", "total_counts", "pct_counts_mt", "pct_counts_rb", "doublet_score", "S_score", "G2M_score"]

		# Cohort analysis
		Boolean run_cross_team_cohort_analysis = false
		String cohort_raw_data_bucket
		Array[String] cohort_staging_data_buckets

		String container_registry
		String zones = "us-central1-c us-central1-f"
	}

	String workflow_execution_path = "workflow_execution"
	String workflow_version = "v4.1.0"
	String workflow_release = "https://github.com/ASAP-CRN/sc-rnaseq-wf/releases/tag/sc_rnaseq_analysis-~{workflow_version}"
	String crn_release_version = "v5.1.0"

	call get_workflow_name {
		input:
			organism = organism,
			zones = zones
	}

	call GetWorkflowMetadata.get_workflow_metadata {
		input:
			zones = zones
	}

	scatter (project in projects) {
		String project_raw_data_path_prefix = "~{project.raw_data_bucket}/~{workflow_execution_path}/~{get_workflow_name.workflow_name}"

		call Preprocess.preprocess {
			input:
				team_id = project.asap_team_id,
				dataset_id = project.asap_dataset_id,
				dataset_doi_url = project.asap_dataset_doi_url,
				samples = project.samples,
				multimodal_sc_data = project.multimodal_sc_data,
				cellranger_reference_data = cellranger_reference_data,
				cellbender_fpr = cellbender_fpr,
				workflow_name = get_workflow_name.workflow_name,
				workflow_version = workflow_version,
				workflow_release = workflow_release,
				run_timestamp = get_workflow_metadata.timestamp,
				raw_data_path_prefix = project_raw_data_path_prefix,
				billing_project = get_workflow_metadata.billing_project,
				container_registry = container_registry,
				zones = zones
		}

		Array[String] preprocessing_output_file_paths = flatten([
			preprocess.sc_rnaseq_outputs_tar_gz,
			preprocess.raw_counts,
			preprocess.filtered_counts,
			preprocess.molecule_info,
			preprocess.metrics_summary_csv,
			preprocess.possorted_genome_bam,
			preprocess.possorted_genome_bam_index,
			preprocess.report_html,
			preprocess.removed_background_counts,
			preprocess.filtered_removed_background_counts,
			preprocess.cell_barcodes_csv,
			preprocess.graph_pdf,
			preprocess.log,
			preprocess.metrics_csv,
			preprocess.posterior_probability,
			preprocess.initial_adata_object
		]) #!StringCoercion

		if (project.run_project_cohort_analysis) {
			call CohortAnalysis.cohort_analysis as project_cohort_analysis {
				input:
					cohort_id = project.asap_team_id,
					project_sample_ids = preprocess.project_sample_ids,
					preprocessed_adata_objects = preprocess.initial_adata_object,
					preprocessing_output_file_paths = preprocessing_output_file_paths,
					pct_counts_mt_max = pct_counts_mt_max,
					doublet_score_max = doublet_score_max,
					total_counts_limits = total_counts_limits,
					n_genes_by_counts_limits = n_genes_by_counts_limits,
					mmc_taxonomy = mmc_taxonomy,
					allen_brain_mmc_precomputed_stats_h5 = allen_brain_mmc_precomputed_stats_h5,
					allen_brain_mmc_marker_genes_json = allen_brain_mmc_marker_genes_json,
					norm_target_sum = norm_target_sum,
					n_top_genes = n_top_genes,
					n_comps = n_comps,
					scvi_latent_key = scvi_latent_key,
					scanvi_latent_key = scanvi_latent_key,
					scanvi_predictions_key = scanvi_predictions_key,
					batch_key = batch_key,
					n_neighbors = n_neighbors,
					leiden_res = leiden_res,
					groups = groups,
					features = features,
					workflow_name = get_workflow_name.workflow_name,
					workflow_version = workflow_version,
					workflow_release = workflow_release,
					crn_release_version = crn_release_version,
					run_timestamp = get_workflow_metadata.timestamp,
					raw_data_path_prefix = project_raw_data_path_prefix,
					staging_data_buckets = project.staging_data_buckets,
					billing_project = get_workflow_metadata.billing_project,
					container_registry = container_registry,
					zones = zones
			}
		}
	}

	if (run_cross_team_cohort_analysis) {
		String cohort_raw_data_path_prefix = "~{cohort_raw_data_bucket}/~{workflow_execution_path}/~{get_workflow_name.workflow_name}"

		call CohortAnalysis.cohort_analysis as cross_team_cohort_analysis {
			input:
				cohort_id = cohort_id,
				project_sample_ids = flatten(preprocess.project_sample_ids),
				preprocessed_adata_objects = flatten(preprocess.initial_adata_object),
				preprocessing_output_file_paths = flatten(preprocessing_output_file_paths),
				pct_counts_mt_max = pct_counts_mt_max,
				doublet_score_max = doublet_score_max,
				total_counts_limits = total_counts_limits,
				n_genes_by_counts_limits = n_genes_by_counts_limits,
				mmc_taxonomy = mmc_taxonomy,
				allen_brain_mmc_precomputed_stats_h5 = allen_brain_mmc_precomputed_stats_h5,
				allen_brain_mmc_marker_genes_json = allen_brain_mmc_marker_genes_json,
				norm_target_sum = norm_target_sum,
				n_top_genes = n_top_genes,
				n_comps = n_comps,
				scvi_latent_key =scvi_latent_key,
				scanvi_latent_key = scanvi_latent_key,
				scanvi_predictions_key = scanvi_predictions_key,
				batch_key = batch_key,
				n_neighbors = n_neighbors,
				leiden_res = leiden_res,
				groups = groups,
				features = features,
				workflow_name = get_workflow_name.workflow_name,
				workflow_version = workflow_version,
				workflow_release = workflow_release,
				crn_release_version = crn_release_version,
				run_timestamp = get_workflow_metadata.timestamp,
				raw_data_path_prefix = cohort_raw_data_path_prefix,
				staging_data_buckets = cohort_staging_data_buckets,
				billing_project = get_workflow_metadata.billing_project,
				container_registry = container_registry,
				zones = zones
		}
	}

	output {
		# Sample-level outputs
		# Sample list
		Array[Array[Array[String]]] project_sample_ids = preprocess.project_sample_ids

		# Cellranger
		Array[Array[File]] cellranger_sc_rnaseq_outputs_tar_gz = preprocess.sc_rnaseq_outputs_tar_gz
		Array[Array[File]] cellranger_raw_counts = preprocess.raw_counts
		Array[Array[File]] cellranger_filtered_counts = preprocess.filtered_counts
		Array[Array[File]] cellranger_molecule_info = preprocess.molecule_info
		Array[Array[File]] cellranger_metrics_summary_csv = preprocess.metrics_summary_csv
		Array[Array[File]] cellranger_possorted_genome_bam = preprocess.possorted_genome_bam
		Array[Array[File]] cellranger_possorted_genome_bam_index = preprocess.possorted_genome_bam_index

		# Preprocess
		Array[Array[File]] cellbender_report_html = preprocess.report_html
		Array[Array[File]] cellbender_removed_background_counts = preprocess.removed_background_counts
		Array[Array[File]] cellbender_filtered_removed_background_counts = preprocess.filtered_removed_background_counts
		Array[Array[File]] cellbender_cell_barcodes_csv = preprocess.cell_barcodes_csv
		Array[Array[File]] cellbender_graph_pdf = preprocess.graph_pdf
		Array[Array[File]] cellbender_log = preprocess.log
		Array[Array[File]] cellbender_metrics_csv = preprocess.metrics_csv
		Array[Array[File]] cellbender_posterior_probability = preprocess.posterior_probability
		Array[Array[File]] initial_adata_object = preprocess.initial_adata_object

		# Project cohort analysis outputs
		## List of samples included in the cohort
		Array[File?] project_cohort_sample_list = project_cohort_analysis.cohort_sample_list

		# Merged adata objects, QC plots, filtered adata objects, MMC results, normalized adata objects
		Array[File?] project_merged_adata_object = project_cohort_analysis.merged_adata_object
		Array[File?] project_qc_initial_metadata_csv = project_cohort_analysis.qc_initial_metadata_csv
		Array[Array[File]?] project_qc_plots_png = project_cohort_analysis.qc_plots_png
		Array[File?] project_filtered_adata_object = project_cohort_analysis.filtered_adata_object
		Array[File?] project_mmc_extended_results_json = project_cohort_analysis.mmc_extended_results_json
		Array[File?] project_mmc_results_csv = project_cohort_analysis.mmc_results_csv
		Array[File?] project_mmc_log_txt = project_cohort_analysis.mmc_log_txt
		Array[File?] project_normalized_adata_object = project_cohort_analysis.normalized_adata_object
		Array[File?] project_all_genes_csv = project_cohort_analysis.all_genes_csv
		Array[File?] project_hvg_genes_csv = project_cohort_analysis.hvg_genes_csv
		Array[File?] project_mmc_adata_object = project_cohort_analysis.mmc_adata_object
		Array[File?] project_mmc_results_parquet = project_cohort_analysis.mmc_results_parquet

		# Clustering outputs
		Array[File?] project_integrated_adata_object = project_cohort_analysis.integrated_adata_object
		Array[File?] project_scvi_model_tar_gz = project_cohort_analysis.scvi_model_tar_gz
		Array[File?] project_labeled_cells_adata_object = project_cohort_analysis.labeled_cells_adata_object
		Array[File?] project_scanvi_model_tar_gz = project_cohort_analysis.scanvi_model_tar_gz
		Array[File?] project_scanvi_cell_types_parquet = project_cohort_analysis.scanvi_cell_types_parquet
		Array[File?] project_umap_clustered_adata_object = project_cohort_analysis.umap_clustered_adata_object

		# PCA and Harmony integrated adata objects and artifact metrics
		Array[File?] project_final_adata_object = project_cohort_analysis.final_adata_object
		Array[File?] project_final_metadata_csv = project_cohort_analysis.final_metadata_csv
		Array[File?] project_scib_report_results_csv = project_cohort_analysis.scib_report_results_csv
		Array[File?] project_scib_report_results_svg = project_cohort_analysis.scib_report_results_svg

		# Groups and features plots
		Array[File?] project_groups_umap_plot_png = project_cohort_analysis.groups_umap_plot_png
		Array[File?] project_features_umap_plot_png = project_cohort_analysis.features_umap_plot_png

		Array[Array[File]?] preprocess_manifests = project_cohort_analysis.preprocess_manifest_tsvs
		Array[Array[File]?] project_manifests = project_cohort_analysis.cohort_analysis_manifest_tsvs

		# Cross-team cohort analysis outputs
		## List of samples included in the cohort
		File? cohort_sample_list = cross_team_cohort_analysis.cohort_sample_list

		# Merged adata objects, QC plots, filtered adata objects, MMC results, normalized adata objects
		File? cohort_merged_adata_object = cross_team_cohort_analysis.merged_adata_object
		File? cohort_qc_initial_metadata_csv = cross_team_cohort_analysis.qc_initial_metadata_csv
		Array[File]? cohort_qc_plots_png = cross_team_cohort_analysis.qc_plots_png
		File? cohort_filtered_adata_object = cross_team_cohort_analysis.filtered_adata_object
		File? cohort_mmc_extended_results_json = cross_team_cohort_analysis.mmc_extended_results_json
		File? cohort_mmc_results_csv = cross_team_cohort_analysis.mmc_results_csv
		File? cohort_mmc_log_txt = cross_team_cohort_analysis.mmc_log_txt
		File? cohort_normalized_adata_object = cross_team_cohort_analysis.normalized_adata_object
		File? cohort_all_genes_csv = cross_team_cohort_analysis.all_genes_csv
		File? cohort_hvg_genes_csv = cross_team_cohort_analysis.hvg_genes_csv
		File? cohort_mmc_adata_object = cross_team_cohort_analysis.mmc_adata_object
		File? cohort_mmc_results_parquet = cross_team_cohort_analysis.mmc_results_parquet

		# Clustering outputs
		File? cohort_integrated_adata_object = cross_team_cohort_analysis.integrated_adata_object
		File? cohort_scvi_model_tar_gz = cross_team_cohort_analysis.scvi_model_tar_gz
		File? cohort_labeled_cells_adata_object = cross_team_cohort_analysis.labeled_cells_adata_object
		File? cohort_scanvi_model_tar_gz = cross_team_cohort_analysis.scanvi_model_tar_gz
		File? cohort_scanvi_cell_types_parquet = cross_team_cohort_analysis.scanvi_cell_types_parquet
		File? cohort_umap_clustered_adata_object = cross_team_cohort_analysis.umap_clustered_adata_object

		# PCA and Harmony integrated adata objects and artifact metrics
		File? cohort_final_adata_object = cross_team_cohort_analysis.final_adata_object
		File? cohort_final_metadata_csv = cross_team_cohort_analysis.final_metadata_csv
		File? cohort_scib_report_results_csv = cross_team_cohort_analysis.scib_report_results_csv
		File? cohort_scib_report_results_svg = cross_team_cohort_analysis.scib_report_results_svg

		# Groups and features plots
		File? cohort_groups_umap_plot_png = cross_team_cohort_analysis.groups_umap_plot_png
		File? cohort_features_umap_plot_png = cross_team_cohort_analysis.features_umap_plot_png

		Array[File]? cohort_manifests = cross_team_cohort_analysis.cohort_analysis_manifest_tsvs
	}

	meta {
		description: "Harmonized human postmortem-derived brain sequencing (PMDBS) and non-human (mouse) brain sc/sn RNA-seq workflow."
	}

	parameter_meta {
		organism: {help: "Organism; used to select workflow name. Options: 'human' or 'mouse'. If human, 'pmdbs_sc_rnaseq' will be the workflow name (i.e., bucket folder name) and if mouse, 'mouse_sc_rnaseq' will be selected."}
		cohort_id: {help: "Name of the cohort; used to name output files during cross-team cohort analysis."}
		projects: {help: "The project ID, set of samples and their associated reads and metadata, output bucket locations, sc data type, and whether or not to run project-level cohort analysis."}
		cellranger_reference_data: {help: "Cellranger transcriptome reference data; see https://support.10xgenomics.com/single-cell-gene-expression/software/downloads/latest."}
		cellbender_fpr: {help: "Cellbender false positive rate. [0.0]"}
		pct_counts_mt_max: {help: "Maximum percentage of mitochondrial gene counts allowed per cell. [10]"}
		doublet_score_max: {help: "Maximum doublet detection score threshold. [0.2]"}
		total_counts_limits: {help: "Minimum and maximum total UMI (unique molecular identifier) counts per cell. [100, 100000]"}
		n_genes_by_counts_limits: {help: "Minimum and maximum number of genes detected per cell (genes with at least one count). [100, 10000]"}
		mmc_taxonomy: {help: "Cell type taxonomy of the precomputed stats reference; appended to MMC output filenames. Must match allen_brain_mmc_precomputed_stats_h5. Options are 'SEEAD' (human), 'Siletti' (human), or 'ABC' (mouse)."}
		allen_brain_mmc_precomputed_stats_h5: {help: "A precomputed statistics file from the Allen Brain Cell Atlas containing reference statistics (the average gene expression profile per cell type cluster and cell type taxonomy)."}
		allen_brain_mmc_marker_genes_json: {help: "A text file that contains the JSON serialization of a dict file from the Allen Brain Cell Atlas specifying which marker genes to use at which node in the cell type taxonomy. Currently, only used when processing mouse data."}
		norm_target_sum: {help: "The total count value that each cell will be normalized to. [10000]"}
		n_top_genes: {help: "Number of HVG genes to keep. [8000]"}
		n_comps: {help: "Number of principal components to compute. [30]"}
		scvi_latent_key: {help: "Latent key to save the scVI latent to. ['X_scVI']"}
		scanvi_latent_key: {help: "Latent key to save the scANVI latent to. ['X_scANVI']"}
		scanvi_predictions_key: {help: "scANVI cell type predictions column name. ['C_scANVI']"}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		n_neighbors: {help: "The size of local neighborhood (in terms of number of neighboring data points) used for manifold approximation. [15]"}
		leiden_res: {help: "Leiden resolutions which are the parameter values controlling the coarseness of the clustering. [0.05, 0.1, 0.2, 0.4]"}
		groups: {help: "Groups to produce umap plots for. ['sample', 'batch', 'cell_type', 'leiden_res_0.05', 'leiden_res_0.10', 'leiden_res_0.20', 'leiden_res_0.40']"}
		features: {help: "Features to produce umap plots for. ['n_genes_by_counts', 'total_counts', 'pct_counts_mt', 'pct_counts_rb', 'doublet_score', 'S_score', 'G2M_score']"}
		run_cross_team_cohort_analysis: {help: "Whether to run downstream harmonization steps on all samples across projects. If set to false, only preprocessing steps (cellranger and generating the initial adata object(s)) will run for samples. [false]"}
		cohort_raw_data_bucket: {help: "Bucket to upload cross-team cohort intermediate files to."}
		cohort_staging_data_buckets: {help: "Set of buckets to stage cross-team cohort analysis outputs in."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in."}
	}
}

task get_workflow_name {
	input {
		String organism
		String zones
	}

	command <<<
		set -euo pipefail

		if [[ ~{organism} == "human" ]]; then
			echo "Detected: [~{organism}]"
			workflow_name="pmdbs_sc_rnaseq"
			echo "${workflow_name}" > workflow_name.txt
			echo "Running: [${workflow_name}]"
		elif [[ ~{organism} == "mouse" ]]; then
			echo "Detected: [~{organism}]"
			workflow_name="mouse_sc_rnaseq"
			echo "${workflow_name}" > workflow_name.txt
			echo "Running: [${workflow_name}]"
		else
			echo "[ERROR] Invalid organism for sc/sn RNAseq: [~{organism}]"
			printf "Please select a valid organism for sc/sn RNAseq:\n  human\n  mouse"
			exit 1
		fi
	>>>

	output {
		String workflow_name = read_string("workflow_name.txt")
	}

	runtime {
		docker: "gcr.io/google.com/cloudsdktool/google-cloud-cli:524.0.0-slim"
		cpu: 2
		cpuPlatform: "Intel Cascade Lake"
		memory: "4 GB"
		disks: "local-disk 10 HDD"
		preemptible: 3
		zones: zones
	}
}
