(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INSUFFICIENT_ALLOWANCE (err u102))
(define-constant ERR_INVALID_AMOUNT (err u103))
(define-constant ERR_INVALID_TOKEN (err u104))
(define-constant ERR_TRANSFER_FAILED (err u105))
(define-constant ERR_APPROVAL_FAILED (err u106))
(define-constant ERR_ALREADY_EXISTS (err u107))
(define-constant ERR_NOT_FOUND (err u108))
(define-constant ERR_NO_REWARDS (err u109))
(define-constant ERR_STILL_LOCKED (err u110))
(define-constant ERR_INVALID_LOCK_PERIOD (err u111))
(define-constant ERR_SELF_REFERRAL (err u112))
(define-constant ERR_REFERRAL_EXISTS (err u113))
(define-constant ERR_COMPOUNDING_DISABLED (err u114))
(define-constant ERR_MIN_COMPOUND_NOT_MET (err u115))

(define-map supported-tokens principal bool)
(define-map user-deposits { user: principal, token: principal } uint)
(define-map token-allowances { owner: principal, spender: principal, token: principal } uint)
(define-map total-deposits principal uint)
(define-map user-last-reward-block { user: principal, token: principal } uint)
(define-map user-earned-rewards { user: principal, token: principal } uint)
(define-map token-reward-rates principal uint)
(define-map locked-deposits { user: principal, token: principal } { amount: uint, unlock-block: uint, bonus-rate: uint, deposit-block: uint })
(define-map lock-period-rates uint uint)
(define-map user-referrer principal principal)
(define-map referral-earnings { user: principal, token: principal } uint)
(define-map referral-counts principal uint)
(define-map auto-compound-enabled { user: principal, token: principal } bool)
(define-map last-compound-block { user: principal, token: principal } uint)
(define-map total-compounded { user: principal, token: principal } uint)

(define-data-var contract-paused bool false)
(define-data-var deposit-fee uint u50)
(define-data-var withdrawal-fee uint u25)
(define-data-var referral-rate uint u500)
(define-data-var min-compound-amount uint u1000)
(define-data-var compound-interval uint u144)

(define-trait sip010-token
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

(define-public (add-supported-token (token-contract principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? supported-tokens token-contract)) ERR_ALREADY_EXISTS)
    (map-set supported-tokens token-contract true)
    (ok true)
  )
)

(define-public (remove-supported-token (token-contract principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? supported-tokens token-contract)) ERR_NOT_FOUND)
    (map-delete supported-tokens token-contract)
    (ok true)
  )
)

(define-public (approve-token (token-contract <sip010-token>) (spender principal) (amount uint))
  (let
    (
      (token-principal (contract-of token-contract))
      (current-allowance (default-to u0 (map-get? token-allowances { owner: tx-sender, spender: spender, token: token-principal })))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (default-to false (map-get? supported-tokens token-principal)) ERR_INVALID_TOKEN)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (map-set token-allowances { owner: tx-sender, spender: spender, token: token-principal } amount)
    (ok amount)
  )
)

(define-public (deposit-tokens (token-contract <sip010-token>) (amount uint))
  (let
    (
      (token-principal (contract-of token-contract))
      (current-balance (unwrap! (contract-call? token-contract get-balance tx-sender) ERR_TRANSFER_FAILED))
      (current-deposit (default-to u0 (map-get? user-deposits { user: tx-sender, token: token-principal })))
      (fee-amount (/ (* amount (var-get deposit-fee)) u10000))
      (deposit-amount (- amount fee-amount))
      (total-token-deposits (default-to u0 (map-get? total-deposits token-principal)))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (default-to false (map-get? supported-tokens token-principal)) ERR_INVALID_TOKEN)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= current-balance amount) ERR_INSUFFICIENT_BALANCE)
    (unwrap! (contract-call? token-contract transfer amount tx-sender (as-contract tx-sender) none) ERR_TRANSFER_FAILED)
    (unwrap-panic (update-rewards tx-sender token-principal))
    (unwrap-panic (process-referral-reward tx-sender token-principal deposit-amount))
    (map-set user-deposits { user: tx-sender, token: token-principal } (+ current-deposit deposit-amount))
    (map-set total-deposits token-principal (+ total-token-deposits deposit-amount))
    (ok deposit-amount)
  )
)

