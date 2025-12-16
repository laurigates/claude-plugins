---
allowed-tools: Read, Write, Edit, Bash(find:*), Bash(ls:*), Grep, TodoWrite
argument-hint: <service-name>
description: Generate comprehensive service decommission documentation
---

# Service Decommission Documentation Generator

Generate a comprehensive decommission checklist for ${1:-[SERVICE_NAME]} to be created at deployment time when all context is fresh.

## Your Task

Create a detailed decommission documentation file that includes:

### 1. Service Overview
- Document the service name, purpose, and deployment date
- List all environments (dev, staging, production)
- Note key stakeholders and team contacts
- Record repository and deployment locations

### 2. Infrastructure Resources Checklist
Create a checklist covering:
- [ ] Cloud resources (compute instances, containers, serverless functions)
- [ ] Storage resources (databases, object storage, file systems, volumes)
- [ ] Network resources (load balancers, DNS records, CDN configurations)
- [ ] Security resources (SSL certificates, API keys, service accounts, IAM roles)
- [ ] Monitoring and alerting (dashboards, alert rules, log aggregations)
- [ ] CI/CD pipelines and automation jobs
- [ ] Scheduled tasks and cron jobs

### 3. Data Management Checklist
- [ ] Identify all data stores and their locations
- [ ] Create data backup procedures and retention policies
- [ ] Document data migration or archival requirements
- [ ] Plan for data deletion in compliance with policies
- [ ] Verify backup completion and integrity
- [ ] Document legal/compliance data retention requirements

### 4. Access and Security Checklist
- [ ] Revoke service accounts and API credentials
- [ ] Remove IAM roles and permissions
- [ ] Rotate any shared secrets or keys
- [ ] Update security groups and firewall rules
- [ ] Remove OAuth applications and integrations
- [ ] Audit and remove user access
- [ ] Update password vaults and secret managers

### 5. DNS and Networking Checklist
- [ ] Document all DNS records (A, CNAME, TXT, MX, etc.)
- [ ] Plan DNS record removal or updates
- [ ] Update load balancer configurations
- [ ] Remove or update CDN configurations
- [ ] Document any hardcoded URLs or endpoints
- [ ] Notify dependent services of endpoint changes

### 6. Integration and Dependencies Checklist
- [ ] Identify all upstream services (services this one depends on)
- [ ] Identify all downstream services (services depending on this one)
- [ ] Document API contracts and integration points
- [ ] Notify dependent teams of decommission timeline
- [ ] Plan migration path for dependent services
- [ ] Update service discovery and registries

### 7. Monitoring and Observability Cleanup
- [ ] Remove monitoring dashboards
- [ ] Delete alert rules and notification channels
- [ ] Clean up log aggregation and retention
- [ ] Remove tracing and APM configurations
- [ ] Archive historical metrics if needed
- [ ] Update status pages and documentation

### 8. Documentation and Knowledge Transfer
- [ ] Archive technical documentation
- [ ] Update architecture diagrams
- [ ] Remove or archive runbooks and SOPs
- [ ] Update team wikis and knowledge bases
- [ ] Document lessons learned
- [ ] Archive incident reports and postmortems

### 9. Financial and Administrative
- [ ] Cancel subscriptions and recurring charges
- [ ] Remove cost allocation tags
- [ ] Update budget and capacity planning
- [ ] Archive invoices and billing records
- [ ] Transfer domain registrations if needed

### 10. Final Verification
- [ ] Verify all resources are deleted or archived
- [ ] Confirm no unexpected charges appear
- [ ] Validate dependent services are functioning
- [ ] Complete decommission sign-off with stakeholders
- [ ] Archive this decommission documentation

## Output Format

Create a markdown file named `DECOMMISSION-${1:-[SERVICE_NAME]}.md` with:
- Clear section headers
- Checkboxes for each action item
- Specific resource identifiers (not generic placeholders)
- Timeline and responsible parties for each major section
- Links to relevant documentation and tools
- Emergency rollback procedures

## Important Notes

- This documentation should be created **at deployment time** when context is fresh
- Include actual resource identifiers, not examples
- Keep it updated as the service evolves
- Store it in the service repository for easy access
- Review and update quarterly or after major changes
