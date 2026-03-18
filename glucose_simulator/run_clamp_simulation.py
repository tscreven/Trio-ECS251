"""
Demonstrates Trio's COB clamping safety feature using the simglucose simulator.

Clinical scenario:
  A Type 1 diabetic patient plans to eat a real meal (REAL_MEAL_GRAMS) but
  accidentally enters a wildly incorrect carb count (CARB_AMOUNT_GRAMS) into
  the app. Two dosing outcomes are compared:

  1. No Clamp  -- the app doses for the full erroneous entry.
                  The massive insulin bolus overwhelms the food, causing
                  severe hypoglycemia.

  2. With Clamp -- Trio's algorithm caps COB at MAX_CLAMPED_COB before dosing.
                   The bolus is proportional to the real meal size, so the
                   patient stays safe.

--- EXPERIMENT SETTINGS (edit these to try different inputs) ---
"""

import sys
import os

# Add this directory to sys.path so the algorithm package can be found
sys.path.insert(0, os.path.dirname(__file__))

# ----------------------------------------------------------------
# EXPERIMENT SETTINGS -- edit these values to change the simulation
# ----------------------------------------------------------------
CARB_AMOUNT_GRAMS = 200   # Carbs the patient accidentally entered in the app (g)
REAL_MEAL_GRAMS = 90        # Carbs the patient actually eats (g)
MAX_CLAMPED_COB = 100       # Maximum COB Trio's algorithm will dose for (g)
# ----------------------------------------------------------------

from datetime import datetime, timedelta

import csv
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from simglucose.simulation.env import T1DSimEnv
from simglucose.patient.t1dpatient import T1DPatient
from simglucose.sensor.cgm import CGMSensor
from simglucose.actuator.pump import InsulinPump
from simglucose.simulation.scenario import CustomScenario
from simglucose.controller.base import Action

from insulin_dosing_algorithm_in_python.algorithm import (
    PatientProfile,
    calculate_iob_from_state,
    calculate_insulin_dosage,
)

# --- Patient constants (adult#003 from Quest.csv / vpatient_params.csv) ---
PATIENT_NAME = "adult#003"
CARB_RATIO = 9.0            # g/U
CORRECTION_FACTOR = 17.93   # mg/dL per U
TARGET_GLUCOSE = 100.0      # mg/dL
CORRECTION_THRESHOLD = 150.0  # mg/dL -- glucose must be above this to trigger correction bolus

# --- Simulation constants ---
BASELINE_BASAL_RATE = 0.05  # U/min -- background basal insulin
SIMULATION_STEPS = 120      # 120 steps × 3 min/step = 6 hours
CARB_EVENT_STEP = 36        # 30% mark: step 36 = 108 minutes into simulation
SAMPLE_TIME_MINUTES = 3     # Dexcom CGM sample interval

# Meal timing: step 36's first mini-step fires at patient.t = 105 min = 1.75 hours.
# Setting the scenario at 1.75 h ensures the food and bolus are delivered together.
_MEAL_DELIVERY_TIME_HOURS = ((CARB_EVENT_STEP - 1) * SAMPLE_TIME_MINUTES + 1) / 60.0


# =============================================================================
# High-level orchestration
# =============================================================================

def run_no_clamp_scenario() -> dict:
    """
    Run the scenario where no COB clamping is applied.

    max_cob equals CARB_AMOUNT_GRAMS, so the full erroneous entry drives
    the dose calculation. The pump hardware physically clips the bolus
    delivery rate, but the resulting insulin still causes severe hypoglycemia
    because it vastly exceeds what REAL_MEAL_GRAMS of food can counteract.
    """
    return run_scenario(
        max_cob=CARB_AMOUNT_GRAMS,
        scenario_label="No Clamp",
    )


def run_clamped_scenario() -> dict:
    """
    Run the scenario where Trio's COB clamping is active.

    Regardless of how large CARB_AMOUNT_GRAMS is, the algorithm only doses
    for MAX_CLAMPED_COB grams of carbs. When MAX_CLAMPED_COB matches the
    patient's actual food intake (REAL_MEAL_GRAMS), the dose is correct and
    the patient remains safe.
    """
    return run_scenario(
        max_cob=MAX_CLAMPED_COB,
        scenario_label="With Clamp",
    )


# =============================================================================
# Simulation engine
# =============================================================================

