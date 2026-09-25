version 1.0

# Run steps in the cohort analysis

import "../../wf-common/wdl/tasks/write_cohort_sample_list.wdl" as WriteCohortSampleList
import "cluster_data/cluster_data.wdl" as ClusterData
import "../../wf-common/wdl/tasks/upload_final_outputs.wdl" as UploadFinalOutputs

workflow cohort_analysis {
	input {
		String cohort_id
		Array[Array[String]] project_sample_ids
		Array[File] preprocessed_adata_objects

		# If provided, these files will be uploaded to the staging bucket alongside other intermediate files made by this workflow
		Array[String] preprocessing_output_file_paths = []

		# Filtering parameters
		Int pct_counts_mt_max
		Float doublet_score_max
		Array[Int] total_counts_limits
		Array[Int] n_genes_by_counts_limits
		Float n_mads_lower
		Float n_mads_upper

		# Allen Institute's Map My Cells
		String mmc_taxonomy
		File allen_brain_mmc_precomputed_stats_h5
		File? allen_brain_mmc_marker_genes_json

		# Normalization parameters
		Int norm_target_sum
		Int n_top_genes
		Int n_comps

		# Sample integration
		String scvi_latent_key
		String scanvi_latent_key 
		String scanvi_predictions_key
		String batch_key

		# Clustering parameters
		Int n_neighbors
		Array[Float] leiden_res

		Array[String] groups
		Array[String] features

		String workflow_name
		String workflow_version
		String workflow_release
		String crn_release_version
		String run_timestamp
		String raw_data_path_prefix
		String? modality
		Array[String] staging_data_buckets
		String billing_project
		String container_registry
		String zones
	}

	String sub_workflow_name = "cohort_analysis"
	String sub_workflow_version = "5.0.0"

	Array[Array[String]] workflow_info = [[run_timestamp, workflow_name, workflow_version, workflow_release]]

	String raw_data_path = if defined(modality) then "~{raw_data_path_prefix}/~{sub_workflow_name}/~{modality}/~{sub_workflow_version}/~{run_timestamp}" else "~{raw_data_path_prefix}/~{sub_workflow_name}/~{sub_workflow_version}/~{run_timestamp}"

	# Each modality needs its own staging prefix
	String staging_path_prefix = "~{workflow_name}/release/~{crn_release_version}"
	String preprocess_staging_data_path = if defined(modality) then "~{staging_path_prefix}/preprocess/~{modality}" else "~{staging_path_prefix}/preprocess"
	String cohort_staging_data_path = if defined(modality) then "~{staging_path_prefix}/~{sub_workflow_name}/~{modality}" else "~{staging_path_prefix}/~{sub_workflow_name}"

	call WriteCohortSampleList.write_cohort_sample_list {
		input:
			cohort_id = cohort_id,
			project_sample_ids = project_sample_ids,
			billing_project = billing_project,
			workflow_info = workflow_info,
			raw_data_path = raw_data_path,
			container_registry = container_registry,
			zones = zones
	}

	call merge_and_plot_qc_metrics {
		input:
			cohort_id = cohort_id,
			preprocessed_adata_objects = preprocessed_adata_objects,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call filter {
		input:
			cohort_id = cohort_id,
			merged_adata_object = merge_and_plot_qc_metrics.merged_adata_object, #!FileCoercion
			pct_counts_mt_max = pct_counts_mt_max,
			doublet_score_max = doublet_score_max,
			total_counts_limits = total_counts_limits,
			n_genes_by_counts_limits = n_genes_by_counts_limits,
			n_mads_lower = n_mads_lower,
			n_mads_upper = n_mads_upper,
			container_registry = container_registry,
			zones = zones
	}

	call map_cell_types {
		input:
			cohort_id = cohort_id,
			filtered_adata_object = filter.filtered_adata_object,
			mmc_taxonomy = mmc_taxonomy,
			allen_brain_mmc_precomputed_stats_h5 = allen_brain_mmc_precomputed_stats_h5,
			allen_brain_mmc_marker_genes_json = allen_brain_mmc_marker_genes_json,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call normalize {
		input:
			cohort_id = cohort_id,
			filtered_adata_object = filter.filtered_adata_object,
			norm_target_sum = norm_target_sum,
			n_top_genes = n_top_genes,
			n_comps = n_comps,
			batch_key = batch_key,
			raw_data_path = raw_data_path,
			workflow_name = workflow_name,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call add_mapped_cell_types {
		input:
			cohort_id = cohort_id,
			normalized_adata_object = normalize.normalized_adata_object,
			mmc_results_csv = map_cell_types.mmc_results_csv, #!FileCoercion
			raw_data_path = raw_data_path,
			workflow_name = workflow_name,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call ClusterData.cluster_data {
		input:
			cohort_id = cohort_id,
			mmc_adata_object = add_mapped_cell_types.mmc_adata_object,
			scvi_latent_key = scvi_latent_key,
			scanvi_latent_key = scanvi_latent_key,
			scanvi_predictions_key = scanvi_predictions_key,
			batch_key = batch_key,
			n_neighbors = n_neighbors,
			leiden_res = leiden_res,
			raw_data_path = raw_data_path,
			workflow_name = workflow_name,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call integrate_harmony {
		input:
			cohort_id = cohort_id,
			umap_clustered_adata_object = cluster_data.umap_clustered_adata_object,
			batch_key = batch_key,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call artifact_metrics {
		input:
			cohort_id = cohort_id,
			final_adata_object = integrate_harmony.final_adata_object, #!FileCoercion
			scanvi_predictions_key = scanvi_predictions_key,
			batch_key = batch_key,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call plot_groups_and_features {
		input:
			cohort_id = cohort_id,
			final_adata_object = integrate_harmony.final_adata_object, #!FileCoercion
			groups = groups,
			features = features,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call UploadFinalOutputs.upload_final_outputs as upload_preprocess_files {
		input:
			output_file_paths = preprocessing_output_file_paths,
			staging_data_buckets = staging_data_buckets,
			staging_data_path = preprocess_staging_data_path,
			billing_project = billing_project,
			zones = zones
	}

	Array[String] cohort_analysis_final_output_paths = flatten([
		[
			write_cohort_sample_list.cohort_sample_list
		],
		[
			merge_and_plot_qc_metrics.merged_adata_object,
			merge_and_plot_qc_metrics.qc_initial_metadata_csv
		],
		merge_and_plot_qc_metrics.qc_plots_png,
		[
			map_cell_types.mmc_extended_results_json,
			map_cell_types.mmc_results_csv,
			map_cell_types.mmc_log_txt
		],
		[
			normalize.all_genes_csv,
			normalize.hvg_genes_csv
		],
		[
			add_mapped_cell_types.mmc_results_parquet
		],
		[
			cluster_data.scvi_model_tar_gz,
			cluster_data.scanvi_model_tar_gz,
			cluster_data.scanvi_cell_types_parquet
		],
		[
			integrate_harmony.final_adata_object,
			integrate_harmony.final_metadata_csv,
		],
		[
			artifact_metrics.scib_report_results_csv,
			artifact_metrics.scib_report_results_svg
		],
		[
			plot_groups_and_features.groups_umap_plot_png,
			plot_groups_and_features.features_umap_plot_png
		]
	]) #!StringCoercion

	call UploadFinalOutputs.upload_final_outputs as upload_cohort_analysis_files {
		input:
			output_file_paths = cohort_analysis_final_output_paths,
			staging_data_buckets = staging_data_buckets,
			staging_data_path = cohort_staging_data_path,
			billing_project = billing_project,
			zones = zones
	}

	output {
		File cohort_sample_list = write_cohort_sample_list.cohort_sample_list #!FileCoercion

		# Merged adata objects, QC plots, filtered adata objects, MMC results, normalized adata objects
		File merged_adata_object = merge_and_plot_qc_metrics.merged_adata_object #!FileCoercion
		File qc_initial_metadata_csv = merge_and_plot_qc_metrics.qc_initial_metadata_csv #!FileCoercion
		Array[File] qc_plots_png = merge_and_plot_qc_metrics.qc_plots_png #!FileCoercion
		File filtered_adata_object = filter.filtered_adata_object
		File mmc_extended_results_json = map_cell_types.mmc_extended_results_json #!FileCoercion
		File mmc_results_csv = map_cell_types.mmc_results_csv #!FileCoercion
		File mmc_log_txt = map_cell_types.mmc_log_txt #!FileCoercion
		File normalized_adata_object = normalize.normalized_adata_object
		File all_genes_csv = normalize.all_genes_csv #!FileCoercion
		File hvg_genes_csv = normalize.hvg_genes_csv #!FileCoercion
		File mmc_adata_object = add_mapped_cell_types.mmc_adata_object
		File mmc_results_parquet = add_mapped_cell_types.mmc_results_parquet #!FileCoercion

		# Clustering output
		File integrated_adata_object = cluster_data.integrated_adata_object
		File scvi_model_tar_gz = cluster_data.scvi_model_tar_gz
		File labeled_cells_adata_object = cluster_data.labeled_cells_adata_object
		File scanvi_model_tar_gz = cluster_data.scanvi_model_tar_gz
		File scanvi_cell_types_parquet = cluster_data.scanvi_cell_types_parquet
		File umap_clustered_adata_object = cluster_data.umap_clustered_adata_object

		# PCA and Harmony integrated adata objects
		File final_adata_object = integrate_harmony.final_adata_object #!FileCoercion
		File final_metadata_csv = integrate_harmony.final_metadata_csv #!FileCoercion

		# Artifact metrics
		File scib_report_results_csv = artifact_metrics.scib_report_results_csv #!FileCoercion
		File scib_report_results_svg = artifact_metrics.scib_report_results_svg #!FileCoercion

		# Groups and features plots
		File groups_umap_plot_png = plot_groups_and_features.groups_umap_plot_png #!FileCoercion
		File features_umap_plot_png = plot_groups_and_features.features_umap_plot_png #!FileCoercion

		Array[File] preprocess_manifest_tsvs = upload_preprocess_files.manifests #!FileCoercion
		Array[File] cohort_analysis_manifest_tsvs = upload_cohort_analysis_files.manifests #!FileCoercion
	}

	meta {
		description: "Merges preprocessed per-sample AnnData objects and runs QC filtering, Allen Brain MMC cell type mapping, normalization, scVI/scANVI integration, Leiden clustering, UMAP visualization, Harmony batch correction, and integration quality metrics for a cohort."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		project_sample_ids: {help: "Associated team ID, sample ID, and dataset DOI URL; used to generate a sample list."}
		preprocessed_adata_objects: {help: "An array of preprocessed AnnData objects to run cohort analysis on."}
		preprocessing_output_file_paths: {help: "Selected preprocessed output files to upload to the staging bucket alongside selected cohort analysis output files."}
		pct_counts_mt_max: {help: "Maximum percentage of mitochondrial gene counts allowed per cell. [10]"}
		doublet_score_max: {help: "Maximum doublet detection score threshold. [0.2]"}
		total_counts_limits: {help: "Minimum and maximum total UMI (unique molecular identifier) counts per cell. [100, 100000]"}
		n_genes_by_counts_limits: {help: "Minimum and maximum number of genes detected per cell (genes with at least one count). [100, 10000]"}
		n_mads_lower: {help: "Number of median absolute deviations below the per-sample median allowed for total UMI counts and number of genes detected per cell. [3]"}
		n_mads_upper: {help: "Number of median absolute deviations above the per-sample median allowed for total UMI counts and number of genes detected per cell. [5]"}
		mmc_taxonomy: {help: "Cell type taxonomy of the precomputed stats reference; appended to MMC output filenames. Must match allen_brain_mmc_precomputed_stats_h5. Options are 'SEAAD' (human), 'Siletti' (human), or 'ABC' (mouse)."}
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
		workflow_name: {help: "Workflow name; stored in the file-level manifest and final manifest with all saved files."}
		workflow_version: {help: "Workflow version; stored in the file-level manifest and final manifest with all saved files."}
		workflow_release: {help: "GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		crn_release_version: {help: "CRN Cloud release version; used to organize outputs and for the CRN Cloud release."}
		run_timestamp: {help: "UTC timestamp; stored in the file-level manifest and final manifest with all saved files."}
		raw_data_path_prefix: {help: "Raw data bucket path prefix; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis`)."}
		modality: {help: "Modality subdirectory ('rna', 'atac', or 'multiome') appended to the raw and staging data paths; set when several modality sub-workflows run together so they do not overwrite each other's outputs. Omit to write directly under the base paths."}
		staging_data_buckets: {help: "Array of staging data buckets to upload intermediate files to (i.e., DEV or UAT buckets depending on internal QC status)."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task merge_and_plot_qc_metrics {
	input {
		String cohort_id
		Array[File] preprocessed_adata_objects

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int mem_gb = ceil(size(preprocessed_adata_objects, "GB") * 2.4 + 20)
	Int disk_size = ceil(size(preprocessed_adata_objects, "GB") * 3 + 50)

	command <<<
		set -euo pipefail

		while read -r adata_objects || [[ -n "${adata_objects}" ]]; do 
			adata_path=$(realpath "${adata_objects}")
			sample=$(basename "${adata_path}" ".cleaned_unfiltered.h5ad")
			echo -e "${sample}\t${adata_path}" >> adata_samples_paths.tsv
		done < ~{write_lines(preprocessed_adata_objects)}

		merge_and_plot_qc \
			--adata-objects-fofn adata_samples_paths.tsv \
			--adata-output ~{cohort_id}.merged_cleaned_unfiltered.h5ad \
			--output-metadata-file ~{cohort_id}.initial_metadata.csv

		mv "plots/violin_n_genes_by_counts.png" "plots/~{cohort_id}.n_genes_by_counts.violin.png"
		mv "plots/violin_total_counts.png" "plots/~{cohort_id}.total_counts.violin.png"
		mv "plots/violin_pct_counts_mt.png" "plots/~{cohort_id}.pct_counts_mt.violin.png"
		mv "plots/violin_pct_counts_rb.png" "plots/~{cohort_id}.pct_counts_rb.violin.png"
		mv "plots/violin_doublet_score.png" "plots/~{cohort_id}.doublet_score.violin.png"

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.merged_cleaned_unfiltered.h5ad" \
			-o "~{cohort_id}.initial_metadata.csv" \
			-o plots/"~{cohort_id}.n_genes_by_counts.violin.png" \
			-o plots/"~{cohort_id}.total_counts.violin.png" \
			-o plots/"~{cohort_id}.pct_counts_mt.violin.png" \
			-o plots/"~{cohort_id}.pct_counts_rb.violin.png" \
			-o plots/"~{cohort_id}.doublet_score.violin.png"
	>>>

	output {
		String merged_adata_object = "~{raw_data_path}/~{cohort_id}.merged_cleaned_unfiltered.h5ad"
		String qc_initial_metadata_csv = "~{raw_data_path}/~{cohort_id}.initial_metadata.csv"

		Array[String] qc_plots_png = [
			"~{raw_data_path}/~{cohort_id}.n_genes_by_counts.violin.png",
			"~{raw_data_path}/~{cohort_id}.total_counts.violin.png",
			"~{raw_data_path}/~{cohort_id}.pct_counts_mt.violin.png",
			"~{raw_data_path}/~{cohort_id}.pct_counts_rb.violin.png",
			"~{raw_data_path}/~{cohort_id}.doublet_score.violin.png"
		]
	}

	runtime {
		docker: "~{container_registry}/sc_tools:1.3.0"
		cpu: 4
		cpuPlatform: "Intel Cascade Lake"
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
	}

	meta {
		description: "Merges sample-level AnnData objects to a single cohort-level AnnData object and generates pre-filtering QC violin plots for key metrics."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		preprocessed_adata_objects: {help: "An array of preprocessed AnnData objects to run cohort analysis on."}
		raw_data_path: {help: "Raw data bucket path for merged adata and QC plots outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task filter {
	input {
		String cohort_id
		File merged_adata_object

		Int pct_counts_mt_max
		Float doublet_score_max
		Array[Int] total_counts_limits
		Array[Int] n_genes_by_counts_limits
		Float n_mads_lower
		Float n_mads_upper

		String container_registry
		String zones
	}

	Int calc_mem_gb = ceil(size(merged_adata_object, "GB") * 18 + 20)
	Int mem_gb = if calc_mem_gb > 624 then 624 else calc_mem_gb
	Int disk_size = ceil(size(merged_adata_object, "GB") * 4 + 20)

	command <<<
		set -euo pipefail

		filter \
			--adata-input ~{merged_adata_object} \
			--pct-counts-mt-max ~{pct_counts_mt_max} \
			--doublet-score-max ~{doublet_score_max} \
			--total-counts-limits ~{sep=' ' total_counts_limits} \
			--n-genes-by-counts-limits ~{sep=' ' n_genes_by_counts_limits} \
			--n-mads-lower ~{n_mads_lower} \
			--n-mads-upper ~{n_mads_upper} \
			--adata-output ~{cohort_id}.filtered.h5ad
	>>>

	output {
		File filtered_adata_object = "~{cohort_id}.filtered.h5ad"
	}

	runtime {
		docker: "~{container_registry}/sc_tools:1.3.0"
		cpu: 4
		cpuPlatform: "Intel Cascade Lake"
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
	}

	meta {
		description: "Filters low-quality cells from the merged AnnData object based on mitochondrial content, doublet score, total UMI counts, and number of detected genes. UMI count and detected gene thresholds combine absolute limits with per-sample median absolute deviation (MAD) cutoffs."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		merged_adata_object: {help: "Merged AnnData object."}
		pct_counts_mt_max: {help: "Maximum percentage of mitochondrial gene counts allowed per cell. [10]"}
		doublet_score_max: {help: "Maximum doublet detection score threshold. [0.2]"}
		total_counts_limits: {help: "Absolute minimum and maximum total UMI (unique molecular identifier) counts per cell; applied on top of the MAD-based thresholds. [500, 100000]"}
		n_genes_by_counts_limits: {help: "Absolute minimum and maximum number of genes detected per cell (genes with at least one count); applied on top of the MAD-based thresholds. [300, 10000]"}
		n_mads_lower: {help: "Number of median absolute deviations below the per-sample median allowed for total UMI counts and number of genes detected per cell. [3]"}
		n_mads_upper: {help: "Number of median absolute deviations above the per-sample median allowed for total UMI counts and number of genes detected per cell. [5]"}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task map_cell_types {
	input {
		String cohort_id
		File filtered_adata_object

		String mmc_taxonomy
		File allen_brain_mmc_precomputed_stats_h5
		File? allen_brain_mmc_marker_genes_json

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	String mmc_mapping_mode = if defined(allen_brain_mmc_marker_genes_json) then "mmc_markers_mapping" else "mmc_otf_mapping"
	String mmc_output_prefix = "~{cohort_id}.~{mmc_mapping_mode}.~{mmc_taxonomy}"

	Int threads = 4
	Int calc_human_mem_gb = ceil(size([filtered_adata_object, allen_brain_mmc_precomputed_stats_h5], "GB") * 4 + 50)
	# Mouse brain mapping requires extra memory due to MMC's FromSpecifiedMarkersRunner's architecture
	Int calc_mouse_mem_gb = ceil(size([filtered_adata_object, allen_brain_mmc_precomputed_stats_h5], "GB") * 4 + 50 + (threads * 10))
	Int mem_gb = if defined(allen_brain_mmc_marker_genes_json) then calc_mouse_mem_gb else calc_human_mem_gb
	# MMC's find_markers_for_all_taxonomy_pairs writes unthinned marker scratch to the working disk
	# That scratch scales with the reference taxonomy rather than with the inputs, so it needs a floor of its own
	Int disk_size = ceil(size([filtered_adata_object, allen_brain_mmc_precomputed_stats_h5], "GB") * 4 + 250)

	command <<<
		set -euo pipefail

		/usr/bin/time \
		mmc \
			--adata-input ~{filtered_adata_object} \
			--mmc-precomputed-stats ~{allen_brain_mmc_precomputed_stats_h5} \
			--n-processors ~{if threads > 4 then 4 else threads} \
			--output-prefix ~{mmc_output_prefix} \
			~{if defined(allen_brain_mmc_marker_genes_json) then "--mmc-marker-genes " + allen_brain_mmc_marker_genes_json else ""}

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{mmc_output_prefix}.extended_results.json" \
			-o "~{mmc_output_prefix}.results.csv" \
			-o "~{mmc_output_prefix}.log.txt"
	>>>

	output {
		String mmc_extended_results_json = "~{raw_data_path}/~{mmc_output_prefix}.extended_results.json"
		String mmc_results_csv = "~{raw_data_path}/~{mmc_output_prefix}.results.csv"
		String mmc_log_txt = "~{raw_data_path}/~{mmc_output_prefix}.log.txt"
	}

	runtime {
		docker: "~{container_registry}/sc_tools:1.3.0"
		cpu: threads
		cpuPlatform: "Intel Cascade Lake"
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} SSD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
	}

	meta {
		description: "Assigns cell type labels using the Allen Brain Cell Atlas MapMyCells (MMC) tool. Uses on-the-fly (SEAAD) mapping for human data or marker-gene-based mapping for mouse data when a marker genes JSON is provided."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		filtered_adata_object: {help: "QC-filtered AnnData object."}
		mmc_taxonomy: {help: "Cell type taxonomy of the precomputed stats reference; appended to MMC output filenames. Must match allen_brain_mmc_precomputed_stats_h5. Options are 'SEAAD' (human), 'Siletti' (human), or 'ABC' (mouse)."}
		allen_brain_mmc_precomputed_stats_h5: {help: "A precomputed statistics file from the Allen Brain Cell Atlas containing reference statistics (the average gene expression profile per cell type cluster and cell type taxonomy)."}
		allen_brain_mmc_marker_genes_json: {help: "A text file that contains the JSON serialization of a dict file from the Allen Brain Cell Atlas specifying which marker genes to use at which node in the cell type taxonomy. Currently, only used when processing mouse data."}
		raw_data_path: {help: "Raw data bucket path for outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task normalize {
	input {
		String cohort_id
		File filtered_adata_object

		Int norm_target_sum
		Int n_top_genes
		Int n_comps
		String batch_key

		String raw_data_path
		String workflow_name
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	# GCP N2D machine configuration for memory-extensive task
	Int calc_mem_gb = ceil(size(filtered_adata_object, "GB") * 20 + 150)
	Int mem_gb = if calc_mem_gb > 768 then 768 else calc_mem_gb
	Int threads = if calc_mem_gb > 768 then 96 else ceil(mem_gb / 8.0)
	Int disk_size = ceil(size(filtered_adata_object, "GB") * 4 + 50)

	command <<<
		set -euo pipefail

		process \
			--adata-input ~{filtered_adata_object} \
			--workflow-name ~{workflow_name} \
			--batch-key ~{batch_key} \
			--norm-target-sum ~{norm_target_sum} \
			--n-top-genes ~{n_top_genes} \
			--n-comps ~{n_comps} \
			--adata-output ~{cohort_id}.normalized.h5ad \
			--output-all-genes ~{cohort_id}.all_genes.csv \
			--output-hvg-genes ~{cohort_id}.hvg_genes.csv

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.all_genes.csv" \
			-o "~{cohort_id}.hvg_genes.csv"
	>>>

	output {
		File normalized_adata_object = "~{cohort_id}.normalized.h5ad"
		String all_genes_csv = "~{raw_data_path}/~{cohort_id}.all_genes.csv"
		String hvg_genes_csv = "~{raw_data_path}/~{cohort_id}.hvg_genes.csv"
	}

	runtime {
		docker: "~{container_registry}/sc_tools:1.3.0"
		cpu: threads
		cpuPlatform: "AMD Rome"
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
	}

	meta {
		description: "Normalizes counts per cell, selects highly variable genes, and computes PCA on the filtered AnnData object."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		filtered_adata_object: {help: "QC-filtered AnnData object."}
		norm_target_sum: {help: "The total count value that each cell will be normalized to. [10000]"}
		n_top_genes: {help: "Number of HVG genes to keep. [8000]"}
		n_comps: {help: "Number of principal components to compute. [30]"}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		raw_data_path: {help: "Raw data bucket path for outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task add_mapped_cell_types {
	input {
		String cohort_id
		File normalized_adata_object
		File mmc_results_csv

		String raw_data_path
		String workflow_name
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int calc_mem_gb = ceil(size(normalized_adata_object, "GB") * 18 + 20)
	Int mem_gb = if calc_mem_gb > 624 then 624 else calc_mem_gb
	Int disk_size = ceil(size(normalized_adata_object, "GB") * 4 + 20)

	command <<<
		set -euo pipefail

		transcriptional_phenotype \
			--adata-input ~{normalized_adata_object} \
			--workflow-name ~{workflow_name} \
			--mmc-results ~{mmc_results_csv} \
			--adata-output ~{cohort_id}.mmc.h5ad \
			--output-cell-types-file ~{cohort_id}.mmc_results.parquet

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.mmc_results.parquet"
	>>>

	output {
		File mmc_adata_object = "~{cohort_id}.mmc.h5ad"
		String mmc_results_parquet = "~{raw_data_path}/~{cohort_id}.mmc_results.parquet"
	}

	runtime {
		docker: "~{container_registry}/sc_tools:1.3.0"
		cpu: 4
		cpuPlatform: "Intel Cascade Lake"
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
	}

	meta {
		description: "Joins MMC cell type mapping results onto the normalized AnnData object and exports a Parquet summary of per-cell type assignments."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		normalized_adata_object: {help: "Normalized AnnData object to annotate with cell type labels."}
		mmc_results_csv: {help: "Cell type mapping results CSV produced by map_cell_types."}
		raw_data_path: {help: "Raw data bucket path for outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task integrate_harmony {
	input {
		String cohort_id
		File umap_clustered_adata_object

		String batch_key

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int mem_gb = ceil(size(umap_clustered_adata_object, "GB") * 8 + 20)
	Int disk_size = ceil(size(umap_clustered_adata_object, "GB") * 4 + 20)

	command <<<
		set -euo pipefail

		nvidia-smi

		add_harmony \
			--batch-key ~{batch_key} \
			--adata-input ~{umap_clustered_adata_object} \
			--adata-output ~{cohort_id}.final.h5ad \
			--output-metadata-file ~{cohort_id}.final_metadata.csv

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.final.h5ad" \
			-o "~{cohort_id}.final_metadata.csv"
	>>>

	output {
		String final_adata_object = "~{raw_data_path}/~{cohort_id}.final.h5ad"
		String final_metadata_csv = "~{raw_data_path}/~{cohort_id}.final_metadata.csv"
	}

	runtime {
		docker: "~{container_registry}/sc_tools:1.3.0"
		cpu: 8
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
		gpuType: "nvidia-tesla-t4"
		gpuCount: 1
		nvidiaDriverVersion: "545.23.08" #!UnknownRuntimeKey
	}

	meta {
		description: "Runs Harmony batch correction on the UMAP-clustered AnnData object and exports the final integrated object with cell metadata."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		umap_clustered_adata_object: {help: "UMAP-clustered AnnData object from cluster_data."}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		raw_data_path: {help: "Raw data bucket path for outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task artifact_metrics {
	input {
		String cohort_id
		File final_adata_object

		String scanvi_predictions_key
		String batch_key

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int mem_gb = ceil(size(final_adata_object, "GB") * 8 + 40)
	Int disk_size = ceil(size(final_adata_object, "GB") * 4 + 40)

	command <<<
		set -euo pipefail

		/usr/bin/time \
		artifact_metrics \
			--predictions-key ~{scanvi_predictions_key} \
			--batch-key ~{batch_key} \
			--adata-input ~{final_adata_object} \
			--output-report-dir scib_report_dir

		mv "scib_report_dir/scib_report.csv" "scib_report_dir/~{cohort_id}.scib_report.csv"
		mv "scib_report_dir/scib_results.svg" "scib_report_dir/~{cohort_id}.scib_results.svg"

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "scib_report_dir/~{cohort_id}.scib_report.csv" \
			-o "scib_report_dir/~{cohort_id}.scib_results.svg"
	>>>

	output {
		String scib_report_results_csv = "~{raw_data_path}/~{cohort_id}.scib_report.csv"
		String scib_report_results_svg = "~{raw_data_path}/~{cohort_id}.scib_results.svg"
	}

	runtime {
		docker: "~{container_registry}/sc_tools:1.3.0"
		cpu: 16
		cpuPlatform: "Intel Cascade Lake"
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		bootDiskSizeGb: 40
		zones: zones
	}

	meta {
		description: "Computes scib-metrics integration quality scores on the final AnnData object and exports results as a CSV report and SVG visualization."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		final_adata_object: {help: "Final Harmony-integrated AnnData object."}
		scanvi_predictions_key: {help: "scANVI cell type predictions column name. ['C_scANVI']"}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		raw_data_path: {help: "Raw data bucket path for outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task plot_groups_and_features {
	input {
		String cohort_id
		File final_adata_object

		Array[String] groups
		Array[String] features

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int mem_gb = ceil(size(final_adata_object, "GB") * 5 + 20)
	Int disk_size = ceil(size(final_adata_object, "GB") * 4 + 20)

	command <<<
		set -euo pipefail

		plot_groups_and_feats \
			--adata-input ~{final_adata_object} \
			--groups ~{sep=',' groups} \
			--output-group-umap-plot-prefix "~{cohort_id}" \
			--features ~{sep=',' features} \
			--output-feature-umap-plot-prefix "~{cohort_id}"

		mv "plots/umap~{cohort_id}_groups_umap.png" "plots/~{cohort_id}.groups.umap.png"
		mv "plots/umap~{cohort_id}_features_umap.png" "plots/~{cohort_id}.features.umap.png"

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o plots/"~{cohort_id}.groups.umap.png" \
			-o plots/"~{cohort_id}.features.umap.png"
	>>>

	output {
		String groups_umap_plot_png = "~{raw_data_path}/~{cohort_id}.groups.umap.png"
		String features_umap_plot_png = "~{raw_data_path}/~{cohort_id}.features.umap.png"
	}

	runtime {
		docker: "~{container_registry}/sc_tools:1.3.0"
		cpu: 2
		cpuPlatform: "Intel Cascade Lake"
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
	}

	meta {
		description: "Generates UMAP plots colored by cell metadata groups and gene expression features from the final integrated AnnData object."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		final_adata_object: {help: "Final integrated AnnData object."}
		groups: {help: "Groups to produce umap plots for. ['sample', 'batch', 'cell_type', 'leiden_res_0.05', 'leiden_res_0.10', 'leiden_res_0.20', 'leiden_res_0.40']"}
		features: {help: "Features to produce umap plots for. ['n_genes_by_counts', 'total_counts', 'pct_counts_mt', 'pct_counts_rb', 'doublet_score', 'S_score', 'G2M_score']"}
		raw_data_path: {help: "Raw data bucket path for outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}
