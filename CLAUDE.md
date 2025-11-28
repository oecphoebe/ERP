# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **oec-erpportal-addon-cpar** project - a Spring Boot application for OEC ERP Portal Add-on Compliance AR APIs. It's a microservice that handles compliance and transaction processing for accounts receivable, integrating with multiple external systems including CWIS, Cargowise, and internal ERP systems.

## Build and Development Commands

```bash
# Build the project
./mvnw clean package

# Run the application locally
./mvnw spring-boot:run

# Build Docker image
docker build -t cpar-api .

# Run tests
./mvnw test

# Run a specific test class
./mvnw test -Dtest=ComplianceApplicationTests

# Skip tests during build
./mvnw clean package -DskipTests
```

## Architecture Overview

### Technology Stack
- **Java 21** with Spring Boot 3.4.3
- **Spring Cloud OpenFeign** for REST client communication
- **Apache Kafka** for async message processing with advanced retry mechanism
- **Dual Database Support**: PostgreSQL (SOPL) and SQL Server (Cargowise)
- **Spring Data JDBC** for database operations
- **Caffeine Cache** for in-memory token caching
- **Apache POI 5.4.1** for Excel report generation
- **Auth0 Java JWT 4.5.0** for JWT token handling
- **Spring Boot Mail** with AWS SES for email notifications
- **JsonPath 2.9.0** for JSON parsing and extraction

### Core Components

1. **API Integration Layer** (`api12`, `api15`, `api16`, `api18` packages)
   - Each API package contains its own authentication client, configuration, and token service
   - Uses Feign clients with token-based authentication
   - Implements token caching and automatic renewal
   - API16 supports ADD & DEL operations for compliance management using `compliance_id + lines id` as key

2. **Transaction Processing** (`transaction` package)
   - Strategy pattern for different transaction types (AP Invoice, AR Invoice, AR Credit Note)
   - Async processing via Kafka for large payloads
   - Handles universal transaction format from Cargowise
   - Enhanced Shipment vs Consol differentiation using `JobCharge.jr_e6`
   - Special handling for reversed transactions (`AP_INV_Reversed`, `AP_CRD_Reversed`)
   - Automatic clearing of outstanding amounts for reversed transactions
   - Graceful collision handling with retry mechanism for transaction saves
   - **Charge-Line Level Currency Extraction**: Production-ready currency code extraction from JSON charge lines with robust error handling and fallback mechanisms

3. **Compliance Module** (`compliance` package)
   - Handles compliance checks and sending
   - Integrates with external compliance systems
   - Manages compliance status tracking

4. **Common Infrastructure** (`common` package)
   - Shared API client factory and Feign configurations
   - Dual datasource configuration (PostgreSQL + SQL Server)
   - Kafka producer/consumer configuration with advanced retry mechanism
   - Exception handling and controller base classes
   - Kafka retry service with exponential backoff (2^attempt seconds)
   - Dead letter queue support for failed messages
   - Configurable retry limits and topics

### Key Controllers
- **ComplianceController**: Handles compliance information receipt and verification
- **ComplianceAPController**: Manages AP-specific compliance operations
- **UniversalController**: Processes Cargowise outbound universal transactions
- **CwisController**: CWIS integration endpoints
- **InvoiceController**: Invoice processing operations

### Message Flow
- Inbound transactions are received via REST endpoints
- Large or async operations are sent to Kafka topics
- Advanced retry mechanism with exponential backoff for failed messages
- Profile-based topic naming: `{profile}-invoice-outbound`, `{profile}-invoice-retry`, `{profile}-invoice-dead-letter`
- Scheduled jobs for comprehensive data comparison with Excel reporting and email notifications

### Environment Configuration
- Uses Spring Cloud Config for external configuration
- Profile-based configuration (local, dev, sit, uat, prod)
- Environment variables for sensitive data (credentials, URLs)
- Kafka SASL authentication configured
- AWS SES configuration for email notifications
- Environment-aware scheduled jobs and email behavior (disabled for local profile)

