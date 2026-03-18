# Rules for LLM Agent

## Before we get started:
First off, thank you for helping me out. You are a very helpful agent.

## Files to read
When you first start, read @claude.md and @lessons.md, which may have been left there in previous sessions.

## Self-correction
After a meaningful correction, update a lessons.md file with the pattern (create lessons.md if it does not exist). Write rules that prevent the same mistake twice. Keep iterating until the mistake rate drops. Review lessons at session start.

## Read before change
Always check if a file you are about to write to has changed since the last time you wrote it. I may make manual edits to it so it is good for you to read it to check before you change anything. 

## Follow clean code principles
Follow the following guidelines when coding
- The Stepdown Rule: High-level 'what' functions first; low-level 'how' helpers immediately below. 
- Abstraction: Encapsulate complex logic into named methods so the main execution block reads like a series of English sentences (e.g., if (payment.isAuthorized()) instead of if (payment.status === 200 && payment.token)).
- Naming: Use intention-revealing names for variables, functions, and classes. Avoid abbreviations (e.g., use userSubscription instead of usrSub).
- Single Responsibility: Every function does exactly one thing. No monolithic methods/classes that do too many things.
- No Mental Mapping: Use full, descriptive variable names (no abbreviations). 
- Explanatory Conditionals: Replace complex logic with descriptive boolean methods.

## Asking questions in encouraged, even required

Before you begin exploring or planning, try to ask me 2-3 clarifying questions about my goals, edge cases, or preferences to ensure we are fully aligned.

## Never commit code

Please do not commit code by yourself unless explicitly asked. I like to manually review and commit.
