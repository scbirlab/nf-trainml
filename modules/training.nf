// id, split_rep, init_rep, [pool, val, test], labelled_idx, structure, target
process train_initial_model {

    tag "${id}:${xy.target}:${config_i}"
    // label "gpu_single"
    label "train"

    // errorStrategy 'retry'  // sometimes GPU fails
    errorStrategy { sleep(Math.pow(2, task.attempt) * 200 as long); return 'retry' }
    maxRetries 3
    // beforeScript 'sleep \$((RANDOM % 60))'

    publishDir(
        "${params.outputs}", 
        mode: 'copy', 
        saveAs: { "${id.id}/runs/config_${config_i}/fold_${id.split_rep}/${it}" },
        pattern: "*.dv",
    )

    // [id, split_rep, init_rep], [structure, target], [pool, val, test]
    input:
    tuple val( id ), path( pool, stageAs: 'pool/*' ), path( validation ), path( test ), val( xy ), path( model_config ), val( config_i )
    val epochs

    output:
    tuple val( id ), path( "*.dv" ), emit: checkpoint
    tuple val( id ), path( "*.dv/*.{csv,png,json}" ), emit: eval
    tuple val( id ), val( config_i ), path( "*.dv/metrics.csv" ), emit: metrics
    
    
    script:
    """
    duckdb -c "
    PRAGMA threads=${task.cpus};
    COPY (
        SELECT * 
        FROM read_parquet('pool/data_pool-*.parquet')
    ) TO 'train.csv' (FORMAT CSV);
    "

    XDG_CACHE_HOME=cache XDG_HOME=cache DUVIDNN_CACHE=cache duvidnn train \
        -1 "train.csv" \
        -2 "${validation}" \
        --test "${test}" \
        -S "${xy.structure}" \
        -y "${xy.target}" \
        -c "${model_config}" \
        -i "${config_i}" \
        --early-stopping 10 \
        --output "model.dv" \
        --cache cache \
        --epochs "${epochs}"

    rm -rf cache

    """

}


process TrainFinal {

    tag "${id}:${xy.target}:${config_i}"
    // label "gpu_single"
    label "train"

    // errorStrategy 'retry'  // sometimes GPU fails
    // maxRetries 3

    publishDir(
        "${params.outputs}/best-model", 
        mode: 'copy', 
        saveAs: { "${id}.${it}" },
        pattern: "*.dv",
    )

    // [id, split_rep, init_rep], [structure, target], [pool, val, test]
    input:
    tuple val( id ), path( pool, stageAs: 'train/*' ), path( validation ), path( test ), val( xy ), path( model_config ), val( config_i )
    val epochs

    output:
    tuple val( id ), path( "*.dv" ), emit: checkpoint
    tuple val( id ), path( "*.dv/*.{csv,png,json}" ), emit: eval
    tuple val( id ), val( config_i ), path( "*.dv/metrics.csv" ), emit: metrics

    script:
    """
    duckdb -c "
    PRAGMA threads=${task.cpus};
    COPY (
        SELECT * 
        FROM read_parquet('train/*.parquet')
    ) TO 'train.csv' (FORMAT CSV);
    "

    XDG_CACHE_HOME=cache XDG_HOME=cache DUVIDNN_CACHE=cache \
    duvidnn train \
        -1 "train.csv" \
        -2 "${validation}" \
        --test "${test}" \
        -S "${xy.structure}" \
        -y "${xy.target}" \
        -c "${model_config}" \
        -i "${config_i}" \
        --early-stopping 10 \
        --output "model.dv" \
        --cache cache \
        --epochs "${epochs}"

    rm -rf cache

    """

}


process train {

    tag "${id}:${xy.target}"
    // label "gpu_single"
    label "train"

    errorStrategy 'retry'  // sometimes GPU fails
    maxRetries 1

    publishDir(
        "${params.outputs}", 
        mode: 'copy', 
        pattern: "*.dv",
    )

    // [id, split_rep, init_rep], [structure, target], acq, [pool, val, test], idx
    input:
    tuple val( id ), path( idx ), path( pool ), path( validation ), path( test )
    val xy
    path model_config
    val epochs

    output:
    tuple val( id ), path( "*.dv" ), emit: checkpoint
    tuple val( id ), path( "*.dv/*.{csv,png,json}" ), emit: eval

    script:
    """
    duckdb -c "
    PRAGMA threads=${task.cpus};
        COPY (
            SELECT * 
            FROM read_parquet('data_pool-*.parquet') 
            INNER JOIN read_csv('${idx}', header=false, names=['rowid']) USING (rowid)
        ) TO 'train.csv' (FORMAT CSV);
    "

    if [ ! -e "train.csv" ]
    then 
        echo "ERROR: train.csv does not exist!"
        exit 1
    fi

    XDG_HOME=cache DUVIDNN_CACHE=cache duvidnn train \
        -1 "train.csv" \
        -2 "${validation}" \
        --test ${test} \
        -x clogp \
        -S "${xy.structure}" \
        -y "${xy.target}" \
        -c "${model_config}" \
        --early-stopping 10 \
        --output "model.dv" \
        --cache cache \
        --epochs "${epochs}"

    rm -rf cache

    """

}