### NONJOB Transaction Support

NONJOB transactions (transactions without shipment/consol references) require explicit configuration to be processed:

```yaml
transaction:
  nonjob:
    enabled: true  # Default: false
    error-message: "Custom error message"  # Optional
```

**Default Behavior (disabled)**:
- NONJOB transactions are rejected with HTTP 400
- Detailed error response includes transaction details and suggestions
- Status recorded as "REJECTED" in api_log table

**When Enabled**:
- NONJOB transactions are processed normally according to the enhanced logic documented in `/docs/mapping/20250816-ARTransaction-Attribute-Mapping.md`
- Data saved to database tables using direct AccTransactionLines data from Cargowise
- Sent to external system based on routing rules (if applicable)

**Migration Note**: Existing deployments processing NONJOB transactions must add `transaction.nonjob.enabled: true` to maintain functionality.

**Configuration Example**:
```yaml
# Enable NONJOB support with custom error message
transaction:
  nonjob:
    enabled: true
    error-message: "NONJOB transactions require special approval. Contact system administrator."
```

### NONJOB Type Differentiation

The system distinguishes between two distinct types of NONJOB transactions based on their data structure in Cargowise and the presence of `JobInvoiceNumber` in the payload.

#### Type Detection Logic

**Detection Method**: Inspects `UniversalTransaction.JobInvoiceNumber` field in the JSON payload
- **If JobInvoiceNumber exists and is not blank** → **JOB_INVOICE type**
- **If JobInvoiceNumber is null/missing/blank** → **GL_ACCOUNT type**

**Implementation**: `NonJobType.detectFromPayload(json)` in `NonJobType.java`

#### Job-Invoice Type NONJOB

**Characteristics**:
- Has `JobInvoiceNumber` value in `UniversalTransaction` payload
- `AccTransactionLines` records exist in Cargowise database
- Uses `AccTransactionLines.AL_PK` directly as `cw_acct_trans_lines_pk`
- Queries Cargowise **WITH** `organizationCode` filter
- Typical use case: Job-related invoices without direct shipment/consol reference

**Processing Flow**:
1. Detect `JobInvoiceNumber` presence → Route to `processJobInvoiceNonJob()`
2. Query Cargowise using `QUERY_CW_ACCOUNT_TRANSACTION_INFO_NONJOB` (includes org filter)
3. Extract `AccTransactionLines.AL_PK` from query results
4. Use `AL_PK` directly as `cw_acct_trans_lines_pk` for uniqueness
5. Populate line data from PostingJournal in payload
6. Save to both `at_account_transaction_header` and `at_account_transaction_lines`
7. Send to external system based on routing rules

**Uniqueness Determination**:
- **Header Level**: `cw_acc_trans_header_pk` (from `AccTransactionHeader.AH_PK`)
- **Line Level**: `cw_acct_trans_lines_pk` (from `AccTransactionLines.AL_PK`)
- Both keys ensure accurate duplicate detection for updates

**Key Implementation Files**:
- `TransactionMappingService.processJobInvoiceNonJob()` - Orchestration
- `TransactionQueryService.getCWAccountTransactionInfo()` - Cargowise query with org filter
- `ChargeLineProcessor.handleNonJobChargeLines()` - Charge line processing

#### GL-Account Type NONJOB

**Characteristics**:
- **NO** `JobInvoiceNumber` in payload (null/missing/blank)
- `AccTransactionLines` records **may NOT exist** in Cargowise database
- Uses **composite key** (header_PK + PostingJournal_index) when `AL_PK` is NULL
- Queries Cargowise **WITHOUT** `organizationCode` filter (no org association)
- Processes **ALL** returned rows as separate line records
- Typical use case: General ledger entries, manual accounting corrections, admin fees

