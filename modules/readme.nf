process MakeReadme {
    tag "${id}"
    label 'med_mem'
    time '1h'

    publishDir( 
        "${params.outputs}/${id}/best-model/repo", 
        mode: 'copy',
        saveAs: { "${it}" },
    )


    input:
    tuple val( id ), val( xy ), path( model ), path( template, stageAs: 'README_template.md' )

    output:
    tuple val( id ), path( 'repo' )

    script:
    """
    set -euox pipefail

    count_rows () (
        tail -n+2 | cut -f1 -d, | grep -v '^ ' | wc -l
    )

    ntrain=\$(count_rows < "${model}"/predictions_training.csv)
    nval=\$(count_rows < "${model}"/predictions_validation.csv)
    ntest=\$(count_rows < "${model}"/predictions_test.csv)
    nrows=\$((\$ntrain + \$nval + \$ntest))

    mkdir -p repo/eval repo/"${model}"
    cp -r "${model}"/* repo/"${model}"

    for csv_file in repo/"${model}"/predictions_*.csv
    do
        gzip --best -f "\$csv_file"
        mv "\$csv_file".gz repo/eval/\$(basename "\$csv_file".gz)
    done

    sed '
        s/__NROWS__/'"\$nrows"'/g;
        s/__NTRAIN__/'"\$ntrain"'/g;
        s/__NVAL__/'"\$nval"'/g;
        s/__NTEST__/'"\$ntest"'/g;
        s/__INPUTS__/'"${xy.structure}"'/g;
        s/__OUTPUTS__/'"${xy.target}"'/g;
        s/__TODAY__/'"\$(date)"'/g;
    ' README_template.md \
    | sed '/__CONFIG__/r 'repo/"${model}"/modelbox-init-config.json \
    | sed '/__TRAIN_EVAL__/r 'repo/"${model}"/eval-metrics_training.json \
    | sed '/__VAL_EVAL__/r 'repo/"${model}"/eval-metrics_validation.json \
    | sed '/__TEST_EVAL__/r 'repo/"${model}"/eval-metrics_test.json \
    | sed 's/__CONFIG__//g;s/__TRAIN_EVAL__//g;s/__VAL_EVAL__//g;s/__TEST_EVAL__//g;' \
    > repo/README.md

    echo scbirlab/"${id}" > repo/repo-name.txt

    """
    
}