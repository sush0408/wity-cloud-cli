# Contributing to Wity Cloud CLI

Thank you for your interest in contributing to Wity Cloud CLI! We welcome contributions from the community and are grateful for your support.

## 🤝 Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## 🚀 How to Contribute

### Reporting Bugs

Before creating bug reports, please check the existing issues to avoid duplicates. When you create a bug report, please include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce the problem**
- **Provide specific examples to demonstrate the steps**
- **Describe the behavior you observed and what behavior you expected**
- **Include system information** (OS, version, hardware specs)
- **Include output from the troubleshooting tool**: `sudo ./troubleshoot.sh` (option 5)

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

- **Use a clear and descriptive title**
- **Provide a step-by-step description of the suggested enhancement**
- **Provide specific examples to demonstrate the enhancement**
- **Describe the current behavior and explain the behavior you expected**
- **Explain why this enhancement would be useful**

### Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Make your changes** following our coding standards
3. **Test your changes** thoroughly
4. **Update documentation** if needed
5. **Ensure your code follows our style guidelines**
6. **Submit a pull request**

## 🛠️ Development Setup

### Prerequisites

- Ubuntu/Debian-based system (recommended for testing)
- Root/sudo access
- Git
- Basic knowledge of Bash scripting and Kubernetes

### Setting Up Development Environment

```bash
# Fork and clone the repository
git clone https://github.com/your-username/wity-cloud-cli.git
cd wity-cloud-cli

# Create a new branch for your feature
git checkout -b feature/your-feature-name

# Make the scripts executable
chmod +x *.sh

# Test the basic functionality
sudo ./check-dependencies.sh
```

### Testing Your Changes

Before submitting a pull request, please test your changes:

```bash
# Run system checks
sudo ./troubleshoot.sh

# Test specific components
sudo ./core.sh  # Test core functionality
sudo ./databases.sh  # Test database deployments
sudo ./monitoring.sh  # Test monitoring stack

# Run integration tests (if available)
sudo ./tests/run-tests.sh
```

## 📝 Coding Standards

### Bash Script Guidelines

1. **Use consistent indentation** (2 spaces)
2. **Add proper error handling** with meaningful error messages
3. **Use descriptive variable names** in UPPER_CASE for globals
4. **Add comments** for complex logic
5. **Follow the existing function structure**
6. **Use the common.sh functions** for consistency

### Example Function Structure

```bash
function your_function_name() {
  section "Your Function Description"
  
  # Check prerequisites
  if ! check_kubectl; then
    echo -e "${RED}Cannot access Kubernetes cluster${NC}"
    return 1
  fi
  
  # Ask for approval in interactive mode
  if ! ask_approval "Do you want to proceed with this action?"; then
    return 0
  fi
  
  # Your implementation here
  echo -e "${YELLOW}Performing action...${NC}"
  
  # Error handling
  if [[ $? -ne 0 ]]; then
    echo -e "${RED}Action failed${NC}"
    return 1
  fi
  
  echo -e "${GREEN}✅ Action completed successfully${NC}"
}
```

### Documentation Standards

1. **Update README.md** if your changes affect user-facing functionality
2. **Add inline comments** for complex logic
3. **Update the component matrix** if adding new components
4. **Create or update documentation** in the `docs/` folder for major features

## 🧪 Testing Guidelines

### Manual Testing

1. **Test on a clean system** when possible
2. **Test both interactive and batch modes**
3. **Verify error handling** by introducing failures
4. **Test rollback scenarios** where applicable
5. **Document any new testing procedures**

### Automated Testing

We encourage adding automated tests for new functionality:

```bash
# Create test files in the tests/ directory
tests/test-your-feature.sh

# Follow the existing test structure
#!/bin/bash
source ./common.sh

function test_your_feature() {
  section "Testing Your Feature"
  
  # Test implementation
  # Assert expected outcomes
  
  echo -e "${GREEN}✅ Test passed${NC}"
}

# Run if script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  test_your_feature
fi
```

## 📋 Pull Request Process

1. **Ensure your PR has a clear title and description**
2. **Reference any related issues** using keywords like "Fixes #123"
3. **Include screenshots or logs** if relevant
4. **Update the CHANGELOG.md** if your changes are user-facing
5. **Ensure all tests pass**
6. **Request review** from maintainers

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Testing
- [ ] Tested on clean system
- [ ] Tested in batch mode
- [ ] Tested error scenarios
- [ ] Updated documentation

## Checklist
- [ ] My code follows the style guidelines
- [ ] I have performed a self-review of my code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings
```

## 🏷️ Issue Labels

We use the following labels to categorize issues:

- `bug` - Something isn't working
- `enhancement` - New feature or request
- `documentation` - Improvements or additions to documentation
- `good first issue` - Good for newcomers
- `help wanted` - Extra attention is needed
- `question` - Further information is requested
- `wontfix` - This will not be worked on

## 🎯 Areas for Contribution

We especially welcome contributions in these areas:

### High Priority
- **Testing automation** - Automated test suites
- **Documentation improvements** - Better guides and examples
- **Error handling** - More robust error detection and recovery
- **Performance optimization** - Faster deployment and better resource usage

### Medium Priority
- **New database integrations** - Additional database operators
- **Cloud provider support** - GCP, Azure integrations
- **Security enhancements** - Better secret management, security scanning
- **Monitoring improvements** - Additional dashboards and alerts

### Low Priority
- **UI improvements** - Better CLI interface and menus
- **Additional utilities** - Helper scripts and tools
- **Platform support** - Support for other Linux distributions

## 🔄 Release Process

1. **Version bumping** follows semantic versioning (MAJOR.MINOR.PATCH)
2. **Changelog updates** document all user-facing changes
3. **Release notes** highlight major features and breaking changes
4. **Testing** on multiple environments before release

## 📞 Getting Help

If you need help with contributing:

1. **Check existing documentation** in the `docs/` folder
2. **Search existing issues** for similar questions
3. **Join our discussions** on GitHub
4. **Contact maintainers** through GitHub issues

## 🙏 Recognition

Contributors will be recognized in:

- **README.md** contributors section
- **Release notes** for significant contributions
- **GitHub contributors** page

## 📄 License

By contributing to Wity Cloud CLI, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to Wity Cloud CLI! Your efforts help make enterprise Kubernetes accessible to everyone. 🚀 