**Processing Flow**:
1. Detect no `JobInvoiceNumber` → Route to `processGLAccountNonJob()`
2. Query Cargowise using `QUERY_CW_ACCOUNT_TRANSACTION_INFO_GL_ACCOUNT` (NO org filter)
3. Process ALL rows returned from query (no org filtering)
4. For each PostingJournal entry:
   - If `AL_PK` exists in query result → use it as `cw_acct_trans_lines_pk`
   - If `AL_PK` is NULL → generate composite key: `UUID.nameUUIDFromBytes(header_PK + "-" + PostingJournal_index)`
5. Populate line data from PostingJournal in payload
6. Save to both `at_account_transaction_header` and `at_account_transaction_lines`
7. Send to external system based on routing rules

**Composite Key Generation**:
```java
// When AL_PK is NULL for GL-Account type
String compositeKeySource = headerPk.toString() + "-" + postingJournalIndex;
UUID compositeKey = UUID.nameUUIDFromBytes(compositeKeySource.getBytes(StandardCharsets.UTF_8));
linesBean.setCwAccountTransactionLinesPk(compositeKey);
```

**Uniqueness Determination**:
- **Header Level**: `cw_acc_trans_header_pk` (from `AccTransactionHeader.AH_PK`)
- **Line Level**: `cw_acct_trans_lines_pk` (either `AL_PK` or composite UUID)
- Composite keys are deterministic - same input always produces same UUID
- Enables idempotent reprocessing for webhook retries

**Key Implementation Files**:
- `TransactionMappingService.processGLAccountNonJob()` - Orchestration
- `TransactionQueryService.getCwTransactionInfoForGLAccount()` - Cargowise query without org filter
- `ChargeLineProcessor.handleGLAccountChargeLines()` - GL-Account charge line processing with composite key logic
- `ChargeLineProcessor.processGLAccountPostingJournalFromOriginalJson()` - Individual PostingJournal processing

#### Comparison Matrix

| Aspect | Job-Invoice Type | GL-Account Type |
|--------|-----------------|-----------------|
| **Detection** | `JobInvoiceNumber` exists | `JobInvoiceNumber` null/missing |
| **Cargowise AccTransactionLines** | Always exists | May NOT exist |
| **Cargowise Query Filter** | WITH `organizationCode` | WITHOUT `organizationCode` |
| **Primary Key Source** | `AccTransactionLines.AL_PK` | `AL_PK` or composite UUID |
| **Composite Key** | Never generated | Generated when `AL_PK` is NULL |
| **Multi-Row Processing** | Single org match | ALL rows (no org filter) |
| **Organization Association** | Yes (required) | No (no org linkage) |
| **Typical Examples** | Job invoices without shipment | GL entries, manual corrections |
| **itemCode Extraction** | `$.ChargeCode.Code` | `$.Glaccount.AccountCode` |
| **itemCode Examples** | "DOC", "FRT", "AMS" | "4070.10.10", "1210.00.10" |

#### ItemCode Extraction Logic

**Critical Implementation Detail**: The system uses priority-based field extraction for `itemCode` to correctly differentiate between NonJob types.

**Extraction Priority** (in `TransactionChargeLineRequestBean.java`):
1. **First Priority**: Check for `$.ChargeCode.Code` → Use if present and non-blank
2. **Second Priority**: Check for `$.Osamount` + absence of `ChargeCode` → Use `$.Glaccount.AccountCode`
3. **Fallback**: Use `$.ChargeCode.Code` (safety net)

**Implementation**:
```java
// Detect if ChargeCode exists (priority for JOB_INVOICE type NonJob)
Object chargeCodeObj = JsonPath.parse(jsonChargeLine).read("$.ChargeCode.Code");
boolean hasChargeCode = chargeCodeObj != null && StringUtils.isNotBlank(chargeCodeObj.toString());

// Extract with proper prioritization
if (hasChargeCode) {
    // JOB_INVOICE type NonJob or standard ChargeLine - use ChargeCode
    this.setItemCode(ChargeCode.Code);  // e.g., "DOC", "FRT", "AMS"
} else if (isNonjobPostingJournal) {
    // GL_ACCOUNT type NonJob - use Glaccount (only when ChargeCode doesn't exist)
    this.setItemCode(Glaccount.AccountCode);  // e.g., "4070.10.10", "1210.00.10"
}
```

