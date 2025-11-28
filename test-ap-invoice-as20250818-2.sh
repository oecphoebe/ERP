#!/bin/bash

# Test execution script for AP_INV_AS20250818_2 integration test
# This script loads environment variables from env.sh and executes the comprehensive test

set -e  # Exit on any error

echo "========================================="
echo "AP Invoice AS20250818_2 Integration Test"
echo "========================================="

# Load environment variables from env.sh
if [ -f "env.sh" ]; then
    echo "Loading environment variables from env.sh..."
    source env.sh
    echo "✓ Environment variables loaded"
else
    echo "❌ env.sh file not found! Please ensure env.sh exists in the current directory"
    exit 1
fi

# Display key environment variables (without sensitive data)
echo ""
echo "Environment Configuration:"
echo "- SOPL DB: ${SOPL_DB_URL}"
echo "- Cargowise DB: ${CARGOWISE_DB_URL}"
echo "- Kafka Enabled: ${KAFKA_ENABLED}"
echo "- Kafka URL: ${KAFKA_URL}"
echo "- Email Recipients: ${JOB_EMAIL_RECEIPIENTS}"
echo ""

# Ensure required directories exist
echo "Checking test resources..."
if [ ! -f "reference/AP_INV_AS20250818_2.json" ]; then
    echo "❌ Test payload file not found: reference/AP_INV_AS20250818_2.json"
    echo "Please ensure the reference JSON file exists"
    exit 1
fi

if [ ! -f "src/test/resources/test-data-cargowise-AS20250818_2.sql" ]; then
    echo "❌ Test SQL data file not found: src/test/resources/test-data-cargowise-AS20250818_2.sql"
    echo "Please ensure the test SQL file exists"
    exit 1
fi

echo "✓ Test resources verified"
echo ""

# Clean and compile
echo "Building project..."
./mvnw clean compile test-compile -DskipTests
echo "✓ Project compiled successfully"
echo ""

# Run the specific integration test
echo "Executing AP Invoice AS20250818_2 Integration Test..."
echo "========================================="

# Run the test with environment variables and detailed output
./mvnw test \
    -Dtest=APInvoiceAS20250818_2IntegrationTest \
    -DSOPL_DB_URL="${SOPL_DB_URL}" \
    -DSOPL_DB_USER="${SOPL_DB_USER}" \
    -DSOPL_DB_PASSWORD="${SOPL_DB_PASSWORD}" \
    -DCARGOWISE_DB_URL="${CARGOWISE_DB_URL}" \
    -DCARGOWISE_DB_USER="${CARGOWISE_DB_USER}" \
    -DCARGOWISE_DB_PASSWORD="${CARGOWISE_DB_PASSWORD}" \
    -DKAFKA_ENABLED="${KAFKA_ENABLED}" \
    -DKAFKA_URL="${KAFKA_URL}" \
    -DKAFKA_USERNAME="${KAFKA_USERNAME}" \
    -DKAFKA_PASSWORD="${KAFKA_PASSWORD}" \
    -DEMAIL_USERNAME="${EMAIL_USERNAME}" \
    -DEMAIL_PASSWORD="${EMAIL_PASSWORD}" \
    -DJOB_EMAIL_RECEIPIENTS="${JOB_EMAIL_RECEIPIENTS}" \
    -Dspring.profiles.active=test \
    -Dmaven.test.failure.ignore=false

test_exit_code=$?

echo ""
echo "========================================="

if [ $test_exit_code -eq 0 ]; then
    echo "✅ AP Invoice AS20250818_2 Integration Test PASSED"
    echo ""
    echo "Test Summary:"
    echo "- Complete transaction processing flow verified"
    echo "- Database persistence validation passed"
    echo "- AP Invoice routing logic confirmed (database-only)"
    echo "- All expected database records created"
    echo "- API logging and audit trail verified"
    echo ""
    echo "Expected Database Changes:"
    echo "- at_account_transaction_header: +1 record"
    echo "- at_account_transaction_lines: +2 records (DOC + FRT charges)"
    echo "- at_shipment_info: +1 record"
    echo "- api_log: +1 record with DONE status"
    echo ""
    echo "Routing Verification:"
    echo "- AP INV transaction processed in LEGACY mode"
    echo "- Saved to database only (no external system send)"
    echo "- Kafka template never invoked (as expected)"
else
    echo "❌ AP Invoice AS20250818_2 Integration Test FAILED"
    echo ""
    echo "Please check the test logs above for detailed error information."
    echo "Common issues:"
    echo "- Database connection problems"
    echo "- Missing test data files"
    echo "- Environment variable configuration"
    echo "- TestContainer setup issues"
fi

echo "========================================="
exit $test_exit_code