def run_scenario(max_cob: float, scenario_label: str) -> dict:
    """
    Simulate 6 hours of patient glucose for a single COB clamping configuration.

    At CARB_EVENT_STEP the patient eats REAL_MEAL_GRAMS (via the scenario)
    and simultaneously receives an insulin bolus computed from CARB_AMOUNT_GRAMS
    clamped to max_cob. All other steps receive only the background basal rate.

    Returns a dict with keys: times, cgm, meals, basal_rates, bolus_rates,
    bolus_given, effective_cob.
    """
    patient = T1DPatient.withName(PATIENT_NAME)
    environment = build_simulation_environment(patient, REAL_MEAL_GRAMS)
    profile = build_patient_profile(max_cob)
    body_weight = patient._params.BW

    start_time = datetime(2018, 1, 1, 0, 0, 0)
    initial_step, _, _, _ = environment.reset()

    times = []
    cgm_readings = []
    meals = []
    basal_rates = []
    bolus_rates = []
    bolus_given = 0.0
    effective_cob = 0.0

    for step_index in range(1, SIMULATION_STEPS + 1):
        action = build_basal_action()

        if step_index == CARB_EVENT_STEP:
            current_cgm = cgm_readings[-1] if cgm_readings else initial_step.CGM
            action, bolus_given, effective_cob = build_bolus_action(
                current_cgm=current_cgm,
                patient=patient,
                body_weight=body_weight,
                profile=profile,
            )

        observation, _, done, info = environment.step(action)
        times.append(start_time + timedelta(minutes=step_index * SAMPLE_TIME_MINUTES))
        cgm_readings.append(observation.CGM)
        meals.append(info["meal"])
        basal_rates.append(action.basal)
        bolus_rates.append(action.bolus)

        if done:
            print(f"  [{scenario_label}] Simulation ended early at step {step_index} "
                  f"({step_index * SAMPLE_TIME_MINUTES} min) -- "
                  f"CGM={observation.CGM:.1f} mg/dL is out of safe range.")
            break

    return {
        "times": times,
        "cgm": cgm_readings,
        "meals": meals,
        "basal_rates": basal_rates,
        "bolus_rates": bolus_rates,
        "bolus_given": bolus_given,
        "effective_cob": effective_cob,
    }


def build_bolus_action(
    current_cgm: float,
    patient: T1DPatient,
    body_weight: float,
    profile: PatientProfile,
):
    """
    Compute the insulin dosing result at the carb event step and return
    the corresponding Action plus summary values for reporting.
    """
    iob = calculate_iob_from_state(patient.state, body_weight)
    dosing_result = calculate_insulin_dosage(
        glucose=current_cgm,
        iob_units=iob,
        carbs=CARB_AMOUNT_GRAMS,
        profile=profile,
    )
    bolus_rate_per_minute = dosing_result.bolus_total_units / SAMPLE_TIME_MINUTES
    action = Action(basal=BASELINE_BASAL_RATE, bolus=bolus_rate_per_minute)
    return action, dosing_result.bolus_total_units, dosing_result.effective_cob


def build_basal_action() -> Action:
    """Return a basal-only action with zero bolus."""
    return Action(basal=BASELINE_BASAL_RATE, bolus=0.0)


# =============================================================================
# Environment and profile setup
# =============================================================================

def build_simulation_environment(patient: T1DPatient, real_meal_grams: float) -> T1DSimEnv:
    """
    Construct the simglucose environment.

    The scenario schedules the patient's actual meal (real_meal_grams) at the
    carb event time. The insulin bolus is delivered separately via Action.
    """
    start_time = datetime(2018, 1, 1, 0, 0, 0)
    sensor = CGMSensor.withName("Dexcom", seed=0)
    pump = InsulinPump.withName("Insulet")
    meal_scenario = CustomScenario(
        start_time=start_time,
        scenario=[(_MEAL_DELIVERY_TIME_HOURS, real_meal_grams)],
    )
    return T1DSimEnv(patient, sensor, pump, meal_scenario)


def build_patient_profile(max_cob: float) -> PatientProfile:
    """Build the patient dosing profile with the given max_cob limit."""
    return PatientProfile(
        max_cob=max_cob,
        carb_ratio=CARB_RATIO,
        correction_factor=CORRECTION_FACTOR,
        target_glucose=TARGET_GLUCOSE,
        correction_threshold=CORRECTION_THRESHOLD,
    )


# =============================================================================
# Plotting
# =============================================================================