**Why Priority-Based?**
- **JOB_INVOICE type** has BOTH `ChargeCode` and `Glaccount` fields in PostingJournal
- **GL_ACCOUNT type** has ONLY `Glaccount` field (no `ChargeCode`)
- Simply checking `Osamount` presence is insufficient to distinguish types
- Priority ensures correct field is extracted based on field availability

**External System Integration**:
- External systems expect `itemCode` to represent business charge codes for job-related transactions
- GL account codes are only appropriate for accounting-only transactions without charge association
- Incorrect extraction would cause integration failures and accounting mismatches

**Reference**:
- Bug Fix: Fixed 2025-11-20 (see `NONJOB_ITEMCODE_FIX.md`)
- Test Coverage: `TransactionChargeLineRequestBeanTest.java` (15 tests including 5 itemCode extraction tests)

#### Database Schema Impact

**No Schema Changes Required**: Both types use the same database tables with the same columns. The `cw_acct_trans_lines_pk` column stores UUIDs regardless of whether they're:
- Direct `AL_PK` values from Cargowise (Job-Invoice type)
- Generated composite UUIDs (GL-Account type when `AL_PK` is NULL)

**Duplicate Detection**: Existing `ON CONFLICT` and UUID comparison logic handles both types transparently since both use UUID values for uniqueness checks.

#### Migration Guide

**Existing Deployments**: No migration required. The type detection is automatic based on payload structure.

**Testing Recommendations**:
1. **Job-Invoice Type**: Test with payloads containing `JobInvoiceNumber` and existing `AccTransactionLines` data
2. **GL-Account Type**: Test with payloads without `JobInvoiceNumber` and NULL `AL_PK` scenarios
3. **Duplicate Handling**: Verify idempotent reprocessing for both types
4. **Multi-Row GL**: Test GL-Account transactions with multiple PostingJournal entries

### Currency Extraction Architecture

The system implements charge-line level currency extraction with comprehensive error handling and fallback mechanisms to provide accurate currency data for external system integration.

#### Currency Extraction Paths
- **AR Transactions**: Extracts from `$.SellOSCurrency.Code` (sales-side currency)
- **AP Transactions**: Extracts from `$.CostOSCurrency.Code` (cost/vendor-side currency)
- **NONJOB Transactions**: Extracts from `$.Oscurrency.Code` (PostingJournal currency)
- **Fallback Mechanism**: Uses header-level currency when charge-line extraction fails

#### Implementation Features
- **Type-Safe Extraction**: Prevents ClassCastException through proper object type validation
- **Error Resilience**: Graceful handling of missing fields, null values, and malformed JSON
- **Production Logging**: Comprehensive debug logging for troubleshooting currency extraction decisions
- **Comprehensive Testing**: 19+ test scenarios covering all paths and edge cases
- **Zero Breaking Changes**: Full backward compatibility with existing functionality

#### Edge Case Handling
- Missing currency objects (graceful fallback to header currency)
- Empty/whitespace currency codes (validated with StringUtils.isNotBlank)
- Malformed currency structures (LinkedHashMap vs String object handling)
- JSON parsing exceptions (exception suppression with meaningful error messages)
- Multi-currency batch processing (consistent extraction across multiple charge lines)

#### Key Implementation Files
- `TransactionChargeLineRequestBean.java`: Core currency extraction logic with type-safe parsing
- `ChargeLineProcessor.java`: NONJOB currency extraction with enhanced error handling
- `CurrencyExtractionUnitTest.java`: Comprehensive unit test framework
- `CurrencyExtractionEdgeCasesTest.java`: Edge case validation with 11 comprehensive scenarios

### NONJOB VAT Amount Handling (CRITICAL)

**IMPORTANT (Nov 21, 2025 - VAT Currency Fix)**: NONJOB transactions have a critical requirement for VAT amount currency handling.

