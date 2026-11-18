 #!/usr/bin/env bash

set -xeuo pipefail

script_dir="$(dirname $0)"
DOCKER=${1:-no}

if [ "$DOCKER" == "gh" ]
then
    export NXF_CONTAINER_ENGINE=docker
    docker_flag='-profile gh'
elif [ "$DOCKER" == "crick" ]
then
    module load Nextflow
    export NXF_CONTAINER_ENGINE=conda
    docker_flag='-profile standard'
else
    export NXF_CONTAINER_ENGINE=conda
    docker_flag='-profile local'
fi

nextflow run "$script_dir"/.. \
    -resume $docker_flag \
    --sample_sheet "$script_dir"/sample-sheet.csv \
    --inputs "$script_dir"/inputs \
    --outputs "$script_dir"/outputs \
    --cache "$script_dir"/outputs/cache \
    -c "$script_dir"/nextflow.config \
    -with-dag "$script_dir"/dag.html \
    -work-dir "$script_dir"/work
