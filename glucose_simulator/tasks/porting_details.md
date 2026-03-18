# Porting the Trio Clamping Algorithm to Python

This document provides answers and guidance for porting the Trio clamping algorithm from its JavaScript (JS) implementation into the Python-based glucose simulator.

### Is the carb-to-insulin pipeline dependent on other metrics like IoB?

**Yes, absolutely.** The core of the Trio logic is the OpenAPS `determine-basal.js` script. To calculate a safe and effective insulin dose, it requires a comprehensive set of data beyond just the immediate carbohydrate entry.

For your simulation, you will need to provide and/or mock the following key inputs:

1.  **Current Blood Glucose (BG):** The algorithm's response is highly dependent on the current BG. This is available in the simulator via `observation.CGM`.
2.  **Insulin on Board (IoB):** This is critical. The algorithm will not recommend a large bolus if there is already a significant amount of active insulin. The OpenAPS scripts calculate IoB internally based on a history of past insulin doses. You will need to feed the history of simulated insulin doses (both basal and bolus) back into the algorithm on each step.
3.  **Carbs on Board (COB):** The clamping logic is applied to this value. The `meal.js` and `cob.js` scripts calculate COB based on carb entries and observed glucose deviations. You will need to port this calculation.
4.  **Patient Profile/Settings:** The algorithm is configured by a `profile` object. Porting the logic will require creating a Python dictionary or object that mimics this structure. Critical settings include:
    *   `maxCOB`: The value for the clamp itself. This is the variable you will manipulate for your two scenarios.
    *   `carb_ratio` (CR): To determine how much insulin is needed per gram of carbs.
    *   `sens` (Insulin Sensitivity Factor or ISF): To determine how much one unit of insulin will lower BG.
    *   `basal`: The patient's basal rate profile.
    *   And several others that fine-tune the algorithm's behavior.

### Other Considerations for Porting

Here are other key points to consider for a successful port:

1.  **It's a JavaScript Port, Not Swift:** The core safety and dosage logic is not in Swift; it's in the collection of JavaScript files located in the `trio-oref/lib/` directory. Your task is to translate the logic from these `.js` files into Python.

2.  **Focus on Key Files:** You do not need to port the entire OpenAPS suite. For your demonstration, focus on the files involved in the meal and dose calculation pipeline:
    *   **`trio-oref/lib/meal/total.js`**: Contains the primary clamping logic where `mealCOB` is compared against `profile_data.maxCOB`.
    *   **`trio-oref/lib/determine-basal/cob.js`**: Calculates how many carbs have been absorbed, which is a necessary input for the clamping logic in `total.js`.
    *   **`trio-oref/lib/determine-basal/determine-basal.js`**: The main engine that takes the (now clamped) COB, along with IOB, BG, and profile settings, to calculate the final insulin dose.

3.  **Create a `TrioController` for the Simulator:** The best way to integrate the ported code is to create a new controller class, similar to the `SafetyBasalController` in `run_simulation.py`.

    ```python
    # In run_simulation.py
    from simglucose.controller.base import Controller, Action

    class TrioController(Controller):
        def __init__(self, init_state, profile):
            self.init_state = init_state
            self.profile = profile
            self.insulin_history = [] # To track for IoB calculation

        def policy(self, observation, reward, done, **kwargs):
            # 1. Get current state from simulator
            bg = observation.CGM
            meal = kwargs.get('meal', 0)
            now = kwargs.get('time') # You'll need the current time

            # 2. Structure the inputs for your ported function
            # This will involve glucose history, meal history, and insulin history
            openaps_inputs = {
                "glucose": bg, # This needs to be a history
                "iob": self.calculate_iob(self.insulin_history), # You need to port the IoB logic
                "carbs": meal, # This needs to be a history
                "profile": self.profile
            }

            # 3. Call your ported main OpenAPS function
            # result = ported_determine_basal(openaps_inputs)
            # action_basal = result.get('basal', 0)
            # action_bolus = result.get('bolus', 0)

            # 4. Store the action to calculate IoB in the next step
            # self.insulin_history.append({'time': now, 'basal': action_basal, 'bolus': action_bolus})

            # return Action(basal=action_basal, bolus=action_bolus)
            pass # Replace with real implementation

        def calculate_iob(self, history):
            # Port the IoB calculation logic from OpenAPS here
            pass
    ```

4.  **Designing the Scenarios (A vs. B):** You can control the two scenarios by simply changing the `maxCOB` value in the profile you pass to your `TrioController`.

    *   **Scenario A (No Clamp):** Create a profile dictionary where `maxCOB` is set to a very high number (e.g., `2000`).
        ```python
        profile_no_clamp = {
            "maxCOB": 2000,
            "carb_ratio": 10,
            "sens": 100,
            # ... other necessary settings
        }
        controller_A = TrioController(init_state=0, profile=profile_no_clamp)
        ```
    *   **Scenario B (With Clamp):** Create a profile where `maxCOB` is a reasonable, safe number (e.g., `120`).
        ```python
        profile_with_clamp = {
            "maxCOB": 120,
            "carb_ratio": 10,
            "sens": 100,
            # ... other necessary settings
        }
        controller_B = TrioController(init_state=0, profile=profile_with_clamp)
        ```

By running the simulation twice with these different controllers, you will be able to generate two `sim_results_summary.csv` files that perfectly demonstrate the clamping mechanism's effect on the final insulin dosage and patient safety.