def plot_results(results_no_clamp: dict, results_with_clamp: dict) -> None:
    """
    Plot both CGM traces on a single figure and save to PNG.

    Visual elements:
      - Red line:  no-clamp scenario (dangerous)
      - Blue line: clamped scenario (safe)
      - Vertical dashed line at the carb/meal event
      - Green shaded band for target glucose range (70-180 mg/dL)
      - Horizontal reference lines at 70 and 54 mg/dL (hypo thresholds)
    """
    fig, ax = plt.subplots(figsize=(12, 6))

    carb_event_time_minutes = CARB_EVENT_STEP * SAMPLE_TIME_MINUTES

    # Target range band
    ax.axhspan(70, 180, alpha=0.15, color="green", label="Target range (70-180 mg/dL)")

    # Hypoglycemia threshold lines
    ax.axhline(70, color="orange", linestyle="--", linewidth=1.2, label="Hypo threshold (70 mg/dL)")
    ax.axhline(54, color="red", linestyle="--", linewidth=1.2, label="Severe hypo threshold (54 mg/dL)")

    # Carb/meal event marker
    ax.axvline(
        carb_event_time_minutes,
        color="gray",
        linestyle="--",
        linewidth=1.5,
        label=f"Meal + bolus event ({carb_event_time_minutes} min)",
    )

    # Convert datetime times to elapsed minutes for the X-axis
    sim_start = datetime(2018, 1, 1, 0, 0, 0)
    def to_minutes(times):
        return [(t - sim_start).total_seconds() / 60 for t in times]

    # CGM traces
    ax.plot(
        to_minutes(results_no_clamp["times"]),
        results_no_clamp["cgm"],
        color="red",
        linewidth=2,
        label=(
            f"No Clamp  | dosed for {results_no_clamp['effective_cob']:.0f}g "
            f"(requested {results_no_clamp['bolus_given']:.1f}U)"
        ),
    )
    ax.plot(
        to_minutes(results_with_clamp["times"]),
        results_with_clamp["cgm"],
        color="blue",
        linewidth=2,
        label=(
            f"With Clamp | dosed for {results_with_clamp['effective_cob']:.0f}g "
            f"(requested {results_with_clamp['bolus_given']:.1f}U)"
        ),
    )

    ax.set_xlabel("Time (minutes)", fontsize=12)
    ax.set_ylabel("CGM (mg/dL)", fontsize=12)
    ax.set_title(
        f"Trio COB Clamping Safety Feature — {PATIENT_NAME}\n"
        f"App entry: {CARB_AMOUNT_GRAMS}g  |  Real meal: {REAL_MEAL_GRAMS}g  "
        f"|  Clamp limit: {MAX_CLAMPED_COB}g",
        fontsize=13,
    )
    ax.legend(loc="upper right", fontsize=9)
    ax.set_xlim(left=0)
    ax.grid(True, alpha=0.3)

    output_path = os.path.join(os.path.dirname(__file__), "clamping_simulation_results.png")
    fig.savefig(output_path, dpi=150, bbox_inches="tight")
    print(f"\nPlot saved to: {output_path}")
    plt.close(fig)


# =============================================================================
# CSV export
# =============================================================================

def save_results_to_csv(results: dict, filename: str) -> None:
    """
    Write simulation results to a CSV file matching the format of
    simulator/sim_results_summary.csv.

    Columns: (index), Time, CGM, Meal, Insulin_Basal, Insulin_Bolus
    """
    output_path = os.path.join(os.path.dirname(__file__), filename)
    with open(output_path, "w", newline="") as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(["", "Time", "CGM", "Meal", "Insulin_Basal", "Insulin_Bolus"])
        for row_index, (time, cgm, meal, basal, bolus) in enumerate(zip(
            results["times"],
            results["cgm"],
            results["meals"],
            results["basal_rates"],
            results["bolus_rates"],
        )):
            writer.writerow([row_index, time.strftime("%Y-%m-%d %H:%M:%S"), cgm, meal, basal, bolus])
    print(f"CSV saved to:  {output_path}")


# =============================================================================
# Summary reporting
# =============================================================================

def print_scenario_summary(label: str, results: dict) -> None:
    """Print a one-line summary of key simulation outcomes."""
    min_cgm = min(results["cgm"])
    final_cgm = results["cgm"][-1]
    print(
        f"  {label:<15} | "
        f"Effective COB: {results['effective_cob']:>8.1f}g | "
        f"Bolus requested: {results['bolus_given']:>7.1f}U | "
        f"Min CGM: {min_cgm:>6.1f} mg/dL | "
        f"Final CGM: {final_cgm:>6.1f} mg/dL"
    )


# =============================================================================
# Entry point
# =============================================================================

if __name__ == "__main__":
    print("=" * 70)
    print(f"Trio COB Clamping Simulation — Patient: {PATIENT_NAME}")
    print(f"App carb entry:  {CARB_AMOUNT_GRAMS} g  (erroneous)")
    print(f"Real meal:       {REAL_MEAL_GRAMS} g")
    print(f"Clamp limit:     {MAX_CLAMPED_COB} g")
    print(f"Duration:        {SIMULATION_STEPS} steps × {SAMPLE_TIME_MINUTES} min = "
          f"{SIMULATION_STEPS * SAMPLE_TIME_MINUTES // 60} hours")
    print(f"Meal + bolus at: step {CARB_EVENT_STEP} ({CARB_EVENT_STEP * SAMPLE_TIME_MINUTES} min)")
    print("=" * 70)

    print("\nRunning Scenario 1: No Clamp ...")
    results_no_clamp = run_no_clamp_scenario()

    print("\nRunning Scenario 2: With Clamp ...")
    results_with_clamp = run_clamped_scenario()

    print("\n--- Results Summary ---")
    print_scenario_summary("No Clamp", results_no_clamp)
    print_scenario_summary("With Clamp", results_with_clamp)

    print("\nSaving CSVs ...")
    save_results_to_csv(results_no_clamp, "no_clamp_sim_results.csv")
    save_results_to_csv(results_with_clamp, "with_clamp_sim_results.csv")

    print("\nGenerating plot ...")
    plot_results(results_no_clamp, results_with_clamp)
