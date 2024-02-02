#!/bin/bash

set -e

GIT_REPO_TOKEN=""
CLUSTER_ID=""
MANIFESTS_REPO_URL=""
MANIFESTS_GIT_REV=main
CONTAINER_REGISTRY="harbor.taco-cat.xyz"
RUN_CONTAINER_CMD=""

GIT_REPO_TYPE=gitea # or github
OUTPUT_DIR="output"
CAPI_PROVIDERS="aws byoh"

function usage {
	echo -e "\nUsage: $0 --git-token GIT_REPO_TOKEN --cluster-id CLUSTER_ID [--use-render-container] [--manifests-git MANIFESTS_GIT_URL] [--git-rev MANIFESTS_GIT_REV] [--registry REGISTRY_URL]"
	exit 1
}

# We use "$@" instead of $* to preserve argument-boundary information
ARGS=$(getopt -o 't:c:m:g:r:h' --long 'git-token:,cluster-id:,use-render-container,manifests-git:,git-rev:,registry:,help' -- "$@") || usage
eval "set -- $ARGS"

while true; do
	case $1 in
	-h | --help)
		usage
		;;
	-t | --git-token)
		GIT_REPO_TOKEN=$2
		shift 2
		;;
	--use-render-container)
		RUN_CONTAINER_CMD="docker run --rm -i -v $(pwd)/base:/root/base -v $(pwd)/$OUTPUT_DIR:/root/output $CONTAINER_REGISTRY/tks/decapod-render:v3.3.4"
		shift 1
		;;
	-c | --cluster-id)
		CLUSTER_ID=$2
		shift 2
		;;
	-m | --manifests-git)
		MANIFESTS_REPO_URL=$2
		shift 2
		;;
	-g | --git-rev)
		MANIFESTS_GIT_REV=$2
		shift 2
		;;
	-r | --registry)
		CONTAINER_REGISTRY=$2
		shift 2
		;;
	--)
		shift
		break
		;;
	*) exit 1 ;; # error
	esac
done

function log() {
	level=$2
	msg=$3
	date=$(date '+%F %H:%M:%S')
	if [ $1 -eq 0 ]; then
		echo "[$date] $level     $msg"
	else
		level="ERROR"
		echo "[$date] $level     $msg failed"
		exit $1
	fi
}

commit_msg=$(git show -s --format="[%h] %s" HEAD)
commit_id=$(git show -s --format="%h" HEAD)

mkdir -p ${OUTPUT_DIR}

