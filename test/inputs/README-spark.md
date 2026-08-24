---
license: mit
pipeline_tag: tabular-regression
tags:
- chemistry
- microbiology
- antibiotics
library_name: duvidnn
datasets:
- scbirlab/thomas-2018-spark-wt
---

# Predictor of MICs of _A. baumannii_

_Updated:_ __TODAY__

Trained on the [human-curated SPARK dataset](https://doi.org/10.1021/acsinfecdis.8b00193) (__NROWS__ rows in total, [HF dataset](https://huggingface.co/datasets/scbirlab/thomas-2018-spark-wt)).

## Model details

This model was trained using [our DuvidNN framework](https://github.com/scbirlab/duvidnn), 
as a result of hyperparameter searches and selecting the model that performs best on unseen test data 
(from a scaffold split). 

DuvidNN also saves the training data in this checkpoint to allows the calculation of uncertainty metrics 
based on that training data.

This model is the best regression model from a hyperparameter search, determined
by Pearson's _r_ on a held-out test set not seen in training or early stopping. 

### Model architecture

- **Regression**

```json
__CONFIG__

```

### Model usage

You can use this model with:

```python
from duvida.autoclasses import AutoModelBox
modelbox = AutoModelBox.from_pretrained("hf://scbirlab/spark-dv-2510")
modelbox.predict(data=..., inputs=[...], columns=[...])  # make predictions on your own data
```

## Training details

- **Dataset:** [SPARK](https://huggingface.co/datasets/scbirlab/thomas-2018-spark-all) (__NROWS__ rows in total for __species__)
- **Input column:** __INPUTS__
- **Output column:** __OUTPUTS__
- **Split type:** Murcko scaffold
- **Split proportions:** 
    - 70% training (__NTRAIN__ rows)
    - 15% validation (for early stopping) (__NVAL__ rows)
    - 15% test (for selecting hyperparameters) (__NTEST__ rows)

Here is the training log:

<img src="training-log.png" width=450>

And these are the evaluation scores.

Train (__NTRAIN__ rows):

```json
__TRAIN_EVAL__

```

<img src="predictions_training.png" width=450>

Validation (__NVAL__ rows):

```json
__VAL_EVAL__

```

<img src="predictions_validation.png" width=450>

Test (__NTEST__ rows):

```json
__TEST_EVAL__

```

<img src="predictions_test.png" width=450>

## Training data details

The training data were collated by the authors of:

> Joe Thomas, Marc Navre, Aileen Rubio, and Allan Coukell
> Shared Platform for Antibiotic Research and Knowledge: A Collaborative Tool to SPARK Antibiotic Discovery
> ACS Infectious Diseases 2018 4 (11), 1536-1539
> DOI: 10.1021/acsinfecdis.8b00193

We cleaned the original SPARK dataset to subset the most relevant columns, remove empty values, 
and give succint column titles.

### Dataset Sources

- **Repository:** https://www.collaborativedrug.com/spark-data-downloads
- **Paper:** https://doi.org/10.1021/acsinfecdis.8b00193

### Data Collection and Processing

Data were processed using [schemist](https://github.com/scbirlab/schemist), a tool for processing chemical datasets.

The SMILES strings have been canonicalized, and split into training (70%), validation (15%), and test (15%) sets 
by Murcko scaffold for each species with more than 1000 entries. Additional features like molecular weight and 
topological polar surface area have also been calculated.

### Who are the source data producers?

Joe Thomas, Marc Navre, Aileen Rubio, and Allan Coukell
