version 1.0

# Generate a preprocessed AnnData object

import "../structs.wdl"

workflow preprocess {
	input {
		String team_id
		String dataset_id
		String dataset_doi_url
		Array[Sample] samples

		Boolean multimodal_sc_data
		File cellranger_reference_data
		Float cellbender_fpr

		String workflow_name
		String workflow_version
		String workflow_release
		String run_timestamp
		String raw_data_path_prefix
		String billing_project
		String container_registry
		String zones
	}

	# Task and subworkflow versions
	String sub_workflow_name = "preprocess"
	String cellranger_task_version = "2.0.0"
	String cellbender_task_version = "1.0.1"
	String adata_task_version = "1.2.0"

	Array[Array[String]] workflow_info = [[run_timestamp, workflow_name, workflow_version, workflow_release]]

	String workflow_raw_data_path_prefix = "~{raw_data_path_prefix}/~{sub_workflow_name}"
	String cellranger_raw_data_path = "~{workflow_raw_data_path_prefix}/cellranger/~{cellranger_task_version}"
	String cellbender_raw_data_path = "~{workflow_raw_data_path_prefix}/remove_technical_artifacts/~{cellbender_task_version}"
	String adata_raw_data_path = "~{workflow_raw_data_path_prefix}/counts_to_adata/~{adata_task_version}"

	scatter (sample_object in samples) {
		String cellranger_count_output = "~{cellranger_raw_data_path}/~{dataset_id}.~{sample_object.sample_id}.raw_feature_bc_matrix.h5"
		String cellbender_count_output = "~{cellbender_raw_data_path}/~{dataset_id}.~{sample_object.sample_id}.cellbender.h5"
		String initial_adata_object_output = "~{adata_raw_data_path}/~{dataset_id}.~{sample_object.sample_id}.cleaned_unfiltered.h5ad"
	}

	# For each sample, outputs an array of true/false: [cellranger_counts_complete, remove_technical_artifacts_complete, initial_adata_object_complete]
	call check_output_files_exist {
		input:
			cellranger_count_output_files = cellranger_count_output,
			remove_technical_artifacts_output_files = cellbender_count_output,
			initial_adata_object_output_files = initial_adata_object_output,
			billing_project = billing_project,
			zones = zones
	}

	scatter (index in range(length(samples))) {
		Sample sample = samples[index]

		String dataset_sample_id = "~{dataset_id}.~{sample.sample_id}"
		Array[String] project_sample_id = [team_id, sample.sample_id, dataset_doi_url]

		String cellranger_count_complete = check_output_files_exist.sample_preprocessing_complete[index][0]
		String cellbender_remove_background_complete = check_output_files_exist.sample_preprocessing_complete[index][1]
		String initial_adata_object_complete = check_output_files_exist.sample_preprocessing_complete[index][2]

		String cellranger_sc_rnaseq_outputs_tar_gz = "~{cellranger_raw_data_path}/~{dataset_sample_id}.cellranger_sc_rnaseq_outputs.tar.gz"
		String cellranger_raw_counts = "~{cellranger_raw_data_path}/~{dataset_sample_id}.raw_feature_bc_matrix.h5"
		String cellranger_filtered_counts = "~{cellranger_raw_data_path}/~{dataset_sample_id}.filtered_feature_bc_matrix.h5"
		String cellranger_molecule_info = "~{cellranger_raw_data_path}/~{dataset_sample_id}.molecule_info.h5"
		String cellranger_metrics_summary_csv = "~{cellranger_raw_data_path}/~{dataset_sample_id}.metrics_summary.csv"
		String cellranger_possorted_genome_bam = "~{cellranger_raw_data_path}/~{dataset_sample_id}.possorted_genome_bam.bam"
		String cellranger_possorted_genome_bam_index = "~{cellranger_raw_data_path}/~{dataset_sample_id}.possorted_genome_bam.bam.bai"

		if (cellranger_count_complete == "false") {
			call cellranger_count {
				input:
					dataset_sample_id = dataset_sample_id,
					sample_id = sample.sample_id,
					fastq_R1s = sample.fastq_R1s,
					fastq_R2s = sample.fastq_R2s,
					fastq_I1s = sample.fastq_I1s,
					fastq_I2s = sample.fastq_I2s,
					multimodal_sc_data = multimodal_sc_data,
					cellranger_reference_data = cellranger_reference_data,
					raw_data_path = cellranger_raw_data_path,
					workflow_info = workflow_info,
					billing_project = billing_project,
					container_registry = container_registry,
					zones = zones
			}
		}

		File sc_rnaseq_outputs_tar_gz_output = select_first([cellranger_count.sc_rnaseq_outputs_tar_gz, cellranger_sc_rnaseq_outputs_tar_gz]) #!FileCoercion
		File raw_counts_output = select_first([cellranger_count.raw_counts, cellranger_raw_counts]) #!FileCoercion
		File filtered_counts_output = select_first([cellranger_count.filtered_counts, cellranger_filtered_counts]) #!FileCoercion
		File molecule_info_output = select_first([cellranger_count.molecule_info, cellranger_molecule_info]) #!FileCoercion
		File metrics_summary_csv_output = select_first([cellranger_count.metrics_summary_csv, cellranger_metrics_summary_csv]) #!FileCoercion
		File possorted_genome_bam_output = select_first([cellranger_count.possorted_genome_bam, cellranger_possorted_genome_bam]) #!FileCoercion
		File possorted_genome_bam_index_output = select_first([cellranger_count.possorted_genome_bam_index, cellranger_possorted_genome_bam_index]) #!FileCoercion

		String cellbender_report_html = "~{cellbender_raw_data_path}/~{dataset_sample_id}.cellbender_report.html"
		String cellbender_removed_background_counts = "~{cellbender_raw_data_path}/~{dataset_sample_id}.cellbender.h5"
		String cellbender_filtered_removed_background_counts = "~{cellbender_raw_data_path}/~{dataset_sample_id}.cellbender_filtered.h5"
		String cellbender_cell_barcodes_csv = "~{cellbender_raw_data_path}/~{dataset_sample_id}.cellbender_cell_barcodes.csv"
		String cellbender_graph_pdf = "~{cellbender_raw_data_path}/~{dataset_sample_id}.cellbender.pdf"
		String cellbender_log = "~{cellbender_raw_data_path}/~{dataset_sample_id}.cellbender.log"
		String cellbender_metrics_csv = "~{cellbender_raw_data_path}/~{dataset_sample_id}.cellbender_metrics.csv"
		String cellbender_posterior_probability = "~{cellbender_raw_data_path}/~{dataset_sample_id}.cellbend_posterior.h5"

		if (cellbender_remove_background_complete == "false") {
			call remove_technical_artifacts {
				input:
					dataset_sample_id = dataset_sample_id,
					raw_counts = raw_counts_output,
					cellbender_fpr = cellbender_fpr,
					raw_data_path = cellbender_raw_data_path,
					workflow_info = workflow_info,
					billing_project = billing_project,
					container_registry = container_registry,
					zones = zones
			}
		}

		File report_html_output = select_first([remove_technical_artifacts.report_html, cellbender_report_html]) #!FileCoercion
		File removed_background_counts_output = select_first([remove_technical_artifacts.removed_background_counts, cellbender_removed_background_counts]) #!FileCoercion
		File filtered_removed_background_counts_output = select_first([remove_technical_artifacts.filtered_removed_background_counts, cellbender_filtered_removed_background_counts]) #!FileCoercion
		File cell_barcodes_csv_output = select_first([remove_technical_artifacts.cell_barcodes_csv, cellbender_cell_barcodes_csv]) #!FileCoercion
		File graph_pdf_output = select_first([remove_technical_artifacts.graph_pdf, cellbender_graph_pdf]) #!FileCoercion
		File log_output = select_first([remove_technical_artifacts.log, cellbender_log]) #!FileCoercion
		File metrics_csv_output = select_first([remove_technical_artifacts.metrics_csv, cellbender_metrics_csv]) #!FileCoercion
		File posterior_probability_output = select_first([remove_technical_artifacts.posterior_probability, cellbender_posterior_probability]) #!FileCoercion

		String preprocessed_adata_object = "~{adata_raw_data_path}/~{dataset_sample_id}.cleaned_unfiltered.h5ad"

		if (initial_adata_object_complete == "false") {
			call counts_to_adata {
				input:
					dataset_sample_id = dataset_sample_id,
					sample_id = sample.sample_id,
					batch = select_first([sample.batch]),
					sex = select_first([sample.sex]),
					team_id = team_id,
					dataset_id = dataset_id,
					cellbender_counts = removed_background_counts_output,
					raw_data_path = adata_raw_data_path,
					workflow_info = workflow_info,
					billing_project = billing_project,
					container_registry = container_registry,
					zones = zones
			}
		}

		File preprocessed_adata_object_output = select_first([counts_to_adata.initial_adata_object, preprocessed_adata_object]) #!FileCoercion
	}

	output {
		# Sample list
		Array[Array[String]] project_sample_ids = project_sample_id

		# Cellranger
		Array[File] sc_rnaseq_outputs_tar_gz = sc_rnaseq_outputs_tar_gz_output #!FileCoercion
		Array[File] raw_counts = raw_counts_output #!FileCoercion
		Array[File] filtered_counts = filtered_counts_output #!FileCoercion
		Array[File] molecule_info = molecule_info_output #!FileCoercion
		Array[File] metrics_summary_csv = metrics_summary_csv_output #!FileCoercion
		Array[File] possorted_genome_bam = possorted_genome_bam_output #!FileCoercion
		Array[File] possorted_genome_bam_index = possorted_genome_bam_index_output #!FileCoercion

		# Remove technical artifacts - Cellbender
		Array[File] report_html = report_html_output
		Array[File] removed_background_counts = removed_background_counts_output #!FileCoercion
		Array[File] filtered_removed_background_counts = filtered_removed_background_counts_output #!FileCoercion
		Array[File] cell_barcodes_csv = cell_barcodes_csv_output #!FileCoercion
		Array[File] graph_pdf = graph_pdf_output #!FileCoercion
		Array[File] log = log_output #!FileCoercion
		Array[File] metrics_csv = metrics_csv_output #!FileCoercion
		Array[File] posterior_probability = posterior_probability_output #!FileCoercion

		# AnnData counts
		Array[File] initial_adata_object = preprocessed_adata_object_output #!FileCoercion
	}

	meta {
		description: "Preprocess the 10x Genomics Single Cell RNA-seq data by running Cell Ranger count, CellBender ambient RNA removal, and converting counts to AnnData object."
	}

	parameter_meta {
		team_id: {help: "Name of the CRN Team; stored in the AnnData objects."}
		dataset_id: {help: "Generated ASAP dataset ID; stored in the AnnData objects."}
		dataset_doi_url: {help: "Generated Zenodo DOI URL referencing the dataset."}
		samples: {help: "An array of Sample struct, set of samples and their associated reads and metadata information."}
		multimodal_sc_data: {help: "Whether or not the sc/sn RNAseq is from multimodal data."}
		cellranger_reference_data: {help: "CellRanger transcriptome reference data; see https://support.10xgenomics.com/single-cell-gene-expression/software/downloads/latest."}
		cellbender_fpr: {help: "Cellbender false positive rate. [0.0]"}
		workflow_name: {help: "Workflow name; stored in the file-level manifest and final manifest with all saved files."}
		workflow_version: {help: "Workflow version; stored in the file-level manifest and final manifest with all saved files."}
		workflow_release: {help: "GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		run_timestamp: {help: "UTC timestamp; stored in the file-level manifest and final manifest with all saved files."}
		raw_data_path_prefix: {help: "Raw data bucket path prefix; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/preprocess`)."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task check_output_files_exist {
	input {
		Array[String] cellranger_count_output_files
		Array[String] remove_technical_artifacts_output_files
		Array[String] initial_adata_object_output_files

		String billing_project
		String zones
	}

	command <<<
		set -euo pipefail

		while read -r output_files || [[ -n "${output_files}" ]]; do
			cellranger_counts_file=$(echo "${output_files}" | cut -f 1)
			cellbender_counts_file=$(echo "${output_files}" | cut -f 2)
			initial_adata_object_file=$(echo "${output_files}" | cut -f 3)

			if gcloud storage ls --billing-project=~{billing_project} "${cellranger_counts_file}"; then
				if gcloud storage ls --billing-project=~{billing_project} "${cellbender_counts_file}"; then
					if gcloud storage ls --billing-project=~{billing_project} "${initial_adata_object_file}"; then
						# If we find all outputs, don't rerun anything
						echo -e "true\ttrue\ttrue" >> sample_preprocessing_complete.tsv
					else
						# If we find cellranger and cellbender outputs, but don't find adata outputs, just rerun counts_to_adata
						echo -e "true\ttrue\tfalse" >> sample_preprocessing_complete.tsv
					fi
				else
					# If we find cellranger, but not cellbender outputs, it does not matter if adata objects exist, so run (or rerun) both cellbender and counts_to_adata
					echo -e "true\tfalse\tfalse" >> sample_preprocessing_complete.tsv
				fi
			else
				# If we don't find cellranger output, we must also need to run (or rerun) preprocessing
				echo -e "false\tfalse\tfalse" >> sample_preprocessing_complete.tsv
			fi
		done < <(paste ~{write_lines(cellranger_count_output_files)} ~{write_lines(remove_technical_artifacts_output_files)} ~{write_lines(initial_adata_object_output_files)})
	>>>

	output {
		Array[Array[String]] sample_preprocessing_complete = read_tsv("sample_preprocessing_complete.tsv")
	}

	runtime {
		docker: "gcr.io/google.com/cloudsdktool/google-cloud-cli:524.0.0-slim"
		cpu: 2
		cpuPlatform: "Intel Cascade Lake"
		memory: "4 GB"
		disks: "local-disk 20 HDD"
		preemptible: 3
		zones: zones
	}
}

task cellranger_count {
	input {
		String dataset_sample_id
		String sample_id

		Array[File] fastq_R1s
		Array[File] fastq_R2s
		Array[File] fastq_I1s
		Array[File] fastq_I2s

		Boolean multimodal_sc_data
		File cellranger_reference_data

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	String cellranger_arc_chemistry_flag = if multimodal_sc_data then "--chemistry=ARC-v1" else ""

	Int threads = 16
	Int mem_gb = 48
	Int disk_size = ceil((size(cellranger_reference_data, "GB") + size(flatten([fastq_R1s, fastq_R2s, fastq_I1s, fastq_I2s]), "GB")) * 4 + 50)

	command <<<
		set -euo pipefail

		# Unpack refdata
		mkdir cellranger_refdata
		tar \
			-zxvf ~{cellranger_reference_data} \
			-C cellranger_refdata \
			--strip-components 1

		# Ensure fastqs are in the same directory
		mkdir fastqs
		while read -r fastq || [[ -n "${fastq}" ]]; do
			if [[ -n "${fastq}" ]]; then
				validated_fastq_name=$(fix_fastq_names --fastq "${fastq}" --sample-id "~{sample_id}" --outdir fastqs)
				if [[ -e "fastqs/${validated_fastq_name}" ]]; then
					echo "[ERROR] Something's gone wrong with fastq renaming; trying to create fastq [${validated_fastq_name}] but it already exists. Exiting."
					exit 1
				else
					ln -s "${fastq}" "fastqs/${validated_fastq_name}"
				fi
			fi
		done < <(cat \
			~{write_lines(fastq_R1s)} \
			~{write_lines(fastq_R2s)} \
			~{write_lines(fastq_I1s)} \
			~{write_lines(fastq_I2s)})

		cellranger --version

		/usr/bin/time \
		cellranger count \
			--id=~{sample_id} \
			--transcriptome="$(pwd)/cellranger_refdata" \
			--fastqs="$(pwd)/fastqs" \
			--create-bam=true \
			--localcores ~{threads} \
			--localmem ~{mem_gb - 4} \
			~{cellranger_arc_chemistry_flag}

		# Save Cell Ranger outs
		cp -r ~{sample_id}/outs sc_rnaseq_outputs
		tar -czvf "~{dataset_sample_id}.cellranger_sc_rnaseq_outputs.tar.gz" sc_rnaseq_outputs

		# Rename outputs to include sample ID
		mv ~{sample_id}/outs/raw_feature_bc_matrix.h5 ~{dataset_sample_id}.raw_feature_bc_matrix.h5
		mv ~{sample_id}/outs/filtered_feature_bc_matrix.h5 ~{dataset_sample_id}.filtered_feature_bc_matrix.h5
		mv ~{sample_id}/outs/molecule_info.h5 ~{dataset_sample_id}.molecule_info.h5
		mv ~{sample_id}/outs/metrics_summary.csv ~{dataset_sample_id}.metrics_summary.csv
		mv ~{sample_id}/outs/possorted_genome_bam.bam ~{dataset_sample_id}.possorted_genome_bam.bam
		mv ~{sample_id}/outs/possorted_genome_bam.bam.bai ~{dataset_sample_id}.possorted_genome_bam.bam.bai

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{dataset_sample_id}.cellranger_sc_rnaseq_outputs.tar.gz" \
			-o "~{dataset_sample_id}.raw_feature_bc_matrix.h5" \
			-o "~{dataset_sample_id}.filtered_feature_bc_matrix.h5" \
			-o "~{dataset_sample_id}.molecule_info.h5" \
			-o "~{dataset_sample_id}.metrics_summary.csv" \
			-o "~{dataset_sample_id}.possorted_genome_bam.bam" \
			-o "~{dataset_sample_id}.possorted_genome_bam.bam.bai"
	>>>

	output {
		String sc_rnaseq_outputs_tar_gz = "~{raw_data_path}/~{dataset_sample_id}.cellranger_sc_rnaseq_outputs.tar.gz"
		String raw_counts = "~{raw_data_path}/~{dataset_sample_id}.raw_feature_bc_matrix.h5"
		String filtered_counts = "~{raw_data_path}/~{dataset_sample_id}.filtered_feature_bc_matrix.h5"
		String molecule_info = "~{raw_data_path}/~{dataset_sample_id}.molecule_info.h5"
		String metrics_summary_csv = "~{raw_data_path}/~{dataset_sample_id}.metrics_summary.csv"
		String possorted_genome_bam = "~{raw_data_path}/~{dataset_sample_id}.possorted_genome_bam.bam"
		String possorted_genome_bam_index = "~{raw_data_path}/~{dataset_sample_id}.possorted_genome_bam.bam.bai"
	}

	runtime {
		docker: "~{container_registry}/cellranger:10.1.0"
		cpu: threads
		cpuPlatform: "Intel Cascade Lake"
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		bootDiskSizeGb: 40
		zones: zones
	}

	meta {
		description: "Processes raw sequencing data from 10x sc RNA-seq experiments to generate raw and filtered feature-barcode count matrices."
	}

	parameter_meta {
		dataset_sample_id: {help: "Generated ASAP dataset ID and sample ID; stored in the AnnData objects."}
		sample_id: {help: "Generated ASAP sample ID; used to name output files."}
		fastq_R1s: {help: "Sample's read 1 FASTQ file."}
		fastq_R2s: {help: "Sample's read 2 FASTQ file."}
		fastq_I1s: {help: "Optional FASTQ index 1."}
		fastq_I2s: {help: "Optional FASTQ index 2."}
		multimodal_sc_data: {help: "Whether or not the sc/sn RNAseq is from multimodal data."}
		cellranger_reference_data: {help: "CellRanger transcriptome reference data; see https://support.10xgenomics.com/single-cell-gene-expression/software/downloads/latest."}
		raw_data_path: {help: "Raw data bucket path for cellranger-atac count outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/preprocess/cellranger/<cellranger_task_version>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task remove_technical_artifacts {
	input {
		String dataset_sample_id

		File raw_counts

		Float cellbender_fpr

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int disk_size = ceil(size(raw_counts, "GB") * 2 + 50)

	command <<<
		set -euo pipefail

		nvidia-smi

		/usr/bin/time \
		cellbender remove-background \
			--cuda \
			--input ~{raw_counts} \
			--output ~{dataset_sample_id}.cellbender. \
			--fpr ~{cellbender_fpr}

		mv ckpt.tar.gz "~{dataset_sample_id}.cellbender_ckpt.tar.gz"

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{dataset_sample_id}.cellbender_report.html" \
			-o "~{dataset_sample_id}.cellbender.h5" \
			-o "~{dataset_sample_id}.cellbender_filtered.h5" \
			-o "~{dataset_sample_id}.cellbender_cell_barcodes.csv" \
			-o "~{dataset_sample_id}.cellbender.pdf" \
			-o "~{dataset_sample_id}.cellbender.log" \
			-o "~{dataset_sample_id}.cellbender_metrics.csv" \
			-o "~{dataset_sample_id}.cellbend_posterior.h5"
	>>>

	output {
		String report_html = "~{raw_data_path}/~{dataset_sample_id}.cellbender_report.html"
		String removed_background_counts = "~{raw_data_path}/~{dataset_sample_id}.cellbender.h5"
		String filtered_removed_background_counts = "~{raw_data_path}/~{dataset_sample_id}.cellbender_filtered.h5"
		String cell_barcodes_csv = "~{raw_data_path}/~{dataset_sample_id}.cellbender_cell_barcodes.csv"
		String graph_pdf = "~{raw_data_path}/~{dataset_sample_id}.cellbender.pdf"
		String log = "~{raw_data_path}/~{dataset_sample_id}.cellbender.log"
		String metrics_csv = "~{raw_data_path}/~{dataset_sample_id}.cellbender_metrics.csv"
		String posterior_probability = "~{raw_data_path}/~{dataset_sample_id}.cellbend_posterior.h5"
	}

	runtime {
		docker: "~{container_registry}/cellbender:0.3.0"
		cpu: 4
		memory: "64 GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
		gpuType: "nvidia-tesla-t4"
		gpuCount: 1
	}

	meta {
		description: "Removes ambient RNA and technical noise from raw CellRanger count matrices using CellBender."
	}

	parameter_meta {
		dataset_sample_id: {help: "Generated ASAP dataset ID and sample ID; stored in the AnnData objects."}
		raw_counts: {help: "Raw CellRanger count matrix (H5 format) to process."}
		cellbender_fpr: {help: "Cellbender false positive rate. [0.0]"}
		raw_data_path: {help: "Raw data bucket path for cellbender outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/preprocess/cellbender/<cellbender_task_version>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task counts_to_adata {
	input {
		String dataset_sample_id
		String sample_id
		String batch
		String sex

		String team_id
		String dataset_id

		File cellbender_counts

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int disk_size = ceil(size(cellbender_counts, "GB") * 2 + 20)

	command <<<
		set -euo pipefail

		prep_metadata \
			--adata-input ~{cellbender_counts} \
			--sample-id ~{sample_id} \
			--batch ~{batch} \
			--sex ~{sex} \
			--team ~{team_id} \
			--dataset ~{dataset_id} \
			--adata-output ~{dataset_sample_id}.cleaned_unfiltered.h5ad

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{dataset_sample_id}.cleaned_unfiltered.h5ad"
	>>>

	output {
		String initial_adata_object = "~{raw_data_path}/~{dataset_sample_id}.cleaned_unfiltered.h5ad"
	}

	runtime {
		docker: "~{container_registry}/sc_tools:1.3.0"
		cpu: 4
		cpuPlatform: "Intel Cascade Lake"
		memory: "32 GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
	}

	meta {
		description: "Converts CellBender-cleaned Cell Ranger counts into AnnData objects using Scanpy."
	}

	parameter_meta {
		dataset_sample_id: {help: "Generated ASAP dataset ID and sample ID; stored in the AnnData objects."}
		sample_id: {help: "Generated ASAP sample ID; stored in the AnnData objects and used to name output files."}
		batch: {help: "The sample's batch; stored in the AnnData objects."}
		sex: {help: "The sample's sex; stored in the AnnData objects."}
		team_id: {help: "Name of the CRN Team; stored in the AnnData objects."}
		dataset_id: {help: "Generated ASAP dataset ID; stored in the AnnData objects."}
		cellbender_counts: {help: "CellBender-cleaned count matrix (H5 format)."}
		raw_data_path: {help: "Raw data bucket path for counts to adata outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/preprocess/counts_to_adata/<adata_task_version>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}
