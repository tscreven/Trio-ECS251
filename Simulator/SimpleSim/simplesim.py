#!/usr/bin/env python3

import argparse
import csv
import json
import math
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from exponential_insulin_model import ExponentialInsulinModel


def parse_args():
    parser = argparse.ArgumentParser(description="SimpleSim - virtual human glucose simulator")
    parser.add_argument("-u", required=True, help="Virtual user directory path")
    parser.add_argument("-i", required=True, choices=["humalog", "lyumjev"], help="Insulin type")
    parser.add_argument("-g", type=float, help="Initial glucose concentration (mg/dL)")
    parser.add_argument("-n", type=int, help="Number of 5-minute simulation steps")
    parser.add_argument("-f", action="store_true", help="Enable low pass filtering on glucose")
    parser.add_argument("-a", help="Added glucose CSV file for trace replay")
    args = parser.parse_args()
    if args.a is None and (args.g is None or args.n is None):
        parser.error("-g and -n are required unless -a is provided")
    return args


def load_added_glucose_csv(path):
    timestamps = []
    added_glucose_values = []
    initial_glucose = None
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Parse UTC timestamp and convert to local timezone
            dt = datetime.fromisoformat(row["time"]).astimezone()
            timestamps.append(dt)
            added_glucose_values.append(float(row["addedGlucose"]))
            if initial_glucose is None:
                initial_glucose = float(row["glucose"])
    return timestamps, initial_glucose, added_glucose_values


OREF_SWIFT_BINARY = ".build/arm64-apple-macosx/debug/oref-swift"


