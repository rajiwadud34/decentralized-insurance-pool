;; Insurance Pool Contract

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))

(define-data-var pool-counter uint u0)
(define-data-var claim-counter uint u0)

(define-map pools
  { pool-id: uint }
  {
    creator: principal,
    pool-type: (string-ascii 50),
    total-funds: uint,
    member-count: uint,
    active: bool
  }
)

(define-map members
  { pool-id: uint, member: principal }
  { contributed: uint, joined-at: uint }
)

(define-map claims
  { claim-id: uint }
  {
    pool-id: uint,
    claimant: principal,
    amount: uint,
    status: (string-ascii 20),
    filed-at: uint
  }
)

;; Create pool
(define-public (create-pool (pool-type (string-ascii 50)))
  (let ((new-id (+ (var-get pool-counter) u1)))
    (var-set pool-counter new-id)
    (map-set pools
      { pool-id: new-id }
      {
        creator: tx-sender,
        pool-type: pool-type,
        total-funds: u0,
        member-count: u0,
        active: true
      }
    )
    (ok new-id)
  )
)

;; Join pool
(define-public (join-pool (pool-id uint) (contribution uint))
  (let
    (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) ERR-NOT-FOUND))
    )
    (map-set members
      { pool-id: pool-id, member: tx-sender }
      { contributed: contribution, joined-at: block-height }
    )
    (map-set pools
      { pool-id: pool-id }
      (merge pool {
        total-funds: (+ (get total-funds pool) contribution),
        member-count: (+ (get member-count pool) u1)
      })
    )
    (ok true)
  )
)

;; File claim
(define-public (file-claim (pool-id uint) (amount uint))
  (let
    (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) ERR-NOT-FOUND))
      (membership (unwrap! (map-get? members { pool-id: pool-id, member: tx-sender }) ERR-NOT-AUTHORIZED))
      (new-claim-id (+ (var-get claim-counter) u1))
    )
    (asserts! (<= amount (get total-funds pool)) ERR-INSUFFICIENT-BALANCE)
    (var-set claim-counter new-claim-id)
    (map-set claims
      { claim-id: new-claim-id }
      {
        pool-id: pool-id,
        claimant: tx-sender,
        amount: amount,
        status: "pending",
        filed-at: block-height
      }
    )
    (ok new-claim-id)
  )
)

;; Approve claim
(define-public (approve-claim (claim-id uint))
  (let
    (
      (claim (unwrap! (map-get? claims { claim-id: claim-id }) ERR-NOT-FOUND))
      (pool (unwrap! (map-get? pools { pool-id: (get pool-id claim) }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get creator pool)) ERR-NOT-AUTHORIZED)
    (map-set claims
      { claim-id: claim-id }
      (merge claim { status: "approved" })
    )
    (map-set pools
      { pool-id: (get pool-id claim) }
      (merge pool {
        total-funds: (- (get total-funds pool) (get amount claim))
      })
    )
    (ok true)
  )
)

(define-read-only (get-pool (pool-id uint))
  (map-get? pools { pool-id: pool-id })
)

(define-read-only (get-member (pool-id uint) (member principal))
  (map-get? members { pool-id: pool-id, member: member })
)

(define-read-only (get-claim (claim-id uint))
  (map-get? claims { claim-id: claim-id })
)

(define-read-only (get-stats)
  (ok {
    total-pools: (var-get pool-counter),
    total-claims: (var-get claim-counter)
  })
)

;; Get pool balance
(define-read-only (get-pool-balance (pool-id uint))
  (match (map-get? pools { pool-id: pool-id })
    pool (ok (get total-funds pool))
    (err ERR-NOT-FOUND)
  )
)

;; Check member contribution
(define-read-only (get-member-contribution (pool-id uint) (member principal))
  (match (map-get? members { pool-id: pool-id, member: member })
    member-data (ok (get contributed member-data))
    (err ERR-NOT-FOUND)
  )
)
