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
