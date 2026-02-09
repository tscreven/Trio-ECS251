# Trio Third Party Feature Integration

Goal: allow third-party applications to compute carbohydrate estimates without
modifying Trio’s insulin dosing logic.

It does not matter how these apps derive the number of carbohydrates. The carbs
calculation happens entirely out of the purview of Trio.

## Data sharing Model
Trio collects the carbohydrate data from a shared JSON file in the shared App
Group container URL. Third-party apps will write to this file, Trio reads the
file.

Trio is responsible only for:
- reading carbohydrate data results from JSON -> memory

Trio is NOT responsible for:
- carbohydrate calculation logic

### Shared JSON Schema (Example)

```json
{
  "timestamp": "ISO-8601 string",
  "carbohydrates_grams": 45.0,
  "source": "third-party-app-id"
}
```

## Setup Assumptions
- An App Group entitlement exists and is functional
- The shared container URL is available at runtime
- Make no UI changes
- Make no changes to the insulin dosing algorithm.

