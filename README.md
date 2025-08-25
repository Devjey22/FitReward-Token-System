# FitReward Token System

A blockchain-based fitness reward system that incentivizes users to complete workout goals by earning FIT tokens.

## Features

- **Token Rewards**: Users earn FIT tokens for completing fitness achievements
- **Achievement Tracking**: Multiple achievement types with different reward amounts
- **Token Transfer**: Users can transfer earned tokens to others
- **Balance Tracking**: Real-time balance and achievement monitoring

## Achievement Types

1. **Daily Workout** (10 FIT): Complete daily exercise routine
2. **Weekly Goal** (50 FIT): Achieve weekly fitness targets
3. **Monthly Challenge** (200 FIT): Complete monthly fitness challenges

## Smart Contract Functions

### Public Functions
- `mint-tokens`: Owner mints new tokens
- `reward-achievement`: Award tokens for fitness achievements
- `transfer`: Transfer tokens between users

### Read-Only Functions
- `get-balance`: Check user token balance
- `get-user-achievements`: View user's total achievements
- `get-total-achievements`: Get platform-wide achievement count
- `get-token-supply`: Check total token supply

## Technology Stack

- **Blockchain**: Stacks
- **Smart Contract Language**: Clarity
- **Token Standard**: Fungible Token (FT)

## Getting Started

1. Deploy the contract to Stacks testnet
2. Initialize achievement types
3. Start rewarding users for fitness achievements
