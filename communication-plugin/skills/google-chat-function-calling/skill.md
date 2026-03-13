---
model: sonnet
created: 2026-03-13
modified: 2026-03-13
reviewed: 2026-03-13
name: google-chat-function-calling
description: |
  Implement Gemini function calling for Google Chat bots. Use when building
  Google Chat bots that need to call external APIs, when integrating Vertex AI
  or Google AI function calling into chat workflows, or when designing function
  declarations for Gemini-powered chat applications.
user-invocable: false
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Google Chat Function Calling

Expert knowledge for implementing Gemini function calling in Google Chat bot applications. Covers function declaration design, execution flow orchestration, and integration with both Google AI and Vertex AI SDKs.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Building a Google Chat bot with Gemini function calling | Formatting messages for Google Chat → `google-chat-formatting` |
| Designing function declarations for Gemini APIs | Using OpenAI or non-Google AI APIs |
| Orchestrating multi-turn function calling flows | Simple one-shot text generation without tools |
| Integrating Vertex AI or Google AI SDK tool use | Building MCP servers → `agent-patterns-plugin` |

## Core Expertise

**Function Calling Flow**

Gemini function calling follows a 4-step loop:

1. **Declare** — define functions with name, description, and OpenAPI-style parameters
2. **Analyze** — model receives user message + declarations, decides if a function call is needed
3. **Execute** — your code extracts the function name/args from the response and runs the actual function
4. **Respond** — send function results back to the model for a natural-language reply

The model never executes functions directly — it outputs structured JSON describing which function to call and with what arguments.

**Supported Models**

| Model | Function Calling | Parallel | Compositional |
|-------|:---:|:---:|:---:|
| Gemini 3.1 Pro/Flash | Yes | Yes | Yes |
| Gemini 3 Pro/Flash | Yes | Yes | Yes |
| Gemini 2.5 Pro/Flash | Yes | Yes | Yes |
| Gemini 2.0 Flash | Yes | Yes | Yes |

**Calling Modes**

| Mode | Behavior | Use Case |
|------|----------|----------|
| `AUTO` (default) | Model decides between text or function call | General-purpose bots |
| `ANY` | Model always produces a function call | Strict tool-use workflows |
| `NONE` | Function calling disabled | Text-only responses |
| `VALIDATED` (preview) | Like AUTO but with schema adherence | Structured output |

## Essential Patterns

### Function Declaration Schema

```python
from google.genai import types

get_calendar_events = {
    "name": "get_calendar_events",
    "description": "Retrieve calendar events for a user within a date range.",
    "parameters": {
        "type": "object",
        "properties": {
            "user_email": {
                "type": "string",
                "description": "Email address of the user"
            },
            "start_date": {
                "type": "string",
                "description": "Start date in YYYY-MM-DD format"
            },
            "end_date": {
                "type": "string",
                "description": "End date in YYYY-MM-DD format"
            }
        },
        "required": ["user_email", "start_date", "end_date"]
    }
}
```

### Google AI SDK — Basic Flow

```python
from google import genai
from google.genai import types

client = genai.Client()
tools = types.Tool(function_declarations=[get_calendar_events])
config = types.GenerateContentConfig(tools=[tools])

# Step 1: Send user message with tool declarations
response = client.models.generate_content(
    model="gemini-2.5-flash",
    contents="What meetings do I have tomorrow?",
    config=config,
)

# Step 2: Check if model wants to call a function
part = response.candidates[0].content.parts[0]
if part.function_call:
    fn = part.function_call
    # Step 3: Execute the function with your own code
    result = call_calendar_api(fn.args)
    # Step 4: Send result back for final response
    followup = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=[
            types.Content(parts=[part]),
            types.Content(parts=[
                types.Part(function_response=types.FunctionResponse(
                    name=fn.name, response=result
                ))
            ]),
        ],
        config=config,
    )
```

### Vertex AI SDK — Basic Flow

```python
from vertexai.generative_models import (
    FunctionDeclaration, GenerativeModel, Tool
)

func = FunctionDeclaration(
    name="get_calendar_events",
    description="Retrieve calendar events for a user within a date range.",
    parameters={
        "type": "object",
        "properties": {
            "user_email": {"type": "string", "description": "User email"},
            "start_date": {"type": "string", "description": "YYYY-MM-DD"},
            "end_date": {"type": "string", "description": "YYYY-MM-DD"},
        },
        "required": ["user_email", "start_date", "end_date"],
    },
)

tool = Tool(function_declarations=[func])
model = GenerativeModel("gemini-2.5-flash", tools=[tool])
chat = model.start_chat()

response = chat.send_message("What meetings do I have tomorrow?")
fn_call = response.candidates[0].content.parts[0].function_call
# Execute and return result via chat.send_message(...)
```

### Google Chat Bot Integration

A Google Chat bot that uses Gemini function calling as its brain:

