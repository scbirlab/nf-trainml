process Hyperprep {
    tag "${id}"

    publishDir(
        "${params.outputs}/hyperparams",
        saveAs: { "${id}.${it}" },
    )

    input:
    tuple val( id ), path( json ), path( cache )

    output:
    tuple val( id ), path( "hyperopt/grid.json" ), emit: grid
    tuple val( id ), env( "N_CONFIGS" ), emit: n_configs
    tuple val( id ), path( "grid.log" ), emit: log

    script:
    """
    set -euox pipefail
    
    XDG_CACHE_HOME="${cache}" DUVIDNN_CACHE="${cache}" \
    duvidnn hyperprep \
        "${json}" \
        -o hyperopt/grid.json \
    2> grid.log

    N_CONFIGS=\$(
        grep -E '^\\[INFO\\] There are [0-9]+ configurations to test.\$' grid.log \
        | head -n1 \
        | cut -f4 -d' '
    )

    """
}
