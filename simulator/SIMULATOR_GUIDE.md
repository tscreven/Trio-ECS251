# Simglucose Simulator Guide

How to use this simulator to test your own insulin dosing algorithms against virtual Type 1 Diabetes patients.

## Quick Start

```bash
cd simulator
source venv_simglucose/bin/activate
python run_simulation.py
```

Results are saved to `sim_results_summary.csv`.

## How It Works

The simulator models the glucose-insulin dynamics of a virtual T1D patient. Every 3 minutes (one step), your controller reads the patient's CGM (continuous glucose monitor) value and decides how much insulin to deliver. The simulator then updates the patient's blood glucose based on physiology, meals, and the insulin you gave.

```
┌─────────────┐     CGM reading      ┌────────────────┐
│   Patient    │ ──────────────────►  │ Your Controller │
│  (+ Sensor)  │                      │   (policy())    │
│  (+ Meals)   │  ◄──────────────────  │                │
└─────────────┘   Action(basal,bolus) └────────────────┘
```

## The Simulation Loop

This is the core pattern. Copy and modify it:

```python
from datetime import datetime
from simglucose.simulation.env import T1DSimEnv
from simglucose.controller.base import Controller, Action
from simglucose.sensor.cgm import CGMSensor
from simglucose.actuator.pump import InsulinPump
from simglucose.patient.t1dpatient import T1DPatient
from simglucose.simulation.scenario_gen import RandomScenario

# 1. Build the environment
patient = T1DPatient.withName('adolescent#003')
sensor  = CGMSensor.withName('Dexcom', seed=1)
pump    = InsulinPump.withName('Insulet')
scenario = RandomScenario(start_time=datetime(2024, 1, 1, 0, 0, 0), seed=1)
env = T1DSimEnv(patient, sensor, pump, scenario)

# 2. Create your controller (see next section)
controller = YourController(init_state=0)

# 3. Run the loop
step = env.reset()
for i in range(480):  # 480 steps = 24 hours (3 min/step)
    action = controller.policy(step.observation, step.reward, step.done, meal=step.meal)
    step = env.step(action)
    if step.done:
        break
```

## Writing Your Own Controller

Subclass `Controller` and implement `policy()`. That's it.

```python
from simglucose.controller.base import Controller, Action

class YourController(Controller):
    def __init__(self, init_state):
        self.init_state = init_state
        self.state = init_state  # use this for any internal state

    def policy(self, observation, reward, done, **kwargs):
        bg = observation.CGM           # current glucose reading (mg/dL)
        meal = kwargs.get('meal', 0)   # carbs ingested this step (grams)

        # --- YOUR ALGORITHM HERE ---
        basal = 0.05   # continuous background insulin (U/min)
        bolus = 0.0    # one-time correction/meal dose (Units)

        return Action(basal=basal, bolus=bolus)

    def reset(self):
        self.state = self.init_state
```

### What your policy receives

| Parameter     | Type   | Description |
|---------------|--------|-------------|
| `observation.CGM` | float | Current CGM glucose reading in mg/dL |
| `reward`      | float  | Risk-based reward from the previous step |
| `done`        | bool   | True if patient BG went below 10 or above 600 (game over) |
| `kwargs['meal']` | float | Carbs ingested this step (grams). 0 if no meal. |

### What your policy returns

`Action(basal=..., bolus=...)` — a namedtuple with two floats:

| Field   | Unit    | Description |
|---------|---------|-------------|
| `basal` | U/min   | Continuous insulin rate. ~0.05 = ~3 U/hr (typical). Set to 0 to suspend. |
| `bolus` | Units   | One-time insulin dose. Used for meals or corrections. |

## The Step Object

`env.reset()` and `env.step(action)` both return a `Step` object with these attributes:

| Attribute       | Description |
|-----------------|-------------|
| `step.observation` | `Observation(CGM=...)` — the CGM reading |
| `step.reward`   | Risk-based reward for RL algorithms |
| `step.done`     | Game over flag (BG < 10 or BG > 600) |
| `step.meal`     | Carbs ingested this step |
| `step.time`     | Current simulation datetime |
| `step.bg`       | True blood glucose (not sensor-filtered) |
| `step.lbgi`     | Low blood glucose index |
| `step.hbgi`     | High blood glucose index |
| `step.risk`     | Combined risk index |
| `step.patient_name` | Patient identifier string |
| `step.patient_state` | Internal patient state vector |
| `step.sample_time` | Minutes per step (default 3) |

## Available Patients, Sensors, and Pumps

### Patients (30 virtual patients)

```
adolescent#001 through adolescent#010
adult#001      through adult#010
child#001      through child#010
```

### Sensors

| Name         | Notes |
|--------------|-------|
| `Dexcom`     | Standard CGM |
| `GuardianRT` | Medtronic sensor |
| `Navigator`  | Abbott sensor |

### Pumps

| Name     | Notes |
|----------|-------|
| `Cozmo`  | Smiths Medical |
| `Insulet`| OmniPod |

## Custom Meal Scenarios

Instead of random meals, define exactly when and how much the patient eats:

```python
from datetime import datetime, timedelta
from simglucose.simulation.scenario import CustomScenario, Action as MealAction

start = datetime(2024, 1, 1, 0, 0, 0)
meals = [
    (timedelta(hours=7),  MealAction(meal=45)),   # 45g breakfast at 7am
    (timedelta(hours=12), MealAction(meal=70)),   # 70g lunch at noon
    (timedelta(hours=18), MealAction(meal=80)),   # 80g dinner at 6pm
]
scenario = CustomScenario(start_time=start, scenario=meals)
```

Use this instead of `RandomScenario` when building the environment.

## Glucose Ranges (Clinical Reference)

| Range           | mg/dL   | Meaning |
|-----------------|---------|---------|
| Severe hypo     | < 54    | Dangerous low |
| Hypoglycemia    | < 70    | Low — suspend insulin |
| Target range    | 70–180  | Goal for most algorithms |
| Hyperglycemia   | > 180   | High — may need correction |
| Severe hyper    | > 250   | Dangerous high |
| Simulation ends | < 10 or > 600 | `done=True` |

## Running Across All Patients

```python
patients = [f'{group}#{i:03d}' for group in ['adolescent', 'adult', 'child'] for i in range(1, 11)]

for name in patients:
    patient = T1DPatient.withName(name)
    env = T1DSimEnv(patient, sensor, pump, scenario)
    # ... run your controller and collect metrics
```

## Tips for Algorithm Development

- **Start simple.** The included `SafetyBasalController` in `run_simulation.py` is a minimal example — fixed basal with a low-glucose suspend and a flat meal bolus. It's intentionally bad (the patient crashes to 39 mg/dL). Beat it.
- **Track time-in-range.** The key clinical metric is % of time the patient's CGM stays in 70–180 mg/dL.
- **Use `step.bg` vs `step.observation.CGM`.** The CGM has sensor noise and lag. `step.bg` is the true BG — useful for evaluation but your controller should only use the CGM (that's all a real pump sees).
- **Test across patient types.** An algorithm that works on `adult#001` may fail on `child#005`. The 30 patients have different insulin sensitivities.
- **Seeds matter.** `RandomScenario(seed=N)` and `CGMSensor(seed=N)` control randomness. Fix them for reproducibility, vary them for robustness testing.
