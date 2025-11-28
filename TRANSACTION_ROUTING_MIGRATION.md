# Transaction Routing Migration Guide

## Overview

This document describes the new transaction routing system that enables configuration-based control over which transactions are sent to external systems (China Compliance System). The key enhancement is the ability to configure AP-CRD (Accounts Payable Credit Notes) to be sent to external systems, which was previously hardcoded to be database-only.

## Key Changes

### Previous Behavior (Hardcoded)
- **AR transactions** (all types): Always sent to external system
- **AP transactions** (all types): Never sent to external system (database only)

### New Behavior (Configurable)
- **Legacy Mode** (default): Maintains exact current behavior for backward compatibility
- **Configuration Mode**: Allows flexible routing based on ledger + transaction type

## Architecture Changes

### Removed Components
- `TransactionProcessingStrategy` interface and implementations
- `APInvoiceProcessingStrategy.java`
- `ARCreditNoteProcessingStrategy.java`
- `ARInvoiceProcessingStrategy.java`
- `TransactionProcessingResult.java`
- `TransactionProcessingConfig.java`

### New Components
- `TransactionRoutingConfig.java`: Configuration model for routing rules
- `TransactionRoutingService.java`: Service for routing decisions with audit logging
- `application.yml`: Configuration file with routing rules

### Modified Components
- `UniversalController.java`: Now uses `TransactionRoutingService` instead of hardcoded logic

## Configuration

### application.yml Structure

```yaml
transaction:
  routing:
    # Enable legacy mode for backward compatibility
    enable-legacy-mode: true  # Default: true
    
    # Routing rules (used when enable-legacy-mode: false)
    rules:
      - ledger: AR
        transaction-type: INV
        send-to-external-system: true
        description: "AR Invoice to China Compliance System"
      
      - ledger: AR
        transaction-type: CRD
        send-to-external-system: true
        description: "AR Credit Note to China Compliance System"
      
      - ledger: AP
        transaction-type: INV
        send-to-external-system: false
        description: "AP Invoice - Database only"
      
      - ledger: AP
        transaction-type: CRD
        send-to-external-system: true  # NEW CAPABILITY
        description: "AP Credit Note to China Compliance System"
```

## Migration Steps

### Phase 1: Testing (Current Behavior)
1. Deploy with default configuration (`enable-legacy-mode: true`)
2. Verify no behavior changes in production
3. Monitor audit logs to confirm routing decisions

### Phase 2: Development/SIT Testing
1. Set `enable-legacy-mode: false` in DEV/SIT environments
2. Test AP-CRD transactions to verify external system integration
3. Monitor audit logs for routing decisions
4. Verify external system receives and processes AP-CRD correctly

### Phase 3: UAT Testing
1. Set `enable-legacy-mode: false` in UAT
2. Perform full regression testing
3. Validate all transaction types route correctly
4. Confirm audit logs show expected routing

### Phase 4: Production Deployment
1. Deploy with `enable-legacy-mode: true` initially
2. Monitor for 24-48 hours to ensure stability
3. Schedule maintenance window to switch to `enable-legacy-mode: false`
4. Monitor closely for first AP-CRD transactions

### Rollback Procedure
If issues arise at any phase:
1. Set `enable-legacy-mode: true` in application.yml
2. Restart application
3. System immediately reverts to original behavior

## Audit Logging

All routing decisions are logged with the prefix `ROUTING_AUDIT` in the main application log.

### Log Format Examples

#### Legacy Mode
```
ROUTING_AUDIT [LEGACY_MODE]: Transaction=AP-CRD-001, Ledger=AP, Type=CRD, Decision=DB_ONLY, Reason=Non-AR ledger not sent in legacy mode
```

#### Configuration Mode
```
ROUTING_AUDIT [CONFIG_MODE]: Transaction=AP-CRD-001, Ledger=AP, Type=CRD, Decision=SEND_EXTERNAL, Rule=AP Credit Note to China Compliance System
```

### Monitoring Commands

View all routing decisions:
```bash
grep "ROUTING_AUDIT" application.log
```

View only external routing decisions:
```bash
grep "ROUTING_AUDIT.*SEND_EXTERNAL" application.log
```

View AP-CRD routing specifically:
```bash
grep "ROUTING_AUDIT.*Ledger=AP.*Type=CRD" application.log
```

## Testing Checklist

### Unit Tests
- [x] `TransactionRoutingServiceTest.java` - Service logic tests
- [x] `TransactionRoutingConfigTest.java` - Configuration model tests

### Integration Tests
- [x] `UniversalControllerIntegrationTest.java` - Controller integration tests

### Manual Testing Scenarios

#### Legacy Mode (enable-legacy-mode: true)
- [ ] AR-INV transaction → Sent to external system
- [ ] AR-CRD transaction → Sent to external system
- [ ] AP-INV transaction → Database only
- [ ] AP-CRD transaction → Database only

#### Configuration Mode (enable-legacy-mode: false)
- [ ] AR-INV transaction → Sent to external system
- [ ] AR-CRD transaction → Sent to external system
- [ ] AP-INV transaction → Database only
- [ ] AP-CRD transaction → Sent to external system (NEW)

## API Response Changes

The API response now includes routing mode information:

### Database Only Response
```
AP CRD Payload received and saved to DB only with Track ID: {uuid} (Routing: LEGACY mode)
```

### External System Response
```
Payload received successfully with Track ID: {uuid}
```

## Troubleshooting

### Issue: AP-CRD not being sent to external system
1. Check `enable-legacy-mode` setting in application.yml
2. Verify routing rules configuration
3. Check audit logs for routing decision
4. Verify TransactionRoutingService is properly injected

### Issue: All AP transactions being sent externally
1. Check routing rules - ensure AP-INV is set to `send-to-external-system: false`
2. Verify configuration is loaded correctly
3. Check for typos in ledger/transaction-type values

### Issue: No audit logs appearing
1. Verify logging level is set to INFO or higher
2. Check log configuration for package `oec.lis.erpportal.addon.compliance.service`
3. Ensure TransactionRoutingService is being called

## Performance Considerations

- Routing decision is made in-memory with O(n) complexity where n = number of rules
- Typical configuration has 4-6 rules, negligible performance impact
- Audit logging adds minimal overhead (single log line per transaction)

## Security Considerations

- No sensitive data in routing configuration
- Audit logs contain transaction numbers but no payment details
- Configuration changes require application restart

## Future Enhancements

Potential future improvements:
1. Dynamic configuration reload without restart
2. Rule priorities for complex routing scenarios
3. Time-based routing rules (e.g., different routing during business hours)
4. Transaction amount thresholds for routing decisions
5. Multi-destination routing support

## Support

For issues or questions:
1. Check audit logs for routing decisions
2. Verify configuration in application.yml
3. Review test cases for expected behavior
4. Contact development team with transaction ID and audit logs