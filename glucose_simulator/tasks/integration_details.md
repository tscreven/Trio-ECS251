# Guidelines for Integrating the Trio Clamping Algorithm with the Glucose Simulator

## 1. Objective

The primary goal is to create a Python script that demonstrates the effectiveness of the Trio app's insulin clamping safety feature. This will be achieved by simulating two scenarios within the `simglucose` environment:

*   **Scenario A (No Clamp):** A dangerously large carbohydrate amount (e.g., 10,000g) is administered without any clamping, leading to a massive insulin dose and a hypoglycemic event.
*   **Scenario B (With Clamp):** The same large carbohydrate amount is administered, but the ported Trio clamping algorithm limits the "Carbs on Board" (COB) value, resulting in a safe insulin dose.

The final output will be a single `matplotlib` graph that plots the simulated blood glucose (CGM) over time for both scenarios, clearly visualizing the impact of the clamp.

## 2. Core Task: Create a Python Tool

You will create a new Python script named `run_clamp_simulation.py` in the `glucose_simulator/` directory. This script will house the logic for running the simulations and generating the comparative plot.

## 3. Key Files for Reference

*   `glucose_simulator/trio_clamping_alg_explanation.md`: This is essential reading. It details the original algorithm's logic and file locations within the Trio (Swift/JavaScript) codebase, which you will be porting to Python.
*   `glucose_simulator/run_simulation.py`: Use this existing script as a foundational template for your new `run_clamp_simulation.py` script. It demonstrates how to initialize the patient, environment, and run a basic simulation loop.
*   **`simglucose` Library:** You will need to interact with the simulator's objects. Be prepared to investigate the `simglucose` source code or documentation to find methods for retrieving specific patient data, such as Insulin on Board (IOB).

## 4. New Directory for Ported Algorithm

First, create a new directory: `glucose_simulator/insulin_dosing_algorithm_in_python/`.

Inside this new directory, create a Python file named `algorithm.py`. This file will contain the pure Python port of the Trio clamping and insulin dosing logic.

## 5. Step-by-Step Integration Guide

### Part 1: Port the Clamping Algorithm to Python

In `glucose_simulator/insulin_dosing_algorithm_in_python/algorithm.py`, you will implement the core logic.

**Function to Create:**
`calculate_insulin_dosage(glucose_level, iob, carbs, profile_data)`

**Parameters:**

*   `glucose_level` (float): The current CGM value.
*   `iob` (float): The current Insulin on Board.
*   `carbs` (float): The amount of carbohydrates entered.
*   `profile_data` (dict): A dictionary containing patient settings. This is critical for the algorithm. It must include:
    *   `maxCOB` (float): The clamping value. For the "No Clamp" scenario, this can be set to a very high number or `float('inf')`.
    *   You will need to identify other necessary profile values (like `min_5m_carbimpact`, insulin sensitivity ratio, etc.) by reviewing `trio_clamping_alg_explanation.md`. You should find reasonable default values for these from the `simglucose` patient object (`env.patient`) or use medically sensible defaults.

**Implementation:**

1.  **Clamping Logic:** Re-implement the clamping mechanism found in `trio-oref/lib/meal/total.js`. The core of this is `mealCOB = min(profile_data['maxCOB'], mealCOB)`.
2.  **Dose Calculation Logic:** Re-implement the dosage calculation from `trio-oref/lib/determine-basal/determine-basal.js`. This will take the clamped `mealCOB`, `glucose_level`, `iob`, and other profile data to determine the appropriate insulin bolus.
3.  **Return Value:** The function should return an `Action` object, just like the `policy` method in the example controller. e.g., `return Action(basal=0, bolus=calculated_bolus)`.

### Part 2: Create the Simulation Script (`run_clamp_simulation.py`)

This script will orchestrate the simulation runs. It should be based heavily on `run_simulation.py`.

**Simulation Flow Function:**
Create a main simulation function, e.g., `run_scenario(carb_amount, max_clamp_amount)`.

1.  **Initialization:** Set up the patient, sensor, pump, and environment as seen in `run_headless_sim`. The total simulation time is 1440 minutes (24 hours).
2.  **Run to 30%:** Loop through the simulation for `432` steps (30% of 1440). For these initial steps, use a simple baseline controller that administers a steady basal rate and no boluses. Record the history.
3.  **At the 30% Mark (step 432):**
    *   Gather the necessary inputs for your ported algorithm:
        *   `glucose_level = obs.CGM`
        *   `iob = env.patient.IOB()` (You may need to verify the exact method to get IOB from the patient object).
        *   `carbs = carb_amount` (the large value passed into the function).
    *   Construct the `profile_data` dictionary. Set the `maxCOB` value from the `max_clamp_amount` function parameter.
    *   Import and call `calculate_insulin_dosage` from your `algorithm.py` file.
    *   Take the returned `Action` object (which contains the calculated bolus) and apply it to the simulation: `env.step(action)`.
4.  **Complete Simulation:** Continue looping from step 433 to 1440, using the simple baseline basal controller again.
5.  **Return Results:** The function should return a list or Pandas DataFrame of the CGM results over time for the full 1440 minutes.

### Part 3: Run Scenarios and Plot

In the `if __name__ == "__main__":` block of `run_clamp_simulation.py`:

1.  **Run Both Scenarios:**
    *   `results_no_clamp = run_scenario(carb_amount=10000, max_clamp_amount=10000)`
    *   `results_with_clamp = run_scenario(carb_amount=10000, max_clamp_amount=100)`
2.  **Plotting with `matplotlib`:**
    *   Create a single plot.
    *   Plot the CGM time series from `results_no_clamp`.
    *   Plot the CGM time series from `results_with_clamp` on the same axes.
    *   Add a vertical dashed line at `x = 432` to mark the time of the carb and insulin event.
    *   Set a clear title (e.g., "Clamping Algorithm Safety Demonstration").
    *   Label the X-axis ("Time (minutes)") and Y-axis ("CGM (mg/dL)").
    *   Include a legend to clearly label the "With Clamp" and "Without Clamp" lines.
    *   Save the plot to a file (e.g., `clamping_simulation_results.png`).

This detailed plan should provide all the necessary guidance to complete the integration and demonstration task.
