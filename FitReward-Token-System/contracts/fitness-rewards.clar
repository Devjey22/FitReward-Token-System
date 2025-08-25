;; FitReward - Fitness Achievement Token System
;; This contract manages a token-based reward system for fitness achievements
(define-fungible-token fit-token)
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-not-found (err u103))
(define-constant err-already-claimed (err u104))
(define-constant err-invalid-streak (err u105))
(define-constant err-unauthorized (err u106))
(define-constant err-challenge-ended (err u107))
(define-constant err-challenge-full (err u108))
(define-constant err-already-participated (err u109))

(define-data-var total-achievements uint u0)
(define-data-var daily-reward-pool uint u1000)
(define-data-var streak-multiplier uint u2)
(define-data-var contract-paused bool false)

(define-map user-achievements principal uint)
(define-map user-streaks principal uint)
(define-map user-last-claim principal uint)
(define-map daily-claims { day: uint, user: principal } bool)
(define-map leaderboard-cache { rank: uint } { user: principal, score: uint })
(define-map user-referrals principal (list 10 principal))
(define-map user-badges principal (list 20 uint))

(define-map achievement-types 
  { achievement-id: uint } 
  { name: (string-ascii 50), reward-amount: uint, badge-id: uint })

;; Initialize achievement types with badges
(map-set achievement-types { achievement-id: u1 } 
  { name: "daily-workout", reward-amount: u10, badge-id: u1 })
(map-set achievement-types { achievement-id: u2 } 
  { name: "weekly-goal", reward-amount: u50, badge-id: u2 })
(map-set achievement-types { achievement-id: u3 } 
  { name: "monthly-challenge", reward-amount: u200, badge-id: u3 })
(map-set achievement-types { achievement-id: u4 } 
  { name: "streak-master", reward-amount: u500, badge-id: u4 })
(map-set achievement-types { achievement-id: u5 } 
  { name: "community-champion", reward-amount: u300, badge-id: u5 })

;; Emergency functions
(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused true)
    (ok true)))

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused false)
    (ok true)))

(define-private (check-contract-active)
  (asserts! (not (var-get contract-paused)) (err u110)))

;; Core token functions
(define-public (mint-tokens (recipient principal) (amount uint))
  (begin
    (unwrap! (check-contract-active) (err u110))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (ft-mint? fit-token amount recipient)))

(define-public (transfer (amount uint) (sender principal) (recipient principal))
  (begin
    (unwrap! (check-contract-active) (err u110))
    (asserts! (is-eq tx-sender sender) err-unauthorized)
    (asserts! (>= (ft-get-balance fit-token sender) amount) err-insufficient-balance)
    (ft-transfer? fit-token amount sender recipient)))

(define-public (burn-tokens (amount uint))
  (begin
    (unwrap! (check-contract-active) (err u110))
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= (ft-get-balance fit-token tx-sender) amount) err-insufficient-balance)
    (ft-burn? fit-token amount tx-sender)))

(define-public (reward-achievement (user principal) (achievement-id uint))
  (let ((achievement-data (unwrap! (map-get? achievement-types { achievement-id: achievement-id }) err-not-found)))
    (begin
      (unwrap! (check-contract-active) (err u110))
      (asserts! (is-eq tx-sender contract-owner) err-owner-only)
      (map-set user-achievements user 
        (+ (default-to u0 (map-get? user-achievements user)) u1))
      (var-set total-achievements (+ (var-get total-achievements) u1))
      ;; Award badge
      (let ((current-badges (default-to (list) (map-get? user-badges user)))
            (badge-id (get badge-id achievement-data)))
        (if (is-none (index-of current-badges badge-id))
          (map-set user-badges user (unwrap-panic (as-max-len? (append current-badges badge-id) u20)))
          true))
      (ft-mint? fit-token (get reward-amount achievement-data) user))))

;; Daily check-in reward system with streak bonuses
(define-public (claim-daily-reward)
  (let ((current-day (/ block-height u144))
        (user-streak (default-to u0 (map-get? user-streaks tx-sender)))
        (last-claim (default-to u0 (map-get? user-last-claim tx-sender))))
    (begin
      (unwrap! (check-contract-active) (err u110))
      (asserts! (is-none (map-get? daily-claims { day: current-day, user: tx-sender })) err-already-claimed)
      (map-set daily-claims { day: current-day, user: tx-sender } true)
      (map-set user-last-claim tx-sender current-day)
      ;; Update streak
      (let ((new-streak (if (is-eq last-claim (- current-day u1))
                          (+ user-streak u1)
                          u1)))
        (map-set user-streaks tx-sender new-streak)
        ;; Calculate reward with streak bonus
        (let ((base-reward (var-get daily-reward-pool))
              (streak-bonus (if (> new-streak u6) 
                              (* base-reward (var-get streak-multiplier)) 
                              (* base-reward (/ (* new-streak (var-get streak-multiplier)) u10))))
              (total-reward (+ base-reward streak-bonus)))
          ;; Award streak master achievement at 30 days
          (if (is-eq new-streak u30)
            (unwrap-panic (reward-achievement tx-sender u4))
            true)
          (ft-mint? fit-token total-reward tx-sender))))))