(define-public (withdraw-tokens (token-contract <sip010-token>) (amount uint))
  (let
    (
      (token-principal (contract-of token-contract))
      (current-deposit (default-to u0 (map-get? user-deposits { user: tx-sender, token: token-principal })))
      (fee-amount (/ (* amount (var-get withdrawal-fee)) u10000))
      (withdrawal-amount (+ amount fee-amount))
      (total-token-deposits (default-to u0 (map-get? total-deposits token-principal)))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (default-to false (map-get? supported-tokens token-principal)) ERR_INVALID_TOKEN)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= current-deposit withdrawal-amount) ERR_INSUFFICIENT_BALANCE)
    (unwrap! (as-contract (contract-call? token-contract transfer amount tx-sender tx-sender none)) ERR_TRANSFER_FAILED)
    (unwrap-panic (update-rewards tx-sender token-principal))
    (map-set user-deposits { user: tx-sender, token: token-principal } (- current-deposit withdrawal-amount))
    (map-set total-deposits token-principal (- total-token-deposits amount))
    (ok amount)
  )
)

(define-public (transfer-from (token-contract <sip010-token>) (owner principal) (recipient principal) (amount uint))
  (let
    (
      (token-principal (contract-of token-contract))
      (current-allowance (default-to u0 (map-get? token-allowances { owner: owner, spender: tx-sender, token: token-principal })))
      (owner-deposit (default-to u0 (map-get? user-deposits { user: owner, token: token-principal })))
      (recipient-deposit (default-to u0 (map-get? user-deposits { user: recipient, token: token-principal })))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (default-to false (map-get? supported-tokens token-principal)) ERR_INVALID_TOKEN)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= current-allowance amount) ERR_INSUFFICIENT_ALLOWANCE)
    (asserts! (>= owner-deposit amount) ERR_INSUFFICIENT_BALANCE)
    (map-set token-allowances { owner: owner, spender: tx-sender, token: token-principal } (- current-allowance amount))
    (map-set user-deposits { user: owner, token: token-principal } (- owner-deposit amount))
    (map-set user-deposits { user: recipient, token: token-principal } (+ recipient-deposit amount))
    (ok amount)
  )
)

(define-public (batch-deposit (token-contract <sip010-token>) (amounts (list 10 uint)))
  (let
    (
      (token-principal (contract-of token-contract))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (default-to false (map-get? supported-tokens token-principal)) ERR_INVALID_TOKEN)
    (ok (map deposit-single-amount amounts))
  )
)

(define-private (deposit-single-amount (amount uint))
  amount
)

(define-public (emergency-withdraw (token-contract <sip010-token>))
  (let
    (
      (token-principal (contract-of token-contract))
      (user-balance (default-to u0 (map-get? user-deposits { user: tx-sender, token: token-principal })))
      (total-token-deposits (default-to u0 (map-get? total-deposits token-principal)))
    )
    (asserts! (default-to false (map-get? supported-tokens token-principal)) ERR_INVALID_TOKEN)
    (asserts! (> user-balance u0) ERR_INSUFFICIENT_BALANCE)
    (unwrap! (as-contract (contract-call? token-contract transfer user-balance tx-sender tx-sender none)) ERR_TRANSFER_FAILED)
    (map-delete user-deposits { user: tx-sender, token: token-principal })
    (map-set total-deposits token-principal (- total-token-deposits user-balance))
    (ok user-balance)
  )
)

(define-public (set-deposit-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-fee u1000) ERR_INVALID_AMOUNT)
    (var-set deposit-fee new-fee)
    (ok new-fee)
  )
)

