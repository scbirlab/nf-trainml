process CreateSharedCache {

    tag "${id}"
    time "1m"

    publishDir(
        "${params.outputs}/${id}", 
        mode: 'link',
        saveAs: { "${it}" },
    )

    input:
    val id

    output:
    tuple val( id ), path( "cache" )

    script:
    """
    mkdir cache
    echo "id=${id}" > cache/_id.txt

    """
}