```python
from flask import Flask, request, jsonify
from google import genai
from google.genai import types

app = Flask(__name__)
client = genai.Client()

TOOLS = types.Tool(function_declarations=[
    # Declare all functions the bot can call
    get_calendar_events,
    create_ticket,
    lookup_user,
])

FUNCTION_MAP = {
    "get_calendar_events": handle_calendar_lookup,
    "create_ticket": handle_ticket_creation,
    "lookup_user": handle_user_lookup,
}

@app.route("/chat", methods=["POST"])
def on_chat_event():
    event = request.json
    user_message = event.get("message", {}).get("text", "")

    config = types.GenerateContentConfig(tools=[TOOLS])
    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=user_message,
        config=config,
    )

    part = response.candidates[0].content.parts[0]
    if part.function_call:
        handler = FUNCTION_MAP.get(part.function_call.name)
        if handler:
            result = handler(**part.function_call.args)
            # Send result back for natural-language response
            followup = client.models.generate_content(
                model="gemini-2.5-flash",
                contents=[
                    types.Content(parts=[part]),
                    types.Content(parts=[types.Part(
                        function_response=types.FunctionResponse(
                            name=part.function_call.name, response=result
                        )
                    )]),
                ],
                config=config,
            )
            reply_text = followup.text
        else:
            reply_text = f"Unknown function: {part.function_call.name}"
    else:
        reply_text = response.text

    return jsonify({"text": reply_text})
```

## Advanced Features

### Parallel Function Calling

The model can request multiple independent function calls in a single turn. Handle all calls before returning results:

```python
parts = response.candidates[0].content.parts
fn_calls = [p for p in parts if p.function_call]

if len(fn_calls) > 1:
    # Execute all in parallel
    results = []
    for call in fn_calls:
        result = FUNCTION_MAP[call.function_call.name](**call.function_call.args)
        results.append(types.Part(
            function_response=types.FunctionResponse(
                name=call.function_call.name, response=result
            )
        ))
    # Return all results together
    followup = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=[
            types.Content(parts=parts),
            types.Content(parts=results),
        ],
        config=config,
    )
```

### Compositional (Sequential) Calling

Chain dependent functions — e.g., look up a user, then fetch their calendar:

```python
# The model will call lookup_user first, then use the result
# to call get_calendar_events. Handle iteratively:
while True:
    part = response.candidates[0].content.parts[0]
    if not part.function_call:
        break  # Model returned text — done
    result = FUNCTION_MAP[part.function_call.name](**part.function_call.args)
    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=[
            types.Content(parts=[part]),
            types.Content(parts=[types.Part(
                function_response=types.FunctionResponse(
                    name=part.function_call.name, response=result
                )
            )]),
        ],
        config=config,
    )
final_text = response.text
```

### Forcing Specific Functions (ANY Mode)

```python
config = types.GenerateContentConfig(
    tools=[TOOLS],
    tool_config=types.ToolConfig(
        function_calling_config=types.FunctionCallingConfig(
            mode="ANY",
            allowed_function_names=["create_ticket"],
        )
    ),
)
```

## Common Patterns

### Function Declaration Design Guidelines

| Guideline | Example |
|-----------|---------|
| Clear, specific descriptions | `"Get weather forecast for a city"` not `"Weather function"` |
| Use enums for constrained values | `"enum": ["celsius", "fahrenheit"]` |
| Mark required parameters | `"required": ["city", "date"]` |
| Provide parameter descriptions | Each property gets its own description |
| Keep declarations under 10-20 per request | More tools = less accurate selection |
| Use strong typing | `"type": "integer"` not `"type": "string"` for numeric values |

### Google AI vs Vertex AI Decision

| Factor | Google AI (`google-genai`) | Vertex AI (`vertexai`) |
|--------|---------------------------|------------------------|
| Setup | API key only | GCP project + IAM |
| Enterprise features | Limited | Full (audit logging, VPC-SC, CMEK) |
| Auto function calling | Python SDK support | Python SDK support |
| Streaming arguments | Gemini 3+ | Gemini 3+ |
| Best for | Prototyping, simple bots | Production enterprise bots |

### Error Handling in Function Responses

Return structured errors so the model can explain failures to the user:

```python
def handle_calendar_lookup(**kwargs):
    try:
        events = calendar_api.get_events(**kwargs)
        return {"status": "success", "events": events}
    except CalendarAPIError as e:
        return {"status": "error", "message": str(e)}
```

## Quick Reference

### Function Declaration Fields

| Field | Type | Required | Description |
|-------|------|:---:|-------------|
| `name` | string | Yes | Function identifier (no spaces/special chars) |
| `description` | string | Yes | Clear explanation of purpose |
| `parameters.type` | string | Yes | Always `"object"` |
| `parameters.properties` | object | Yes | Parameter definitions |
| `parameters.required` | array | No | Required parameter names |

### Calling Config Options

| Option | Values | Default |
|--------|--------|---------|
| `mode` | `AUTO`, `ANY`, `NONE`, `VALIDATED` | `AUTO` |
| `allowed_function_names` | list of strings | all declared |

### Limits

| Limit | Value |
|-------|-------|
| Max function declarations per request | 512 |
| Recommended active functions | 10-20 |
| Max message size | Model-dependent |
| Temperature for deterministic calls | 0.0 (except Gemini 3: use 1.0) |

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Quick prototype | Use Google AI SDK with API key, `AUTO` mode, 2-3 functions |
| Production bot | Vertex AI SDK, `AUTO` mode, structured error returns, parallel call handling |
| Strict tool use | `ANY` mode with `allowed_function_names` to force specific function |
| Debug function calls | Log `response.candidates[0].content.parts` to inspect model decisions |
| Reduce latency | Minimize function declarations to only relevant ones per context |

## Resources

- **Google AI Function Calling**: https://ai.google.dev/gemini-api/docs/function-calling
- **Vertex AI Function Calling**: https://cloud.google.com/vertex-ai/generative-ai/docs/multimodal/function-calling
- **Google Chat API**: https://developers.google.com/workspace/chat/api/reference/rest
- **OpenAPI 3.0 Schema**: https://swagger.io/specification/