#### Cargowise Schema Currency Issue

Cargowise's `AccTransactionLines` table has an inconsistent currency design:
- `AL_OSAmount`: **OS currency** (e.g., USD) - VAT-inclusive gross amount
- **`AL_GSTVAT`: LOCAL currency** (e.g., CNY) - **NOT OS currency!**
- `AL_LineAmount`: **LOCAL currency** (e.g., CNY) - net amount

**Root Problem**: `AL_GSTVAT` contains LOCAL currency VAT amounts (e.g., 4.81 CNY), but the field name and context suggest it should be OS currency.

#### JSON PostingJournal vs Cargowise

**JSON PostingJournal provides BOTH currencies correctly**:
```json
{
  "Osamount": 11,                    // OS net (USD)
  "Osgstvatamount": 0.66,            // OS VAT (USD) ✅
  "LocalAmount": 80.19,              // Local net (CNY)
  "LocalGSTVATAmount": 4.81,         // Local VAT (CNY) ✅
  "ChargeExchangeRate": 7.29
}
```

**Cargowise Database has currency mismatch**:
```sql
AL_OSAmount = 11.66 USD     -- OS gross (net + VAT)
AL_GSTVAT = 4.81 CNY       -- LOCAL VAT (⚠️ NOT OS currency!)
AL_LineAmount = 80.19 CNY   -- Local net
```

#### Correct Implementation (After Nov 21, 2025 Fix)

**Database Columns**:
- `vat_amt`: Should store **OS currency** VAT (e.g., 0.66 USD from JSON `Osgstvatamount`)
- `local_vat_amt`: Should store **LOCAL currency** VAT (e.g., 4.81 CNY calculated from JSON)

**Implementation**:
1. Extract VAT from JSON PostingJournal:
   - `vat_amt` = `Osgstvatamount` (OS currency)
   - `local_vat_amt` = `Osgstvatamount × exchangeRate` (convert to local)
2. **Do NOT override** these values from Cargowise `AL_GSTVAT`
3. Other amounts (chargeAmount, totalAmount) can be overridden from Cargowise

**Code Location**: `ChargeLineProcessor.java`
- `createNonjobTransactionLinesBean()` - Initial extraction (lines 978-1057)
- `processNonJobPostingJournalFromOriginalJson()` - Job-Invoice processing (lines 874-975)
- `processGLAccountPostingJournalFromOriginalJson()` - GL-Account processing (lines 637-760)

#### Why NOT Override from Cargowise

**Problem if overridden**:
```
vat_amt = AL_GSTVAT = 4.81 CNY       ❌ Wrong currency (should be USD)
local_vat_amt = 4.81 × 7.29 = 35.06  ❌ Double conversion
```

**Correct approach**:
```
vat_amt = Osgstvatamount = 0.66 USD              ✅ OS currency
local_vat_amt = 0.66 × 7.29 = 4.81 CNY          ✅ Single conversion
```

#### Testing Validation

**Reference File**: `reference/NonJob-AR_INV_2511001027-ADD.json`

**Expected Values**:
- Charge 1 (AMS): `vat_amt` = 0.66 USD, `local_vat_amt` = 4.81 CNY
- Charge 2 (FRT): `vat_amt` = 0.48 USD, `local_vat_amt` = 3.50 CNY

**NOT**:
- `vat_amt` = 4.81 or 3.50 (wrong currency)
- `local_vat_amt` = 35.06 or 25.52 (double conversion)

### Shipment View Architecture (vw_shipment_info)

The system implements a dual-access pattern for shipment information with feature flag control to enable seamless migration from table-based to view-based data access.

#### View vs Table Implementation
- **View Implementation**: `VwShipmentInfoRepository` - Uses native SQL against `vw_shipment_info` view
- **Table Implementation**: Complex multi-table joins in `AtAccountTransactionTableServiceImpl`
- **Feature Flag**: `shipment.use-view` controls which implementation is used
- **Fallback Mechanism**: Automatic degradation to table implementation if view access fails

