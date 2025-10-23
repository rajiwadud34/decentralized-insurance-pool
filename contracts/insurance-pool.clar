;; Decentralized Insurance Pool Smart Contract
;; Manages mutual insurance pools with member contributions, claims, and automated payouts

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-POOL-INACTIVE (err u103))
(define-constant ERR-ALREADY-MEMBER (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-CLAIM-ALREADY-PROCESSED (err u106))
(define-constant ERR-MINIMUM-NOT-MET (err u107))

;; Data Variables
(define-data-var pool-counter uint u0)
(define-data-var claim-counter uint u0)
(define-data-var min-contribution uint u1000000) ;; Minimum contribution in microSTX
(define-data-var claim-vote-threshold uint u60) ;; 60% approval needed

;; Data Maps
(define-map pools
  { pool-id: uint }
  {
    creator: principal,
    pool-name: (string-ascii 50),
    pool-type: (string-ascii 50),
    total-funds: uint,
    member-count: uint,
    active: bool,
    created-at: uint,
    min-contribution: uint,
    max-coverage: uint,
    total-claims-paid: uint
  }
)

(define-map members
  { pool-id: uint, member: principal }
  { 
    contributed: uint,
    joined-at: uint,
    claims-filed: uint,
    claims-approved: uint,
    active: bool
  }
)

(define-map claims
  { claim-id: uint }
  {
    pool-id: uint,
    claimant: principal,
    amount: uint,
    status: (string-ascii 20),
    filed-at: uint,
    description: (string-ascii 200),
    votes-for: uint,
    votes-against: uint,
    processed-at: uint
  }
)

(define-map claim-votes
  { claim-id: uint, voter: principal }
  { vote: bool, voted-at: uint }
)

;; Pool Management Functions

;; Create a new insurance pool
(define-public (create-pool 
  (pool-name (string-ascii 50))
  (pool-type (string-ascii 50))
  (minimum-contribution uint)
  (maximum-coverage uint))
  (let ((new-id (+ (var-get pool-counter) u1)))
    (asserts! (> minimum-contribution u0) ERR-INVALID-AMOUNT)
    (asserts! (> maximum-coverage u0) ERR-INVALID-AMOUNT)
    (var-set pool-counter new-id)
    (map-set pools
      { pool-id: new-id }
      {
        creator: tx-sender,
        pool-name: pool-name,
        pool-type: pool-type,
        total-funds: u0,
        member-count: u0,
        active: true,
        created-at: block-height,
        min-contribution: minimum-contribution,
        max-coverage: maximum-coverage,
        total-claims-paid: u0
      }
    )
    (ok new-id)
  )
)

;; Join an existing pool with contribution
(define-public (join-pool (pool-id uint) (contribution uint))
  (let
    (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) ERR-NOT-FOUND))
      (existing-member (map-get? members { pool-id: pool-id, member: tx-sender }))
    )
    (asserts! (get active pool) ERR-POOL-INACTIVE)
    (asserts! (is-none existing-member) ERR-ALREADY-MEMBER)
    (asserts! (>= contribution (get min-contribution pool)) ERR-MINIMUM-NOT-MET)
    
    (map-set members
      { pool-id: pool-id, member: tx-sender }
      { 
        contributed: contribution,
        joined-at: block-height,
        claims-filed: u0,
        claims-approved: u0,
        active: true
      }
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

;; Add additional contribution to pool
(define-public (add-contribution (pool-id uint) (additional-amount uint))
  (let
    (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) ERR-NOT-FOUND))
      (member-data (unwrap! (map-get? members { pool-id: pool-id, member: tx-sender }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (get active pool) ERR-POOL-INACTIVE)
    (asserts! (> additional-amount u0) ERR-INVALID-AMOUNT)
    
    (map-set members
      { pool-id: pool-id, member: tx-sender }
      (merge member-data {
        contributed: (+ (get contributed member-data) additional-amount)
      })
    )
    (map-set pools
      { pool-id: pool-id }
      (merge pool {
        total-funds: (+ (get total-funds pool) additional-amount)
      })
    )
    (ok true)
  )
)

;; Claims Management Functions

;; File a new claim
(define-public (file-claim 
  (pool-id uint)
  (amount uint)
  (description (string-ascii 200)))
  (let
    (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) ERR-NOT-FOUND))
      (member-data (unwrap! (map-get? members { pool-id: pool-id, member: tx-sender }) ERR-NOT-AUTHORIZED))
      (new-claim-id (+ (var-get claim-counter) u1))
    )
    (asserts! (get active pool) ERR-POOL-INACTIVE)
    (asserts! (get active member-data) ERR-NOT-AUTHORIZED)
    (asserts! (<= amount (get max-coverage pool)) ERR-INVALID-AMOUNT)
    (asserts! (<= amount (get total-funds pool)) ERR-INSUFFICIENT-BALANCE)
    
    (var-set claim-counter new-claim-id)
    (map-set claims
      { claim-id: new-claim-id }
      {
        pool-id: pool-id,
        claimant: tx-sender,
        amount: amount,
        status: "pending",
        filed-at: block-height,
        description: description,
        votes-for: u0,
        votes-against: u0,
        processed-at: u0
      }
    )
    (map-set members
      { pool-id: pool-id, member: tx-sender }
      (merge member-data {
        claims-filed: (+ (get claims-filed member-data) u1)
      })
    )
    (ok new-claim-id)
  )
)

