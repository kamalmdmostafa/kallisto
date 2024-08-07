#!/bin/bash

set -e

# Function to display usage
usage() {
    echo "Usage: $0 -cds <CDS file> -k <k-mer number> -threads <number of threads> [-bias]"
    echo "  -cds      : Path to the CDS FASTA file"
    echo "  -k        : K-mer size for indexing"
    echo "  -threads  : Number of threads to use"
    echo "  -bias     : (Optional) Enable sequence bias correction"
    exit 1
}

# Parse command-line arguments
USE_BIAS=false
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -cds)
        CDS_FILE="$2"
        shift 2
        ;;
        -k)
        K_VALUE="$2"
        shift 2
        ;;
        -threads)
        THREADS="$2"
        shift 2
        ;;
        -bias)
        USE_BIAS=true
        shift
        ;;
        *)
        echo "Unknown option: $1"
        usage
        ;;
    esac
done

# Check if required arguments are provided
if [ -z "$CDS_FILE" ] || [ -z "$K_VALUE" ] || [ -z "$THREADS" ]; then
    echo "Error: Missing required arguments"
    usage
fi

# Set up directory structure
KALLISTO_DIR="kallisto"
mkdir -p "$KALLISTO_DIR"

# Set variables
INDEX_PREFIX="${KALLISTO_DIR}/kallisto_index_k${K_VALUE}"
QUANT_PREFIX="${KALLISTO_DIR}/kallisto_quant_k${K_VALUE}"
CLEANED_CDS="${KALLISTO_DIR}/cleaned_$(basename "$CDS_FILE")"
QC_REPORT="${KALLISTO_DIR}/qc_report.txt"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required commands
for cmd in kallisto awk grep sed; do
    if ! command_exists "$cmd"; then
        echo "Error: $cmd is not installed or not in PATH"
        exit 1
    fi
done

echo "Kallisto version:"
kallisto version

# Step 1: Check and clean CDS FASTA
echo "Checking and cleaning CDS FASTA..."
awk '
BEGIN {OFS="\n"}
/^>/ {
    if (NR>1 && len>=20) 
        print header, seq
    header=$0
    seq=""
    len=0
    next
}
{
    gsub(/[^ATGCN]/, "N")
    seq=seq $0
    len+=length($0)
}
END {
    if (len>=20)
        print header, seq
}' "$CDS_FILE" > "$CLEANED_CDS"

echo "Cleaned CDS file created: $CLEANED_CDS"

# Step 2: Build Kallisto index
echo "Building Kallisto index..."
kallisto index -i "$INDEX_PREFIX" -k "$K_VALUE" "$CLEANED_CDS"

if [ -f "$INDEX_PREFIX" ]; then
    echo "Index created successfully: $INDEX_PREFIX"
else
    echo "Error: Index creation failed"
    exit 1
fi

# Step 3: Quantification
echo "Starting quantification..."
mkdir -p "$QUANT_PREFIX"

for R1_FILE in *_R1.fastq.gz
do
    R2_FILE="${R1_FILE/_R1/_R2}"
    SAMPLE_NAME=$(basename "$R1_FILE" _R1.fastq.gz)
    
    # Check if both R1 and R2 files exist
    if [ ! -f "$R1_FILE" ] || [ ! -f "$R2_FILE" ]; then
        echo "Error: Missing paired-end file for $SAMPLE_NAME"
        continue
    fi
    
    echo "Processing sample: $SAMPLE_NAME"
    
    BIAS_FLAG=""
    if [ "$USE_BIAS" = true ]; then
        BIAS_FLAG="--bias"
    fi
    
    # Retry mechanism
    MAX_RETRIES=3
    for ((i=1; i<=MAX_RETRIES; i++)); do
        echo "Attempt $i of $MAX_RETRIES"
        
        kallisto quant -i "$INDEX_PREFIX" \
                       -o "${QUANT_PREFIX}/${SAMPLE_NAME}" \
                       -t "$THREADS" \
                       $BIAS_FLAG \
                       --bootstrap-samples=100 \
                       "$R1_FILE" "$R2_FILE" 2>&1 | tee "${QUANT_PREFIX}/${SAMPLE_NAME}_kallisto.log"
        
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            echo "Quantification successful for $SAMPLE_NAME"
            break
        else
            echo "Error in quantification for $SAMPLE_NAME (Attempt $i)"
            if [ $i -eq $MAX_RETRIES ]; then
                echo "Failed to quantify $SAMPLE_NAME after $MAX_RETRIES attempts"
                echo "See log file: ${QUANT_PREFIX}/${SAMPLE_NAME}_kallisto.log"
            else
                echo "Retrying..."
                sleep 5
            fi
        fi
    done
done

# Check if any samples were processed
if [ -z "$(ls -A "$QUANT_PREFIX")" ]; then
    echo "Error: No samples were processed successfully. Check your input files and logs."
    exit 1
fi

echo "All samples have been processed. Results are in $QUANT_PREFIX"

# Step 4: Quality Check
echo "Performing quality checks..."
echo "Quality Check Report" > "$QC_REPORT"
echo "=====================" >> "$QC_REPORT"
echo "" >> "$QC_REPORT"

for SAMPLE_DIR in "${QUANT_PREFIX}"/*
do
    if [ -d "$SAMPLE_DIR" ]; then
        SAMPLE_NAME=$(basename "$SAMPLE_DIR")
        echo "Sample: $SAMPLE_NAME" >> "$QC_REPORT"
        
        if [ -f "${SAMPLE_DIR}/run_info.json" ]; then
            # Extract QC metrics from run_info.json
            TOTAL_READS=$(jq .n_processed "${SAMPLE_DIR}/run_info.json")
            MAPPED_READS=$(jq .n_pseudoaligned "${SAMPLE_DIR}/run_info.json")
            MAPPING_RATE=$(jq .p_pseudoaligned "${SAMPLE_DIR}/run_info.json")
            
            echo "  Total reads processed: $TOTAL_READS" >> "$QC_REPORT"
            echo "  Reads pseudoaligned: $MAPPED_READS" >> "$QC_REPORT"
            echo "  Pseudoalignment rate: $MAPPING_RATE" >> "$QC_REPORT"
        else
            echo "  Warning: run_info.json not found for $SAMPLE_NAME" >> "$QC_REPORT"
        fi
        
        if [ -f "${SAMPLE_DIR}/abundance.tsv" ]; then
            # Check number of quantified genes
            QUANTIFIED_GENES=$(awk 'NR>1 {count += ($5 > 0)} END {print count}' "${SAMPLE_DIR}/abundance.tsv")
            echo "  Genes quantified (TPM > 0): $QUANTIFIED_GENES" >> "$QC_REPORT"
            
            # Calculate mean TPM
            MEAN_TPM=$(awk 'NR>1 {sum += $5} END {print sum/NR}' "${SAMPLE_DIR}/abundance.tsv")
            echo "  Mean TPM: $MEAN_TPM" >> "$QC_REPORT"
        else
            echo "  Warning: abundance.tsv not found for $SAMPLE_NAME" >> "$QC_REPORT"
        fi
        
        echo "" >> "$QC_REPORT"
    fi
done

echo "QC report generated: $QC_REPORT"
echo "Pipeline completed successfully."