(define-public (set-withdrawal-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-fee u1000) ERR_INVALID_AMOUNT)
    (var-set withdrawal-fee new-fee)
    (ok new-fee)
  )
)

(define-public (toggle-contract-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-paused (not (var-get contract-paused)))
    (ok (var-get contract-paused))
  )
)

(define-read-only (get-user-deposit (user principal) (token principal))
  (default-to u0 (map-get? user-deposits { user: user, token: token }))
)

(define-read-only (get-token-allowance (owner principal) (spender principal) (token principal))
  (default-to u0 (map-get? token-allowances { owner: owner, spender: spender, token: token }))
)

(define-read-only (get-total-deposits (token principal))
  (default-to u0 (map-get? total-deposits token))
)

(define-read-only (is-token-supported (token principal))
  (default-to false (map-get? supported-tokens token))
)

(define-read-only (get-contract-info)
  {
    paused: (var-get contract-paused),
    deposit-fee: (var-get deposit-fee),
    withdrawal-fee: (var-get withdrawal-fee),
    owner: CONTRACT_OWNER
  }
)

(define-read-only (get-deposit-fee)
  (var-get deposit-fee)
)

(define-read-only (get-withdrawal-fee)
  (var-get withdrawal-fee)
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

(define-public (set-reward-rate (token-contract principal) (rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (default-to false (map-get? supported-tokens token-contract)) ERR_INVALID_TOKEN)
    (asserts! (<= rate u10000) ERR_INVALID_AMOUNT)
    (map-set token-reward-rates token-contract rate)
    (ok rate)
  )
)

(define-public (claim-rewards (token-contract principal))
  (let
    (
      (user-rewards (default-to u0 (map-get? user-earned-rewards { user: tx-sender, token: token-contract })))
    )
    (asserts! (default-to false (map-get? supported-tokens token-contract)) ERR_INVALID_TOKEN)
    (asserts! (> user-rewards u0) ERR_NO_REWARDS)
    (unwrap-panic (update-rewards tx-sender token-contract))
    (map-delete user-earned-rewards { user: tx-sender, token: token-contract })
    (ok user-rewards)
  )
)

(define-private (update-rewards (user principal) (token-contract principal))
  (let
    (
      (current-block-height stacks-block-height)
      (last-reward-block (default-to current-block-height (map-get? user-last-reward-block { user: user, token: token-contract })))
      (user-balance (default-to u0 (map-get? user-deposits { user: user, token: token-contract })))
      (reward-rate (default-to u0 (map-get? token-reward-rates token-contract)))
      (blocks-elapsed (- current-block-height last-reward-block))
      (earned-rewards (/ (* user-balance reward-rate blocks-elapsed) u10000))
      (current-rewards (default-to u0 (map-get? user-earned-rewards { user: user, token: token-contract })))
    )
    (map-set user-last-reward-block { user: user, token: token-contract } current-block-height)
    (map-set user-earned-rewards { user: user, token: token-contract } (+ current-rewards earned-rewards))
    (ok earned-rewards)
  )
)

(define-read-only (get-pending-rewards (user principal) (token-contract principal))
  (let
    (
      (current-block-height stacks-block-height)
      (last-reward-block (default-to current-block-height (map-get? user-last-reward-block { user: user, token: token-contract })))
      (user-balance (default-to u0 (map-get? user-deposits { user: user, token: token-contract })))
      (reward-rate (default-to u0 (map-get? token-reward-rates token-contract)))
      (blocks-elapsed (- current-block-height last-reward-block))
      (pending-rewards (/ (* user-balance reward-rate blocks-elapsed) u10000))
      (current-rewards (default-to u0 (map-get? user-earned-rewards { user: user, token: token-contract })))
    )
    (+ current-rewards pending-rewards)
  )
)

(define-read-only (get-reward-rate (token-contract principal))
  (default-to u0 (map-get? token-reward-rates token-contract))
)

(define-read-only (get-user-rewards (user principal) (token-contract principal))
  (default-to u0 (map-get? user-earned-rewards { user: user, token: token-contract }))
)

(define-public (set-lock-period-rate (lock-blocks uint) (bonus-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= bonus-rate u5000) ERR_INVALID_AMOUNT)
    (map-set lock-period-rates lock-blocks bonus-rate)
    (ok bonus-rate)
  )
)

