#!/usr/bin/env nextflow

/*
========================================================================================
   Variant calling Nextflow Workflow
========================================================================================
   Github   : https://github.com/scbirlab/nf-trainml
   Contact  : Eachan Johnson <user@crick.ac.uk>
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl=2

/*
========================================================================================
   Help text
========================================================================================
*/

def pipeline_name = """\
         S C B I R   P I P E L I N E
         ===========================
         """.stripIndent()

if ( params.help ) {
   println """${pipeline_name}
         Nextflow pipeline to ....

         Usage:
            nextflow run scbirlab/nf-trainml --sample_sheet <csv> --inputs <dir>
            nextflow run scbirlab/nf-trainml -c <config-file>

         Required parameters:
            sample_sheet      Path to a CSV with information about the samples 
                                 to be processed

         Optional parameters (with defaults):  
            inputs             Directory containing inputs. Default: "./inputs".

         The parameters can be provided either in the `nextflow.config` file or on the `nextflow run` command.
   
   """.stripIndent()
   exit 0
}

/*
========================================================================================
   Check parameters
========================================================================================
*/
if ( !params.sample_sheet ) {
   throw new Exception("!!! PARAMETER MISSING: Please provide a path to sample_sheet")
}

working_dir = params.outputs

log.info """${pipeline_name}
         inputs
            input dir.     : ${params.inputs}
            sample sheet   : ${params.sample_sheet}
         output            : ${params.outputs}
         """
         .stripIndent()

/*
========================================================================================
   MAIN Workflow
========================================================================================
*/

include { 
  CreateSharedCache;
} from './modules/cache.nf'
include { 
  split_data_remote as SplitDataRemote;
  split_data_remote as SplitDataLocal;
  SplitDataFinal;
} from './modules/data-prep.nf'
include { 
  Hyperprep; 
} from './modules/hyperprep.nf'
include { 
  MakeReadme; 
} from './modules/readme.nf'
include { 
  train_initial_model; 
  TrainFinal;
} from './modules/training.nf'
include { 
  stack_tables; 
} from './modules/utils.nf'
include { 
  best_model; 
} from './modules/filter.nf'


workflow {
    
  init(
    Channel.fromPath( 
      "${params.sample_sheet}",
      checkIfExists: true,
    ),
    Channel.value( [ 
      train: params.train, 
      val: params.validation, 
      test: params.test,
    ] ),
    Channel.value( params.k ),
    Channel.value( params.n_partitions ),
    Channel.of( params.split_replicates ),
    Channel.value( params.epochs ),
  )

}