#### Performance Benefits
- **Query Simplification**: Single view access vs complex 8-table joins
- **Column Optimization**: 10 essential columns vs 24 full table columns
- **Index Optimization**: View leverages database-optimized indexes
- **Reduced Network Traffic**: Minimized data transfer through column selection

#### Implementation Features
- **Prefix-Based Routing**: Intelligent job number lookup using 'S'/'C' prefixes
- **Multi-Strategy Search**: Shipment → Consolidation → Prefix-based fallback
- **Retry Mechanism**: Configurable retry attempts with exponential backoff
- **Health Monitoring**: View availability checks and operational metrics
- **Type-Safe Conversion**: VwShipmentInfoBean ↔ AtShipmentInfoBean mapping

#### Configuration Control
```yaml
shipment:
  use-view: true              # Enable view implementation
  fallback-enabled: true     # Enable automatic fallback to table
  retry-attempts: 3           # Number of retry attempts
  retry-delay-ms: 1000       # Delay between retries
  query-timeout-ms: 30000    # Query timeout threshold
```

#### Key Classes
- **VwShipmentInfoRepository**: Core view access repository with JDBC operations
- **VwShipmentInfoBean**: Lightweight 10-column data model for view
- **ShipmentViewService**: Service layer with prefix routing and retry logic
- **ShipmentProperties**: Configuration properties for feature flag control
- **AtAccountTransactionTableServiceImpl**: Enhanced with view integration and fallback

#### Production Readiness Features
- **Feature Flag Control**: Runtime enable/disable without application restart
- **Graceful Degradation**: Automatic fallback to proven table implementation
- **Comprehensive Testing**: 190+ test methods covering all scenarios
- **Error Resilience**: Exception handling with proper error propagation
- **Monitoring Integration**: Health checks and performance metrics

## Key Integration Points

1. **CWIS API** - Token-based authentication, shipment data
2. **Compliance API** - Compliance checking and submission
3. **ERP Portal API** - Authentication and profile services
4. **Cargowise Database** - Direct SQL Server connection for transaction data
5. **SOPL Database** - PostgreSQL for application data
6. **API16** - Compliance management with ADD/DEL operations
7. **AWS SES** - Email service for notifications and reports

## Monitoring and Operations

- Actuator endpoints enabled for health checks
- Prometheus metrics exposed at `/cpar-api/actuator/prometheus`
- Swagger UI available at `/cpar-api/swagger-ui/index.html`
- OpenTelemetry (OTLP) support available but disabled by default
- Comprehensive logging with different levels per package
- MetricsService for tracking job execution metrics

### Scheduled Jobs

**Data Comparison Job** (`schedule` package)
- Compares AR transactions between Cargowise (source) and SOPL (target) databases
- Runs at 2:30, 4:30, 6:30, 8:30, and 10:30 daily
- Generates Excel reports with detailed comparison results
- Sends email notifications via AWS SES
- Configurable retrieval days and email recipients
- Tracks execution metrics for monitoring

## Database Schema

### Core Tables
- **at_account_transaction_header**: Transaction headers with job references
- **at_account_transaction_lines**: Transaction line items with charge details
- **at_shipment_info**: Shipment information with collision prevention
- **cp_compliance**: Compliance tracking and status
- **api_log**: API request/response logging for audit trail

### Key Services
- **AtAccountTransactionTableService**: Manages transaction persistence
- **CpComplianceTableService**: Compliance data management
- **ApiLogService**: API logging service
- **CommonGlobalTableService**: Shared data access layer

## Lessons Learned

### Spring Boot Testing Migration (Spring Boot 3.4+)

**Issue**: Maven test compilation shows deprecation warnings for `@MockBean`
```
[WARNING] org.springframework.boot.test.mock.mockito.MockBean in org.springframework.boot.test.mock.mockito has been deprecated and marked for removal
```

**Solution**: Replace deprecated `@MockBean` with new `@MockitoBean` annotation

