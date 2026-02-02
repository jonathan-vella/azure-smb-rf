# Contributing to Azure SMB Landing Zone

Thank you for your interest in contributing to the Azure SMB Landing Zone! This document provides
guidelines and instructions for contributing.

## 📜 Code of Conduct

This project adheres to the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
By participating, you are expected to uphold this code. Please report unacceptable behavior to the
project maintainers.

## 🚀 Getting Started

### Development Environment

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:

   ```bash
   git clone https://github.com/YOUR-USERNAME/azure-agentic-smb-lz.git
   cd azure-agentic-smb-lz
   ```

3. **Open in Dev Container** (recommended):
   - Open in VS Code
   - Press `F1` → **Dev Containers: Reopen in Container**

4. **Install dependencies**:

   ```bash
   npm install
   ```

5. **Set up pre-commit hooks** (automatic with npm install):

   ```bash
   # Verify hooks are installed
   git config core.hooksPath
   # Should show: .husky or similar
   ```

### Branch Naming

Use descriptive branch names following this pattern:

| Type          | Pattern                | Example                        |
| ------------- | ---------------------- | ------------------------------ |
| Feature       | `feature/description`  | `feature/add-cosmos-db-module` |
| Bug fix       | `fix/description`      | `fix/vpn-gateway-timeout`      |
| Documentation | `docs/description`     | `docs/update-readme`           |
| Refactor      | `refactor/description` | `refactor/simplify-networking` |

## 📝 Commit Conventions

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for automated
versioning and changelog generation.

### Commit Message Format

```text
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

| Type                          | Description                 | Version Bump  |
| ----------------------------- | --------------------------- | ------------- |
| `feat`                        | New feature                 | Minor (0.X.0) |
| `fix`                         | Bug fix                     | Patch (0.0.X) |
| `docs`                        | Documentation only          | None          |
| `style`                       | Formatting, no code change  | None          |
| `refactor`                    | Code change, no feature/fix | None          |
| `perf`                        | Performance improvement     | Patch         |
| `test`                        | Adding tests                | None          |
| `chore`                       | Build process, dependencies | None          |
| `feat!` or `BREAKING CHANGE:` | Breaking change             | Major (X.0.0) |

### Examples

```bash
# Feature
git commit -m "feat(bicep): add Cosmos DB module with private endpoint"

# Bug fix
git commit -m "fix(deploy): resolve VPN Gateway race condition"

# Documentation
git commit -m "docs(readme): add deployment duration estimates"

# Breaking change
git commit -m "feat!: rename scenario 'basic' to 'baseline'"
```

## 🧪 Testing Requirements

Before submitting a PR, ensure:

### 1. Linting Passes

```bash
# Markdown linting
npm run lint:md

# Bicep linting
bicep lint infra/bicep/smb-landing-zone/*.bicep

# Artifact template validation
npm run lint:artifact-templates
```

### 2. Bicep Builds Successfully

```bash
bicep build infra/bicep/smb-landing-zone/main.bicep
```

### 3. What-If Passes (for infrastructure changes)

```bash
cd infra/bicep/smb-landing-zone
./deploy.ps1 -Scenario baseline -WhatIf
./deploy.ps1 -Scenario full -WhatIf
```

## 🔄 Pull Request Process

1. **Create a feature branch** from `main`
2. **Make your changes** with proper commits
3. **Run all tests** (see Testing Requirements above)
4. **Push to your fork** and open a PR against `main`
5. **Fill out the PR template** completely
6. **Wait for review** - maintainers will review within 48 hours

### PR Checklist

- [ ] Branch is up-to-date with `main`
- [ ] Commits follow Conventional Commits format
- [ ] `npm run lint:md` passes
- [ ] `bicep build` succeeds (if Bicep changes)
- [ ] Documentation updated (if applicable)
- [ ] CHANGELOG.md updated (for features/fixes)

## 📁 Project Structure

When contributing, be aware of these key directories:

| Directory                        | Purpose                   | Who Should Edit           |
| -------------------------------- | ------------------------- | ------------------------- |
| `.github/agents/`                | Copilot agent definitions | Agent behavior changes    |
| `.github/instructions/`          | AI coding standards       | Coding convention changes |
| `.github/templates/`             | Artifact output templates | Output format changes     |
| `agent-output/smb-landing-zone/` | Generated artifacts       | Usually auto-generated    |
| `infra/bicep/smb-landing-zone/`  | Bicep templates           | Infrastructure changes    |
| `docs/`                          | Documentation             | Documentation updates     |

## 🏷️ Issue Guidelines

### Reporting Bugs

Use the **Bug Report** template and include:

- Clear description of the issue
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, Azure CLI version, etc.)
- Relevant logs or error messages

### Requesting Features

Use the **Feature Request** template and include:

- Problem you're trying to solve
- Proposed solution
- Alternative approaches considered
- Impact on existing functionality

## 📄 License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

## 🙏 Thank You

Your contributions help make Azure infrastructure accessible to more organizations. We appreciate
your time and effort!

For questions, open an issue or reach out to the maintainers.