#-----------------------------------------------------------
# rendering decapod base and site / creating manifests files
#-----------------------------------------------------------
log 0 "INFO" "Starting build manifests for '${CLUSTER_ID}' site"
for app in $(ls site/$CLUSTER_ID/); do
	hr_file="base/${app}/$CLUSTER_ID/${app}-manifest.yaml"
	mkdir -p base/${app}/$CLUSTER_ID
	cp -r site/$CLUSTER_ID/${app}/*.yaml base/${app}/$CLUSTER_ID/

	log 0 "INFO" ">>>>>>>>>> Rendering ${app}-manifest.yaml for $CLUSTER_ID site"
	$RUN_CONTAINER_CMD kustomize build --enable-alpha-plugins "base/${app}/$CLUSTER_ID" -o "base/${app}/$CLUSTER_ID/${app}-manifest.yaml"
	log $? "INFO" "run kustomize build"

	if [ -f "${hr_file}" ]; then
		log 0 "INFO" "[${hr_file}] Successfully Generate Helm-Release Files!"
	else
		log 1 "ERROR" "[${hr_file}] Failed to render manifest yaml"
	fi

	$RUN_CONTAINER_CMD helm2yaml -m "${hr_file}" -t -o "${OUTPUT_DIR}/$CLUSTER_ID/${app}"
	log 0 "INFO" "Successfully Generate ${app} manifests Files!"

	rm -f "$hr_file"
	rm -rf "base/${app}/$CLUSTER_ID"
done

[ -d "$(pwd)/${OUTPUT_DIR}/$CLUSTER_ID/tks-cluster/cluster-api" ] && rm -rf "$(pwd)/${OUTPUT_DIR}/$CLUSTER_ID/tks-cluster/cluster-api"
for provider in ${CAPI_PROVIDERS}; do
	[ -d "$(pwd)/${OUTPUT_DIR}/$CLUSTER_ID/tks-cluster/cluster-api-${provider}" ] && mv -f "$(pwd)/${OUTPUT_DIR}/$CLUSTER_ID/tks-cluster/cluster-api-${provider}" "$(pwd)/${OUTPUT_DIR}/$CLUSTER_ID/tks-cluster/cluster-api"
done

log 0 "INFO" "Almost finished: changing namespace for cluster-resouces from argo to cluster-name.."
sed -i "s/ namespace: argo/ namespace: $CLUSTER_ID/g" $(pwd)/${OUTPUT_DIR}/$CLUSTER_ID/tks-cluster/cluster-api/*
sed -i "s/- argo/- $CLUSTER_ID/g" $(pwd)/${OUTPUT_DIR}/$CLUSTER_ID/tks-cluster/cluster-api/*
echo "---
apiVersion: v1
kind: Namespace
metadata:
  name: $CLUSTER_ID
  labels:
    name: $CLUSTER_ID
    # It bring the secret 'dacapod-argocd-config' using kubed
    decapod-argocd-config: enabled
" >Namespace_$CLUSTER_ID.yaml
mv Namespace_$CLUSTER_ID.yaml "$(pwd)/${OUTPUT_DIR}/$CLUSTER_ID/tks-cluster/cluster-api/"

if [ "$MANIFESTS_REPO_URL" == "" ]; then
	log 1 "INFO" "MANIFESTS_REPO_URL is empty, so we stop here."
fi

#-----------------------------------------------
# push manifests files
#-----------------------------------------------
manifests_repo_url_scheme=${MANIFESTS_REPO_URL%%:*}
manifests_repo_url_rest=${MANIFESTS_REPO_URL#*\/\/}

git clone ${manifests_repo_url_scheme}://$(echo -n ${GIT_REPO_TOKEN})@${manifests_repo_url_rest} origin-manifests
log 0 "INFO" "git clone ${MANIFESTS_REPO_URL}"
cd origin-manifests
if [ -z "${MANIFESTS_GIT_REV}" ]; then
	MANIFESTS_GIT_REV="decapod-${commit_id}"
fi
check_branch=$(git ls-remote --heads origin ${MANIFESTS_GIT_REV})
if [[ -z ${check_branch} ]]; then
	git checkout -b ${MANIFESTS_GIT_REV}
	log 0 "INFO" "create and checkout new branch: ${MANIFESTS_GIT_REV}"
else
	git checkout ${MANIFESTS_GIT_REV}
	log 0 "INFO" "checkout exist branch: ${MANIFESTS_GIT_REV}"
fi

rm -rf ./*
cp -r ../${OUTPUT_DIR}/* ./

git config --global user.email "taco_support@sk.com"
git config --global user.name "SKTelecom TKS"
git add -A
git commit -m "decapod: ${commit_msg}"
git push origin ${MANIFESTS_GIT_REV}

if [ "${MANIFESTS_GIT_REV}" != "main" ] && [ "${GIT_REPO_TYPE}" == "gitea" ]; then
	curl -X POST -H "content-type: application/json" -H "Authorization: token ${GIT_REPO_TOKEN}" --data "{ \"base\": \"main\", \"body\": \"rendered from\n - decapod: ${commit_msg}\n\", \"head\": \"${MANIFESTS_GIT_REV}\", \"title\": \"rendered from decapod: ${commit_msg}\"}" ${manifests_repo_url_scheme}://${manifests_repo_url_rest%%/*}/api/v1/repos/${manifests_repo_url_rest##*/}/pulls
fi

cd ..
rm -rf origin-manifests ${OUTPUT_DIR}

log 0 "INFO" "pushed all manifests files"