(define-public (deposit-locked (token-contract <sip010-token>) (amount uint) (lock-blocks uint))
  (let
    (
      (token-principal (contract-of token-contract))
      (current-balance (unwrap! (contract-call? token-contract get-balance tx-sender) ERR_TRANSFER_FAILED))
      (fee-amount (/ (* amount (var-get deposit-fee)) u10000))
      (deposit-amount (- amount fee-amount))
      (total-token-deposits (default-to u0 (map-get? total-deposits token-principal)))
      (unlock-block (+ stacks-block-height lock-blocks))
      (bonus-rate (default-to u0 (map-get? lock-period-rates lock-blocks)))
      (existing-lock (map-get? locked-deposits { user: tx-sender, token: token-principal }))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (default-to false (map-get? supported-tokens token-principal)) ERR_INVALID_TOKEN)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= current-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> bonus-rate u0) ERR_INVALID_LOCK_PERIOD)
    (asserts! (is-none existing-lock) ERR_ALREADY_EXISTS)
    (unwrap! (contract-call? token-contract transfer amount tx-sender (as-contract tx-sender) none) ERR_TRANSFER_FAILED)
    (unwrap-panic (update-rewards tx-sender token-principal))
    (unwrap-panic (process-referral-reward tx-sender token-principal deposit-amount))
    (map-set locked-deposits { user: tx-sender, token: token-principal } 
      { amount: deposit-amount, unlock-block: unlock-block, bonus-rate: bonus-rate, deposit-block: stacks-block-height })
    (map-set total-deposits token-principal (+ total-token-deposits deposit-amount))
    (ok deposit-amount)
  )
)

(define-public (withdraw-locked (token-contract <sip010-token>))
  (let
    (
      (token-principal (contract-of token-contract))
      (lock-info (unwrap! (map-get? locked-deposits { user: tx-sender, token: token-principal }) ERR_NOT_FOUND))
      (locked-amount (get amount lock-info))
      (unlock-block (get unlock-block lock-info))
      (total-token-deposits (default-to u0 (map-get? total-deposits token-principal)))
    )
    (asserts! (default-to false (map-get? supported-tokens token-principal)) ERR_INVALID_TOKEN)
    (asserts! (>= stacks-block-height unlock-block) ERR_STILL_LOCKED)
    (unwrap! (as-contract (contract-call? token-contract transfer locked-amount tx-sender tx-sender none)) ERR_TRANSFER_FAILED)
    (unwrap-panic (update-locked-rewards tx-sender token-principal))
    (map-delete locked-deposits { user: tx-sender, token: token-principal })
    (map-set total-deposits token-principal (- total-token-deposits locked-amount))
    (ok locked-amount)
  )
)

(define-private (update-locked-rewards (user principal) (token-contract principal))
  (let
    (
      (lock-info (unwrap! (map-get? locked-deposits { user: user, token: token-contract }) ERR_NOT_FOUND))
      (locked-amount (get amount lock-info))
      (bonus-rate (get bonus-rate lock-info))
      (deposit-block (get deposit-block lock-info))
      (current-block-height stacks-block-height)
      (blocks-locked (- current-block-height deposit-block))
      (bonus-rewards (/ (* locked-amount bonus-rate blocks-locked) u10000))
      (current-rewards (default-to u0 (map-get? user-earned-rewards { user: user, token: token-contract })))
    )
    (map-set user-earned-rewards { user: user, token: token-contract } (+ current-rewards bonus-rewards))
    (ok bonus-rewards)
  )
)

