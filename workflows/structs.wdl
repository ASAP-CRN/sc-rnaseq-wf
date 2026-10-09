version 1.0

struct Sample {
	String sample_id
	String? batch
	String? sex
	String? brain_region_level_1
	String? brain_region_level_2
	String? brain_region_level_3

	Array[File]+ fastq_R1s
	Array[File]+ fastq_R2s
	Array[File] fastq_I1s
	Array[File] fastq_I2s
}

struct Project {
	String asap_team_id
	String asap_dataset_id
	String asap_dataset_doi_url
	Array[Sample] samples

	Boolean multimodal_sc_data

	Boolean run_project_cohort_analysis

	String raw_data_bucket
	Array[String] staging_data_buckets
}
