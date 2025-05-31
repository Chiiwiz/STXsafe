;; STXsafe Smart Contract with Multi-Token Support
;; Description- An Automated Payment Service Contract supporting STX and SIP-010 tokens

(define-data-var controller principal tx-sender)
(define-data-var min-term uint u30)
(define-data-var early-exit-fee uint u200)

;; Token types
(define-constant TOKEN-STX u0)
(define-constant TOKEN-SIP010 u1)

;; Error codes
(define-constant ERR-INVALID-RATE (err u100))
(define-constant ERR-INVALID-TERM (err u101))
(define-constant ERR-INVALID-CYCLE (err u102))
(define-constant ERR-TERM-TOO-SHORT (err u103))
(define-constant ERR-SELF-VENDOR (err u104))
(define-constant ERR-PLAN-NOT-FOUND (err u200))
(define-constant ERR-UNAUTHORIZED-EXECUTOR (err u201))
(define-constant ERR-PLAN-INACTIVE (err u202))
(define-constant ERR-PAYMENT-TOO-EARLY (err u203))
(define-constant ERR-PLAN-EXPIRED (err u204))
(define-constant ERR-INVALID-TOKEN-TYPE (err u205))
(define-constant ERR-TOKEN-TRANSFER-FAILED (err u206))
(define-constant ERR-INVALID-MIN-TERM (err u300))
(define-constant ERR-INVALID-CONTROLLER (err u301))
(define-constant ERR-NOT-CONTROLLER (err u403))

;; Plans map with token information
(define-map plans
  { client: principal }
  {
    vendor: principal,
    rate: uint,
    begin: uint,
    expire: uint,
    cycle: uint,
    recent: uint,
    live: bool,
    token-type: uint,
    token-contract: (optional principal)
  }
)

;; Supported SIP-010 tokens
(define-map supported-tokens
  { token-contract: principal }
  { enabled: bool }
)

;; SIP-010 trait definition
(define-trait sip010-trait
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-balance (principal) (response uint uint))
  )
)

;; Token management functions
(define-public (add-supported-token (token-contract principal))
  (begin
    (asserts! (is-eq tx-sender (var-get controller)) ERR-NOT-CONTROLLER)
    (asserts! (not (is-eq token-contract tx-sender)) ERR-INVALID-TOKEN-TYPE)
    (asserts! (not (is-eq token-contract (as-contract tx-sender))) ERR-INVALID-TOKEN-TYPE)
    (ok (map-set supported-tokens { token-contract: token-contract } { enabled: true }))
  )
)

(define-public (remove-supported-token (token-contract principal))
  (begin
    (asserts! (is-eq tx-sender (var-get controller)) ERR-NOT-CONTROLLER)
    (asserts! (not (is-eq token-contract tx-sender)) ERR-INVALID-TOKEN-TYPE)
    (asserts! (not (is-eq token-contract (as-contract tx-sender))) ERR-INVALID-TOKEN-TYPE)
    (ok (map-set supported-tokens { token-contract: token-contract } { enabled: false }))
  )
)

(define-private (is-token-supported (token-contract principal))
  (default-to false (get enabled (map-get? supported-tokens { token-contract: token-contract })))
)

;; Setup plan with STX
(define-public (setup-plan-stx (vendor principal) (rate uint) (term uint) (cycle uint))
  (let
    (
      (now (unwrap-panic (get-stacks-block-info? time u0)))
      (deposit (* rate (/ term cycle)))
    )
    (asserts! (> rate u0) ERR-INVALID-RATE)
    (asserts! (> term u0) ERR-INVALID-TERM)
    (asserts! (> cycle u0) ERR-INVALID-CYCLE)
    (asserts! (>= term cycle) ERR-TERM-TOO-SHORT)
    (asserts! (not (is-eq vendor tx-sender)) ERR-SELF-VENDOR)
    
    (try! (stx-transfer? deposit tx-sender (as-contract tx-sender)))
    
    (ok (map-set plans
      { client: tx-sender }
      {
        vendor: vendor,
        rate: rate,
        begin: now,
        expire: (+ now term),
        cycle: cycle,
        recent: now,
        live: true,
        token-type: TOKEN-STX,
        token-contract: none
      }
    ))
  )
)

