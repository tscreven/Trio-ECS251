"""
Simplified port of Trio's COB clamping and insulin dosing logic.

Source reference: trio-oref/lib/meal/total.js ~line 120
The core safety feature is clamp_cob(), which prevents dangerously large
insulin doses when a patient enters an erroneous carb amount.
"""

from dataclasses import dataclass
from typing import NamedTuple


@dataclass
class PatientProfile:
    """Insulin dosing parameters for a specific patient."""
    max_cob: float              # Maximum allowed Carbs on Board (g)
    carb_ratio: float           # Grams of carbs per unit of insulin (g/U)
    correction_factor: float    # Blood glucose drop per unit of insulin (mg/dL per U)
    target_glucose: float       # Target blood glucose level (mg/dL)
    correction_threshold: float # Glucose must exceed this before a correction is given (mg/dL)


class DosingResult(NamedTuple):
    """Result of an insulin dosage calculation."""
    bolus_total_units: float    # Final bolus to deliver (U), after IOB subtraction
    effective_cob: float        # Carbs on Board after clamping (g)
    carb_bolus: float           # Insulin needed to cover effective COB (U)
    correction_bolus: float     # Insulin needed to correct high glucose (U)
    iob_adjustment: float       # Insulin on Board subtracted from the dose (U)


def clamp_cob(carbs: float, max_cob: float) -> float:
    """
    Clamp carbs to a safe maximum value.

    Port of trio-oref/lib/meal/total.js ~line 120.
    Prevents runaway insulin doses from erroneous carb entries.
    """
    return min(max_cob, carbs)


def calculate_iob_from_state(patient_state, body_weight: float) -> float:
    """
    Estimate Insulin on Board (U) from the patient ODE state vector.

    state[10] = isc1: first subcutaneous insulin compartment (pmol/kg)
    state[11] = isc2: second subcutaneous insulin compartment (pmol/kg)

    Conversion: pmol/kg * kg / 6000 pmol/U = U
    """
    subcutaneous_insulin_pmol_per_kg = patient_state[10] + patient_state[11]
    return subcutaneous_insulin_pmol_per_kg * body_weight / 6000.0


def calculate_insulin_dosage(
    glucose: float,
    iob_units: float,
    carbs: float,
    profile: PatientProfile,
) -> DosingResult:
    """
    Calculate the insulin bolus required to cover a carb event and correct glucose.

    Steps:
      1. Clamp COB to profile.max_cob to prevent dangerous overdose.
      2. Compute carb bolus from clamped COB and carb ratio.
      3. Compute correction bolus if glucose exceeds the correction threshold.
      4. Subtract IOB so we do not stack insulin already in the body.
    """
    effective_cob = clamp_cob(carbs, profile.max_cob)

    carb_bolus = effective_cob / profile.carb_ratio

    glucose_requires_correction = glucose > profile.correction_threshold
    if glucose_requires_correction:
        correction_bolus = max(0.0, (glucose - profile.target_glucose) / profile.correction_factor)
    else:
        correction_bolus = 0.0

    total_bolus = max(0.0, carb_bolus + correction_bolus - iob_units)

    return DosingResult(
        bolus_total_units=total_bolus,
        effective_cob=effective_cob,
        carb_bolus=carb_bolus,
        correction_bolus=correction_bolus,
        iob_adjustment=iob_units,
    )
