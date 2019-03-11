#!/bin/bash

set -o pipefail

umask 077

tokenfile="/var/run/secrets/kubernetes.io/serviceaccount/token"
namespace="openshift-machine-api"

# Support for
# as in kubectl $yamldump -o yaml
# a mature expression might look like:
# kubectl --token=$(cat $tokenfile) --insecure-skip-tls-verify=true -n $namespace $yamldump -o yaml > $tmpfile
# cat $tmpfile | yq -r $clusteridyqexpression
yamldump="get machines"
clusteridyqexpression="items[0].metadata.labels[sigs.k8s.io/cluster-api-cluster]"
regionyqexpression="items[0].spec.providerSpec.value.placement.region"

accesskeyinfile="/secrets/aws_access_key_id"
secretkeyinfile="/secrets/aws_secret_access_key"
clusteridfileout="/config/cluster/id.txt"
regionfile="/secrets/aws/config.ini"
credsfile="/secrets/aws/credentials.ini"

usage() {
  echo "Usage: $0 <options>"
  echo
  echo -e "\t-n <namespace> Namespace to run the yaml dump expression is (def: ${namespace})"
  echo
  echo -e "\t-y <yaml dump expression> kubectl expression to dump the object (def: ${yamldump})"
  echo -e "\tex: kubectl -o yaml ${yamldump}"
  echo -e "\tOmit namespace,     ^ Starting at carot"
  echo
  echo -e "\t-q <cluster id yq expression> yq expression to access cluster ID"
  echo -e "\t  (def: ${clusteridyqexpression})"
  echo -e "\t-Q <region yq expression> yq expression to access AWS region"
  echo -e "\t  (def: ${regionyqexpression})"
  echo
  echo -e "\t-c <file> Write Cluster ID to <file> (def: ${regionfile})"
  echo
  echo -e "\t-r <file> Write name of AWS region to <file> in AWS ini file format (def: ${regionfile})"
  echo -e "\t-a <file> Path to input file for AWS access key ID (def: ${accesskeyinfile})"
  echo -e "\t-A <file> Path to input file for AWS secret access key (def: ${secretkeyinfile})"
  echo -e "\t-o <file> Write AWS credentials in AWS ini file format to <file>. Requires -a and -A and -r. (def: ${credsfile})"
  echo
  echo -e "\t-t <tokenfile> Location to serviceAccount tokenfile (def: ${tokenfile})"
}

err() { 
  echo "$@" 1>&2 
}

# Ensure the directory to the file at $target exists
ensure_directory() {
  target=$1 base=
  base=$(dirname $target)
  if [[ $? -ne 0 ]]; then
    err "Couldn't figure out the base directory name of $target"
    exit 1
  fi
  mkdir -p $base
  if [[ $? -ne 0 ]]; then
    err "Couldn't create the directory tree to $base"
    exit 1
  fi
}

get_raw_yamlobj() {
  local tokenfile=$1 namespace=$2 getcmd=$3 destination=$4 
  kubectl --token=$(cat $tokenfile) --insecure-skip-tls-verify=true -n $namespace  get $getcmd -o yaml 2> /dev/null 1> $destination 
  if [[ $? -ne 0 ]]; then
    err "Couldn't get the raw configmap."
    exit 1
  fi
  return 0
}

get_cluster_awsregion() {
  local raw_yaml=$1 regionquery=$2 region=
  region="$(yq r $raw_yaml ${regionquery})"
  if [[ $? -ne 0 ]]; then
    err "Couldn't read the cluster's AWS region."
    exit 1
  fi
  echo $region
}

get_cluster_id() {
  local raw_yaml=$1 regionquery=$2 clusterid=
  clusterid="$(yq r $raw_yaml ${regionquery})"
  if [[ $? -ne 0 ]]; then
    err "Couldn't read the cluster's ID."
    exit 1
  fi
  echo $clusterid
}

