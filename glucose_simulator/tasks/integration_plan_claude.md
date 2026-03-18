# Plan: Integrate Trio Clamping Algorithm with Glucose Simulator

## Context

The Trio app has a critical safety feature that clamps Carbs on Board (COB) to a maximum value (`maxCOB`), preventing dangerously large insulin doses from erroneous carb entries. We need to demonstrate this by running two simglucose simulations -- one without clamping (causing hypoglycemia) and one with clamping (safe outcome) -- and plotting the results.

## User Decisions
- **Simulation duration**: 6 hours (120 steps at 3 min/step)
- **Carb event at 30% mark**: step 36 (108 minutes)
- **Algorithm scope**: Simplified port -- core clamping + carb-ratio dosing
- **IOB source**: Patient state vector (`state[10]`, `state[11]`)

## Key Technical Findings

- `Action(basal, bolus)` -- basal in U/min, bolus in U/min (convert total Units / sample_time)
- `env.step()` returns `(observation, reward, done, info_dict)`; `observation.CGM` gives glucose
- No `IOB()` method exists; use `env.patient.state[10]` + `state[11]` (pmol/kg), convert via `* BW / 6000`
- Patient `adolescent#003`: CR=23, CF=33.53 (from Quest.csv)
- Insulet pump clips bolus at 30 U/min (so max ~90U per 3-min step)
- `CustomScenario(start_time, scenario=[])` delivers zero meals -- only insulin affects patient
- Simulation may end early (`done=True`) if BG < 10 or BG > 600 in the no-clamp scenario

## Files to Create

### 1. `glucose_simulator/insulin_dosing_algorithm_in_python/__init__.py`
Empty file.

### 2. `glucose_simulator/insulin_dosing_algorithm_in_python/algorithm.py`

Three functions + two data structures:

- **`PatientProfile`** (dataclass): `max_cob`, `carb_ratio`, `correction_factor`, `target_glucose`, `correction_threshold`
- **`DosingResult`** (NamedTuple): `bolus_total_units`, `effective_cob`, `carb_bolus`, `correction_bolus`, `iob_adjustment`
- **`clamp_cob(carbs, max_cob)`**: Returns `min(max_cob, carbs)` -- port of `trio-oref/lib/meal/total.js` line ~120
- **`calculate_iob_from_state(patient_state, body_weight)`**: Reads `state[10]` + `state[11]` (pmol/kg), converts to Units via `* BW / 6000`
- **`calculate_insulin_dosage(glucose, iob_units, carbs, profile)`**:
  1. Clamp: `effective_cob = min(max_cob, carbs)`
  2. `carb_bolus = effective_cob / CR`
  3. `correction_bolus = max(0, (glucose - target) / CF)` if glucose > threshold, else 0
  4. `total = max(0, carb_bolus + correction_bolus - iob_units)`
  5. Returns `DosingResult`

### 3. `glucose_simulator/run_clamp_simulation.py`

Based on existing `run_simulation.py` patterns.

- **`run_scenario(carb_amount, max_clamp_amount)`**:
  1. Setup: `T1DPatient.withName('adolescent#003')`, Dexcom sensor, Insulet pump, empty `CustomScenario`
  2. Loop 120 steps with baseline basal (0.05 U/min, no bolus)
  3. At step 36: read CGM + IOB from state, call `calculate_insulin_dosage`, deliver bolus via `Action(basal, bolus_units/3)`
  4. Continue remaining steps with basal only
  5. Handle early termination (`done=True`)
  6. Return dict: `times`, `cgm`, `bolus_given`, `effective_cob`

- **`plot_results(results_no_clamp, results_with_clamp)`**:
  - Single matplotlib figure, two CGM lines (red=no clamp, blue=with clamp)
  - Vertical dashed line at step 36 (108 min)
  - Reference lines at 70 mg/dL and 54 mg/dL (hypo thresholds)
  - Green band for target range (70-180)
  - Save to `clamping_simulation_results.png`

- **`__main__` block**:
  - Scenario 1: `run_scenario(10000, 10000)` -- no clamp
  - Scenario 2: `run_scenario(10000, 120)` -- with clamp
  - Print summary (effective COB, bolus, min CGM)
  - Call `plot_results`

## Expected Behavior

| Scenario | Effective COB | Bolus | Expected Outcome |
|----------|--------------|-------|-----------------|
| No Clamp | 10,000g | ~434U (clipped to ~90U by pump) | Severe hypoglycemia, sim may terminate early |
| With Clamp | 120g | ~5.2U | Moderate dip, stays safe |

## Verification

1. Activate venv: `source glucose_simulator/venv_simglucose/bin/activate`
2. Run: `python glucose_simulator/run_clamp_simulation.py`
3. Check console output shows both scenarios with correct effective COB values
4. Verify `clamping_simulation_results.png` shows divergent CGM curves
5. No-clamp line should drop severely; with-clamp line should stay in/near safe range
