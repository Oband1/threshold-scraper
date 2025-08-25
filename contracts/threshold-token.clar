;; Threshold Token: Digital Asset Issuance and Management Platform
;; This contract manages the lifecycle of digital tokens with threshold-based mechanisms
;; on the Stacks blockchain, enabling secure and flexible token distribution.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TOKEN-NOT-FOUND (err u101))
(define-constant ERR-TOKEN-ALREADY-EXISTS (err u102))
(define-constant ERR-INSUFFICIENT-FUNDS (err u103))
(define-constant ERR-TOKEN-ALLOCATION-EXHAUSTED (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-TOKEN-NOT-MATURE (err u106))
(define-constant ERR-TOKEN-ALREADY-MATURE (err u107))
(define-constant ERR-DISTRIBUTION-ALREADY-MADE (err u108))
(define-constant ERR-INSUFFICIENT-BALANCE (err u109))
(define-constant ERR-INVALID-PARAMETERS (err u110))
(define-constant ERR-NOT-TOKEN-OWNER (err u111))
(define-constant ERR-DISTRIBUTION-INSUFFICIENT (err u112))

;; Data Maps and Variables

;; Tracks token issuers and their authorization status
(define-map token-issuers principal bool)

;; Token structure storing all token parameters and state
(define-map tokens 
  uint 
  {
    issuer: principal,
    total-supply: uint,
    distribution-threshold: uint,
    distribution-rate: uint,
    release-frequency: uint,
    maturity-block: uint,
    is-mature: bool,
    remaining-supply: uint,
    allow-early-release: bool
  }
)

;; Track individual holdings of each token
(define-map token-holdings 
  { token-id: uint, owner: principal } 
  uint
)

;; Track distribution schedules
(define-map token-distributions
  { token-id: uint, distribution-date: uint }
  { amount: uint, is-distributed: bool }
)

;; Track total distribution amount funded by issuer
(define-map token-distribution-funds
  uint  ;; token-id
  uint  ;; amount
)

;; Counter for token IDs
(define-data-var next-token-id uint u1)

;; Private Functions

;; Check if principal is an authorized token issuer
(define-private (is-authorized-issuer (issuer principal))
  (default-to false (map-get? token-issuers issuer))
)

;; Calculate distribution amount based on holdings and distribution rate
(define-private (calculate-distribution-amount (token-id uint) (holdings uint))
  (let (
    (token (unwrap! (map-get? tokens token-id) u0))
    (distribution-rate (get distribution-rate token))
    (distribution-threshold (get distribution-threshold token))
  )
    ;; Calculate: holdings * distribution-threshold * distribution-rate / 10000
    (/ (* (* holdings distribution-threshold) distribution-rate) u10000)
  )
)

;; Get current token balance for an owner
(define-private (get-token-balance (token-id uint) (owner principal))
  (default-to u0 
    (map-get? token-holdings { token-id: token-id, owner: owner })
  )
)

;; Check if token exists
(define-private (token-exists (token-id uint))
  (is-some (map-get? tokens token-id))
)

;; Transfer token units between principals
(define-private (transfer-token-units (token-id uint) (sender principal) (recipient principal) (amount uint))
  (let (
    (sender-balance (get-token-balance token-id sender))
    (recipient-balance (get-token-balance token-id recipient))
  )
    (if (>= sender-balance amount)
      (begin
        ;; Update sender balance
        (map-set token-holdings 
          { token-id: token-id, owner: sender }
          (- sender-balance amount)
        )
        ;; Update recipient balance
        (map-set token-holdings 
          { token-id: token-id, owner: recipient }
          (+ recipient-balance amount)
        )
        (ok true)
      )
      ERR-INSUFFICIENT-BALANCE
    )
  )
)

;; Read-only Functions

;; Get token details
(define-read-only (get-token (token-id uint))
  (map-get? tokens token-id)
)

;; Get token balance for a specific owner
(define-read-only (get-balance (token-id uint) (owner principal))
  (ok (get-token-balance token-id owner))
)

;; Check if a token is mature
(define-read-only (is-token-mature (token-id uint))
  (match (map-get? tokens token-id)
    token (ok (get is-mature token))
    (err ERR-TOKEN-NOT-FOUND)
  )
)

;; Get upcoming distribution for a token
(define-read-only (get-next-distribution (token-id uint))
  (match (map-get? tokens token-id)
    token 
    (let (
      (current-block block-height)
      (release-frequency (get release-frequency token))
      (maturity-block (get maturity-block token))
    )
      (if (>= current-block maturity-block)
        (ok { distribution-date: u0, amount: u0 }) ;; No more distributions after maturity
        (let (
          (next-distribution-date (+ current-block release-frequency))
        )
          (if (> next-distribution-date maturity-block)
            (ok { distribution-date: maturity-block, amount: u0 })
            (ok { distribution-date: next-distribution-date, amount: u0 })
          )
        )
      )
    )
    (err ERR-TOKEN-NOT-FOUND)
  )
)

;; Get total distribution fund for a token
(define-read-only (get-distribution-fund (token-id uint))
  (default-to u0 (map-get? token-distribution-funds token-id))
)

;; Public Functions

;; Add a new authorized token issuer (admin only)
(define-public (add-token-issuer (issuer principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set token-issuers issuer true))
  )
)