;; Setup plan with SIP-010 token
(define-public (setup-plan-sip010 (vendor principal) (rate uint) (term uint) (cycle uint) (token-contract <sip010-trait>))
  (let
    (
      (now (unwrap-panic (get-stacks-block-info? time u0)))
      (deposit (* rate (/ term cycle)))
      (token-principal (contract-of token-contract))
    )
    (asserts! (> rate u0) ERR-INVALID-RATE)
    (asserts! (> term u0) ERR-INVALID-TERM)
    (asserts! (> cycle u0) ERR-INVALID-CYCLE)
    (asserts! (>= term cycle) ERR-TERM-TOO-SHORT)
    (asserts! (not (is-eq vendor tx-sender)) ERR-SELF-VENDOR)
    (asserts! (is-token-supported token-principal) ERR-INVALID-TOKEN-TYPE)
    
    ;; Transfer SIP-010 token deposit to contract
    (try! (contract-call? token-contract transfer deposit tx-sender (as-contract tx-sender) none))
    
    (ok (map-set plans
      { client: tx-sender }
      {
        vendor: vendor,
        rate: rate,
        begin: now,
        expire: (+ now term),
        cycle: cycle,
        recent: now,
        live: true,
        token-type: TOKEN-SIP010,
        token-contract: (some token-principal)
      }
    ))
  )
)

;; Execute payment for STX plans
(define-public (execute-payment-stx (client principal))
  (let
    (
      (plan (unwrap! (map-get? plans {client: client}) ERR-PLAN-NOT-FOUND))
      (now (unwrap-panic (get-stacks-block-info? time u0)))
    )
    (asserts! (not (is-eq client tx-sender)) ERR-UNAUTHORIZED-EXECUTOR)
    (asserts! (get live plan) ERR-PLAN-INACTIVE)
    (asserts! (>= now (+ (get recent plan) (get cycle plan))) ERR-PAYMENT-TOO-EARLY)
    (asserts! (<= now (get expire plan)) ERR-PLAN-EXPIRED)
    (asserts! (is-eq (get token-type plan) TOKEN-STX) ERR-INVALID-TOKEN-TYPE)
    
    (try! (as-contract (stx-transfer? (get rate plan) tx-sender (get vendor plan))))
    
    (ok (map-set plans
      { client: client }
      (merge plan { recent: now })))
  )
)

;; Execute payment for SIP-010 token plans
(define-public (execute-payment-sip010 (client principal) (token-contract <sip010-trait>))
  (let
    (
      (plan (unwrap! (map-get? plans {client: client}) ERR-PLAN-NOT-FOUND))
      (now (unwrap-panic (get-stacks-block-info? time u0)))
      (token-principal (contract-of token-contract))
    )
    (asserts! (not (is-eq client tx-sender)) ERR-UNAUTHORIZED-EXECUTOR)
    (asserts! (get live plan) ERR-PLAN-INACTIVE)
    (asserts! (>= now (+ (get recent plan) (get cycle plan))) ERR-PAYMENT-TOO-EARLY)
    (asserts! (<= now (get expire plan)) ERR-PLAN-EXPIRED)
    (asserts! (is-eq (get token-type plan) TOKEN-SIP010) ERR-INVALID-TOKEN-TYPE)
    (asserts! (is-eq (some token-principal) (get token-contract plan)) ERR-INVALID-TOKEN-TYPE)
    
    (try! (as-contract (contract-call? token-contract transfer (get rate plan) tx-sender (get vendor plan) none)))
    
    (ok (map-set plans
      { client: client }
      (merge plan { recent: now })))
  )
)

;; Terminate STX plan
(define-public (terminate-plan-stx)
  (let
    (
      (plan (unwrap! (map-get? plans {client: tx-sender}) ERR-PLAN-NOT-FOUND))
      (now (unwrap-panic (get-stacks-block-info? time u0)))
      (time-left (- (get expire plan) now))
      (min-time (* (var-get min-term) u144))
    )
    (asserts! (get live plan) ERR-PLAN-INACTIVE)
    (asserts! (is-eq (get token-type plan) TOKEN-STX) ERR-INVALID-TOKEN-TYPE)
    
    ;; Apply early exit fee if terminating before minimum term
    (if (< time-left min-time)
      (let
        (
          (fee (/ (* (get rate plan) (var-get early-exit-fee)) u10000))
        )
        (try! (stx-transfer? fee tx-sender (get vendor plan)))
      )
      true
    )
    
    (ok (map-set plans
      { client: tx-sender }
      (merge plan { live: false })))
  )
)

