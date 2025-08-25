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