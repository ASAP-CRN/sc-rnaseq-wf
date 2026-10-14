version 1.0

# Validate input parquet files
# Input type: parquet file

task check_parquet {
	input {
		File current_run_output
		File validated_output
	}

	Int disk_size = ceil(size(current_run_output, "GB") + size(validated_output, "GB") + 10)

	command <<<
		set -euo pipefail

		err() {
			message=$1

			echo -e "[ERROR] $message" >&2
		}

		check_parquet() {
			test_file=$1
			python3.9 -c "
		import sys
		import pyarrow.parquet as pq
		try:
			pq.read_table('$test_file')
		except Exception as e:
			sys.exit(1)
		"
		}

		# Confirm that validated output is in parquet format
		if ! (check_parquet ~{validated_output}); then
			err "Validated output file [~{basename(validated_output)}] is not a valid parquet file"
			exit 1
		fi

		# Confirm that current output is in parquet format
		if (check_parquet ~{current_run_output}); then
			echo "Current run output [~{basename(current_run_output)}] is a valid parquet file"
		else
			err "Current run output [~{basename(current_run_output)}] is not a valid parquet file"
			exit 1
		fi
	>>>

	output {
	}

	runtime {
		docker: "dnastack/dnastack-wdl-ci-tools:0.1.1"
		cpu: 1
		memory: "3.75 GB"
		disk: disk_size + " GB"
		disks: "local-disk " + disk_size + " SSD"
		preemptible: 1
	}
}
