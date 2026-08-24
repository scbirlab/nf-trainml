---
license: mit
pipeline_tag: tabular-regression
tags:
- chemistry
- microbiology
- antibiotics
library_name: duvidnn
datasets:
- scbirlab/stokes-2020-ai
---

# Predictor of inhibition of _E. coli_

_Updated:_ __TODAY__

Trained on the published training dataset of [A Deep Learning Approach to Antibiotic Discovery](https://doi.org/10.1016/j.cell.2020.01.021) (__NROWS__ rows in total, [HF dataset](https://huggingface.co/datasets/scbirlab/scbirlab/stokes-2020-ai)).

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
modelbox = AutoModelBox.from_pretrained("hf://scbirlab/stokes-dv-2608")
modelbox.predict(data=..., inputs=[...], columns=[...])  # make predictions on your own data
```

## Training details

- **Dataset:** [stokes-2020-ai](https://huggingface.co/datasets/scbirlab/scbirlab/stokes-2020-ai) (__NROWS__ rows in total for __species__)
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

> Stokes, J. M., Yang, K., ..., Collins, J. J. (2020). 
> A Deep Learning Approach to Antibiotic Discovery. 
> Cell, 180(4), 688–702.e13. 
> https://doi.org/10.1016/j.cell.2020.01.021
> PMID: 32084340; PMCID: PMC8349178.

We cleaned the original dataset to subset the most relevant columns, remove empty values, 
and give succint column titles.


### Data Collection and Processing

Data were processed using [schemist](https://github.com/scbirlab/schemist), a tool for processing chemical datasets.


### Who are the source data producers?

Stokes, J. M., Yang, K., Swanson, K., Jin, W., Cubillos-Ruiz, A., Donghia, N. M., 
MacNair, C. R., French, S., Carfrae, L. A., Bloom-Ackermann, Z., Tran, V. M., 
Chiappino-Pepe, A., Badran, A. H., Andrews, I. W., Chory, E. J., Church, G. M., 
Brown, E. D., Jaakkola, T. S., Barzilay, R., & Collins, J. J.Joe Thomas, Marc Navre, Aileen Rubio, and Allan Coukell
