# Issue Management Reference

Extended reference for the `git-issue-manage` skill.

## Custom Issue Fields API

This section is the single source for issue-field endpoints in git-plugin; other skills link here.

### Overview

Issue fields are owner-level definitions (an organization, or a personal account) that add structured metadata to issues beyond labels and milestones. They are separate from issue types: an issue has one type, and fields apply across types. Projects v2 fields are separate objects; an org issue field is attached to a project with the GraphQL mutation `createProjectV2IssueField`.

Data types (REST `data_type`): `text`, `date`, `single_select`, `multi_select`, `number`. `iteration` is a Projects v2 field type only; there is no iteration issue field.

Limits (GitHub docs): 25 issue fields per organization, 100 options per single-select field, 10 pinned fields per issue type.

### Endpoints

Field definitions. Organization writes need an org administrator (classic token: `read:org` to list, `admin:org` to write). Personal accounts use `/user/...` for the authenticated user only (classic token: `read:user` to list, `user` to write); `/users/{name}/issue-fields` does not exist.

| Method | Organization | Personal account | Description |
|--------|--------------|------------------|-------------|
| `GET` | `/orgs/{org}/issue-fields` | `/user/issue-fields` | List field definitions |
| `POST` | `/orgs/{org}/issue-fields` | `/user/issue-fields` | Create a field |
| `PATCH` | `/orgs/{org}/issue-fields/{field_id}` | `/user/issue-fields/{field_id}` | Update a field; an `options` array replaces the whole option set |
| `DELETE` | `/orgs/{org}/issue-fields/{field_id}` | `/user/issue-fields/{field_id}` | Delete a field |

Per-issue values (push access to the repository; classic token: `repo`):

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/repos/{owner}/{repo}/issues/{number}/issue-field-values` | List the issue's values |
| `POST` | `/repos/{owner}/{repo}/issues/{number}/issue-field-values` | Add values; an empty array clears all values |
| `PUT` | `/repos/{owner}/{repo}/issues/{number}/issue-field-values` | Replace all values |
| `DELETE` | `/repos/{owner}/{repo}/issues/{number}/issue-field-values/{field_id}` | Clear one value (404 if unset) |

`POST /repos/{owner}/{repo}/issues` and `PATCH /repos/{owner}/{repo}/issues/{number}` also accept `issue_field_values[]` and `type`, and `GET` on an issue returns both inline.

Field ids are integers. A live organization returned, for example, `Priority` 1416532, `Start date` 1416533, `Target date` 1416534 and `Effort` 1416535.

### Value Formats

The POST/PUT body is `{"issue_field_values": [{"field_id": <int>, "value": ...}]}`.

| Type | Value written (REST) | Value read back (REST) |
|------|----------------------|------------------------|
| `text` | String | String |
| `number` | Number | Number |
| `date` | ISO 8601 date string, e.g. `"2026-04-01"` | Date string |
| `single_select` | Option **name** string, matching an existing option | Option **id**, with a `single_select_option` object holding `id`, `name`, `color` |
| `multi_select` | Array of option names | (not observed) |

GraphQL (`setIssueFieldValue`, `IssueFieldCreateOrUpdateInput`) takes option **ids** (`singleSelectOptionId`, `multiSelectOptionIds`) where REST takes names.

### Example: List Fields

```bash
gh api orgs/my-org/issue-fields --jq '.[] | {id, name, data_type}'
```

For a personal account, use `gh api user/issue-fields` with the same filter.

### Example: Look Up a Field Id by Name

```bash
gh api orgs/my-org/issue-fields | jq --arg name "Target date" '.[] | select(.name == $name) | .id'
```

`gh api --jq` takes no `--arg`, so pass the name through `jq --arg`. A name written inside the single-quoted filter (`select(.name == "$FIELD_NAME")`) is a literal string, not a shell variable.

### Example: Get All Field Values for an Issue

```bash
gh api repos/my-org/my-repo/issues/42/issue-field-values \
  --jq '.[] | "\(.issue_field_name): \(.single_select_option.name // .value)"'
```

Read-back items carry `issue_field_id`, `data_type`, `issue_field_name` and `value`; a single-select item's `value` is the option id, so print `single_select_option.name` for the label.

### Setting and Clearing Values (unverified)

The write path in this subsection comes from the REST OpenAPI description only; no write call has been exercised live. Fine-grained token permission names for these endpoints are not documented in the OpenAPI description, and whether `multi_select` is generally available in the UI is unverified.

Write the body to a file and pass it with `--input`, because `-f`/`-F` cannot build an array of objects:

```json
{"issue_field_values": [{"field_id": 1416534, "value": "2026-04-01"}]}
```

```bash
gh api repos/my-org/my-repo/issues/42/issue-field-values -X POST --input /tmp/fields.json
```

Use `-X PUT` to replace every value instead of adding. To clear one value:

```bash
gh api repos/my-org/my-repo/issues/42/issue-field-values/1416534 -X DELETE
```

### Tooling Coverage

- `gh` (2.103.3) has `gh issue create/edit --type` and `--remove-type` for issue types, and no flag for issue fields; use `gh api`.
- The GitHub MCP server exposes `list_issue_fields` (read). Whether `issue_write` can set field values is unverified.

## Transfer Prerequisites

| Requirement | Details |
|-------------|---------|
| Write access | Must have write access to both source and target repos |
| Same owner | Both repos should be owned by the same user or organization |
| Comments preserved | All comments transfer with the issue |
| Labels | Labels are preserved if they exist in target repo |
| Assignees | Assignees are preserved if they have access to target repo |
| Milestones | Milestones do NOT transfer (different per repo) |
| Projects | Project associations do NOT transfer |

## Lock Reasons Reference

| Reason | Displayed As | When to Use |
|--------|-------------|-------------|
| `off-topic` | "This conversation was marked as off-topic" | Discussion drifted |
| `too heated` | "This conversation was marked as too heated" | Unproductive argument |
| `resolved` | "This conversation was marked as resolved" | Issue fixed, no more input needed |
| `spam` | "This conversation was marked as spam" | Spam content |
| (none) | "This conversation has been locked" | General lock, no specific reason |

## gh issue develop Requirements

- **Minimum gh version:** 2.30.0
- **GitHub feature:** Issue branch linking (generally available)
- **Default branch name:** `{issue-number}-{title-slug}` (e.g., `42-fix-auth-timeout`)
- **Linked on GitHub:** Branch automatically appears in issue sidebar under "Development"
