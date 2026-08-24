process best_model {
    tag "${id}"
    label 'med_mem'
    time '1h'
    stageInMode 'link'

    publishDir( 
        "${params.outputs}/summary", 
        mode: 'copy',
        saveAs: { "${id}.${it}" },
    )


    input:
    tuple val( id ), path( table )

    output:
    tuple val( id ), path( 'summary.csv' ), emit: summary
    tuple val( id ), path( 'best.csv' ), emit: best

    script:
    """
    #!/usr/bin/env python

    import sys
    
    import pandas as pd
    
    df = pd.read_csv(
        "${table}",
        low_memory=False,
    ).assign(id="${id}")
    print(df)

    metric_cols = [
        "pearson_r", "rmse", "spearman_rho"
    ]
    filter_metric = "pearson_r"

    df_summary = (
        df
        .groupby([
            col for col in df 
            if col not in metric_cols
        ], dropna=False)
    )
    df_summary = (
        df_summary
        .agg(["mean", "median", "std", "var"])
    )
    print(df_summary)
    df_summary.columns = [f"{col[0]}_{col[1]}" for col in df_summary.columns]
    print(df_summary)
    df_summary = (
        df_summary
        .assign(**{
            f"{col}_z": lambda x, c=col: x[f"{c}_mean"]  / x[f"{c}_std"]
            for col in metric_cols
        })
    )
    print(df_summary)
    df_summary.to_csv("summary.csv")

    df_best = (
        df_summary
        .query("split == 'test'")
        .sort_values(f"{filter_metric}_z")
        .groupby("data")
        .tail(1)
    )
    df_best.to_csv("best.csv")
    
    """
}