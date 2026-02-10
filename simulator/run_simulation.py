import logging
import pandas as pd
from datetime import timedelta, datetime
from simglucose.simulation.env import T1DSimEnv
from simglucose.controller.base import Controller, Action
from simglucose.sensor.cgm import CGMSensor
from simglucose.actuator.pump import InsulinPump
from simglucose.patient.t1dpatient import T1DPatient
from simglucose.simulation.scenario_gen import RandomScenario

# Configure logging to avoid console spam
logging.basicConfig(level=logging.INFO)

class SafetyBasalController(Controller):
    def __init__(self, init_state):
        self.init_state = init_state

    def policy(self, observation, reward, done, **kwargs):
        # OBSERVE
        bg = observation.CGM
        meal = kwargs.get('meal', 0)

        # DECIDE (Simple Logic)
        # Basal: 0.05 U/min (approx 3 Units/hour)
        # Bolus: If carb intake > 0, give small bolus

        action_basal = 0.05
        action_bolus = 0.0

        if meal > 0:
            action_bolus = 1.0  # Conservative fixed bolus
            print(f"   [EVENT] Meal Detected: {meal}g. Bolusing {action_bolus}U")

        # SAFETY CHECK (The "Do Not Kill Patient" Guardrail)
        if bg < 70:
            action_basal = 0.0 # Suspend pump
            print(f"   [ALERT] Low Glucose ({bg} mg/dL). Suspending Basal.")

        return Action(basal=action_basal, bolus=action_bolus)

def run_headless_sim():
    # 1. Setup Patient and Hardware
    p_name = 'adolescent#003'
    patient = T1DPatient.withName(p_name)
    sensor = CGMSensor.withName('Dexcom', seed=1)
    pump = InsulinPump.withName('Insulet')

    # 2. Setup Scenario (24 Hours)
    start_time = datetime(2024, 1, 1, 0, 0, 0)
    scenario = RandomScenario(start_time=start_time, seed=1)

    # 3. Create Environment
    env = T1DSimEnv(patient, sensor, pump, scenario)

    # 4. Initialize Controller
    controller = SafetyBasalController(init_state=0)

    # 5. Run Simulation (manually stepping through the env for headless operation)
    print(f"Starting 24-hour simulation for {p_name}...")

    # Simulation: 24 hours = 1440 minutes, env steps in 1-min increments
    sim_steps = 1440
    obs, reward, done, info = env.reset()
    records = []

    for step in range(sim_steps):
        meal = info.get('meal', 0)
        action = controller.policy(obs, reward, done, meal=meal)
        obs, reward, done, info = env.step(action)
        records.append({
            'Time': info.get('time', step),
            'CGM': obs.CGM,
            'Meal': info.get('meal', 0),
            'Insulin_Basal': action.basal,
            'Insulin_Bolus': action.bolus
        })
        if done:
            break

    results = pd.DataFrame(records)

    # 6. Validate Results
    mean_bg = results['CGM'].mean()
    min_bg = results['CGM'].min()
    max_bg = results['CGM'].max()

    print("-" * 30)
    print("SIMULATION REPORT")
    print(f"Mean Glucose: {mean_bg:.1f} mg/dL")
    print(f"Min Glucose:  {min_bg:.1f} mg/dL")
    print(f"Max Glucose:  {max_bg:.1f} mg/dL")
    print("-" * 30)

    # Save CSV manually to confirm file write access
    results.to_csv('sim_results_summary.csv')
    print("Results saved to 'sim_results_summary.csv'")

if __name__ == "__main__":
    run_headless_sim()