**Migration Steps**:
1. **Update import**: 
   - Remove: `import org.springframework.boot.test.mock.mockito.MockBean;`
   - Add: `import org.springframework.test.context.bean.override.mockito.MockitoBean;`

2. **Update annotations**:
   - Replace all `@MockBean` with `@MockitoBean`

**Example**:
```java
// OLD (deprecated in Spring Boot 3.4+)
import org.springframework.boot.test.mock.mockito.MockBean;
@MockBean
private TransactionService transactionService;

// NEW (recommended)
import org.springframework.test.context.bean.override.mockito.MockitoBean;
@MockitoBean
private TransactionService transactionService;
```

**Why**: Spring Boot 3.4+ introduced a new bean override testing framework that provides cleaner separation of concerns and better integration with Spring's testing infrastructure. The `@MockitoBean` annotation is part of this new framework.

## Integration Testing Architecture

### V2 Framework: BaseTransactionIntegrationTest (RECOMMENDED)

**IMPORTANT**: Always use the V2 integration testing framework for new tests. It provides superior architecture, performance, and maintainability.

#### V2 Framework Benefits
- **78% code reduction** compared to traditional V1 approach
- **75-78% faster test development** (45-60 minutes vs 3-4 hours)
- **Enhanced test coverage** with utility-driven validation
- **Built-in debugging capabilities** with investigation utilities
- **Standardized patterns** for consistent test implementation
- **Enterprise-grade validation** with comprehensive error handling

#### Creating New V2 Integration Tests

**Step 1: Extend BaseTransactionIntegrationTest**
```java
@Slf4j
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class YourNewIntegrationTestV2 extends BaseTransactionIntegrationTest {
    
    @Override
    protected void setupSpecificTestData() throws Exception {
        // Setup Cargowise test data specific to your test
        setupCargowiseTestData(getTestDataSqlFile());
        
        // Verify critical test data was loaded
        Map<String, Object> expectedData = new HashMap<>();
        expectedData.put("jobNumber", "YOUR_JOB_NUMBER");
        expectedData.put("transactionNumber", "YOUR_TRANSACTION_NUMBER");
        expectedData.put("organizationCode", "YOUR_ORG_CODE");
        
        try (Connection conn = getSqlServerConnection()) {
            sqlUtils.verifyCargowiseTestData(conn, expectedData);
        }
    }
    
    @Override
    protected String getTestDataSqlFile() {
        return "test-data-cargowise-YOUR_TEST_FILE.sql";
    }
}
```

**Step 2: Use V2 Utility Classes**
```java
@BeforeEach
void setupTest() throws Exception {
    // Load and validate test payloads
    testPayloadJson = payloadLoader.loadAndValidatePayload("reference/YOUR_PAYLOAD.json");
    
    // Setup mocks using utility
    mockUtils.setupBuyerInfoMock(globalTableService, "YOUR_ORG", "Organization Name");
    mockUtils.setupAPInvoiceRouting(transactionRoutingService, "YOUR_TRANSACTION_NUM");
    
    // Record initial database state
    initialCounts = databaseUtils.recordInitialCounts(getPostgreSQLConnection());
}
```

**Step 3: Implement Comprehensive Test Methods**
```java
@Test
@Order(1)
void testCompleteTransactionFlow() throws Exception {
    // Execute transaction using utility
    MvcResult result = testUtils.executeTransactionRequest(mockMvc, "/universal/transaction", testPayloadJson);
    
    // Verify response using utility
    verificationUtils.verifySuccessfulResponse(result, "DONE");
    
    // Verify database changes
    verificationUtils.verifyDatabaseChanges(getPostgreSQLConnection(), initialCounts, expectedChanges);
    
    // Verify specific business logic
    verificationUtils.verifyTransactionHeader(getPostgreSQLConnection(), expectedHeaderData);
    verificationUtils.verifyTransactionLines(getPostgreSQLConnection(), expectedLinesData);
}
```

#### V2 Framework Utility Classes

