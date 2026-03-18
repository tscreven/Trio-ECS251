<context>
I am working on a project with a classmate. His job has been to make modifications to the swift app Trio. Trio is an app for automating insulin delivery. He has been working on integrating a lot of features.

I have been tasked with demonstrating one of Trio's key components for safety: the clamp function. Clamping is a safety mechanism in Trio that doesn't take in a reported carbohydrated amount at face value. It has its own mechanisms for "clamping" down how many carbs has been reported. This is because a very high carb count will result in a lot of insulin being dosed, which can be dangerous.

Here is an example: Say trio has a food scanning feature that estimates carbs. Say it mistook cheese for a cheeseburger and inputted a great amount. The clamp would catch this and dose a safe amount of insulin.

My task is to use the glucose simulator at glucose_simulator to show that clamping works. Here is what I will demonstrate:

Scenario A: I input 10000 carbs => There is no clamp => A great amount of insulin is dosed, and the virtual human is in danger

Scenario B: I input 10000 carbs => Clamp exist=> The right amount of insulin is dosed, and the human is safe.

I want to show Scenarios A and B side by side in a plotted out graph to show Trio working in action.
</context>

<progress-so-far>
Another LLM has assessed how the trio swift algo goes from carbs to insulin dosages. 
It can be read @trio_clampining_alg_explanation.md
</progress-so-far>

<instructions>
Now we need to come up with a plan for how we should port over the trio algorithm into python so that we can simulate a big carb dose getting clamped for the glucose simulator which can be found @run_simulation.py

I have some questions:

- Is the carb to insulin pipeline dependent on any other metrics such as IoB? If so, for my simulation, do I need to mock up those values to get a valid insulin dosage?
- Anything else I should consider when porting over the swift algorithm into python to be used for the demo of the clamp using the simulator?
  </instructions>

<constraints>
Read a few relevant files at a time. Reading everything at once will lead to you running out of tokens.
</constraints>

<output>
Detail answers at a new document called @porting_details.md inside the glucose_simulator/tasks dir
</output>
