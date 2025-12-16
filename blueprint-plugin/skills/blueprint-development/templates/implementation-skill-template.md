---
name: implementation-guides
description: "Step-by-step guides for implementing specific feature types in [PROJECT_NAME]. Provides patterns for APIs, UI, data access, and integrations."
---

# Implementation Guides

## API Endpoint Implementation

### Step-by-Step Pattern

#### Step 1: Write Integration Test (RED)
```[language]
describe('[HTTP_METHOD] [endpoint_path]', () => {
  it('should [expected behavior] when [valid input]', async () => {
    const response = await request(app)
      .[method]('[endpoint]')
      .send([request_body]);

    expect(response.status).toBe([expected_status]);
    expect(response.body).toMatchObject([expected_shape]);
  });
});
```

**Run**: `[test_command]`
**Expected**: **FAIL** (endpoint doesn't exist yet)

#### Step 2: Create Route (GREEN)
```[language]
// [routes_file_path]
router.[method]('[path]', [controller].[method]);
```

#### Step 3: Implement Controller (GREEN)
```[language]
// [controllers_file_path]
async [methodName](req, res, next) {
  try {
    const [input] = req.[body/params/query];
    const [result] = await this.[service].[method]([input]);
    res.status([status]).json([result]);
  } catch (error) {
    next(error);
  }
}
```

#### Step 4: Implement Service Logic (GREEN)
```[language]
// [services_file_path]
async [methodName]([params]) {
  // Business logic implementation
  [implementation]
  return [result];
}
```

**Run**: `[test_command]`
**Expected**: **PASS**

#### Step 5: Refactor
- Extract magic numbers to constants
- Improve error handling
- Add input validation
- Optimize database queries

**Run**: `[test_command]`
**Expected**: **STILL PASS**

### Error Handling in APIs
```[language]
// Pattern for API error handling
[ERROR_HANDLING_EXAMPLE]
```

### Input Validation
```[language]
// Pattern for input validation
[VALIDATION_EXAMPLE]
```

## [Feature Type 2: e.g., UI Component Implementation]

### Step-by-Step Pattern

[SIMILAR STRUCTURE FOR OTHER FEATURE TYPES]

## Database Operations

### Creating Records
```[language]
// Create pattern
[CREATE_EXAMPLE]
```

### Reading Records
```[language]
// Read pattern
[READ_EXAMPLE]
```

### Updating Records
```[language]
// Update pattern
[UPDATE_EXAMPLE]
```

### Deleting Records
```[language]
// Delete pattern
[DELETE_EXAMPLE]
```

### Transactions
```[language]
// Transaction pattern
[TRANSACTION_EXAMPLE]
```

## External Service Integration

### Adapter Pattern
```[language]
// Service adapter pattern
[ADAPTER_EXAMPLE]
```

### Error Handling
- Timeout handling
- Retry logic
- Circuit breaker pattern
- Fallback strategies

## Background Jobs

[If applicable to project]

### Job Definition
```[language]
// Job pattern
[JOB_EXAMPLE]
```

### Scheduling
```[language]
// Schedule pattern
[SCHEDULE_EXAMPLE]
```

## Common Implementation Patterns

### Pattern 1: [Name]
**When to use**: [Scenario]
**Implementation**: [Code example]

### Pattern 2: [Name]
**When to use**: [Scenario]
**Implementation**: [Code example]

## References

- [Link to PRD implementation sections]
- [Link to architecture patterns skill]
- [Link to testing strategies skill]
