You are an expert Python DevOps agent. Your goal is to set up a simulation environment for Type 1 Diabetes insulin dosing using the 'simglucose' library.

Follow these steps sequentially. Do not skip validation checks.

STEP 1: ENVIRONMENT SETUP
1. Create a new Python virtual environment named 'venv_simglucose' in the current directory.
2. Activate the virtual environment.
3. Install the required libraries:
   - pip install simglucose pandas numpy

STEP 2: CREATE THE SIMULATION SCRIPT
Create a file named 'run_simulation.py' in the current directory. Write the exact code block below into the file. This script is designed to run HEADLESS (no GUI popups) to ensure it does not hang your terminal.

'''python
import logging
from datetime import timedelta, datetime
from simglucose.simulation.env import T1DSimEnv
from simglucose.controller.base import Controller, Action
from simglucose.sensor.cgm import CGMSensor
from simglucose.actuator.pump import InsulinPump
from simglucose.patient.t1dpatient import T1DPatient
from simglucose.simulation.scenario_gen import RandomScenario
from simglucose.simulation.user_interface import simulate

# Configure logging to avoid console spam
logging.basicConfig(level=logging.INFO)

class SafetyBasalController(Controller):
    def __init__(self, init_state):
        self.init_state = init_state

    def policy(self, observation, reward, done, **kwargs):
        # OBSERVE
        bg = observation.CGM
        
        # DECIDE (Simple Logic)
        # Basal: 0.05 U/min (approx 3 Units/hour)
        # Bolus: If carb intake > 0, give small bolus
        
        action_basal = 0.05 
        action_bolus = 0.0
        
        if observation.CHO > 0:
            action_bolus = 1.0  # Conservative fixed bolus
            print(f"   [EVENT] Meal Detected: {observation.CHO}g. Bolusing {action_bolus}U")

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
    pump = InsulinPump.withName('Insulet', seed=1)
    
    # 2. Setup Scenario (24 Hours)
    start_time = datetime(2024, 1, 1, 0, 0, 0)
    scenario = RandomScenario(start_time=start_time, seed=1)
    
    # 3. Create Environment
    env = T1DSimEnv(patient, sensor, pump, scenario)
    
    # 4. Initialize Controller
    controller = SafetyBasalController(init_state=0)
    
    # 5. Run Simulation
    print(f"Starting 24-hour simulation for {p_name}...")
    results = simulate(env, controller, sim_time=timedelta(days=1))
    
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
'''

STEP 3: EXECUTE AND VERIFY
1. Run the script using the python executable from the virtual environment: `python run_simulation.py`
2. If the script runs successfully, it will print a "SIMULATION REPORT".
3. Verify that the file 'sim_results_summary.csv' exists.

STEP 4: REPORT
If the simulation finishes and the CSV is generated, report "SUCCESS: Simglucose environment is active and validated." If there are errors, report the specific Python traceback.
