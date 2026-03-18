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

It has also thought through how the algorithm in Trio should be ported over to Python at porting_to_python_guideline.md
</progress-so-far>

<objective>
Write guidelines for another LLM agent who will be integrating the ported algorithm with the glucose simulator.

The other LLM will write the following tools
 - An interface where a carb amount can be physically inputted, and a max clamp amount can be set
 - A tool that takes in the carb and clamp amount and passes it through the python port of the insulin algorithm for trio. It should provide up all the metrics that the python port requires to get the insulin outputl. For these metrics, it should use the values that the simulator is at (cgm, ins on board, meal) at the 30% mark of the simulator. It should mock up the rest of the values that it cannot get from the simulator with reasonable "default" values. So it should first run the simulator up to the 30%, get values, and feed it into the ported algorithm.

- Once it gets the insulin output from the ported algorithm, the dosages should be applied to the simualtor at the 30% mark, and the rest of the simulation should run.

- Once simulation is done, it should plot a CGM vs time graph with a marker denoting where the insulin dosage was.


</objective>

<instructions>
Create guidelines for the integration process, citing which files the other LLM agent should reference. 
Make it clear that the integration will take in one insulin (basal and bolus) and apply it once in the simulator. I just need to see what the effects of the clamp for one insulin dosage. This dosing time should be at the 30% mark of the simulation. This is so that people can see what the baseline CGM looks like before they see the effects of an insulin dosage at the 30% mark.
</instructions>

<constraints>
Read a few relevant files at a time. Reading everything at once will lead to you running out of tokens.

Try to ask 2-3 clarifying questions at the start to make sure eveything is clear for you.
</constraints>

<output>
Detail answers at a new document called @porting_details.md inside the glucose_simulator/tasks dir
</output>