;; Remove token issuer authorization (admin only)
(define-public (remove-token-issuer (issuer principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set token-issuers issuer false))
  )
)

;; Create a new token with threshold-based distribution
(define-public (create-token 
  (total-supply uint) 
  (distribution-threshold uint) 
  (distribution-rate uint) 
  (release-frequency uint)
  (maturity-blocks uint)
  (allow-early-release bool))
  
  (let (
    (token-id (var-get next-token-id))
    (maturity-date (+ block-height maturity-blocks))
  )
    ;; Validation checks
    (asserts! (is-authorized-issuer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> total-supply u0) ERR-INVALID-PARAMETERS)
    (asserts! (> distribution-threshold u0) ERR-INVALID-PARAMETERS)
    (asserts! (>= distribution-rate u0) ERR-INVALID-PARAMETERS)
    (asserts! (> release-frequency u0) ERR-INVALID-PARAMETERS)
    (asserts! (> maturity-blocks u0) ERR-INVALID-PARAMETERS)
    
    ;; Ensure total supply is divisible by distribution threshold
    (asserts! (is-eq u0 (mod total-supply distribution-threshold)) ERR-INVALID-PARAMETERS)
    
    ;; Create the token
    (map-set tokens 
      token-id
      {
        issuer: tx-sender,
        total-supply: total-supply,
        distribution-threshold: distribution-threshold,
        distribution-rate: distribution-rate,
        release-frequency: release-frequency,
        maturity-block: maturity-date,
        is-mature: false,
        remaining-supply: (/ total-supply distribution-threshold),
        allow-early-release: allow-early-release
      }
    )
    
    ;; Increment token ID counter
    (var-set next-token-id (+ token-id u1))
    
    (ok token-id)
  )
)

;; Purchase tokens in primary market (from issuer)
(define-public (purchase-tokens (token-id uint) (units uint) (recipient (optional principal)))
  (let (
    (token (unwrap! (map-get? tokens token-id) ERR-TOKEN-NOT-FOUND))
    (issuer (get issuer token))
    (distribution-threshold (get distribution-threshold token))
    (remaining-supply (get remaining-supply token))
    (buyer (default-to tx-sender recipient))
    (total-cost (* units distribution-threshold))
  )
    ;; Check if token has available supply
    (asserts! (>= remaining-supply units) ERR-TOKEN-ALLOCATION-EXHAUSTED)
    ;; Check if buyer has enough STX
    (asserts! (>= (stx-get-balance tx-sender) total-cost) ERR-INSUFFICIENT-FUNDS)
    
    ;; Transfer STX to issuer
    (try! (stx-transfer? total-cost tx-sender issuer))
    
    ;; Update buyer's token balance
    (let (
      (current-balance (get-token-balance token-id buyer))
    )
      (map-set token-holdings 
        { token-id: token-id, owner: buyer }
        (+ current-balance units)
      )
    )
    
    ;; Update remaining supply
    (map-set tokens 
      token-id
      (merge token { remaining-supply: (- remaining-supply units) })
    )
    
    (ok units)
  )
)