;; Vote on a claim
(define-public (vote-on-claim (claim-id uint) (approve bool))
  (let
    (
      (claim (unwrap! (map-get? claims { claim-id: claim-id }) ERR-NOT-FOUND))
      (pool (unwrap! (map-get? pools { pool-id: (get pool-id claim) }) ERR-NOT-FOUND))
      (member-data (unwrap! (map-get? members { pool-id: (get pool-id claim), member: tx-sender }) ERR-NOT-AUTHORIZED))
      (existing-vote (map-get? claim-votes { claim-id: claim-id, voter: tx-sender }))
    )
    (asserts! (is-eq (get status claim) "pending") ERR-CLAIM-ALREADY-PROCESSED)
    (asserts! (get active member-data) ERR-NOT-AUTHORIZED)
    (asserts! (is-none existing-vote) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq tx-sender (get claimant claim))) ERR-NOT-AUTHORIZED)
    
    (map-set claim-votes
      { claim-id: claim-id, voter: tx-sender }
      { vote: approve, voted-at: block-height }
    )
    
    (map-set claims
      { claim-id: claim-id }
      (merge claim {
        votes-for: (if approve (+ (get votes-for claim) u1) (get votes-for claim)),
        votes-against: (if approve (get votes-against claim) (+ (get votes-against claim) u1))
      })
    )
    (ok true)
  )
)

;; Process claim after voting
(define-public (process-claim (claim-id uint))
  (let
    (
      (claim (unwrap! (map-get? claims { claim-id: claim-id }) ERR-NOT-FOUND))
      (pool (unwrap! (map-get? pools { pool-id: (get pool-id claim) }) ERR-NOT-FOUND))
      (member-data (unwrap! (map-get? members { pool-id: (get pool-id claim), member: (get claimant claim) }) ERR-NOT-FOUND))
      (total-votes (+ (get votes-for claim) (get votes-against claim)))
      (approval-percentage (if (> total-votes u0)
        (/ (* (get votes-for claim) u100) total-votes)
        u0))
    )
    (asserts! (is-eq (get status claim) "pending") ERR-CLAIM-ALREADY-PROCESSED)
    (asserts! (>= total-votes (/ (get member-count pool) u2)) ERR-MINIMUM-NOT-MET)
    
    (if (>= approval-percentage (var-get claim-vote-threshold))
      (begin
        (map-set claims
          { claim-id: claim-id }
          (merge claim {
            status: "approved",
            processed-at: block-height
          })
        )
        (map-set pools
          { pool-id: (get pool-id claim) }
          (merge pool {
            total-funds: (- (get total-funds pool) (get amount claim)),
            total-claims-paid: (+ (get total-claims-paid pool) (get amount claim))
          })
        )
        (map-set members
          { pool-id: (get pool-id claim), member: (get claimant claim) }
          (merge member-data {
            claims-approved: (+ (get claims-approved member-data) u1)
          })
        )
        (ok true)
      )
      (begin
        (map-set claims
          { claim-id: claim-id }
          (merge claim {
            status: "rejected",
            processed-at: block-height
          })
        )
        (ok false)
      )
    )
  )
)

;; Deactivate pool
(define-public (deactivate-pool (pool-id uint))
  (let
    (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get creator pool)) ERR-NOT-AUTHORIZED)
    (map-set pools
      { pool-id: pool-id }
      (merge pool { active: false })
    )
    (ok true)
  )
)

;; Read-only Functions

(define-read-only (get-pool (pool-id uint))
  (map-get? pools { pool-id: pool-id })
)

(define-read-only (get-member (pool-id uint) (member principal))
  (map-get? members { pool-id: pool-id, member: member })
)

(define-read-only (get-claim (claim-id uint))
  (map-get? claims { claim-id: claim-id })
)

(define-read-only (get-claim-vote (claim-id uint) (voter principal))
  (map-get? claim-votes { claim-id: claim-id, voter: voter })
)

(define-read-only (get-stats)
  (ok {
    total-pools: (var-get pool-counter),
    total-claims: (var-get claim-counter),
    min-contribution: (var-get min-contribution),
    vote-threshold: (var-get claim-vote-threshold)
  })
)

(define-read-only (get-pool-balance (pool-id uint))
  (match (map-get? pools { pool-id: pool-id })
    pool (ok (get total-funds pool))
    ERR-NOT-FOUND
  )
)

(define-read-only (get-member-contribution (pool-id uint) (member principal))
  (match (map-get? members { pool-id: pool-id, member: member })
    member-data (ok (get contributed member-data))
    ERR-NOT-FOUND
  )
)

(define-read-only (is-pool-member (pool-id uint) (member principal))
  (is-some (map-get? members { pool-id: pool-id, member: member }))
)

(define-read-only (get-pool-stats (pool-id uint))
  (match (map-get? pools { pool-id: pool-id })
    pool (ok {
      total-funds: (get total-funds pool),
      member-count: (get member-count pool),
      total-claims-paid: (get total-claims-paid pool),
      active: (get active pool)
    })
    ERR-NOT-FOUND
  )
)