write_clusterid() {
  local dest=$1 clusterid=$2
  cat >$dest <<EOF
CLUSTERID="${clusterid}"
EOF
  if [[ $? -ne 0 ]]; then
    err "Couldn't write cluster ID to $dest"
    exit 1
  fi
  return 0
}

read_access_key() {
  local src=$1 access_key=
  access_key=$(cat $src)
  if [[ $? -ne 0 ]]; then
    err "Couldn't read the AWS access key from $src"
    exit 1
  fi
  echo $access_key
}

read_secret_key() {
  local src=$1 secret_key=
  secret_key=$(cat $src)
  if [[ $? -ne 0 ]]; then
    err "Couldn't read the AWS secret key from $src"
    exit 1
  fi
  echo $secret_key
}

# Read in the "raw" secret keypair from $1 and then write an ini-file style out to $2
write_aws_credentials_file() {
  local dest=$1 access_key=$2 secret_key=$3
  cat >$dest <<EOF
[default]
aws_access_key_id = ${access_key}
aws_secret_access_key = ${secret_key}
EOF
  if [[ $? -ne 0 ]]; then
    err "Couldn't write AWS credentials file to $dest"
    exit 1
  fi
  return 0 
}

# Write an ini-file style config for AWS region out to $2
write_aws_config_file() {
  local dest=$1 region=$2
  cat >$dest <<EOF
[default]
region = ${region}
EOF
  if [[ $? -ne 0 ]]; then
    err "Couldn't write AWS config file to $dest"
    exit 1
  fi
  return 0
}

#####
do_clusterid=
do_region=
do_accesskey=
do_secretkey=

# temp file
raw_configmap=

while getopts ":hn:c:r:a:A:o:t:q:Q:" opt; do
  case $opt in
    h)
      usage
      exit 0
    ;;
    q)
      clusteridyqexpression=$OPTARG
    ;;
    Q)
      regionyqexpression=$OPTARG
    ;;
    t)
      tokenfile=$OPTARG
    ;;
    y)
      yamldump=$OPTARG
    ;;
    n)
      namespace=$OPTARG
    ;;
    c)
      clusteridfileout=$OPTARG
      do_clusterid=1
    ;;
    r)
      regionfile=$OPTARG
      do_region=1
    ;;
    a)
      accesskeyinfile=$OPTARG
      do_accesskey=1
    ;;
    A)
      secretkeyinfile=$OPTARG
      do_secretkey=1
    ;;
    o)
      credsfile=$OPTARG
      do_secretkey=1
      do_accesskey=1
    ;;
    \?)
      err "Invalid option"
      echo
      usage
      exit 1
    ;;
  esac
done

# FIXME: Validate input options?

if [[ -z $do_region && -z $do_accesskey && -z $do_secretkey && -z $do_clusterid ]]; then
  echo "Nothing to do"
  exit 0
fi

if [[ -n $do_region || -n $do_accesskey || -n $do_secretkey ]]; then
  # do one? do them all
  do_region=1
  do_accesskey=1
  do_secretkey=1
fi

if [[ -n $do_region || -n $do_clusterid ]]; then
  raw_configmap=$(mktemp)
  if [[ $? -ne 0 ]]; then
    err "Couldn't allocate a temporary YAML file"
    exit 1
  fi
  get_raw_yamlobj $tokenfile $namespace $yamldump $raw_configmap
fi

if [[ -n $do_clusterid ]]; then
  clustername=$(get_cluster_id $raw_configmap $clusteridyqexpression)
  ensure_directory $clusteridfileout
  write_clusterid $clusteridfileout $clustername
fi

if [[ -n $do_region ]]; then
  regionname=$(get_cluster_awsregion $raw_configmap $regionyqexpression)
  ensure_directory $regionfile
  write_aws_config_file $regionfile $regionname
fi

if [[ -n $do_accesskey || -n $do_secretkey ]]; then
  access_key=$(read_access_key $accesskeyinfile)
  secret_key=$(read_secret_key $secretkeyinfile)
  ensure_directory $credsfile
  write_aws_credentials_file $credsfile $access_key $secret_key
fi
