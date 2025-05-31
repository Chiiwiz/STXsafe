# STXsafe Smart Contract

An automated payment service contract for the Stacks blockchain that supports both STX and SIP-010 token payments. STXsafe enables recurring payment subscriptions with customizable terms, cycles, and automatic execution.

## Features

- **Multi-Token Support**: Accept payments in STX or any supported SIP-010 token
- **Flexible Payment Plans**: Customizable rates, terms, and payment cycles
- **Automated Execution**: Third-party payment execution with built-in safeguards
- **Early Termination**: Exit plans with configurable penalty fees
- **Admin Controls**: Token whitelist management and emergency functions
- **Legacy Compatibility**: Backward compatible with STX-only implementations

## Contract Overview

### Core Components

- **Payment Plans**: Store subscription details including vendor, rate, schedule, and token type
- **Token Management**: Whitelist system for supported SIP-010 tokens
- **Controller System**: Administrative functions with proper access controls
- **Emergency Functions**: Safety mechanisms for fund recovery

## Function Reference

### Setup Functions

#### `setup-plan-stx`
Create a new payment plan using STX tokens.
```clarity
(setup-plan-stx vendor rate term cycle)
```
- `vendor`: Principal receiving payments
- `rate`: Payment amount per cycle (in microSTX)
- `term`: Total plan duration (in blocks)
- `cycle`: Payment frequency (in blocks)

#### `setup-plan-sip010`
Create a new payment plan using SIP-010 tokens.
```clarity
(setup-plan-sip010 vendor rate term cycle token-contract)
```
- `token-contract`: SIP-010 token contract reference

### Payment Execution

#### `execute-payment-stx`
Execute a scheduled STX payment.
```clarity
(execute-payment-stx client)
```

#### `execute-payment-sip010`
Execute a scheduled SIP-010 token payment.
```clarity
(execute-payment-sip010 client token-contract)
```

### Plan Management

#### `terminate-plan-stx`
Terminate an active STX payment plan.
```clarity
(terminate-plan-stx)
```

#### `terminate-plan-sip010`
Terminate an active SIP-010 token payment plan.
```clarity
(terminate-plan-sip010 token-contract)
```

### Legacy Functions (STX Only)

For backward compatibility:
- `setup-plan`: Equivalent to `setup-plan-stx`
- `execute-payment`: Equivalent to `execute-payment-stx`
- `terminate-plan`: Equivalent to `terminate-plan-stx`

### Read-Only Functions

#### `fetch-plan`
Retrieve plan details for a client.
```clarity
(fetch-plan client-principal)
```

#### `get-plan-token-info`
Get token information for a specific plan.
```clarity
(get-plan-token-info client-principal)
```

#### `is-token-enabled`
Check if a SIP-010 token is supported.
```clarity
(is-token-enabled token-contract)
```

### Administrative Functions

#### Token Management
```clarity
(add-supported-token token-contract)    ;; Enable new token
(remove-supported-token token-contract) ;; Disable token
```

#### Controller Functions
```clarity
(update-min-term new-term)              ;; Update minimum term requirement
(change-controller new-controller)      ;; Transfer controller role
```

#### Emergency Functions
```clarity
(emergency-withdraw-stx amount recipient)
(emergency-withdraw-sip010 token-contract amount recipient)
```

## Usage Examples

### Basic STX Subscription

```clarity
;; Setup a monthly STX subscription (30 days ≈ 4320 blocks)
(contract-call? .stxsafe setup-plan-stx 
  'SP1VENDOR... 
  u1000000    ;; 1 STX per payment
  u129600     ;; 30 days total
  u4320)      ;; Pay every day

;; Execute payment (callable by anyone after cycle period)
(contract-call? .stxsafe execute-payment-stx 'SP1CLIENT...)
```

### SIP-010 Token Subscription

```clarity
;; First, enable the token (controller only)
(contract-call? .stxsafe add-supported-token .my-token)

;; Setup token subscription
(contract-call? .stxsafe setup-plan-sip010
  'SP1VENDOR...
  u100000000  ;; 100 tokens per payment
  u129600     ;; 30 days total
  u4320       ;; Pay every day
  .my-token)

;; Execute token payment
(contract-call? .stxsafe execute-payment-sip010 
  'SP1CLIENT... 
  .my-token)
```

## Plan Structure

Each payment plan contains:

```clarity
{
  vendor: principal,           ;; Payment recipient
  rate: uint,                  ;; Payment amount per cycle
  begin: uint,                 ;; Plan start time (block height)
  expire: uint,                ;; Plan end time (block height)
  cycle: uint,                 ;; Payment frequency (blocks)
  recent: uint,                ;; Last payment time
  live: bool,                  ;; Plan active status
  token-type: uint,            ;; TOKEN-STX (0) or TOKEN-SIP010 (1)
  token-contract: (optional principal)  ;; SIP-010 contract address
}
```

## Constants

### Token Types
- `TOKEN-STX`: `u0`
- `TOKEN-SIP010`: `u1`

### Default Settings
- `min-term`: 30 blocks minimum plan duration
- `early-exit-fee`: 200 basis points (2%) penalty

## Error Codes

| Code | Description |
|------|-------------|
| u100 | Invalid rate (must be > 0) |
| u101 | Invalid term (must be > 0) |
| u102 | Invalid cycle (must be > 0) |
| u103 | Term too short (must be >= cycle) |
| u104 | Cannot set self as vendor |
| u200 | Payment plan not found |
| u201 | Unauthorized payment executor |
| u202 | Payment plan inactive |
| u203 | Payment too early (cycle not complete) |
| u204 | Payment plan expired |
| u205 | Invalid token type |
| u206 | Token transfer failed |
| u300 | Invalid minimum term |
| u301 | Invalid controller address |
| u403 | Not authorized (controller only) |

## Security Considerations

### Input Validation
- All user inputs are validated before processing
- Prevents self-referential contracts and addresses
- Amount and time parameters must be positive

### Access Controls
- Controller-only functions for administrative operations
- Clients can only manage their own plans
- Payment executors cannot be the client themselves

### Fund Safety
- Deposits held in contract escrow
- Emergency withdrawal functions for recovery
- Early termination penalties discourage abuse

### Token Security
- Whitelist system for supported SIP-010 tokens
- Token contract validation before operations
- Separate functions prevent token confusion

## Development Setup

### Prerequisites
- Clarinet CLI
- Stacks blockchain access
- SIP-010 token contracts for testing

### Testing
```bash
clarinet test
clarinet check
```

### Deployment
```bash
clarinet deploy --network testnet
```

## Integration Guide

### For Service Providers
1. Deploy the contract with appropriate controller
2. Add supported SIP-010 tokens via `add-supported-token`
3. Set minimum term requirements via `update-min-term`
4. Monitor plans and execute payments as needed

### For Clients
1. Choose payment token (STX or supported SIP-010)
2. Call appropriate setup function with plan parameters
3. Ensure sufficient balance for deposit calculation
4. Monitor plan status via read-only functions

### For Payment Executors
1. Monitor active plans for payment opportunities
2. Execute payments after cycle completion
3. Earn execution fees (if implemented separately)

## Roadmap

### Planned Features
- Gas fee optimization for batch operations
- Integration with decentralized schedulers
- Advanced analytics and reporting
- Multi-signature plan management
- Automated plan renewal options

### Integration Opportunities
- DeFi protocol subscriptions
- SaaS service payments
- Content creator patronage
- DAO treasury management

