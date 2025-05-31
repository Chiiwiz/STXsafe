;; STXsafe Smart Contract
;; Description- An Automated Payment Service Contract
(define-data-var controller principal tx-sender)
(define-data-var min-term uint u30)
(define-data-var early-exit-fee uint u200)

(define-map plans
  { client: principal }
  {
    vendor: principal,
    rate: uint,
    begin: uint,
    expire: uint,
    cycle: uint,
    recent: uint,
    live: bool
  }
)

(define-public (setup-plan (vendor principal) (rate uint) (term uint) (cycle uint))
  (let
    (
      (now (unwrap-panic (get-stacks-block-info? time u0)))
      (deposit (* rate (/ term cycle)))
    )
    (asserts! (> rate u0) (err u100))
    (asserts! (> term u0) (err u101))
    (asserts! (> cycle u0) (err u102))
    (asserts! (>= term cycle) (err u103))
    (asserts! (not (is-eq vendor tx-sender)) (err u104))
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
        live: true
      }
    ))
  )
)

(define-public (execute-payment (client principal))
  (let
    (
      (plan (unwrap! (map-get? plans {client: client}) (err u200)))
      (now (unwrap-panic (get-stacks-block-info? time u0)))
    )
    (asserts! (not (is-eq client tx-sender)) (err u201))
    (asserts! (get live plan) (err u202))
    (asserts! (>= now (+ (get recent plan) (get cycle plan))) (err u203))
    (asserts! (<= now (get expire plan)) (err u204))
    (try! (as-contract
      (stx-transfer? (get rate plan) tx-sender (get vendor plan))))
    (ok (map-set plans
      { client: client }
      (merge plan { recent: now })))
  )
)

(define-public (terminate-plan)
  (let
    (
      (plan (unwrap! (map-get? plans {client: tx-sender}) (err u200)))
      (now (unwrap-panic (get-stacks-block-info? time u0)))
      (time-left (- (get expire plan) now))
      (min-time (* (var-get min-term) u144))
    )
    (asserts! (get live plan) (err u202))
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

(define-read-only (fetch-plan (client principal))
  (map-get? plans {client: client})
)

(define-read-only (fetch-min-term)
  (var-get min-term)
)

(define-read-only (fetch-controller)
  (var-get controller)
)

(define-public (update-min-term (new-term uint))
  (begin
    (asserts! (is-eq tx-sender (var-get controller)) (err u403))
    (asserts! (> new-term u0) (err u300))
    (ok (var-set min-term new-term))
  )
)

(define-public (change-controller (new-controller principal))
  (begin
    (asserts! (is-eq tx-sender (var-get controller)) (err u403))
    (asserts! (not (is-eq new-controller tx-sender)) (err u301))
    (ok (var-set controller new-controller))
  )
)