(define-public (set-achievement-type (achievement-id uint) (name (string-ascii 50)) (reward-amount uint) (badge-id uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> reward-amount u0) err-invalid-amount)
    (ok (map-set achievement-types { achievement-id: achievement-id } 
      { name: name, reward-amount: reward-amount, badge-id: badge-id }))))

(define-public (batch-reward (users (list 20 principal)) (achievement-id uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (unwrap! (check-contract-active) (err u110))
    (ok (map reward-single-user users achievement-id))))

(define-private (reward-single-user (user principal) (achievement-id uint))
  (let ((achievement-data (unwrap-panic (map-get? achievement-types { achievement-id: achievement-id }))))
    (begin
      (map-set user-achievements user 
        (+ (default-to u0 (map-get? user-achievements user)) u1))
      (var-set total-achievements (+ (var-get total-achievements) u1))
      ;; Award badge
      (let ((current-badges (default-to (list) (map-get? user-badges user)))
            (badge-id (get badge-id achievement-data)))
        (if (is-none (index-of current-badges badge-id))
          (map-set user-badges user (unwrap-panic (as-max-len? (append current-badges badge-id) u20)))
          true))
      (unwrap-panic (ft-mint? fit-token (get reward-amount achievement-data) user)))))

;; Weekly/monthly bonus system
(define-map weekly-bonuses { week: uint } { claimed: bool, amount: uint })
(define-map monthly-bonuses { month: uint } { claimed: bool, amount: uint })

(define-public (claim-weekly-bonus)
  (let ((current-week (/ block-height u1008))) ;; ~7 days
    (begin
      (unwrap! (check-contract-active) (err u110))
      (asserts! (>= (default-to u0 (map-get? user-streaks tx-sender)) u7) err-invalid-streak)
      (asserts! (is-none (map-get? weekly-bonuses { week: current-week })) err-already-claimed)
      (map-set weekly-bonuses { week: current-week } { claimed: true, amount: u100 })
      (ft-mint? fit-token u100 tx-sender))))

(define-public (claim-monthly-bonus)
  (let ((current-month (/ block-height u4320))) ;; ~30 days
    (begin
      (unwrap! (check-contract-active) (err u110))
      (asserts! (>= (default-to u0 (map-get? user-achievements tx-sender)) u20) err-insufficient-balance)
      (asserts! (is-none (map-get? monthly-bonuses { month: current-month })) err-already-claimed)
      (map-set monthly-bonuses { month: current-month } { claimed: true, amount: u500 })
      (ft-mint? fit-token u500 tx-sender))))

;; Enhanced referral system with tiers
(define-public (refer-user (referred-user principal))
  (let ((current-referrals (default-to (list) (map-get? user-referrals tx-sender)))
        (referral-count (len current-referrals)))
    (begin
      (unwrap! (check-contract-active) (err u110))
      (asserts! (not (is-eq tx-sender referred-user)) err-invalid-amount)
      (asserts! (< referral-count u10) err-invalid-amount)
      (map-set user-referrals tx-sender (unwrap-panic (as-max-len? (append current-referrals referred-user) u10)))
      ;; Tiered rewards based on referral count
      (let ((referrer-reward (if (>= referral-count u5) u50 u25))
            (referred-reward (if (>= referral-count u5) u30 u15)))
        (unwrap! (ft-mint? fit-token referrer-reward tx-sender) err-invalid-amount)
        (ft-mint? fit-token referred-reward referred-user)))))

(define-public (update-parameters (daily-pool uint) (multiplier uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> daily-pool u0) err-invalid-amount)
    (asserts! (> multiplier u0) err-invalid-amount)
    (var-set daily-reward-pool daily-pool)
    (var-set streak-multiplier multiplier)
    (ok true)))

;; Governance functions for future upgrades
(define-public (propose-parameter-change (param (string-ascii 20)) (new-value uint))
  (begin
    (asserts! (>= (ft-get-balance fit-token tx-sender) u10000) err-insufficient-balance) ;; Need 10k tokens to propose
    ;; This could be expanded to include actual voting mechanism
    (ok true)))