def initialize(virtual_user):
    result = subprocess.run(
        [OREF_SWIFT_BINARY, "initialize", "-u", virtual_user, "-o", "-"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"Error initializing: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    output = json.loads(result.stdout)
    return output["stateDir"]


def load_basal_profile(state_dir):
    with open(f"{state_dir}/basal_profile.json") as f:
        return json.load(f)


def load_insulin_sensitivities(state_dir):
    with open(f"{state_dir}/insulin_sensitivities.json") as f:
        data = json.load(f)
    return data["sensitivities"]


def minutes_of_day(dt):
    return dt.hour * 60 + dt.minute


def lookup_basal_rate(basal_profile, dt):
    mod = minutes_of_day(dt)
    active = basal_profile[0]
    for entry in basal_profile:
        if entry["minutes"] <= mod:
            active = entry
    return active["rate"]


def lookup_isf(sensitivities, dt):
    mod = minutes_of_day(dt)
    active = sensitivities[0]
    for entry in sensitivities:
        if entry["offset"] <= mod:
            active = entry
    return active["sensitivity"]


def calculate(state_dir, timestamp, glucose):
    input_data = json.dumps({"timestamp": timestamp, "glucose": glucose})
    result = subprocess.run(
        [OREF_SWIFT_BINARY, "calculate", "-s", state_dir, "-i", "-", "-o", "-"],
        input=input_data, capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"Error calculating: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def simulate_step(state_dir, basal_profile, t, glucose, pump_temp_basal, determination):
    """Process a single simulation step: handle insulin dosing from determination.
    Returns (five_min_insulin, pump_temp_basal)."""
    five_min_insulin = 0.0

    # Handle SMB bolus
    bolus_units = determination.get("units")
    if bolus_units is not None and bolus_units > 0:
        five_min_insulin += bolus_units

    # Handle temp basal state machine
    det_rate = determination.get("rate")
    det_duration = determination.get("duration")

    if det_rate is not None and det_duration is not None:
        if det_rate == 0 and det_duration == 0:
            pump_temp_basal = None
        else:
            pump_temp_basal = {"rate": det_rate, "remaining_minutes": det_duration}

    # Determine basal rate for this 5-min period
    if pump_temp_basal is not None:
        active_rate = pump_temp_basal["rate"]
    else:
        active_rate = lookup_basal_rate(basal_profile, t)

    five_min_insulin += active_rate / 12.0

    # Decrement temp basal remaining time
    if pump_temp_basal is not None:
        pump_temp_basal["remaining_minutes"] -= 5
        if pump_temp_basal["remaining_minutes"] <= 0:
            pump_temp_basal = None

    return five_min_insulin, pump_temp_basal


LOW_PASS_TAU = 11.3  # minutes


def low_pass_filter(raw_glucose, prev_filtered, delta_minutes):
    """Apply time-aware IIR low-pass filter to a glucose reading.
    Returns the filtered glucose value."""
    alpha = 1 - math.exp(-delta_minutes / LOW_PASS_TAU)
    return alpha * raw_glucose + (1 - alpha) * prev_filtered


def compute_insulin_action(model, insulin_deliveries, t):
    """Sum insulin action from all deliveries in the last 10 hours."""
    cutoff = t - timedelta(hours=10)
    total = 0.0
    for delivery_time, units in insulin_deliveries:
        if delivery_time < cutoff:
            continue
        t_minus_one_secs = (t - timedelta(minutes=5) - delivery_time).total_seconds()
        t_secs = (t - delivery_time).total_seconds()
        pct_at_t_minus_one = model.percent_effect_remaining(t_minus_one_secs)
        pct_at_t = model.percent_effect_remaining(t_secs)
        total += (pct_at_t_minus_one - pct_at_t) * units
    return total


def main():
    args = parse_args()
    sys.stdout.reconfigure(line_buffering=True)

    if args.i == "humalog":
        model = ExponentialInsulinModel.humalog()
    else:
        model = ExponentialInsulinModel.lyumjev()

    state_dir = initialize(args.u)
    basal_profile = load_basal_profile(state_dir)
    sensitivities = load_insulin_sensitivities(state_dir)

    insulin_deliveries = []  # list of (datetime, units)
    pump_temp_basal = None

    print("time,glucose,insulin")

    filtered_glucose = None
    prev_t = None

    if args.a is not None:
        # Replay added glucose trace
        timestamps, glucose, added_glucose_values = load_added_glucose_csv(args.a)
        num_steps = len(timestamps)

        for step in range(num_steps):
            t = timestamps[step]

            algo_glucose = glucose
            if args.f:
                if filtered_glucose is None:
                    filtered_glucose = glucose
                else:
                    delta_minutes = (t - prev_t).total_seconds() / 60.0
                    filtered_glucose = low_pass_filter(glucose, filtered_glucose, delta_minutes)
                algo_glucose = filtered_glucose
            prev_t = t

            determination = calculate(state_dir, t.timestamp(), algo_glucose)

            five_min_insulin, pump_temp_basal = simulate_step(
                state_dir, basal_profile, t, glucose, pump_temp_basal, determination
            )
            insulin_deliveries.append((t, five_min_insulin))

            print(f"{t.isoformat()},{glucose:.1f},{five_min_insulin:.4f}")

            if step < num_steps - 1:
                t_next = timestamps[step + 1]
                isf = lookup_isf(sensitivities, t_next)
                total_insulin_action = compute_insulin_action(model, insulin_deliveries, t_next)
                glucose = max(40, min(400, glucose - total_insulin_action * isf + added_glucose_values[step + 1]))
    else:
        # Original simulation mode
        t = datetime.now()
        glucose = args.g

        for step in range(args.n):
            algo_glucose = glucose
            if args.f:
                if filtered_glucose is None:
                    filtered_glucose = glucose
                else:
                    delta_minutes = (t - prev_t).total_seconds() / 60.0
                    filtered_glucose = low_pass_filter(glucose, filtered_glucose, delta_minutes)
                algo_glucose = filtered_glucose
            prev_t = t

            determination = calculate(state_dir, t.timestamp(), algo_glucose)

            five_min_insulin, pump_temp_basal = simulate_step(
                state_dir, basal_profile, t, glucose, pump_temp_basal, determination
            )
            insulin_deliveries.append((t, five_min_insulin))

            print(f"{t.isoformat()},{glucose:.1f},{five_min_insulin:.4f}")

            t = t + timedelta(minutes=5)

            scheduled_basal = lookup_basal_rate(basal_profile, t)
            isf = lookup_isf(sensitivities, t)
            basal_glucose = scheduled_basal * isf / 12.0
            total_insulin_action = compute_insulin_action(model, insulin_deliveries, t)

            glucose = max(40, min(400, glucose - total_insulin_action * isf + basal_glucose))


if __name__ == "__main__":
    main()
