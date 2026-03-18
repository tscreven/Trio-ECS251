# Trio Carbohydrate to Insulin Dosage Pipeline with Clamping

This document details the algorithmic pipeline in the Trio application that converts a carbohydrate entry into a final insulin dosage, with a specific focus on the "clamping" safety mechanism.

The core logic for this process resides in a combination of Swift code and a suite of JavaScript files that implement the OpenAPS (oref) algorithm.

## High-Level Overview

1.  **Carb Entry:** The user enters a carbohydrate amount into the Trio app.
2.  **Swift to JavaScript Bridge:** The Swift code in Trio gathers all necessary data (glucose, IOB, current settings, etc.) and passes it to a JavaScript engine.
3.  **OpenAPS (oref) JavaScript Execution:** A series of JavaScript files are executed to calculate the appropriate insulin dosage.
4.  **Carb Absorption and Clamping:** The `meal` module in the JavaScript code calculates the "Carbs on Board" (COB) and applies a "clamp" to this value.
5.  **Dosage Calculation:** The final, clamped COB value is used by the `determine-basal` module to calculate the required insulin dosage.
6.  **Dosage Enactment:** The calculated dosage is passed back to the Swift code, which then commands the insulin pump to deliver the dose.

## Detailed Algorithmic Flow

### 1. Swift Entry Point

-   **File:** `Trio/Sources/APS/APSManager.swift`
-   **Class:** `BaseAPSManager`
-   **Methods:** `determineBasal()` and `simulateDetermineBasal()`

When a new loop is triggered (either automatically or manually), the `determineBasal` method is called. For simulations, `simulateDetermineBasal` is used, which allows for manually inputting carb amounts.

This method then calls `openAPS.determineBasal(...)`.

### 2. The `OpenAPS` Bridge

-   **File:** `Trio/Sources/APS/OpenAPS/OpenAPS.swift`
-   **Class:** `OpenAPS`
-   **Method:** `determineBasal(...)`

This Swift class acts as a bridge to the JavaScript implementation of the OpenAPS algorithm. It gathers all the required data from the app's storage and formats it into JSON objects that the JavaScript code can understand. It then calls a series of JavaScript functions, starting with the `meal` function.

### 3. The `meal` Module (JavaScript)

The `meal` module is responsible for calculating Carbs on Board (COB).

-   **Entry Point:** `trio-oref/lib/meal/index.js`
    -   This file simply calls `find_meals` from `history.js` to get recent carb entries, and then passes them to `sum` from `total.js`.

-   **Core Logic:** `trio-oref/lib/meal/total.js`
    -   This file is the heart of the meal calculation and contains the clamping logic.
    -   It calls `calcMealCOB` (which is an alias for the function in `trio-oref/lib/determine-basal/cob.js`) to determine how many of the entered carbs have been absorbed so far.
    -   The remaining, unabsorbed carbs are considered "Carbs on Board" (`mealCOB`).
    -   **Clamping Logic:** The `mealCOB` is then clamped using the `maxCOB` value from the user's profile:
        ```javascript
        // set a hard upper limit on COB to mitigate impact of erroneous or malicious carb entry
        if (typeof(profile_data.maxCOB) === 'number' && ! isNaN(profile_data.maxCOB)) {
            mealCOB = Math.min( profile_data.maxCOB, mealCOB );
        }
        ```
        This is the primary safety mechanism. No matter how large the carb entry is, the algorithm will only ever consider a maximum of `maxCOB` grams of carbohydrates when calculating insulin.

-   **Carb Absorption Calculation:** `trio-oref/lib/determine-basal/cob.js`
    -   This file calculates how many carbs have been absorbed based on the deviation of blood glucose from what would be expected based on insulin alone.
    -   It uses the `min_5m_carbimpact` profile setting to ensure that at least a minimum amount of carb absorption is always factored in.

### 4. The `determine-basal` Module (JavaScript)

-   **File:** `trio-oref/lib/determine-basal/determine-basal.js`

This is the main algorithm that takes all the inputs (including the final, clamped `mealCOB` value) and determines the required insulin dosage. It will calculate whether a temporary basal rate or a bolus (or both) is needed to cover the carbs and bring the blood glucose to the target range.

### 5. Back to Swift for Enactment

The final insulin dosage calculated by `determine-basal.js` is returned to the `OpenAPS.swift` and `APSManager.swift` classes. The `enactTempBasal` or `enactBolus` methods in `APSManager.swift` are then called to send the commands to the insulin pump.

## Summary of Key Files and Functions

| File                                               | Role                                                                          | Key Functions/Variables                               |
| -------------------------------------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------- |
| `Trio/Sources/APS/APSManager.swift`                | Main entry point in the Swift code.                                           | `determineBasal()`, `simulateDetermineBasal()`        |
| `Trio/Sources/APS/OpenAPS/OpenAPS.swift`           | Bridge between Swift and the JavaScript OpenAPS implementation.               | `determineBasal()`                                    |
| `trio-oref/lib/meal/index.js`                      | Entry point for the JavaScript `meal` module.                                 | `generate()`                                          |
| `trio-oref/lib/meal/total.js`                      | Calculates Carbs on Board (COB) and applies the clamp.                        | `recentCarbs()`, `profile_data.maxCOB`                |
| `trio-oref/lib/determine-basal/cob.js`             | Calculates the amount of carbs that have been absorbed.                       | `detectCarbAbsorption()`, `profile.min_5m_carbimpact` |
| `trio-oref/lib/determine-basal/determine-basal.js` | Main OpenAPS algorithm for calculating the final insulin dosage.              | `determine_basal()`                                   |

This documentation should provide a clear path for another agent to port the clamping algorithm to Python by understanding which files and functions are involved in the carb to insulin pipeline.
