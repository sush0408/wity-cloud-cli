# Test Scripts

This directory contains test scripts for validating the Wity Cloud Deploy functionality.

## Test Scripts

### `test-environment.sh`
Tests the environment setup and kubectl functionality:
- Environment setup script creation
- kubectl availability and cluster access
- KUBECONFIG and PATH validation
- Basic cluster connectivity

```bash
cd tests
./test-environment.sh
```

### `test-individual-components.sh`
Tests individual component scripts with existing installations:
- Core components (RKE2, Helm, etc.)
- Storage (Longhorn)
- Databases (PostgreSQL)
- Management tools (cert-manager)
- Monitoring (status check)

```bash
cd tests
./test-individual-components.sh
```

### `test-batch-mode.sh`
Tests the batch mode functionality for automatic handling:
- Existing installation detection
- Automatic cleanup and reinstallation
- Non-interactive mode behavior

```bash
cd tests
./test-batch-mode.sh
```

### `test-error-scenarios.sh`
Tests various error scenarios and recovery mechanisms:
- Missing KUBECONFIG handling
- Helm release detection
- Namespace detection
- Deployment readiness checks
- Cluster connectivity validation

```bash
cd tests
./test-error-scenarios.sh
```

## Running All Tests

To run all tests in sequence:

```bash
cd tests
for test in test-*.sh; do
    echo "Running $test..."
    chmod +x "$test"
    ./"$test"
    echo "----------------------------------------"
done
```

## Test Requirements

- Root access (all scripts must run as root)
- Active RKE2 cluster
- kubectl configured and working
- Existing installations (for testing error handling)

## Expected Behavior

- **Green messages**: Successful operations
- **Yellow messages**: Warnings or expected conditions
- **Red messages**: Errors that need attention

The tests are designed to be non-destructive and should not break existing installations. 