(define-read-only (get-locked-deposit (user principal) (token-contract principal))
  (map-get? locked-deposits { user: user, token: token-contract })
)

(define-read-only (get-lock-period-rate (lock-blocks uint))
  (default-to u0 (map-get? lock-period-rates lock-blocks))
)

(define-read-only (is-deposit-unlocked (user principal) (token-contract principal))
  (match (map-get? locked-deposits { user: user, token: token-contract })
    lock-info (>= stacks-block-height (get unlock-block lock-info))
    true
  )
)

(define-public (set-referrer (referrer principal))
  (begin
    (asserts! (not (is-eq tx-sender referrer)) ERR_SELF_REFERRAL)
    (asserts! (is-none (map-get? user-referrer tx-sender)) ERR_REFERRAL_EXISTS)
    (map-set user-referrer tx-sender referrer)
    (map-set referral-counts referrer (+ (default-to u0 (map-get? referral-counts referrer)) u1))
    (ok referrer)
  )
)

(define-public (set-referral-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u2000) ERR_INVALID_AMOUNT)
    (var-set referral-rate new-rate)
    (ok new-rate)
  )
)

(define-public (claim-referral-rewards (token-contract principal))
  (let
    (
      (user-rewards (default-to u0 (map-get? referral-earnings { user: tx-sender, token: token-contract })))
    )
    (asserts! (default-to false (map-get? supported-tokens token-contract)) ERR_INVALID_TOKEN)
    (asserts! (> user-rewards u0) ERR_NO_REWARDS)
    (map-delete referral-earnings { user: tx-sender, token: token-contract })
    (ok user-rewards)
  )
)

(define-private (process-referral-reward (user principal) (token-contract principal) (deposit-amount uint))
  (match (map-get? user-referrer user)
    referrer 
      (let
        (
          (reward-amount (/ (* deposit-amount (var-get referral-rate)) u10000))
          (current-earnings (default-to u0 (map-get? referral-earnings { user: referrer, token: token-contract })))
        )
        (map-set referral-earnings { user: referrer, token: token-contract } (+ current-earnings reward-amount))
        (ok reward-amount)
      )
    (ok u0)
  )
)

(define-read-only (get-referrer (user principal))
  (map-get? user-referrer user)
)

(define-read-only (get-referral-count (user principal))
  (default-to u0 (map-get? referral-counts user))
)

(define-read-only (get-referral-earnings (user principal) (token-contract principal))
  (default-to u0 (map-get? referral-earnings { user: user, token: token-contract }))
)

(define-read-only (get-referral-rate)
  (var-get referral-rate)
)

(define-public (enable-auto-compound (token-contract principal))
  (begin
    (asserts! (default-to false (map-get? supported-tokens token-contract)) ERR_INVALID_TOKEN)
    (map-set auto-compound-enabled { user: tx-sender, token: token-contract } true)
    (map-set last-compound-block { user: tx-sender, token: token-contract } stacks-block-height)
    (ok true)
  )
)

(define-public (disable-auto-compound (token-contract principal))
  (begin
    (asserts! (default-to false (map-get? supported-tokens token-contract)) ERR_INVALID_TOKEN)
    (map-delete auto-compound-enabled { user: tx-sender, token: token-contract })
    (ok true)
  )
)

