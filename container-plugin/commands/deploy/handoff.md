---
allowed-tools: Read, Bash(git:*), mcp__github__get_pull_request, mcp__github__list_issues, TodoWrite
argument-hint: [resource-name] [deployment-type]
description: Generate deployment handoff documentation
---

# Deployment Handoff Command

Generate professional handoff messages for deployed resources and services with all necessary information for developer handoff.

## Usage
```bash
claude chat --file ~/.claude/commands/deploy:handoff.md [RESOURCE_NAME] [DEPLOYMENT_TYPE]
```

## Arguments
- `RESOURCE_NAME` (optional): Name of the deployed resource/service
- `DEPLOYMENT_TYPE` (optional): Type of deployment (web-app, api, database, infrastructure, etc.)

## Workflow

1. **Resource Discovery**
   - Gather deployment details from current repository context
   - Identify relevant documentation and configuration files
   - Extract repository information and branch details

2. **Information Collection**
   - Service/resource name and purpose
   - Deployment environment details
   - Access URLs and endpoints
   - Configuration and environment variables
   - Dependencies and prerequisites
   - Monitoring and logging information

3. **Documentation Links**
   - Repository URL and relevant branches
   - Deployment documentation
   - API documentation (if applicable)
   - Configuration guides
   - Troubleshooting resources

4. **Access Information**
   - Service URLs and endpoints
   - Database connection details (without credentials)
   - Admin/management interfaces
   - Monitoring dashboards
   - Log locations and access methods

5. **Handoff Message Generation**
   - Professional Podio-friendly formatting
   - Clear sections for different types of information
   - Action items for the receiving developer
   - Contact information for follow-up questions

## Template Structure

### Service Overview
- **Name**: Resource/service identifier
- **Purpose**: Brief description of functionality
- **Environment**: Production/staging/development
- **Deployment Date**: When the deployment occurred
- **Deployed By**: Who performed the deployment

### Technical Details
- **Technology Stack**: Languages, frameworks, databases used
- **Architecture**: High-level system design
- **Dependencies**: External services and libraries
- **Configuration**: Key settings and environment variables

### Access Information
- **Service URL**: Primary access point
- **Admin Interface**: Management dashboard (if applicable)
- **Database**: Connection information (non-sensitive)
- **File Storage**: Asset/file locations
- **Monitoring**: Health check endpoints and dashboards

### Documentation
- **Repository**: GitHub/GitLab repository URL
- **Branch**: Deployed branch/tag
- **API Docs**: API documentation location
- **Setup Guide**: Installation/configuration instructions
- **Troubleshooting**: Known issues and solutions

### Developer Handoff Checklist
- [ ] Review service functionality and purpose
- [ ] Access all provided URLs and interfaces
- [ ] Verify monitoring and alerting setup
- [ ] Check backup and recovery procedures
- [ ] Review security configurations
- [ ] Test deployment process
- [ ] Document any additional findings

## Output Format

The command generates a Podio-friendly message with:
- **Professional tone** suitable for client communications
- **Clear structure** with headers and bullet points
- **Actionable information** for immediate developer productivity
- **Complete context** for understanding the deployment

## Configuration Options

```yaml
format: podio              # podio, slack, email, markdown
include_sensitive: false   # Include sensitive config info
detail_level: standard     # minimal, standard, comprehensive
template_style: professional # professional, technical, brief
podio_workspace:          # Default workspace for Podio integration
  org_label: fvh
  space_label: iot-workspace
  app_label: datadev-kanban
```

## Integration Points

- **Repository Detection**: Automatically detects git repository information
- **Environment Variables**: Reads from `.env` files and configuration
- **Documentation Scanning**: Searches for README, docs, and API specifications
- **CI/CD Integration**: Extracts deployment pipeline information
- **Monitoring Integration**: Links to observability tools and dashboards

## Success Criteria
- Handoff message contains all necessary information for developer productivity
- Format is suitable for Podio ticket comments
- Message includes clear next steps and action items
- All links and references are accurate and accessible
- Professional tone appropriate for client-facing communications

## Example Usage

```bash
# Basic handoff for current project
claude chat --file ~/.claude/commands/deploy:handoff.md

# Specific service handoff
claude chat --file ~/.claude/commands/deploy:handoff.md "User API" "web-service"

# Comprehensive handoff with full details
claude chat --file ~/.claude/commands/deploy:handoff.md "Payment System" "microservice" --detail-level comprehensive
```

## Sample Output Format

```
## 🚀 Deployment Handoff: [Service Name]

**Service**: [Service Name]
**Environment**: [Production/Staging/Development]
**Deployment Date**: [Date]
**Deployed By**: [Developer Name]

### 📋 Service Overview
- **Purpose**: [Brief description of functionality]
- **Technology Stack**: [Languages/frameworks used]
- **Status**: ✅ Active and operational

### 🔗 Access Information
- **Service URL**: [Primary access point]
- **Admin Dashboard**: [Management interface]
- **API Documentation**: [API docs location]
- **Health Check**: [Monitoring endpoint]

### 📚 Documentation & Resources
- **Repository**: [GitHub repository URL]
- **Branch/Tag**: [Deployed version]
- **Setup Guide**: [Configuration instructions]
- **Troubleshooting**: [Known issues and solutions]

### ✅ Developer Handoff Checklist
- [ ] Review service functionality and purpose
- [ ] Access all provided URLs and interfaces
- [ ] Verify monitoring and alerting setup
- [ ] Test basic functionality
- [ ] Review configuration and environment variables

### 📞 Support & Contact
For questions or issues with this deployment, please:
1. Check the troubleshooting guide first
2. Review logs at [log location]
3. Contact [deployer] for immediate assistance

*Generated on [date] for [project/client]*
```