workflow init {

  take:
  sample_sheet
  split_fracs
  knn
  n_partitions
  split_replicates
  epochs

  main:
  sample_sheet
    .splitCsv( header: true )
    .map { v -> [ 
      v.id, 
      v.dataset, 
      v.structure, 
      v.split, 
      v.target,
      file( 
        "${params.inputs}/${v.hyperparams}", 
        checkIfExists: true,
      ),
     ] }
    .unique()
    .set { csv_rows }  // id, dataset, structure, split method, target

  csv_rows
    .map { v -> v[0..-3] }  // id, dataset, structure, split method
    .tap { unbranched_data_ch }
    .combine( split_replicates )
    .branch { v ->
      remote: (v[1].startsWith("hf://") || v[1].startsWith("https://"))
      local: true
    }
    .set { data_ch }  // id, dataset, structure, split method, split_rep

  csv_rows
    .map { v -> [ v[0], v[5] ] }
    .unique()
    .set { hyperparam_ch }

  CreateSharedCache(
    csv_rows.map { v -> v[0] }.unique()
  )
    .set { cache_ch }

  sample_sheet
    .splitCsv( header: true )
    .filter { v -> v.containsKey("readme") }
    .map { v -> [ 
      v.id, 
      file( 
        "${params.inputs}/${v.readme}", 
        checkIfExists: true,
      ),
     ] }
    .unique()
    .set { id2template_ch }

  Hyperprep( hyperparam_ch.combine( cache_ch, by: 0 ) )

  Hyperprep.out.grid
    .combine(
      Hyperprep.out.n_configs,
      by: 0,
    )
    .map { v -> [
      v[0],
      v[1],
      0..(v[2].toInteger() - 1),
    ] }
    .transpose()
    .unique()
    .map { v -> [
      v[0],
      [
        config: v[1],
        config_i: v[2],
      ]
    ] }
    .set { configs_ch }

  // Workflow
  SplitDataLocal( 
    data_ch.local
      .map { v -> [ 
        v[0], 
        file( 
          v[1], 
          checkIfExists: true,
        ) 
      ] + v[2..-1] }
      .combine ( cache_ch, by: 0 ),
    split_fracs,
    knn,
    n_partitions,
    Channel.value( params.skip_plot ),
  )  // id, split_method, [pool, val, test]
  SplitDataRemote( 
    data_ch.remote.combine ( cache_ch, by: 0 ),
    split_fracs,
    knn,
    n_partitions,
    Channel.value( params.skip_plot ),
  )  // test_val -> id, split_method, [test, val] // pool -> id, split_method, pool
  SplitDataFinal(
    unbranched_data_ch.combine ( cache_ch, by: 0 ),
    split_fracs,
    knn,
    n_partitions,
    Channel.value( params.skip_plot ),
  )

  SplitDataLocal.out.pool
    .concat( SplitDataRemote.out.pool )
    .transpose()
    .map { v -> [ 
      v[0], v[1], 
      v[2].parent.name.split("_")[-1], 
      v[2],
    ] }
    .groupTuple( by: [0, 1, 2] )   // [id, split_method, fold, [all partition files]]
    .set { pool_by_fold }

  SplitDataLocal.out.test_val
    .concat( SplitDataRemote.out.test_val )
    .transpose()
    .map { v -> [ 
      v[0], v[1], 
      v[2].parent.name.split("_")[-1], 
      v[2],
    ] }
    .groupTuple( by: [0, 1, 2] )   // [id, split_method, fold, [val, test]]
    .set { testval_by_fold }

  pool_by_fold
    .combine( 
      testval_by_fold, 
      by: [0, 1, 2],
     )
    .combine( configs_ch, by: 0 ) // [id, split_method, fold, [val, test], [config, config_i]]
    .map { v -> [
        [
          id: v[0], 
          split_rep: v[2], 
          split_method: v[1],
        ],
        [
          pool: v[3],
          validation: v[4].find { it.name.contains("validation") },
          test: v[4].find { it.name.contains("test") },
        ],
        v[5],
    ]} // [id, split_rep], [pool, val, test], [config, config_i]
    .set { split_data_out }
  
  csv_rows
    .map { v -> tuple( 
      v[0], 
      [
        structure: v[2], 
        target: v[4],
      ],
    ) }
    .set { id2xy_ch }
  
  split_data_out
    .map { v -> [ v[0].id ] + v }
    .combine(
      id2xy_ch,
      by: 0,
    )  // id, [id, split_rep], [pool, val, test], [config, config_i], [structure, target]
    .map { v -> [ v[1], v[-1] ] + v[2..-2]  }  // [id, split_rep], [structure, target], [pool, val, test], [config, config_i]
    .set { init_data }

  train_initial_model(
    init_data
      // .take(3)
      // .view()
      .map { v -> [ 
        v[0], 
        v[2].pool, 
        v[2].validation, 
        v[2].test,
        v[1],
        v[3].config,
        v[3].config_i,
      ] }
      .unique().combine ( cache_ch, by: 0 ),
    epochs,
  )  // [id, split_rep, init_rep], init_model

  stack_tables(
    train_initial_model.out.metrics
      .map { v -> [v[0].id, v[2]] }
      .groupTuple( by: 0 ), //.map { v -> [v[0], v[2]] },
    Channel.value("metrics"),
    Channel.value("all-training.tsv"),
  ) 
  | best_model

  best_model.out.best
    .map { v -> v[1] }
    .splitCsv( header: true )
    .map { v -> [ v.id, new BigDecimal(v.config_i).round(0).toInteger() ] }
    .set { best_config_ch }

  SplitDataFinal.out.main 
    .combine( configs_ch, by: 0 )  // id, pool, val, test, [config, config_i]
    .map { v -> [ 
      v[0], 
      v[4].config_i.toInteger(), 
      [train: v[1], validation: v[2], test: v[3]], 
      v[4],
     ] }  // id, config_i, [pool, val, test], [config, config_i]
    .combine( best_config_ch, by: [0, 1] ) // id, config_i, [pool, val, test], [config, config_i]
    .combine( id2xy_ch, by: 0 )  // id, config_i, [pool, val, test], [config, config_i], [structure, target]
    .map { v -> [ v[0], v[4], v[2], v[3] ] }
    .set { retrain_input_ch }  // id, [structure, target], [pool, val, test], [config, config_i]

  TrainFinal(
    retrain_input_ch
      // .take(3)
      .map { v -> [ 
        v[0], 
        v[2].train, 
        v[2].validation, 
        v[2].test,
        v[1],
        v[3].config,
        v[3].config_i,
      ] }
      .unique().combine ( cache_ch, by: 0 ),
    epochs,
  )  // [id, split_rep, init_rep], init_model

  MakeReadme(
    id2xy_ch
      .combine( TrainFinal.out.checkpoint, by: 0 )
      .combine( id2template_ch, by: 0 )
  )

  init_data
    .combine( 
      TrainFinal.out.checkpoint, 
      by: [0,1],
    )  // [id, split_rep, init_rep], [structure, target], [pool, val, test], init_model
    .set { initial_model }

  emit:
  initial_model

}

/*
========================================================================================
   Workflow Event Handler
========================================================================================
*/

workflow.onComplete {

   println ( workflow.success ? """
      Pipeline execution summary
      ---------------------------
      Completed at: ${workflow.complete}
      Duration    : ${workflow.duration}
      Success     : ${workflow.success}
      workDir     : ${workflow.workDir}
      exit status : ${workflow.exitStatus}
      """ : """
      Failed: ${workflow.errorReport}
      exit status : ${workflow.exitStatus}
      """
   )
}

/*
========================================================================================
   THE END
========================================================================================
*/