;; Challenge system
(define-map active-challenges 
  { challenge-id: uint } 
  { 
    creator: principal, 
    name: (string-ascii 50), 
    reward-pool: uint, 
    entry-fee: uint,
    end-block: uint,
    max-participants: uint,
    current-participants: uint,
    completed: bool
  })

(define-map challenge-participants { challenge-id: uint, user: principal } bool)
(define-map challenge-winners { challenge-id: uint } (list 10 principal))
(define-data-var next-challenge-id uint u1)

(define-public (create-challenge (name (string-ascii 50)) (reward-pool uint) (entry-fee uint) (duration-blocks uint) (max-participants uint))
  (let ((challenge-id (var-get next-challenge-id)))
    (begin
      (unwrap! (check-contract-active) (err u110))
      (asserts! (>= (ft-get-balance fit-token tx-sender) reward-pool) err-insufficient-balance)
      (asserts! (> duration-blocks u0) err-invalid-amount)
      (asserts! (> max-participants u0) err-invalid-amount)
      (asserts! (<= max-participants u100) err-invalid-amount) ;; Max 100 participants
      (unwrap! (ft-transfer? fit-token reward-pool tx-sender (as-contract tx-sender)) err-insufficient-balance)
      (map-set active-challenges { challenge-id: challenge-id }
        {
          creator: tx-sender,
          name: name,
          reward-pool: reward-pool,
          entry-fee: entry-fee,
          end-block: (+ block-height duration-blocks),
          max-participants: max-participants,
          current-participants: u0,
          completed: false
        })
      (var-set next-challenge-id (+ challenge-id u1))
      (ok challenge-id))))

(define-public (join-challenge (challenge-id uint))
  (let ((challenge-data (unwrap! (map-get? active-challenges { challenge-id: challenge-id }) err-not-found)))
    (begin
      (unwrap! (check-contract-active) (err u110))
      (asserts! (< block-height (get end-block challenge-data)) err-challenge-ended)
      (asserts! (< (get current-participants challenge-data) (get max-participants challenge-data)) err-challenge-full)
      (asserts! (is-none (map-get? challenge-participants { challenge-id: challenge-id, user: tx-sender })) err-already-participated)
      (asserts! (>= (ft-get-balance fit-token tx-sender) (get entry-fee challenge-data)) err-insufficient-balance)
      (asserts! (not (get completed challenge-data)) err-challenge-ended)
      (unwrap! (ft-transfer? fit-token (get entry-fee challenge-data) tx-sender (as-contract tx-sender)) err-insufficient-balance)
      (map-set challenge-participants { challenge-id: challenge-id, user: tx-sender } true)
      (map-set active-challenges { challenge-id: challenge-id }
        (merge challenge-data { current-participants: (+ (get current-participants challenge-data) u1) }))
      (ok true))))

;; Complete challenge and distribute rewards
(define-public (complete-challenge (challenge-id uint) (winners (list 10 principal)))
  (let ((challenge-data (unwrap! (map-get? active-challenges { challenge-id: challenge-id }) err-not-found)))
    (begin
      (asserts! (is-eq tx-sender (get creator challenge-data)) err-unauthorized)
      (asserts! (>= block-height (get end-block challenge-data)) err-invalid-amount)
      (asserts! (not (get completed challenge-data)) err-already-claimed)
      (map-set challenge-winners { challenge-id: challenge-id } winners)
      (map-set active-challenges { challenge-id: challenge-id }
        (merge challenge-data { completed: true }))
      ;; Distribute rewards to winners
      (let ((winner-count (len winners))
            (reward-per-winner (if (> winner-count u0) (/ (get reward-pool challenge-data) winner-count) u0)))
        (ok (map distribute-challenge-reward winners reward-per-winner))))))

(define-private (distribute-challenge-reward (winner principal) (amount uint))
  (as-contract (ft-transfer? fit-token amount tx-sender winner)))

;; Enhanced staking system
(define-map user-stakes 
  { user: principal, stake-id: uint } 
  { amount: uint, lock-blocks: uint, start-block: uint, reward-rate: uint, auto-compound: bool })

(define-data-var next-stake-id uint u1)
(define-data-var base-reward-rate uint u5)

