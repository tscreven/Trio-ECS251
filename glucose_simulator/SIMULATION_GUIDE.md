# Trio COB Clamping Simulation — User Guide

This simulation demonstrates Trio's safety feature that **clamps Carbs on Board (COB)**
to a maximum value, preventing dangerously large insulin doses from erroneous carb entries.

## What the simulation does

Two scenarios are run side-by-side using a virtual Type 1 diabetic patient (`adult#003`):

| Scenario | What happens |
|---|---|
| **No Clamp** | The app doses for the full (erroneous) carb entry → severe hypoglycemia |
| **With Clamp** | Trio caps COB at `MAX_CLAMPED_COB` → correct-ish dose → patient stays safe |

---

## How to run

From the **repository root**:

```bash
glucose_simulator/venv_simglucose/bin/python3 glucose_simulator/run_clamp_simulation.py
```

The plot is saved to `glucose_simulator/clamping_simulation_results.png`.

---

## Parameters you can change

Open **`glucose_simulator/run_clamp_simulation.py`** and edit the block at the top of the file:

```python
# ----------------------------------------------------------------
# EXPERIMENT SETTINGS -- edit these values to change the simulation
# ----------------------------------------------------------------
CARB_AMOUNT_GRAMS = 10000   # Carbs the patient accidentally entered in the app (g)
REAL_MEAL_GRAMS = 80        # Carbs the patient actually eats (g)
MAX_CLAMPED_COB = 80        # Maximum COB Trio's algorithm will dose for (g)
# ----------------------------------------------------------------
```

| Parameter | Description | Try changing it to... |
|---|---|---|
| `CARB_AMOUNT_GRAMS` | The wrong carb entry the patient made in the app | `500`, `1000`, `50000` |
| `REAL_MEAL_GRAMS` | The actual food the patient eats | `40`, `60`, `120` |
| `MAX_CLAMPED_COB` | Trio's safety clamp limit | Set equal to `REAL_MEAL_GRAMS` for perfect coverage, or higher to see partial protection |

### Interesting experiments to try

**How small does the bad entry need to be before clamping stops helping?**
```python
CARB_AMOUNT_GRAMS = 200   # moderate over-entry
REAL_MEAL_GRAMS = 80
MAX_CLAMPED_COB = 80
```

**What if the clamp is set too high?**
```python
CARB_AMOUNT_GRAMS = 10000
REAL_MEAL_GRAMS = 80
MAX_CLAMPED_COB = 500     # clamp is above real meal → patient still gets too much insulin
```

**Perfect clamping (clamp == real meal)**
```python
CARB_AMOUNT_GRAMS = 10000
REAL_MEAL_GRAMS = 80
MAX_CLAMPED_COB = 80      # ideal: doses exactly for what the patient eats
```

---

## Patient and algorithm parameters (advanced)

These are in the same file (`run_clamp_simulation.py`) just below the experiment settings block:

| Constant | Meaning | File location |
|---|---|---|
| `PATIENT_NAME` | Which simglucose patient to simulate | `run_clamp_simulation.py` |
| `CARB_RATIO` | Grams of carbs per unit of insulin (g/U) | `run_clamp_simulation.py` |
| `CORRECTION_FACTOR` | BG drop per unit of insulin (mg/dL/U) | `run_clamp_simulation.py` |
| `TARGET_GLUCOSE` | Target BG used in correction bolus calc | `run_clamp_simulation.py` |
| `CORRECTION_THRESHOLD` | BG must be above this to trigger correction | `run_clamp_simulation.py` |

Available patients (from `Quest.csv`): `adult#001` through `adult#010`.
Each has different CR and CF values — `adult#007` (CR=22) behaves more like an adolescent.

The clamping logic itself lives in:
```
glucose_simulator/insulin_dosing_algorithm_in_python/algorithm.py
```
The key function is `clamp_cob(carbs, max_cob)` — a direct port of `trio-oref/lib/meal/total.js`.

---

## Output

After running, you get:

- **Console output**: effective COB, requested bolus, min CGM, and final CGM for each scenario
- **`clamping_simulation_results.png`**: plot with both CGM traces, the meal/bolus event marker, hypo threshold lines, and the target glucose band
