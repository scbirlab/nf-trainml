process split_data_remote {

    tag "${id}.${split_rep}:${split_method}"
    label "big_time"

    publishDir(
        "${params.outputs}/${id}/splits", 
        mode: 'copy',
        saveAs: { "method_${split_method}/${it}" },
        pattern: "fold_*/data_{test,validation}*.parquet",
    )

    publishDir(
        "${params.outputs}/${id}/splits", 
        mode: 'copy',
        saveAs: { "method_${split_method}/${it.split('/')[0]}/pool/${it.split('/')[1]}" },
        pattern: "fold_*/data_pool-partition_id_*.parquet",
    )

    publishDir(
        "${params.outputs}/${id}/splits", 
        mode: 'copy',
        saveAs: { "method_${split_method}/${it}" },
        pattern: "split-plot*.{png,csv}",
    )

    // id, dataset, structure, split method, split_rep
    input:
    tuple val( id ), val( dataset ), val( structure ), val( split_method ), val( split_rep ), path( cache )
    val split_p
    val knn
    val n_partitions
    val skip_plot

    // id, split_rep, [pool, val, test]
    output:
    tuple val( id ), val( split_method ), path( "fold_*/data_{test,validation}*.parquet", arity: "2..*" ), emit: test_val
    tuple val( id ), val( split_method ), path( "fold_*/data_pool-partition_id_*.parquet", arity: "1..*" ), emit: pool
    tuple val( id ), val( split_method ), path( "split-plot*.{png,csv}" ), emit: plot, optional: true

    script:
    """
    set -eoux pipefail

    XDG_CACHE_HOME="${cache}" ELUENT_CACHE="${cache}" eluent split \
        "${dataset}" \
        --train "${split_p.train}" \
        --validation "${split_p.val}" \
        --kfold ${split_rep} \
        --test "${split_p.test}" \
        --structure "${structure}" \
        --type "${split_method}" \
        -k ${knn} \
        --seed "${split_rep}" \
        --cache "${cache}" \
        --output data.parquet \
        --plot-seed 0 \
        ${skip_plot ? "" : "--plot split-plot.png"}

    for f in fold_*/data_train.parquet
    do
        duckdb -c "
            PRAGMA threads=${task.cpus};
            COPY (
                WITH indexed AS (
                    SELECT 
                        row_number() OVER () AS rowid,
                        *
                    FROM read_parquet('\${f}')
                )
                SELECT *, (rowid % ${n_partitions})::INTEGER AS partition_id
                FROM indexed
            ) TO 'data_train-partitioned/' 
            (
                FORMAT Parquet,
                PARTITION_BY (partition_id),
                OVERWRITE_OR_IGNORE
            );
        "
        rm "\$f"
        fold_dir=\$(dirname "\$f")   # fold_0
        for g in data_train-partitioned/partition_id=*/
        do
            outname=\$(basename "\${g%/}")
            outname=data_pool-\${outname//=/_}.parquet
            duckdb -c "
                PRAGMA threads=${task.cpus};
                COPY (
                    SELECT *
                    FROM read_parquet('\${g}/data_*.parquet')
                ) TO '\${fold_dir}/\${outname}' 
                (FORMAT Parquet);
            "
        rm -rf "\${g}"
        done
    done

    """

}

process SplitDataFinal {

    tag "${id}:${split_method}${split_p}"
    label "big_time"

    publishDir(
        "${params.outputs}/${id}/best-model/data",
        mode: 'copy',
        saveAs: { "method_${split_method}/${it.split('/')[1]}" },
        pattern: "fold_*/data_{test,validation}*.parquet",
    )

    publishDir(
        "${params.outputs}/${id}/best-model/data", 
        mode: 'copy',
        saveAs: { "method_${split_method}/train/${it.split('/')[1]}" },
        pattern: "fold_*/data_pool-partition_id_*.parquet",
    )

    publishDir(
        "${params.outputs}/${id}/best-model/data", 
        mode: 'copy',
        saveAs: { "method_${split_method}/${it}" },
        pattern: "split-plot*.{png,csv}",
    )

    // id, dataset, structure, split method, split_rep
    input:
    tuple val( id ), val( dataset ), val( structure ), val( split_method ), path( cache )
    val split_p
    val knn
    val n_partitions
    val skip_plot

    // id, split_rep, [pool, val, test]
    output:
    tuple val( id ), path( "fold_*/data_pool-partition_id_*.parquet", arity: "1..*" ), path( "fold_*/data_validation*.parquet", arity: "1" ), path( "fold_*/data_test*.parquet", arity: "1" ), emit: main
    tuple val( id ), path( "split-plot*.{png,csv}" ), emit: plot, optional: true

    script:
    """
    set -eoux pipefail

    XDG_CACHE_HOME="${cache}" ELUENT_CACHE="${cache}" eluent split \
        "${dataset}" \
        --train "${split_p.train}" \
        --validation "${split_p.val}" \
        --test "${split_p.test}" \
        --structure "${structure}" \
        --type "${split_method}" \
        -k ${knn} \
        --seed 42 \
        --cache "${cache}" \
        --output data.parquet \
        --plot-seed 0 \
        ${skip_plot ? "" : "--plot split-plot.png"}

    for f in fold_*/data_train.parquet
    do
        duckdb -c "
            PRAGMA threads=${task.cpus};
            COPY (
                WITH indexed AS (
                    SELECT 
                        row_number() OVER () AS rowid,
                        *
                    FROM read_parquet('\${f}')
                )
                SELECT *, (rowid % ${n_partitions})::INTEGER AS partition_id
                FROM indexed
            ) TO 'data_train-partitioned/' 
            (
                FORMAT Parquet,
                PARTITION_BY (partition_id),
                OVERWRITE_OR_IGNORE
            );
        "
        rm "\$f"
        fold_dir=\$(dirname "\$f")   # fold_0
        for g in data_train-partitioned/partition_id=*/
        do
            outname=\$(basename "\${g%/}")
            outname=data_pool-\${outname//=/_}.parquet
            duckdb -c "
                PRAGMA threads=${task.cpus};
                COPY (
                    SELECT *
                    FROM read_parquet('\${g}/data_*.parquet')
                ) TO '\${fold_dir}/\${outname}' 
                (FORMAT Parquet);
            "
        rm -rf "\${g}"
        done
    done

    """

}
