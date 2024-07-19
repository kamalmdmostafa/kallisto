
# Kallisto Pipeline

This README file provides detailed instructions on how to use the `flexible_kallisto_pipeline.sh` script for transcript quantification using the Kallisto tool.

## Introduction

Kallisto is a program for quantifying abundances of transcripts from RNA-Seq data. It uses a novel algorithm based on the idea of pseudoalignment for rapidly determining the compatibility of reads with targets, without the need for alignment. This makes Kallisto extremely fast and efficient. It is particularly useful for transcriptomic analysis, where accurate and rapid quantification of gene expression is essential for understanding the transcriptome dynamics in different conditions or treatments.

## Prerequisites

Ensure the following tools are installed and available in your system's PATH:

- Kallisto: Tool for quantifying transcript abundances
- awk: Text processing tool
- grep: Text searching tool
- sed: Text stream editor

You can install these tools using package managers like `apt`, `brew`, or `conda`.

## Usage

\`\`\`bash
./flexible_kallisto_pipeline.sh -cds <CDS file> -k <k-mer number> -threads <number of threads> [-bias]
\`\`\`

### Parameters

- `-cds`: Path to the CDS FASTA file (required)
- `-k`: K-mer size for indexing (required)
- `-threads`: Number of threads to use (required)
- `-bias`: (Optional) Enable sequence bias correction

### Example

\`\`\`bash
./flexible_kallisto_pipeline.sh -cds example.fasta -k 31 -threads 4 -bias
\`\`\`

## Steps

1. **Check and Clean CDS FASTA File**

   The script verifies and cleans the CDS FASTA file, ensuring sequences contain only valid nucleotide characters (ATGCN) and are at least 20 nucleotides long.

2. **Build Kallisto Index**

   The script builds a Kallisto index using the cleaned CDS file and specified k-mer size.

3. **Quantification**

   The script performs transcript quantification using Kallisto for each paired-end sample. It supports up to 3 retries for each sample in case of errors.

4. **Quality Check**

   The script generates a quality check report with metrics such as the total number of reads processed, reads pseudoaligned, pseudoalignment rate, the number of quantified genes (TPM > 0), and mean TPM.

## Output

- Cleaned CDS file
- Kallisto index
- Quantification results for each sample
- Quality check report

## Detailed Instructions

1. **Install Kallisto**

   Follow the installation instructions for Kallisto from the [official website](https://pachterlab.github.io/kallisto/).

2. **Prepare Your Data**

   Ensure your CDS FASTA file and paired-end RNA-Seq files (e.g., `sample_R1.fastq.gz` and `sample_R2.fastq.gz`) are in the working directory.

3. **Run the Script**

   Use the provided command-line example to run the script with your data. Adjust the parameters as needed based on your dataset.

4. **Interpret Results**

   The results will be stored in the `kallisto` directory. The `qc_report.txt` file will provide a summary of the quality metrics for each sample.

## Troubleshooting

- Ensure all required tools are installed and accessible.
- Check input file paths and formats.
- Review the log files in the output directory for error messages and retry information.
