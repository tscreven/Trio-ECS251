<context>
I am working on a project with a classmate. His job has been to make modifications to the swift app Trio. Trio is an app for automating insulin delivery. He has been working on integrating a lot of features.

I have been tasked with demonstrating one of Trio's key components for safety: the clamp function. Clamping is a safety mechanism in Trio that doesn't take in a reported carbohydrated amount at face value. It has its own mechanisms for "clamping" down how many carbs has been reported. This is because a very high carb count will result in a lot of insulin being dosed, which can be dangerous.

Here is an example: Say trio has a food scanning feature that estimates carbs. Say it mistook cheese for a cheeseburger and inputted a great amount. The clamp would catch this and dose a safe amount of insulin.

My task is to use the glucose simulator at glucose_simulator to show that clamping works. Here is what I will demonstrate:

Scenario A: I input 10000 carbs => There is no clamp => A great amount of insulin is dosed, and the virtual human is in danger

Scenario B: I input 10000 carbs => Clamp exist=> The right amount of insulin is dosed, and the human is safe.

I want to show Scenarios A and B side by side in a plotted out graph to show Trio working in action.
</context>

<instructions>
Before we get started on this task, we first need to do some code exploration

The swift algorithms from going to carb -> clamp -> insulin dosage needs to be ported over to Python. Find where this algorithmic step and explain how trio goes fro, carb to insulin doses. All I need is an interface that I input a carb amount manually and have it go through the exact same algorithm as trio to arrive at an insulin dosage.
</objective>



<reference>
openaps.swift 
apsmanager 
item.swift
</reference>

<output>
An trio_clamping_alg_explanatiion.md that details how the carb to insulin dosage pipeline works in trio. Name which functions and classes in which files are involved. The goal is that another agent should be able to read your details and get to work in porting the algorithm to swift
</output>