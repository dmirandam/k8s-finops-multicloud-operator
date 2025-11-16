#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

CSI="\033["
RESET="${CSI}0m"
BOLD="${CSI}1m"
DIM="${CSI}2m"
RED="${CSI}31m"
GREEN="${CSI}32m"
YELLOW="${CSI}33m"
BLUE="${CSI}34m"
MAGENTA="${CSI}35m"
CYAN="${CSI}36m"

timestamp() {
	date +"%Y-%m-%d %H:%M:%S"
}

header() {
	echo -e "${BOLD}${CYAN}\n=== $1 ===${RESET}"
}

info() {
	echo -e "${BLUE}[$(timestamp)][INFO]${RESET} $1"
}

step() {
	echo -e "${YELLOW}[$(timestamp)][STEP]${RESET} $1"
}

success() {
	echo -e "${GREEN}[$(timestamp)][OK]${RESET} $1"
}

warn() {
	echo -e "${MAGENTA}[$(timestamp)][WARN]${RESET} $1"
}

err() {
	echo -e "${RED}[$(timestamp)][ERROR]${RESET} $1" >&2
}

on_error() {
	local exit_code=$?
	local line_no=${1:-"?"}
	err "Command failed at line ${line_no} with exit code ${exit_code}."
	exit ${exit_code}
}

trap 'on_error $LINENO' ERR

run_step() {
	local msg="$1"
	shift
	step "${msg}"
	"$@"
	success "Completed: ${msg}"
}

header "Crossplane installation and AWS compositions"

install_crossplane() {
	if helm status crossplane -n crossplane-system >/dev/null 2>&1; then
		err "Helm release 'crossplane' already exists. Skipping installation."
		return 0
	fi

	helm install crossplane --namespace crossplane-system --create-namespace crossplane-stable/crossplane
}

run_step "Install Crossplane (helm)" install_crossplane

run_step "Apply AWS functions" kubectl apply -f ./crossplane/AWS/functions.yaml
run_step "Apply AWS secret" kubectl apply -f ./crossplane/AWS/secret.yaml
run_step "Apply AWS providers" kubectl apply -f ./crossplane/AWS/providers.yaml
run_step "Apply AWS provider config (namespace: crossplane-system)" kubectl apply -f ./crossplane/AWS/provider_config.yaml -n crossplane-system
run_step "Apply AWS XRD" kubectl apply -f ./crossplane/AWS/XRD.yaml

header "Apply AWS Compositions"
run_step "Apply VPC composition" kubectl apply -f ./crossplane/AWS/Compositions/vpc.yaml
run_step "Apply IAM composition" kubectl apply -f ./crossplane/AWS/Compositions/iam.yaml
run_step "Apply SQS composition" kubectl apply -f ./crossplane/AWS/Compositions/sqs.yaml
run_step "Apply EKS composition" kubectl apply -f ./crossplane/AWS/Compositions/eks.yaml

info "All steps finished."