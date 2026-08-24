# scbirlab/nf-trainml

![GitHub Workflow Status (with branch)](https://img.shields.io/github/actions/workflow/status/scbirlab/nf-trainml/nf-test.yml)
[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A524.10.0-23aa62.svg)](https://www.nextflow.io/)
[![run with conda](https://img.shields.io/badge/run%20with-conda-3EB049?labelColor=000000&logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)

**scbirlab/nf-trainml** trains chemistry regression models with hyperparameter
search and ships a ready-to-publish model, in one command.

Point it at a [HuggingFace dataset](https://huggingface.co/datasets) (or a URL) of
molecules and a numeric label. For each dataset it:

1. expands a hyperparameter **grid** into concrete model configs;
2. makes a **chemistry-aware split** (Murcko scaffold, FAISS *k*-NN, or random),
   repeated over *k* folds;
3. **trains an ensemble** for every config × fold using
   [DuvidNN](https://github.com/scbirlab/duvidnn), with pluggable featurizers
   (fingerprints, 2D/3D descriptors, Chemprop message-passing, or LLM embeddings);
4. **selects the best config** by Pearson *r* on held-out test data;
5. **refits** that config on a fresh full split; and
6. writes a **HuggingFace-style model card** and a push-ready model repo.

The trained checkpoints are [DuvidNN](https://github.com/scbirlab/duvidnn)
"modelboxes" (`.dv`), which embed their training data so downstream uncertainty
metrics can be computed at prediction time.

**Table of contents**

- [Quick start](#quick-start)
- [Requirements](#requirements)
- [Common usage](#common-usage)
  - [Sample sheet](#sample-sheet)
  - [Hyperparameter grids](#hyperparameter-grids)
  - [Split methods](#split-methods)
  - [Featurizers](#featurizers)
  - [Model cards](#model-cards)
  - [Pipeline parameters](#pipeline-parameters)
- [Processing steps](#processing-steps)
- [Outputs](#outputs)
- [For developers and contributors](#for-developers-and-contributors)
- [Issues, problems, suggestions](#issues-problems-suggestions)
- [Further help](#further-help)

## Quick start

If Nextflow and one of Conda/Docker/Singularity are installed, you can train a
model from a public dataset in three small files.

**1. A tiny hyperparameter grid** — `inputs/hyperparams.json`. Every value is a
list; the pipeline trains one model per combination. This one is two configs
(1- vs 5-layer):

```json
{
    "class_name": ["fingerprint"],
    "use_fp": [true],
    "use_2d": [true],
    "n_units": [16],
    "n_hidden": [1, 5],
    "learning_rate": [1e-5],
    "dropout": [0.0],
    "ensemble_size": [3]
}
```

**2. A sample sheet** — `sample-sheet.csv`. One row = one model:

```csv
id,dataset,structure,split,target,hyperparams
my-first-model,hf://scbirlab/stokes-2020-ai~eco-full:train,smiles,scaffold,normalized_inhibition,hyperparams.json
```

**3. Run it:**

```bash
nextflow run scbirlab/nf-trainml \
    --sample_sheet sample-sheet.csv \
    --inputs inputs \
    --outputs outputs \
    -profile local
```

When it finishes, the best model and its card are under
`outputs/best-model/` and `outputs/my-first-model/best-model/repo/`.

To always fetch the latest pipeline version, add `-latest`; to pin a release,
add `-r v0.0.1`. For help, run `nextflow run scbirlab/nf-trainml --help`.

> The first run installs the software dependencies (see
> [Requirements](#requirements)); this can take several minutes.

## Requirements

You need **Nextflow** (`>=24.10.0, <26`) and **one** of Conda/Mamba, Docker, or
Singularity.

At the Crick or on a cluster that already has them:

```bash
module load Nextflow Singularity
```

First time with Nextflow, and you have Conda? Install it, and point `NXF_HOME`
somewhere persistent:

```bash
conda install -c bioconda nextflow
mkdir -p ~/.nextflow
echo "export NXF_HOME=~/.nextflow" >> ~/.bash_profile
source ~/.bash_profile
```

The pipeline runs in a prebuilt container
(`ghcr.io/scbirlab/nf-trainml:latest`) or from the bundled Conda environment
(`environment.yml`). Either way the key dependencies are
[`duvidnn`](https://github.com/scbirlab/duvidnn) (training, hyperparameter
expansion), [`eluent`](https://github.com/scbirlab/eluent) (chemistry-aware
splitting), and `duckdb`.

**GPU** is optional but recommended for larger grids: the training processes
carry a `train` label you can map to GPU nodes in your own profile.

## Common usage

Provide parameters on the command line (as in the quick start) or in a
`nextflow.config` in your run directory:

```nextflow
params {
    sample_sheet = "/path/to/sample-sheet.csv"
    inputs       = "/path/to/inputs"
    outputs      = "/path/to/outputs"
    split_replicates = 5   // k-folds for model selection
    epochs           = 50
}
```

### Sample sheet

A CSV with one row per model. Required columns:

| Column        | Meaning                                                                                       |
| ------------- | --------------------------------------------------------------------------------------------- |
| `id`          | Unique name for the model. Also becomes the output model-repo name (`scbirlab/<id>`).         |
| `dataset`     | Where the data lives. `hf://org/name~subset:split`, an `https://` URL, or a local file path.  |
| `structure`   | Name of the input column holding the molecular structure (e.g. `smiles`).                     |
| `split`       | Split method: `scaffold`, `faiss`, or `random` (see [below](#split-methods)).                 |
| `target`      | Name of the numeric column to regress (e.g. `pmic`, `normalized_inhibition`).                 |
| `hyperparams` | Filename (relative to `--inputs`) of the [hyperparameter grid](#hyperparameter-grids) JSON.   |

Optional column:

| Column   | Meaning                                                                                             |
| -------- | -------------------------------------------------------------------------------------------------- |
| `readme` | Filename (relative to `--inputs`) of a [model-card template](#model-cards) to fill in for this model. |

Example with two models:

```csv
id,dataset,structure,split,target,hyperparams,readme
stokes-scaffold,hf://scbirlab/stokes-2020-ai~eco-full:train,smiles,scaffold,normalized_inhibition,hyperparams.json,README-stokes.md
spark-abau,hf://scbirlab/thomas-2018-spark-wt~Acinetobacter-baumannii:train,smiles,faiss,pmic,hyperparams2.json,README-spark.md
```

### Hyperparameter grids

The `hyperparams` JSON is a grid: **every value is a list**, and DuvidNN's
`hyperprep` expands the full cartesian product into individual configs. The
pipeline trains all of them and keeps the best.

Common keys:

| Key               | Example                | Notes                                                        |
| ----------------- | ---------------------- | ------------------------------------------------------------ |
| `class_name`      | `["fingerprint"]`      | `fingerprint` (feed-forward on descriptors) or `chemprop` (message-passing). |
| `use_fp`          | `[true, false]`        | Include Morgan-style fingerprints.                           |
| `use_2d`          | `[true, false]`        | Include 2D descriptors.                                      |
| `use_3d`          | `[false, true]`        | Include 3D descriptors (adds a conformer step).              |
| `n_hidden`        | `[1, 5]`               | Hidden layers.                                               |
| `n_units`        | `[16, 128]`            | Units per layer.                                             |
| `ensemble_size`   | `[10]`                 | Models per ensemble (drives the uncertainty estimate).       |
| `learning_rate`   | `[1e-5]`               |                                                              |
| `dropout`         | `[0.0]`                |                                                              |
| `residual_depth`  | `[2]`                  |                                                              |
| `mp_hidden`, `mp_units` | `[1]`, `[100]`   | Message-passing depth/width (for `chemprop`).                |
| `extra_featurizers` | see [below](#featurizers) | Append external embeddings.                             |

Grid size is the product of all list lengths, so keep lists short unless you
have the compute. Prebuilt single-config examples live in
[`models/configs/`](models/configs).

### Split methods

Set per model in the sample sheet's `split` column; split fractions and *k* are
[pipeline parameters](#pipeline-parameters).

- **`scaffold`** — split by Murcko scaffold so whole chemical series stay
  together. The realistic default for measuring generalization to new chemistry.
- **`faiss`** — FAISS *k*-nearest-neighbour split (`k` neighbours), for
  out-of-distribution evaluation in feature space.
- **`random`** — a plain random split.

Model selection uses `split_replicates` folds; the final refit uses a single
fixed-seed split.

### Featurizers

Featurizers are chosen by the config, not code. Beyond `use_fp`/`use_2d`/`use_3d`,
you can append external embeddings with `extra_featurizers`, for example an LLM
molecular encoder:

```json
"extra_featurizers": [
    "transformer://scbirlab/lchemme-base-zinc22-lteq300:clean_smiles~mean"
]
```

The `transformer://<hf-model>:<column>~<pooling>` form runs the named
HuggingFace model over the given column and pools token embeddings (e.g. `mean`).

### Model cards

If a row has a `readme` template, `MakeReadme` fills it in for the winning model
and writes a push-ready HuggingFace repo (`.dv` checkpoint, gzipped predictions,
`README.md`, `repo-name.txt`). Templates are ordinary Markdown with
placeholders substituted at the end of the run:

| Placeholder    | Filled with                                   |
| -------------- | --------------------------------------------- |
| `__TODAY__`    | Run date.                                     |
| `__NROWS__`, `__NTRAIN__`, `__NVAL__`, `__NTEST__` | Row counts.               |
| `__INPUTS__`, `__OUTPUTS__` | Input/target column names.       |
| `__CONFIG__`   | The winning model config (JSON).              |
| `__TRAIN_EVAL__`, `__VAL_EVAL__`, `__TEST_EVAL__` | Eval metrics (JSON).      |

See [`test/inputs/README-stokes.md`](test/inputs/README-stokes.md) for a
worked template.

### Pipeline parameters

Required:

- `sample_sheet` — path to the sample sheet CSV.

Optional (with defaults):

| Parameter          | Default     | Meaning                                              |
| ------------------ | ----------- | ---------------------------------------------------- |
| `inputs`           | `"inputs"`  | Folder holding `hyperparams`/`readme` files.         |
| `outputs`          | `"outputs"` | Output folder.                                       |
| `train`            | `0.7`       | Training fraction.                                   |
| `validation`       | `0.15`      | Validation fraction (early stopping).                |
| `test`             | `0.15`      | Test fraction (hyperparameter selection).            |
| `k`                | `3`         | Neighbours for the FAISS split.                      |
| `split_replicates` | `3`         | Folds used for model selection.                      |
| `epochs`           | `10`        | Max epochs (early stopping patience is 10).          |
| `n_partitions`     | `100`       | DuckDB shards the training pool is written in.       |
| `skip_plot`        | `false`     | Skip split diagnostic plots.                         |

## Processing steps

For each sample-sheet row:

1. **Hyperprep** (`duvidnn hyperprep`) — expand the grid into `grid.json` and
   count the configs.
2. **Split** (`eluent split`) — download the dataset, split
   train/validation/test by the chosen method over `split_replicates` folds,
   then partition the training pool into `n_partitions` Parquet shards.
3. **Initial training** (`duvidnn train`) — for every config × fold, train an
   ensemble with early stopping and record `pearson_r`, `rmse`, `spearman_rho`.
4. **Select** (`stack_tables` → `best_model`) — aggregate metrics across folds,
   z-score by `pearson_r` on the test split, and pick the best config per model.
5. **Final training** (`SplitDataFinal` → `TrainFinal`) — refit the winning
   config on a fresh full split (fixed seed).
6. **Model card** (`MakeReadme`) — assemble the publishable model repo (if a
   template was given).

## Outputs

Written under `--outputs` (`outputs` by default):

```
outputs/
├── hyperparams/
│   └── <id>.grid.json, <id>.grid.log        # expanded configs + count
├── <id>/
│   ├── splits/method_<split>/fold_*/…        # per-fold test/validation/pool
│   ├── runs/config_<i>/fold_<rep>/*.dv       # per-config checkpoints + metrics
│   └── best-model/
│       ├── data/…                            # final split
│       └── repo/                             # push-ready HF repo (if templated)
│           ├── README.md
│           ├── model.dv/
│           └── eval/predictions_*.csv.gz
├── metrics/
│   └── <id>.all-training.tsv                 # stacked selection metrics
├── summary/
│   ├── <id>.summary.csv                      # mean/median/std/var + z-scores
│   └── <id>.best.csv                         # winning config
└── best-model/
    └── <id>.model.dv/                        # final trained checkpoint
```

Load a checkpoint with DuvidNN:

```python
from duvida.autoclasses import AutoModelBox
modelbox = AutoModelBox.from_pretrained("path/to/model.dv")
modelbox.predict(data=..., inputs=[...], columns=[...])
```

## For developers and contributors

### Layout

```
main.nf                 # workflow wiring
nextflow.config         # params, container, profiles (standard/local/gh)
environment.yml         # Conda env (duvidnn, eluent, duckdb)
Dockerfile              # micromamba image → ghcr.io/scbirlab/nf-trainml
models/configs/         # example single-model configs
modules/                # process definitions
test/                   # sample sheet, inputs, and run-tests.sh
```

### Active modules

The live DAG uses only:

- `modules/hyperprep.nf` — `Hyperprep`
- `modules/data-prep.nf` — `split_data_remote` (aliased twice), `SplitDataFinal`
- `modules/training.nf` — `train_initial_model`, `TrainFinal`
- `modules/utils.nf` — `stack_tables`
- `modules/filter.nf` — `best_model`
- `modules/readme.nf` — `MakeReadme`

> **Note:** the repo also carries processes inherited from sibling pipelines
> (`batches.nf`, `predicting.nf`, `label.nf`, `db-stats.nf`, `info.nf`,
> `multiqc.nf`, the `train` and target-prioritization processes in `utils.nf`).
> These are **not** wired into `main.nf`. Treat them as scaffolding, not API.

### Profiles

Set with `-profile`:

- **`local`** — everything on the local executor with Conda.
- **`standard`** — Slurm executor (arrays of 100), Conda, email notification,
  DAG export. Labels `big_cpu`, `med_mem`, `some_mem` map to resource requests.
- **`gh`** — Docker on the local executor, for CI.

To run on GPU, add a profile that maps the `train` label to your GPU
partition/queue.

### Container and CI

- `.github/workflows/docker-build.yml` builds and pushes the image to GHCR.
- `.github/workflows/nf-test.yml` runs `test/run-tests.sh gh` on every push.

Run the tests locally:

```bash
bash test/run-tests.sh          # local + conda
bash test/run-tests.sh gh       # docker
bash test/run-tests.sh crick    # slurm + conda (module load Nextflow)
```

### Extending

- **New model type / featurizer:** add config keys supported by
  `duvidnn train`; no pipeline change needed as long as they appear in the grid.
- **New split type:** must be supported by `eluent split --type`.
- **Selection metric:** change `filter_metric` in
  [`modules/filter.nf`](modules/filter.nf) (default `pearson_r`).

### Known rough edges

- In `main.nf`, `SplitDataLocal` is an alias of `split_data_remote`, so the
  local-file path is effectively unexercised; `split_data_local` in
  `data-prep.nf` is currently orphaned. Prefer `hf://`/`https://` datasets.
- The Singularity profile sets `--network=none`, which will block dataset
  downloads in the split step for remote datasets. Use Docker/Conda, or drop
  that option, when the data is remote.
- The train step re-materializes the whole pool to CSV; watch memory on very
  large datasets.

## Issues, problems, suggestions

Add to the [issue tracker](https://www.github.com/scbirlab/nf-trainml/issues).

## Further help

- [DuvidNN](https://github.com/scbirlab/duvidnn) — training and uncertainty
- [eluent](https://github.com/scbirlab/eluent) — chemistry-aware splitting
- [Nextflow](https://www.nextflow.io/docs/latest/index.html)
- [DuckDB](https://duckdb.org/docs/)
- [HuggingFace datasets](https://huggingface.co/docs/datasets/)