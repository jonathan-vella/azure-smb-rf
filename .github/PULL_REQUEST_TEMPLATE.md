## Summary

<!-- Describe what this PR changes and why. One or two sentences is fine. -->

## Type of change

- [ ] `feat` — new feature or enhancement
- [ ] `fix` — bug fix
- [ ] `docs` — documentation only
- [ ] `chore` — dependency, config, or tooling update
- [ ] `refactor` — code change with no feature or fix

## Checklist

- [ ] Bicep templates compile without errors (`bicep build infra/bicep/smb-landing-zone/main.bicep`)
- [ ] Markdown lint passes (`npm run lint:md`)
- [ ] Internal links are valid (`npm run lint:links`)
- [ ] Deployment scenario tested (baseline / firewall / vpn / full — check which applies)
- [ ] CHANGELOG.md updated if this is a `feat` or `fix`
- [ ] No hardcoded subscription IDs, tenant IDs, or secrets