;; Terminate SIP-010 token plan
(define-public (terminate-plan-sip010 (token-contract <sip010-trait>))
  (let
    (
      (plan (unwrap! (map-get? plans {client: tx-sender}) ERR-PLAN-NOT-FOUND))
      (now (unwrap-panic (get-stacks-block-info? time u0)))
      (time-left (- (get expire plan) now))
      (min-time (* (var-get min-term) u144))
      (token-principal (contract-of token-contract))
    )
    (asserts! (get live plan) ERR-PLAN-INACTIVE)
    (asserts! (is-eq (get token-type plan) TOKEN-SIP010) ERR-INVALID-TOKEN-TYPE)
    (asserts! (is-eq (some token-principal) (get token-contract plan)) ERR-INVALID-TOKEN-TYPE)
    
    ;; Apply early exit fee if terminating before minimum term
    (if (< time-left min-time)
      (let
        (
          (fee (/ (* (get rate plan) (var-get early-exit-fee)) u10000))
        )
        (try! (contract-call? token-contract transfer fee tx-sender (get vendor plan) none))
      )
      true
    )
    
    (ok (map-set plans
      { client: tx-sender }
      (merge plan { live: false })))
  )
)

;; Legacy function for backward compatibility (STX only)
(define-public (setup-plan (vendor principal) (rate uint) (term uint) (cycle uint))
  (setup-plan-stx vendor rate term cycle)
)

;; Legacy function for backward compatibility (STX only)
(define-public (execute-payment (client principal))
  (execute-payment-stx client)
)

;; Legacy function for backward compatibility (STX only)
(define-public (terminate-plan)
  (terminate-plan-stx)
)

;; Read-only functions
(define-read-only (fetch-plan (client principal))
  (map-get? plans {client: client})
)

(define-read-only (fetch-min-term)
  (var-get min-term)
)

(define-read-only (fetch-controller)
  (var-get controller)
)

(define-read-only (is-token-enabled (token-contract principal))
  (is-token-supported token-contract)
)

(define-read-only (get-plan-token-info (client principal))
  (match (map-get? plans {client: client})
    plan (ok { 
      token-type: (get token-type plan),
      token-contract: (get token-contract plan)
    })
    ERR-PLAN-NOT-FOUND
  )
)

;; Controller functions
(define-public (update-min-term (new-term uint))
  (begin
    (asserts! (is-eq tx-sender (var-get controller)) ERR-NOT-CONTROLLER)
    (asserts! (> new-term u0) ERR-INVALID-MIN-TERM)
    (ok (var-set min-term new-term))
  )
)

(define-public (change-controller (new-controller principal))
  (begin
    (asserts! (is-eq tx-sender (var-get controller)) ERR-NOT-CONTROLLER)
    (asserts! (not (is-eq new-controller tx-sender)) ERR-INVALID-CONTROLLER)
    (ok (var-set controller new-controller))
  )
)

;; Emergency functions (controller only)
(define-public (emergency-withdraw-stx (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender (var-get controller)) ERR-NOT-CONTROLLER)
    (asserts! (> amount u0) ERR-INVALID-RATE)
    (asserts! (not (is-eq recipient tx-sender)) ERR-INVALID-CONTROLLER)
    (asserts! (not (is-eq recipient (as-contract tx-sender))) ERR-INVALID-CONTROLLER)
    (as-contract (stx-transfer? amount tx-sender recipient))
  )
)

(define-public (emergency-withdraw-sip010 (token-contract <sip010-trait>) (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender (var-get controller)) ERR-NOT-CONTROLLER)
    (asserts! (> amount u0) ERR-INVALID-RATE)
    (asserts! (not (is-eq recipient tx-sender)) ERR-INVALID-CONTROLLER)
    (asserts! (not (is-eq recipient (as-contract tx-sender))) ERR-INVALID-CONTROLLER)
    (let ((token-principal (contract-of token-contract)))
      (asserts! (is-token-supported token-principal) ERR-INVALID-TOKEN-TYPE)
      (as-contract (contract-call? token-contract transfer amount tx-sender recipient none))
    )
  )
)