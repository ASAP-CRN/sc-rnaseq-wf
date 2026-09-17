version 1.0

# Perform dataset integration, annotation, and UMAP clustering steps

workflow cluster_data {
	input {
		String cohort_id
		File mmc_adata_object

		# Sample integration
		String scvi_latent_key
		String scanvi_latent_key 
		String scanvi_predictions_key
		String batch_key

		# Clustering parameters
		Int n_neighbors
		Array[Float] leiden_res

		String raw_data_path
		String workflow_name
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	call integrate_sample_data {
		input:
			cohort_id = cohort_id,
			mmc_adata_object = mmc_adata_object,
			scvi_latent_key = scvi_latent_key,
			batch_key = batch_key,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call assign_remaining_cells {
		input:
			cohort_id = cohort_id,
			integrated_adata_object = integrate_sample_data.integrated_adata_object,
			scvi_model_tar_gz = integrate_sample_data.scvi_model_tar_gz, #!FileCoercion
			scanvi_latent_key = scanvi_latent_key,
			scanvi_predictions_key = scanvi_predictions_key,
			raw_data_path = raw_data_path,
			workflow_name = workflow_name,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call cluster_cells {
		input:
			cohort_id = cohort_id,
			labeled_cells_adata_object = assign_remaining_cells.labeled_cells_adata_object,
			scvi_latent_key = scvi_latent_key,
			n_neighbors = n_neighbors,
			leiden_res = leiden_res,
			container_registry = container_registry,
			zones = zones
	}

	output {
		File integrated_adata_object = integrate_sample_data.integrated_adata_object
		File scvi_model_tar_gz = integrate_sample_data.scvi_model_tar_gz #!FileCoercion
		File labeled_cells_adata_object = assign_remaining_cells.labeled_cells_adata_object
		File scanvi_model_tar_gz = assign_remaining_cells.scanvi_model_tar_gz #!FileCoercion
		File scanvi_cell_types_parquet = assign_remaining_cells.scanvi_cell_types_parquet #!FileCoercion
		File umap_clustered_adata_object = cluster_cells.umap_clustered_adata_object
	}

	meta {
		description: "Integrates samples with scVI, propagates MMC cell type labels to unlabeled cells using scANVI, builds a neighborhood graph, and produces UMAP-clustered output at multiple Leiden resolutions."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files during cross-team cohort analysis."}
		mmc_adata_object: {help: "AnnData object with MMC cell type labels from cohort_analysis."}
		scvi_latent_key: {help: "Latent key to save the scVI latent to. ['X_scVI']"}
		scanvi_latent_key: {help: "Latent key to save the scANVI latent to. ['X_scANVI']"}
		scanvi_predictions_key: {help: "scANVI cell type predictions column name. ['C_scANVI']"}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		n_neighbors: {help: "The size of local neighborhood (in terms of number of neighboring data points) used for manifold approximation. [15]"}
		leiden_res: {help: "Leiden resolutions which are the parameter values controlling the coarseness of the clustering. [0.05, 0.1, 0.2, 0.4]"}
		raw_data_path: {help: "Raw data bucket path for outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_name: {help: "Workflow name; stored in the file-level manifest and final manifest with all saved files."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task integrate_sample_data {
	input {
		String cohort_id
		File mmc_adata_object

		String scvi_latent_key
		String batch_key

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int mem_gb = ceil(size(mmc_adata_object, "GB") * 5 + 20)
	Int disk_size = ceil(size(mmc_adata_object, "GB") * 3 + 50)

	command <<<
		set -euo pipefail

		nvidia-smi

		/usr/bin/time \
		integrate_scvi \
			--latent-key ~{scvi_latent_key} \
			--batch-key ~{batch_key} \
			--adata-input ~{mmc_adata_object} \
			--adata-output ~{cohort_id}.scvi_integrated.h5ad \
			--output-scvi-dir ~{cohort_id}_scvi_model

		# Model name cannot be changed because scvi models serialization expects a path containing a model.pt object
		tar -czvf "~{cohort_id}.scvi_model.tar.gz" "~{cohort_id}_scvi_model"

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.scvi_model.tar.gz"
	>>>

	output {
		File integrated_adata_object = "~{cohort_id}.scvi_integrated.h5ad"
		String scvi_model_tar_gz = "~{raw_data_path}/~{cohort_id}.scvi_model.tar.gz"
	}

	runtime {
		docker: "~{container_registry}/sc_tools:1.3.0"
		cpu: 4
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		bootDiskSizeGb: 40
		zones: zones
		gpuType: "nvidia-tesla-t4"
		gpuCount: 1
		nvidiaDriverVersion: "545.23.08" #!UnknownRuntimeKey
	}

	meta {
		description: "Trains a scVI variational autoencoder to produce a batch-corrected latent representation of the cohort. Exports trained scVI model."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		mmc_adata_object: {help: "AnnData object with MMC cell type labels to integrate."}
		scvi_latent_key: {help: "Latent key to save the scVI latent to. ['X_scVI']"}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		raw_data_path: {help: "Raw data bucket path for outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task assign_remaining_cells {
	input {
		String cohort_id
		File integrated_adata_object
		File scvi_model_tar_gz

		String scanvi_latent_key
		String scanvi_predictions_key

		String raw_data_path
		String workflow_name
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int mem_gb = ceil(size(integrated_adata_object, "GB") * 12 + 30)
	Int disk_size = ceil(size(integrated_adata_object, "GB") * 3 + 50)

	command <<<
		set -euo pipefail

		nvidia-smi

		mkdir -p "~{cohort_id}_scvi_model"
		tar -xzvf ~{scvi_model_tar_gz} -C "~{cohort_id}_scvi_model" --strip-components=1

		/usr/bin/time \
		label_scanvi \
			--workflow-name ~{workflow_name} \
			--latent-key ~{scanvi_latent_key} \
			--predictions-key ~{scanvi_predictions_key} \
			--adata-input ~{integrated_adata_object} \
			--scvi-outputs-dir "~{cohort_id}_scvi_model" \
			--adata-output ~{cohort_id}.scanvi_labeled.h5ad \
			--output-scanvi-dir ~{cohort_id}_scanvi_model \
			--output-cell-types-file "~{cohort_id}.scanvi_cell_types.parquet"

		# Model name cannot be changed because scvi models serialization expects a path containing a model.pt object
		tar -czvf "~{cohort_id}.scanvi_model.tar.gz" "~{cohort_id}_scanvi_model"

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.scanvi_model.tar.gz" \
			-o "~{cohort_id}.scanvi_cell_types.parquet"
	>>>

	output {
		File labeled_cells_adata_object = "~{cohort_id}.scanvi_labeled.h5ad"
		String scanvi_model_tar_gz = "~{raw_data_path}/~{cohort_id}.scanvi_model.tar.gz"
		String scanvi_cell_types_parquet = "~{raw_data_path}/~{cohort_id}.scanvi_cell_types.parquet"
	}

	runtime {
		docker: "~{container_registry}/sc_tools:1.3.0"
		cpu: 16
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		bootDiskSizeGb: 40
		zones: zones
		gpuType: "nvidia-tesla-t4"
		gpuCount: 1
		nvidiaDriverVersion: "545.23.08" #!UnknownRuntimeKey
	}

	meta {
		description: "Uses scANVI (semi-supervised) to propagate MMC cell type labels to unlabeled cells using the pretrained scVI model. Exports per-cell type predictions and the trained scANVI model."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		integrated_adata_object: {help: "scVI-integrated AnnData object with batch-corrected latent representation."}
		scvi_model_tar_gz: {help: "Tarball of the trained scVI model directory from integrate_sample_data."}
		scanvi_latent_key: {help: "Latent key to save the scANVI latent to. ['X_scANVI']"}
		scanvi_predictions_key: {help: "scANVI cell type predictions column name. ['C_scANVI']"}
		raw_data_path: {help: "Raw data bucket path for outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_name: {help: "Workflow name; stored in the file-level manifest and final manifest with all saved files."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task cluster_cells {
	input {
		String cohort_id
		File labeled_cells_adata_object

		String scvi_latent_key

		Int n_neighbors
		Array[Float] leiden_res

		String container_registry
		String zones
	}

	Int mem_gb = ceil(size(labeled_cells_adata_object, "GB") * 8.7 + 20)
	Int disk_size = ceil(size([labeled_cells_adata_object], "GB") * 6 + 50)

	command <<<
		set -euo pipefail

		/usr/bin/time \
		clustering_umap \
			--latent-key ~{scvi_latent_key} \
			--n-neighbors ~{n_neighbors} \
			--leiden-res ~{sep=' ' leiden_res} \
			--adata-input ~{labeled_cells_adata_object} \
			--adata-output ~{cohort_id}.umap_clustered.h5ad
	>>>

	output {
		File umap_clustered_adata_object = "~{cohort_id}.umap_clustered.h5ad"
	}

	runtime {
		docker: "~{container_registry}/sc_tools:1.3.0"
		cpu: 16
		cpuPlatform: "Intel Cascade Lake"
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
	}

	meta {
		description: "Builds a neighborhood graph from the scVI latent space, runs Leiden clustering at multiple resolutions, and computes UMAP embeddings."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		labeled_cells_adata_object: {help: "AnnData object with scANVI cell type labels from assign_remaining_cells."}
		scvi_latent_key: {help: "Latent key to save the scVI latent to. ['X_scVI']"}
		n_neighbors: {help: "The size of local neighborhood (in terms of number of neighboring data points) used for manifold approximation. [15]"}
		leiden_res: {help: "Leiden resolutions which are the parameter values controlling the coarseness of the clustering. [0.05, 0.1, 0.2, 0.4]"}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}