;; Transfer tokens to another investor (secondary market)
(define-public (transfer (token-id uint) (amount uint) (recipient principal))
  (begin
    (asserts! (token-exists token-id) ERR-TOKEN-NOT-FOUND)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (not (is-eq tx-sender recipient)) ERR-INVALID-PARAMETERS)
    
    ;; Execute the transfer
    (try! (transfer-token-units token-id tx-sender recipient amount))
    
    (ok amount)
  )
)

;; Fund token distributions (issuer only)
(define-public (fund-token-distributions (token-id uint) (amount uint))
  (let (
    (token (unwrap! (map-get? tokens token-id) ERR-TOKEN-NOT-FOUND))
    (issuer (get issuer token))
    (current-fund (get-distribution-fund token-id))
  )
    ;; Ensure only the issuer can fund distributions
    (asserts! (is-eq tx-sender issuer) ERR-NOT-AUTHORIZED)
    ;; Ensure amount is positive
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    ;; Check if issuer has enough STX
    (asserts! (>= (stx-get-balance tx-sender) amount) ERR-INSUFFICIENT-FUNDS)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update distribution fund
    (map-set token-distribution-funds token-id (+ current-fund amount))
    
    (ok amount)
  )
)

;; Claim token distribution as token holder
(define-public (claim-distribution (token-id uint))
  (let (
    (token (unwrap! (map-get? tokens token-id) ERR-TOKEN-NOT-FOUND))
    (holder-units (get-token-balance token-id tx-sender))
    (distribution-fund (get-distribution-fund token-id))
  )
    ;; Check if the caller owns any tokens
    (asserts! (> holder-units u0) ERR-NOT-TOKEN-OWNER)
    
    ;; Calculate distribution amount
    (let (
      (distribution-amount (calculate-distribution-amount token-id holder-units))
    )
      ;; Check if sufficient funds exist in the distribution pool
      (asserts! (>= distribution-fund distribution-amount) ERR-DISTRIBUTION-INSUFFICIENT)
      
      ;; Transfer distribution to holder
      (try! (as-contract (stx-transfer? distribution-amount tx-sender tx-sender)))
      
      ;; Update distribution fund
      (map-set token-distribution-funds token-id (- distribution-fund distribution-amount))
      
      (ok distribution-amount)
    )
  )
)

;; Update token maturity status (can be called by anyone)
(define-public (update-token-maturity (token-id uint))
  (let (
    (token (unwrap! (map-get? tokens token-id) ERR-TOKEN-NOT-FOUND))
    (is-mature (get is-mature token))
    (maturity-block (get maturity-block token))
  )
    ;; Check if token is already marked as mature
    (asserts! (not is-mature) ERR-TOKEN-ALREADY-MATURE)
    ;; Check if token has reached maturity block
    (asserts! (>= block-height maturity-block) ERR-TOKEN-NOT-MATURE)
    
    ;; Mark token as mature
    (map-set tokens 
      token-id
      (merge token { is-mature: true })
    )
    
    (ok true)
  )
)

;; Allow early release if permitted by token terms
(define-public (early-release (token-id uint))
  (let (
    (token (unwrap! (map-get? tokens token-id) ERR-TOKEN-NOT-FOUND))
    (allow-early (get allow-early-release token))
    (issuer (get issuer token))
    (holder-units (get-token-balance token-id tx-sender))
    (distribution-threshold (get distribution-threshold token))
    (release-amount (* holder-units distribution-threshold))
  )
    ;; Check if early release is allowed
    (asserts! allow-early ERR-NOT-AUTHORIZED)
    ;; Check if holder has tokens to release
    (asserts! (> holder-units u0) ERR-NOT-TOKEN-OWNER)
    ;; Ensure token is not already mature
    (asserts! (not (get is-mature token)) ERR-TOKEN-ALREADY-MATURE)
    ;; Check if issuer has sufficient balance for release
    (asserts! (>= (stx-get-balance issuer) release-amount) ERR-INSUFFICIENT-FUNDS)
    
    ;; Transfer distribution from issuer to holder
    (try! (stx-transfer? release-amount issuer tx-sender))
    
    ;; Update holder's token balance
    (map-set token-holdings 
      { token-id: token-id, owner: tx-sender }
      u0
    )
    
    (ok release-amount)
  )
)

;; Contract owner variable
(define-data-var contract-owner principal tx-sender)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)