**Available Utilities:**
- **PayloadLoader**: Load and validate JSON test payloads
- **MockUtils**: Setup service mocks and routing configurations
- **DatabaseUtils**: Database operations and state management
- **VerificationUtils**: Comprehensive validation methods
- **TestUtils**: HTTP request execution and response handling
- **SQLUtils**: Cargowise data verification and validation

### Reference Data Architecture (CRITICAL)

**IMPORTANT**: Always use consolidated reference data architecture. Do NOT duplicate reference data in individual test files.

#### Consolidated Schema Files
- **test-schema-sqlserver.sql**: Full schema with all common reference data
- **test-schema-sqlserver-minimal.sql**: Minimal schema for lightweight tests

#### Common Reference Data (In Schema Files)
- **AccChargeCode**: DOC, FRT, AMS, OCHC, OCLR, etc.
- **OrgHeader**: OECGRPORD, CMACGMORF, MEISINYTN, etc.
- **GlbCompany**: Standard company records
- **GlbBranch**: Standard branch records  
- **GlbDepartment**: Standard department records

#### Test-Specific Data (In Individual Test Files)
- **AccTransactionHeader**: Your transaction records
- **AccTransactionLines**: Your transaction lines
- **JobHeader**: Your job-specific data
- **JobShipment**: Your shipment data
- **JobCharge**: Your charge data

#### Test Data File Template
```sql
-- Test data for YOUR_TEST_NAME
-- Only include test-specific data - reference data is in schema files

-- Test-specific transaction data
INSERT INTO AccTransactionHeader (AH_PK, AH_TransactionNum, AH_Ledger, ...)
VALUES('YOUR-TRANSACTION-GUID', 'YOUR_TRANSACTION_NUM', 'AP', ...);

-- Test-specific line data
INSERT INTO AccTransactionLines (AL_PK, AL_AH, AL_AC, ...)
VALUES('YOUR-LINE-GUID', 'YOUR-TRANSACTION-GUID', 'DOC', ...);

-- Test-specific job data
INSERT INTO JobHeader (JH_PK, JH_JobNum, ...)
VALUES('YOUR-JOB-GUID', 'YOUR_JOB_NUMBER', ...);
```

### Performance Benchmarks

**V2 Framework Performance (Validated):**
- **Individual test execution**: 1.5-2.5 seconds average
- **Test suite execution**: 15-25 seconds for comprehensive tests
- **Container startup**: ~8-10 seconds (SQL Server + PostgreSQL)
- **Per-test efficiency**: 78% improvement over V1 framework

### Documentation References

When creating new integration tests, refer to these comprehensive documents:

1. **docs/testing/reference-data-consolidation-guide.md**: Reference data management
2. **docs/testing/integration-test-architecture-insights.md**: V2 framework strategic analysis
3. **docs/testing/consolidate/SESSION_4_FINAL_MASTER_REPORT.md**: Complete project analysis
4. **docs/testing/consolidate/session_handover_*.md**: Detailed implementation guides

### Validation Commands

**Test individual V2 integration test:**
```bash
./mvnw test -Dtest=YourTestNameV2
```

**Verify reference data consolidation:**
```bash
grep -r "INSERT INTO AccChargeCode.*DOC\|FRT\|AMS" src/test/resources/test-data-cargowise-*.sql
# Should return no results - all reference data should be in schema files
```

**Run comprehensive test validation:**
```bash
./mvnw test -Dtest="*IntegrationTestV2"
```

### Migration Guidelines

**When migrating V1 tests to V2:**
1. **Extend BaseTransactionIntegrationTest** instead of manual setup
2. **Use utility classes** instead of manual implementations
3. **Follow consolidated reference data** architecture
4. **Implement comprehensive validation** using verification utils
5. **Document performance improvements** and capability enhancements

**Quality Gates:**
- All tests must pass consistently
- Performance must be under 3 seconds per test
- Code must be under 400 lines (75%+ reduction from V1)
- Must use consolidated reference data architecture