(define-public (stake-tokens (amount uint) (lock-blocks uint) (auto-compound bool))
  (let ((stake-id (var-get next-stake-id))
        (reward-rate (+ (var-get base-reward-rate) (/ lock-blocks u1440))))
    (begin
      (unwrap! (check-contract-active) (err u110))
      (asserts! (> amount u0) err-invalid-amount)
      (asserts! (>= lock-blocks u1440) err-invalid-amount) ;; Minimum 10 days
      (asserts! (>= (ft-get-balance fit-token tx-sender) amount) err-insufficient-balance)
      (unwrap! (ft-transfer? fit-token amount tx-sender (as-contract tx-sender)) err-insufficient-balance)
      (map-set user-stakes { user: tx-sender, stake-id: stake-id }
        {
          amount: amount,
          lock-blocks: lock-blocks,
          start-block: block-height,
          reward-rate: reward-rate,
          auto-compound: auto-compound
        })
      (var-set next-stake-id (+ stake-id u1))
      (ok stake-id))))

(define-public (unstake-tokens (stake-id uint))
  (let ((stake-data (unwrap! (map-get? user-stakes { user: tx-sender, stake-id: stake-id }) err-not-found)))
    (begin
      (unwrap! (check-contract-active) (err u110))
      (asserts! (>= block-height (+ (get start-block stake-data) (get lock-blocks stake-data))) err-invalid-streak)
      (let ((stake-amount (get amount stake-data))
            (base-reward (/ (* stake-amount (get reward-rate stake-data)) u100))
            (compound-multiplier (if (get auto-compound stake-data) u12 u10))
            (final-reward (/ (* base-reward compound-multiplier) u10)))
        (begin
          (map-delete user-stakes { user: tx-sender, stake-id: stake-id })
          (unwrap! (as-contract (ft-transfer? fit-token stake-amount tx-sender tx-sender)) err-insufficient-balance)
          (unwrap! (ft-mint? fit-token final-reward tx-sender) err-invalid-amount)
          (ok { returned: stake-amount, reward: final-reward }))))))

;; Marketplace system
(define-map marketplace-listings
  { listing-id: uint }
  {
    seller: principal,
    achievement-type: uint,
    price: uint,
    active: bool,
    created-block: uint
  })

(define-data-var next-listing-id uint u1)
(define-data-var marketplace-fee-rate uint u5) ;; 5% fee

(define-public (list-achievement (achievement-type uint) (price uint))
  (let ((listing-id (var-get next-listing-id))
        (user-achievement-count (default-to u0 (map-get? user-achievements tx-sender))))
    (begin
      (unwrap! (check-contract-active) (err u110))
      (asserts! (> user-achievement-count u0) err-insufficient-balance)
      (asserts! (> price u0) err-invalid-amount)
      (map-set marketplace-listings { listing-id: listing-id }
        {
          seller: tx-sender,
          achievement-type: achievement-type,
          price: price,
          active: true,
          created-block: block-height
        })
      (var-set next-listing-id (+ listing-id u1))
      (ok listing-id))))

(define-public (buy-achievement (listing-id uint))
  (let ((listing-data (unwrap! (map-get? marketplace-listings { listing-id: listing-id }) err-not-found)))
    (begin
      (unwrap! (check-contract-active) (err u110))
      (asserts! (get active listing-data) err-not-found)
      (asserts! (not (is-eq tx-sender (get seller listing-data))) err-unauthorized)
      (asserts! (>= (ft-get-balance fit-token tx-sender) (get price listing-data)) err-insufficient-balance)
      (let ((marketplace-fee (/ (* (get price listing-data) (var-get marketplace-fee-rate)) u100))
            (seller-amount (- (get price listing-data) marketplace-fee)))
        (unwrap! (ft-transfer? fit-token seller-amount tx-sender (get seller listing-data)) err-insufficient-balance)
        (unwrap! (ft-transfer? fit-token marketplace-fee tx-sender (as-contract tx-sender)) err-insufficient-balance)
        (map-set user-achievements tx-sender 
          (+ (default-to u0 (map-get? user-achievements tx-sender)) u1))
        (map-set user-achievements (get seller listing-data)
          (- (default-to u0 (map-get? user-achievements (get seller listing-data))) u1))
        (map-set marketplace-listings { listing-id: listing-id }
          (merge listing-data { active: false }))
        (ok true)))))

(define-public (cancel-listing (listing-id uint))
  (let ((listing-data (unwrap! (map-get? marketplace-listings { listing-id: listing-id }) err-not-found)))
    (begin
      (asserts! (is-eq tx-sender (get seller listing-data)) err-unauthorized)
      (asserts! (get active listing-data) err-not-found)
      (map-set marketplace-listings { listing-id: listing-id }
        (merge listing-data { active: false }))
      (ok true))))