(define-public (compound-rewards (token-contract principal))
  (let
    (
      (is-enabled (default-to false (map-get? auto-compound-enabled { user: tx-sender, token: token-contract })))
      (last-compound (default-to u0 (map-get? last-compound-block { user: tx-sender, token: token-contract })))
      (blocks-since-compound (- stacks-block-height last-compound))
      (pending-rewards (get-pending-rewards tx-sender token-contract))
      (current-deposit (default-to u0 (map-get? user-deposits { user: tx-sender, token: token-contract })))
      (total-token-deposits (default-to u0 (map-get? total-deposits token-contract)))
      (total-compounded-amount (default-to u0 (map-get? total-compounded { user: tx-sender, token: token-contract })))
    )
    (asserts! (default-to false (map-get? supported-tokens token-contract)) ERR_INVALID_TOKEN)
    (asserts! is-enabled ERR_COMPOUNDING_DISABLED)
    (asserts! (>= blocks-since-compound (var-get compound-interval)) ERR_INVALID_AMOUNT)
    (asserts! (>= pending-rewards (var-get min-compound-amount)) ERR_MIN_COMPOUND_NOT_MET)
    (unwrap-panic (update-rewards tx-sender token-contract))
    (map-set user-deposits { user: tx-sender, token: token-contract } (+ current-deposit pending-rewards))
    (map-set total-deposits token-contract (+ total-token-deposits pending-rewards))
    (map-delete user-earned-rewards { user: tx-sender, token: token-contract })
    (map-set last-compound-block { user: tx-sender, token: token-contract } stacks-block-height)
    (map-set total-compounded { user: tx-sender, token: token-contract } (+ total-compounded-amount pending-rewards))
    (ok pending-rewards)
  )
)

(define-public (set-min-compound-amount (new-amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> new-amount u0) ERR_INVALID_AMOUNT)
    (var-set min-compound-amount new-amount)
    (ok new-amount)
  )
)

(define-public (set-compound-interval (new-interval uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> new-interval u0) ERR_INVALID_AMOUNT)
    (var-set compound-interval new-interval)
    (ok new-interval)
  )
)

(define-read-only (is-auto-compound-enabled (user principal) (token-contract principal))
  (default-to false (map-get? auto-compound-enabled { user: user, token: token-contract }))
)

(define-read-only (get-last-compound-block (user principal) (token-contract principal))
  (default-to u0 (map-get? last-compound-block { user: user, token: token-contract }))
)

(define-read-only (get-total-compounded (user principal) (token-contract principal))
  (default-to u0 (map-get? total-compounded { user: user, token: token-contract }))
)

(define-read-only (get-compound-settings)
  {
    min-amount: (var-get min-compound-amount),
    interval: (var-get compound-interval)
  }
)

(define-read-only (can-compound (user principal) (token-contract principal))
  (let
    (
      (is-enabled (default-to false (map-get? auto-compound-enabled { user: user, token: token-contract })))
      (last-compound (default-to u0 (map-get? last-compound-block { user: user, token: token-contract })))
      (blocks-since-compound (- stacks-block-height last-compound))
      (pending-rewards (get-pending-rewards user token-contract))
    )
    {
      enabled: is-enabled,
      interval-met: (>= blocks-since-compound (var-get compound-interval)),
      min-amount-met: (>= pending-rewards (var-get min-compound-amount)),
      can-execute: (and is-enabled 
                       (>= blocks-since-compound (var-get compound-interval))
                       (>= pending-rewards (var-get min-compound-amount)))
    }
  )
)

(define-private (make-portfolio-item (token principal))
  (let
    (
      (supported (default-to false (map-get? supported-tokens token)))
      (deposit (default-to u0 (map-get? user-deposits { user: tx-sender, token: token })))
      (pending (get-pending-rewards tx-sender token))
      (lock-opt (map-get? locked-deposits { user: tx-sender, token: token }))
      (locked (is-some lock-opt))
      (compound-enabled (default-to false (map-get? auto-compound-enabled { user: tx-sender, token: token })))
      (compound-info (can-compound tx-sender token))
      (can-execute (get can-execute compound-info))
    )
    {
      token: token,
      supported: supported,
      deposit: deposit,
      pending-rewards: pending,
      locked: locked,
      auto-compound: compound-enabled,
      can-compound: can-execute
    }
  )
)

(define-read-only (get-my-portfolio (tokens (list 50 principal)))
  (map make-portfolio-item tokens)
)
