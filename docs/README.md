# Technical Documentation

This directory contains detailed technical documentation for the research project.

## Documents

### technical-deep-dive.md

Comprehensive technical analysis of running k3s in sandboxed environments.

**Contents**:
- Detailed problem statement
- Environment specifications
- What works and what doesn't
- Root cause analysis of blockers
- All attempted workarounds
- Technical breakthrough documentation
- Recommendations for different use cases

**Audience**: Developers and system architects who need to understand the technical details.

## Quick Links

- **For Researchers**: See `/research/` directory for methodology and findings
- **For Developers**: See `/solutions/` for ready-to-use implementations
- **For Context**: See main `README.md` for project overview

## Related Documentation

- Research question and methodology: `/research/`
- Experiment details: `/experiments/*/README.md`
- Solution guides: `/solutions/*/README.md`
- Setup tools: `/tools/README.md`

## Contributing to Documentation

When updating technical documentation:

1. **Keep it accurate** - Verify all technical claims
2. **Include examples** - Show commands and outputs
3. **Explain why** - Don't just document what, explain why
4. **Update cross-references** - Keep links between docs current
5. **Version information** - Include version numbers for software

## Documentation Structure

```
docs/
└── technical-deep-dive.md    # Detailed technical analysis
    ├── Environment details
    ├── What works/doesn't work
    ├── Root cause analysis
    ├── Attempted solutions
    └── Recommendations
```

## See Also

- [k3s Documentation](https://docs.k3s.io/)
- [gVisor Documentation](https://gvisor.dev/)
- [cAdvisor on GitHub](https://github.com/google/cadvisor)
- [Kubernetes Architecture](https://kubernetes.io/docs/concepts/architecture/)
